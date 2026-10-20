# Plane Issue 数据库插入 — 参考规格

> 这是 Plane.so Issue 数据库插入的完整 SQL 生成规则参考文档。
> 主 SKILL.md 中的工作流会引导你使用这些规则。

---

## 一、数据库连接

| 参数 | 值 |
|------|-----|
| Host | `plane-plane-db-1`（容器内）或 `localhost:5432`（宿主机） |
| Database | `plane` |
| User | `plane` |
| Password | `plane` |

---

## 二、固定引用值

以下 UUID 中，**项目与空间相关**的值由用户在对话中提供（见 SKILL.md 工作流），其余为项目常量必须原样使用。

### 2.1 项目与空间

| 字段 | 说明 |
|------|------|
| workspace_id | 由用户提供（默认 `2265abc2-6f3f-4b9f-b474-bd53b8021efe`） |
| project_id | 由用户提供（必须） |
| project_identifier | 由用户提供（默认 `CAMPUSSCHE`），用于 Issue 显示名称前缀 |
| created_by / updated_by | `6d0536f5-6f25-4cae-ac3a-0e347f9baab3` — 需确认用户身份 |

### 2.2 可用 States

> ⚠️ State ID 是**项目级隔离**的。不同项目的同名 state 拥有不同的 UUID，
> 不可跨项目复用。每次插入前必须动态查询目标项目的实际 state ID。

查询方法：

```sql
SELECT id, name, "group" FROM states
WHERE project_id = '<project_id>'
ORDER BY name;
```

典型返回示例（UUID 因项目而异）：

| name | group | 用途 |
|------|-------|------|
| Backlog | backlog | 默认状态，阻塞未解除的 Issue 放这里 |
| Todo | unstarted | 就绪可开始 |
| In Progress | started | 进行中 |
| Done | completed | 已完成 |
| Cancelled | cancelled | 已取消 |

> 实际可用状态取决于 Plane 版本和项目配置。部分项目可能还有 `Triage`、`Merging`、`Rework` 等额外状态。

> **自动解锁触发条件**：Done 和 Cancelled 是终端状态。当 Issue 状态变更为这两个之一时，PostgreSQL 触发器会扫描 `issue_blockers` 表，检查其下游 Issue 是否所有阻塞方都已 Done/Cancelled，若是则自动将下游 Issue 从 Backlog 移到 Todo。

### 2.3 可用 Labels

> ⚠️ 当前项目尚无预定义标签。如需使用标签，请先在 Plane 页面中创建标签，然后通过以下 SQL 查询对应的 label_id：
>
> ```sql
> SELECT id, name FROM labels WHERE project_id = '<project_id>' ORDER BY name;
> ```

---

## 三、Issue YAML 输入格式

用户可用 YAML 或自然语言描述 Issue 及其阻塞关系：

```yaml
issues:
  - name: "[CS-P0-I01] 示例任务A — 后端API开发"
    description: |
      ## 任务描述
      开发REST API接口，包含CRUD操作。

      ### 验收标准
      - [ ] GET /api/v1/items 返回分页列表
      - [ ] POST /api/v1/items 创建新项
    state: Backlog              # 初始状态
    priority: high              # urgent|high|medium|low|none
    labels: []                  # 标签名称列表，留空如无预定义标签
    estimate_point: 3           # 预估点数（可选, 1-12）
    start_date: "2026-07-01"    # 可选
    target_date: "2026-07-05"   # 可选
    blocked_by: ["CS-P0-I01"]   # 原始卡片 ID（非 Plane 编号）
```

---

## 四、SQL 生成规则

### 4.0 清理已有数据（独立操作，仅用户明确需要时执行）

清理已有数据是一个**独立操作**，不在每次插入时自动执行。仅在用户确认需要替换项目数据时才进行。

**子表不可硬编码** — Plane 不同版本、不同部署的数据库结构可能不同。必须**动态查询**目标数据库来发现所有引用 `issues` 表的外键子表。

#### 步骤：发现外键依赖

连接到用户指定的 Plane 数据库，执行以下查询获取所有引用 `issues` 的子表：

```sql
SELECT
    tc.table_schema,
    tc.table_name,
    kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = 'issues'
ORDER BY tc.table_name;
```

#### 步骤：生成清理 SQL

根据查询结果生成 DELETE 语句，从所有子表开始，最后删 `issues`。此外还包括按 `project_id` 引用的项目级关联表（无直接 FK 但属于 Issue 数据）。

生成的清理脚本模板：

```sql
-- 子表（按 FK 依赖，子表优先 — 从上面查询结果逐条生成）
DELETE FROM <child_table_1> WHERE issue_id IN (SELECT id FROM issues WHERE project_id = '<project_id>');
DELETE FROM <child_table_2> WHERE issue_id IN (SELECT id FROM issues WHERE project_id = '<project_id>');
-- ...按查询结果逐表列出

-- 项目级关联表（按 project_id 清理，无直接 FK）
-- 常见的有：issue_activities, issue_blockers, issue_relations, issue_sequences
DELETE FROM issue_activities WHERE project_id = '<project_id>';
DELETE FROM issue_blockers WHERE project_id = '<project_id>';
DELETE FROM issue_relations WHERE project_id = '<project_id>';
DELETE FROM issue_sequences WHERE project_id = '<project_id>';

-- 最后删除 issues
DELETE FROM issues WHERE project_id = '<project_id>';
```

> ⚠️ 子表数量和名称**完全取决于目标 Plane 数据库的实际 schema**。每次执行前必须重新查询，不依赖缓存或硬编码列表。

### 4.1 主表 `issues` INSERT

目标表 `issues`，共 28 列。

> ⚠️ **硬性约束：description 必须原封不动插入。** `description_html` 和 `description_stripped`
> 填入源数据的完整原文，禁止压缩、摘要、截断或改写。只做 SQL 字符串转义（单引号 `'` → `''`），
> 不修改任何内容。即使原文长达数千字符，也必须完整插入。

```sql
INSERT INTO issues (
    id, created_at, updated_at, created_by_id, updated_by_id,
    project_id, workspace_id,
    name, description_json, description_html, description_stripped,
    state_id, parent_id, priority, sort_order, sequence_id,
    point, estimate_point_id, type_id,
    start_date, target_date,
    completed_at, archived_at, is_draft,
    external_source, external_id, description_binary,
    deleted_at
) VALUES (
    '<UUID>',          -- id: 每个Issue生成唯一UUID v4
    NOW(), NOW(),      -- created_at, updated_at
    '<user_id>', '<user_id>',
    '<project_id>', '<workspace_id>',
    '<name>',          -- 完整名称，含 Plane 编号前缀如 "CAMPUSSCHE-1: ..."
    '{}'::jsonb,       -- description_json: 空对象即可
    '<description>',   -- description_html: Markdown 描述的纯文本内容
    '<plain_text>',    -- description_stripped: 去除 HTML 标签后的纯文本版
    '<state_id>',      -- 默认用 Backlog
    NULL,              -- parent_id: 无父子关系时填NULL
    '<priority>',      -- urgent|high|medium|low|none
    <sort_order>,      -- 见 4.1.1 计算规则
    <sequence_id>,     -- 见 4.1.2 计算规则
    <point>,           -- 整数1-12或NULL
    NULL, NULL,        -- estimate_point_id, type_id
    '<start_date>',    -- 'YYYY-MM-DD' 或 NULL
    '<target_date>',   -- 'YYYY-MM-DD' 或 NULL
    NULL, NULL, false, -- completed_at, archived_at, is_draft
    NULL, NULL, NULL,  -- external_source, external_id, description_binary
    NULL               -- deleted_at
);
```

#### 4.1.1 sort_order 计算规则

对每个 Issue，查询对应 state 下当前最大 sort_order，在此基础上递增：

```sql
SELECT COALESCE(MAX(sort_order), 0)
FROM issues
WHERE project_id = '<project_id>'
  AND state_id = '<state_id>'
  AND deleted_at IS NULL;
```

> ⚠️ 同一批次内的多个 Issue 如果属于同一 state，sort_order 不能重复。第一个取 `max + 10000`，第二个取 `max + 20000`，以此类推。

#### 4.1.2 sequence_id 计算规则

每个项目独立的递增序列号。**必须使用 PostgreSQL 行级锁保证原子性**：

```sql
-- 对每个 INSERT 前执行
SELECT pg_advisory_xact_lock(hashtextextended('<project_id>', 0));

-- 获取下一个 sequence_id
SELECT COALESCE(MAX(sequence), 0) + 1
FROM issue_sequences
WHERE project_id = '<project_id>';
```

### 4.2 `issue_sequences` 表 INSERT

每个 Issue 必须创建一条 sequence 记录：

```sql
INSERT INTO issue_sequences (
    id, created_at, updated_at, created_by_id, updated_by_id,
    issue_id, sequence, project_id, workspace_id,
    deleted, deleted_at
) VALUES (
    '<new_uuid>', NOW(), NOW(),
    '<user_id>', '<user_id>',
    '<issue_id>',
    <sequence_id>,
    '<project_id>', '<workspace_id>',
    false, NULL
);
```

### 4.3 `issue_blockers` 表 INSERT（阻塞关系 — 自动解锁）

**阻塞语义**：A 被 B 阻塞 → `block_id = A.id`, `blocked_by_id = B.id`

```sql
INSERT INTO issue_blockers (
    id, created_at, updated_at, created_by_id, updated_by_id,
    block_id, blocked_by_id, project_id, workspace_id,
    deleted_at
) VALUES (
    '<new_uuid>', NOW(), NOW(),
    '<user_id>', '<user_id>',
    '<被阻塞方UUID>',          -- block: 下游，不能开始
    '<阻塞方UUID>',            -- blocked_by: 上游，挡路者
    '<project_id>', '<workspace_id>',
    NULL
);
```

### 4.3b `issue_relations` 表 INSERT（阻塞关系 — UI 展示）

**Plane 前端 Issue 详情页的阻塞关系图依赖此表。** 与 `issue_blockers` 成对插入。

| 列 | 说明 |
|----|------|
| `issue_id` | 被阻塞方（下游 Issue UUID） |
| `related_issue_id` | 阻塞方（上游 Issue UUID） |
| `relation_type` | `'blocked_by'` |

```sql
INSERT INTO issue_relations (
    id, created_at, updated_at, created_by_id, updated_by_id,
    issue_id, related_issue_id, relation_type, project_id, workspace_id
) VALUES (
    '<new_uuid>', NOW(), NOW(),
    '<user_id>', '<user_id>',
    '<被阻塞方UUID>',
    '<阻塞方UUID>',
    'blocked_by',
    '<project_id>', '<workspace_id>'
);
```

> ✅ 对每对阻塞关系，`issue_blockers` 和 `issue_relations` 各有一条记录。

### 4.4 `issue_labels` 表 INSERT（可选）

```sql
INSERT INTO issue_labels (
    id, created_at, updated_at, created_by_id, updated_by_id,
    issue_id, label_id, project_id, workspace_id, deleted_at
) VALUES (
    '<new_uuid>', NOW(), NOW(),
    '<user_id>', '<user_id>',
    '<issue_id>', '<label_id>', '<project_id>', '<workspace_id>',
    NULL
);
```

> ⚠️ label_id 必须从 Plane 数据库中查询匹配。YAML 中填写的标签名称如果在数据库中没有对应项，该标签将被跳过。

### 4.5 `issue_activities` 表 INSERT

每个 Issue 创建后需插入一条 `created` 活动记录：

```sql
INSERT INTO issue_activities (
    id, created_at, updated_at, created_by_id, updated_by_id,
    issue_id, verb, field, old_value, new_value,
    comment, attachments, old_identifier, new_identifier,
    epoch, project_id, workspace_id, actor_id, issue_comment_id, deleted_at
) VALUES (
    '<new_uuid>', NOW(), NOW(),
    '<user_id>', '<user_id>',
    '<issue_id>',
    'created',
    NULL, NULL, NULL,
    '',
    '{}',
    NULL, NULL,
    EXTRACT(EPOCH FROM NOW()),
    '<project_id>', '<workspace_id>',
    '<user_id>',
    NULL, NULL
);
```

> ⚠️ `issue_activities.comment` 列有 NOT NULL 约束，INSERT 时必须提供 `''` 而非 NULL。

---

## 五、整体事务模板

```sql
BEGIN;

-- 0. 清理已有数据（重新插入时）— 见 §4.0

-- 1. 获取项目级排他锁
SELECT pg_advisory_xact_lock(hashtextextended('<project_id>', 0));

-- 2. 确定起始 sequence_id

-- 3. 按原始顺序插入 issues 和 issue_sequences

-- 4. 插入 issue_blockers（阻塞关系 — 自动解锁）

-- 5. 插入 issue_relations（阻塞关系 — UI 展示）
--    与 issue_blockers 成对插入

-- 6. 插入 issue_labels（如果有）

-- 7. 插入 issue_activities（每个 Issue 一条 created 记录）

COMMIT;
```

---

## 六、自动解锁行为

| 表 | 用途 |
|----|------|
| `issue_blockers` | PostgreSQL 触发器 `auto_unlock_issues_fn` 监听，负责自动解锁 |
| `issue_relations` | Plane 前端 Issue 详情页读取，负责展示阻塞关系图 |

当阻塞方状态变更为 Done/Cancelled 时，触发器自动将下游 Issue 从 Backlog 移到 Todo，形成链式解锁。

---

## 七、输出要求

1. **完整 SQL 脚本** — 可直接在 `psql` 中执行，包含 `BEGIN`/`COMMIT` 事务边界
2. **阻塞关系 ASCII 图** — 展示 Issue 间的有向依赖（X → Y 表示 X 阻塞 Y）
3. **验证 SQL** — 执行后查询确认插入正确
