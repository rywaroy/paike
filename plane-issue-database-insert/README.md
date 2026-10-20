# Plane Issue Database Insert

将带阻塞关系的多个 Issue 通过 SQL 直接写入 Plane.so PostgreSQL 数据库，
生成可执行的事务脚本。阻塞关系同时写入 `issue_blockers` 和 `issue_relations`，
确保自动解锁触发器与前端 UI 阻塞关系图同时正确工作。

## 触发方式

在对话中提到以下关键词即可触发此 skill：

- "插入 Plane Issue" / "批量创建 Issue"
- "写入 Plane 数据库" / "生成 Plane SQL"
- "Issue 阻塞关系" / "Plane 数据库插入"
- 需要在 Plane 项目中建立带依赖关系的任务

## 工作流

### 1. 收集参数

Skill 会询问以下参数（标 ✅ 的必须用户提供，其余有默认值可跳过）：

| 参数 | 必填 | 默认值 |
|------|:--:|--------|
| Plane 地址 | ✅ | — |
| project_id | ✅ | — |
| project_identifier | | `CAMPUSSCHE` |
| workspace_id | | `2265abc2-6f3f-4b9f-b474-bd53b8021efe` |
| 数据库连接方式 | | 容器内 (`plane-db`) |

### 2. 描述 Issue

用 YAML 或自然语言描述要创建的 Issue，包含名称、描述、优先级、状态、阻塞关系等：

```yaml
issues:
  - name: "[CS-P0-I01] 数据库设计"
    description: |
      ## 任务描述
      设计数据库 Schema。
    state: Backlog
    priority: high
    blocked_by: ["CS-P0-I00"]  # 被用户认证阻塞
```

### 3. 清理已有数据（独立操作）

清理已有数据是一个**独立的可选操作**，不与插入捆绑。
Skill 会询问用户是否需要先清理该项目下的已有 Issue。

如果需要清理，Skill 会**动态查询目标 Plane 数据库**来发现所有引用 `issues` 表的外键子表：

```sql
SELECT tc.table_name, kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu ...
WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'issues';
```

> 子表数量和名称取决于具体的 Plane 版本和数据库状态，**每次动态查询，不依赖硬编码列表**。

### 4. 生成 SQL

Skill 按以下顺序生成完整事务脚本：

1. 清理已有数据（仅当用户确认需要时 — 使用动态查询到的子表列表）
2. 获取项目级排他锁
3. 计算 sequence_id 和 sort_order
4. 插入 `issues` 表
5. 插入 `issue_sequences` 表
6. 插入 `issue_blockers` 表（自动解锁触发器）
7. 插入 `issue_relations` 表（前端 UI 展示）
8. 插入 `issue_labels` 表（可选）
9. 插入 `issue_activities` 表
10. COMMIT

### 5. 输出

- **完整 SQL 脚本** — 可直接复制到 `psql` 执行
- **阻塞关系 ASCII 图** — 展示 Issue 间的有向依赖
- **验证 SQL** — 执行后验证数据正确性

## 示例

**输入**：
```
在这个项目里创建 3 个 Issue：
- 数据库设计，被用户认证阻塞
- API 开发，被数据库设计阻塞
- 前端页面，被 API 开发阻塞
```

**输出 — 阻塞关系图**：
```
CAMPUSSCHE-1 (用户认证)
    ↓
CAMPUSSCHE-2 (数据库设计)
    ↓
CAMPUSSCHE-3 (API开发)
    ↓
CAMPUSSCHE-4 (前端页面)
```

## 关键规则

| 规则 | 说明 |
|------|------|
| 清理为独立操作 | 不在每次插入时自动执行，需用户确认；子表通过动态查询发现 |
| 双表阻塞 | 每条阻塞关系同时写入 `issue_blockers` 和 `issue_relations` |
| sort_order | 同 state 内以 10000 为步长递增 |
| sequence_id | 使用 `pg_advisory_xact_lock` 原子递增 |
| 事务性 | 所有 INSERT 在 `BEGIN`/`COMMIT` 中执行 |
| description_json | 固定填 `'{}'::jsonb` |
| activities.comment | 填 `''` 而非 NULL（NOT NULL 约束） |

## State 速查

| 状态 | state_id |
|------|----------|
| Backlog | `29fb489d-6646-4d23-a5ef-0744ccb94a4d` |
| Todo | `63d0a8c4-b987-4392-933a-d93fe0b94dc3` |
| In Progress | `867f8363-a4d1-4a27-8c30-bfea9b866c4f` |
| Merging | `48f133ae-2b53-4f82-afd0-43080477d57f` |
| Done | `43a77c53-2c92-45bf-8424-8f89a361232d` |
| Cancelled | `8b41cf15-5cba-423f-a2ec-7cfa528a94cd` |
| Triage | `7ce72da7-b067-4d7e-9a5f-c89b0902f597` |

## 文件结构

```
plane-issue-database-insert/
├── SKILL.md                              # 主工作流指令
├── README.md                             # 本文件
└── references/
    └── database-insert-spec.md           # 完整 SQL 生成规则参考
```

## 自动解锁机制

当阻塞方 Issue 状态变更为 Done 或 Cancelled 时，
PostgreSQL 触发器 `auto_unlock_issues_fn` 自动将下游 Issue 从 Backlog 移到 Todo，
并形成链式解锁。

| 表 | 用途 |
|----|------|
| `issue_blockers` | PostgreSQL 触发器监听，负责自动解锁 |
| `issue_relations` | Plane 前端读取，负责展示阻塞关系图 |
