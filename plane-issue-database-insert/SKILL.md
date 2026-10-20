---
name: plane-issue-database-insert
description: >
  将带阻塞关系的多个 Issue 直接插入 Plane.so PostgreSQL 数据库，生成完整 SQL 脚本。
  当你需要批量创建 Plane Issue、建立 Issue 间的阻塞依赖关系、或生成 Plane 数据库插入 SQL 时使用此 skill。
  触发场景：用户提到"插入 Plane Issue"、"批量创建 Issue"、"写入 Plane 数据库"、"生成 Plane SQL"、
  "Issue 阻塞关系"、"Plane 数据库插入"、或需要在 Plane 项目中建立带依赖关系的任务。
---

# Plane Issue 数据库插入

将带阻塞关系的 Issue 通过 SQL 直接写入 Plane.so 的 PostgreSQL 数据库，
生成可执行的完整事务脚本。阻塞关系同时写入 `issue_blockers`（自动解锁触发器）
和 `issue_relations`（前端 UI 展示），确保自动解锁和页面可视化同时正确工作。

---

## 硬性约束

> 1. **禁止对 description 做任何压缩、摘要、截断或改写。**
>    必须将源数据中的 description 字段**逐字逐句、原封不动**地插入到
>    `description_html` 和 `description_stripped` 列中。只需要做 SQL 字符串转义
>    （单引号→双引号），不允许修改任何内容。
>
> 2. **禁止凭记忆逐表清理。** 清理/重置 Issue 时必须先执行 FK 发现查询
>    （`information_schema`），得到完整的子表清单后再逐表 DELETE，
>    最后用验证 SQL 逐表确认。常见遗漏项：`issue_comments`、
>    `issue_description_versions`、`issue_versions`。

---

## 工作流

按以下步骤与用户交互，收集必要信息后生成 SQL。

### 第一步：收集连接与项目参数

逐一询问以下参数。**Plane 地址**和 **project_id** 必须由用户提供，
**project_identifier** 和 **workspace_id** 有默认值，用户可跳过。

使用 `AskUserQuestion` 工具一次性收集所有参数，参考以下选项：

1. **Plane 地址**（必填）
   - 示例：`http://localhost:3000/xunzhi/projects/<project_id>/issues/`
   - 用途：告知用户 Issue 创建后在哪个页面查看

2. **project_id**（必填）
   - 示例：`8f1fb71f-3e8a-4ad9-b76e-a362a59b87e1`
   - 用途：目标项目的 UUID

3. **project_identifier**（选填，默认 `CAMPUSSCHE`）
   - 用途：Issue 显示名称前缀，如 `CAMPUSSCHE-1`、`CAMPUSSCHE-2`
   - 若用户不提供，使用默认值 `CAMPUSSCHE`

4. **workspace_id**（选填，默认 `2265abc2-6f3f-4b9f-b474-bd53b8021efe`）
   - 用途：工作空间 UUID
   - 若用户不提供，使用默认值

5. **数据库连接方式**（选填，默认容器内 `plane-plane-db-1`）
   - 选项：容器内 (`plane-plane-db-1`) 或宿主机 (`localhost:5432`)

6. **State ID 获取方式**（选填，默认自动查询）
   - 选项：
     - **自动查询**（推荐）：连接数据库查询 `SELECT id, name FROM states WHERE project_id = '<project_id>'` 获取实际 state ID
     - **手动指定**：用户直接提供各 state 对应的 UUID
   - 用途：`issues` 表的 `state_id` 列有外键约束，必须使用目标项目实际存在的 state UUID。不同项目的同名 state（如 "Backlog"）拥有不同的 UUID，不可跨项目复用

收集完毕后，向用户确认所有参数再继续。

### 第二步：收集 Issue 列表

请用户以 YAML 格式或自然语言描述要创建的 Issue。
如果用户用自然语言描述，帮其整理为 YAML 格式并请用户确认。

每个 Issue 包含：

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | ✅ | 格式：`[卡片ID] 任务名`，如 `[CS-P0-I01] 后端API开发`。最终 Plane 名称会自动加上编号前缀 |
| `description` | ✅ | Markdown 格式，含任务描述和验收标准 |
| `state` | ✅ | 初始状态，默认 `Backlog`（阻塞未解除时推荐） |
| `priority` | ✅ | `urgent` / `high` / `medium` / `low` / `none` |
| `labels` | - | 标签名称列表，如项目无预定义标签则留空 |
| `estimate_point` | - | 预估点数 1-12 |
| `start_date` | - | `YYYY-MM-DD` 格式 |
| `target_date` | - | `YYYY-MM-DD` 格式 |
| `blocked_by` | - | 被哪些卡片阻塞，填原始卡片 ID 列表（非 Plane 编号） |

### 第三步：询问是否需要清理已有数据

清理已有数据是一个**独立操作**，不与插入捆绑。询问用户：

> 是否需要先清理该项目下已有的 Issue 数据？如果这是首次插入或要全量替换，选"是"。

若用户选择清理，则你需要**动态查询目标数据库**来发现所有引用 `issues` 表的外键子表，
而不是依赖固定列表。方法如下：

1. 连接到用户指定的 Plane 数据库（使用第一步中确认的连接方式）
2. 执行以下查询获取所有引用 `issues` 表的子表及其外键：

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

3. 根据查询结果，生成从子表到父表（issues 最后）的 DELETE 语句
4. 此外还包括按 `project_id` 清理的项目级表（无直接外键但属于 Issue 关联数据）

> ⚠️ 子表数量和名称取决于具体的 Plane 版本和数据库状态，**必须动态查询，不可假设固定数量**。

### 第三步附：单 Issue 重置到初始状态

当需要将某张已插入的卡片恢复到插入时的初始状态时，**必须系统化清理所有关联表**，
不可凭记忆逐表手动删。

#### 步骤

1. **动态发现所有 FK 子表**（与第三步相同的方法）：

```sql
SELECT
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

2. **对查询结果中的每张子表**，执行 DELETE（注意 `issue_activities` 和 `issue_comments` 是最常见的遗漏项）：

```sql
DELETE FROM <child_table> WHERE issue_id = '<issue_uuid>';
```

3. **额外的关联表**（引用了 `issue_activities` 的子表）：

```sql
-- 查询 issue_activities 的子表
SELECT tc.table_name, kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu ON ...
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = 'issue_activities';

-- 清理
DELETE FROM <child_table> WHERE activity_id IN (
  SELECT id FROM issue_activities WHERE issue_id = '<issue_uuid>'
);
```

4. **重置 issue 自身状态**：将 `state_id` 恢复为插入时的初始值

5. **验证清单**——逐表确认计数：

```sql
SELECT 'issue_activities' AS tbl, COUNT(*) FROM issue_activities WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_comments', COUNT(*) FROM issue_comments WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_description_versions', COUNT(*) FROM issue_description_versions WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_versions', COUNT(*) FROM issue_versions WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_assignees', COUNT(*) FROM issue_assignees WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_labels', COUNT(*) FROM issue_labels WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_links', COUNT(*) FROM issue_links WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_subscribers', COUNT(*) FROM issue_subscribers WHERE issue_id = '<uuid>'
UNION ALL SELECT 'issue_reactions', COUNT(*) FROM issue_reactions WHERE issue_id = '<uuid>';
```

> ⚠️ 核心原则：**不凭记忆，只信 FK 查询结果。** 每次重置前先运行 FK 发现查询，
> 得到子表清单后再逐表清理，最后用验证 SQL 确认无误。

### 第四步：解析 State ID

> ⚠️ State ID 是项目级隔离的，不可硬编码或跨项目复用。

根据第一步中选择的获取方式：

- **自动查询**：连接数据库执行 `SELECT id, name FROM states WHERE project_id = '<project_id>'`，获取各 state 的实际 UUID
- **手动指定**：使用用户提供的 state ID 映射

将解析结果记录下来，供第五步生成 SQL 时使用。

### 第五步：生成 SQL 脚本

读取 `references/database-insert-spec.md` 获取完整 SQL 生成规则，按以下顺序生成：

1. **清理已有数据**（仅当用户第三步选择"是"时包含）— 使用动态查询到的子表列表
2. **获取项目级排他锁**
3. **计算 sequence_id 和 sort_order**
4. **插入 issues 表** — 每行一个完整的 INSERT
5. **插入 issue_sequences 表** — 每个 Issue 一条
6. **插入 issue_blockers 表** — 每对阻塞关系一条（自动解锁）
7. **插入 issue_relations 表** — 与 blockers 成对插入（UI 展示）
8. **插入 issue_labels 表** — 如果有标签
9. **插入 issue_activities 表** — 每个 Issue 一条 created 记录
10. **COMMIT**

关键规则：
- 所有 INSERT 在一个 `BEGIN`/`COMMIT` 事务中
- 每个 Issue 生成唯一 UUID v4
- `sort_order` 同 state 内递增（+10000, +20000...）
- `sequence_id` 使用 `pg_advisory_xact_lock` 原子递增
- `description_json` 填 `'{}'::jsonb`
- **`description_html` 和 `description_stripped` 必须填入源数据的完整原文，禁止压缩、摘要、截断或改写。只做 SQL 转义，不修改内容**
- `issue_activities.comment` 填 `''` 而非 NULL
- **每条阻塞关系必须同时写入 `issue_blockers` 和 `issue_relations`**

### 第六步：输出

输出三部分内容：

1. **完整 SQL 脚本** — 可直接复制到 `psql` 执行
2. **阻塞关系 ASCII 图** — 展示有向依赖关系
3. **验证 SQL** — 用于执行后验证数据正确性的查询语句

---

## 示例

用户输入：
```
在这个项目里创建 3 个 Issue：
- 数据库设计，被用户认证阻塞
- API 开发，被数据库设计阻塞
- 前端页面，被 API 开发阻塞
```

收集参数后生成的 SQL 脚本应形如：
```sql
BEGIN;

-- 清理已有数据 ...

-- 获取排他锁
SELECT pg_advisory_xact_lock(hashtextextended('<project_id>', 0));

-- Issues
INSERT INTO issues (...) VALUES (...);  -- CAMPUSSCHE-1: 用户认证
INSERT INTO issues (...) VALUES (...);  -- CAMPUSSCHE-2: 数据库设计
INSERT INTO issues (...) VALUES (...);  -- CAMPUSSCHE-3: API 开发
INSERT INTO issues (...) VALUES (...);  -- CAMPUSSCHE-4: 前端页面

-- Sequences
INSERT INTO issue_sequences (...) VALUES (...);
-- ...每个 Issue 一条

-- Blockers
INSERT INTO issue_blockers (...) VALUES (...);  -- CAMPUSSCHE-2 blocked by CAMPUSSCHE-1
INSERT INTO issue_blockers (...) VALUES (...);  -- CAMPUSSCHE-3 blocked by CAMPUSSCHE-2
INSERT INTO issue_blockers (...) VALUES (...);  -- CAMPUSSCHE-4 blocked by CAMPUSSCHE-3

-- Relations
INSERT INTO issue_relations (...) VALUES (...);  -- 与 blockers 成对

-- Activities
INSERT INTO issue_activities (...) VALUES (...);
-- ...每个 Issue 一条

COMMIT;
```

阻塞关系图：
```
CAMPUSSCHE-1 (用户认证)
    ↓
CAMPUSSCHE-2 (数据库设计)
    ↓
CAMPUSSCHE-3 (API开发)
    ↓
CAMPUSSCHE-4 (前端页面)
```

---

## State ID 获取

> ⚠️ State ID 是**项目级隔离**的——不同项目的同名 state 拥有不同的 UUID。
> **禁止硬编码或跨项目复用 state ID。** 必须在每次插入前获取目标项目的实际 state ID。

### 方式一：自动查询（推荐）

连接数据库执行：

```sql
SELECT id, name, "group" FROM states
WHERE project_id = '<project_id>'
ORDER BY name;
```

### 方式二：用户手动指定

若数据库不可达，请用户从 Plane 页面或数据库提供各 state 的 UUID。

---

> 完整的 SQL 生成规则（清理顺序、列映射、事务模板等）参见 `references/database-insert-spec.md`。
> 生成 SQL 前务必先读取该文件。
