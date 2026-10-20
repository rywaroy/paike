# Phase 3 契约摘要（p3-contracts.md）

> Phase 3 = 治理、身份与数据交换：governance（D07）、identity（D08）、exchange 应用模块（D09、D10），以及集成收口卡 INT-01~INT-03。
> `exchange` 是应用编排模块（不构成新的限界上下文），只通过各域查询服务与共享内核工作。

---

## 1. 产出卡片

| 卡片 | 范围 |
|------|------|
| D07 | 操作日志查询、学期存档、当前学期切换（含草稿守卫）、存档只读 |
| D08 | 用户 CRUD、角色分配、停用/启用、重置密码、教师一键开通账号、服务端权限边界 |
| D09 | 批量导入（学期/年级/班级/科目/教师/任课/场地）、错误报告、导入批次 |
| D10 | 全维度 Excel 导出、打印模板、服务端 PDF 预览/打印 |
| INT-01 | 端到端集成收口（七类确认、跨域引用保护、并发、权限、D15 全链路） |
| INT-02 | 契约冻结归档与发布基线 |
| INT-03 | 运行态刷新与交付状态确认 |

---

## 2. 表结构

### 2.1 governance

```sql
CREATE TYPE operation_module AS ENUM (
  'DELETE','PUBLISH','OVERWRITE','SWITCH_SEMESTER','IMPORT','ARCHIVE','ADJUST'
);

operation_log (
  log_id uuid pk,
  operator_id uuid not null,
  operator_name text not null,        -- 快照，用户改名后仍可追溯
  module operation_module not null,
  action text not null,               -- 中文动作，如「发布」「覆盖发布」
  content text not null,              -- 中文、可直接展示
  target_type text not null,
  target_id uuid,
  request_id text,
  created_at timestamptz not null default now()
);
-- 追加写：无 UPDATE/DELETE API，无清理任务（A-20）

semester_archive (
  archive_id uuid pk,
  semester_id uuid not null unique,
  plan_id uuid not null,              -- 存档时的正式方案
  archived_by uuid not null,
  archived_at timestamptz not null,
  summary jsonb not null,             -- { planName, classCount, lessonCount, conflictCount }
  created_at
);
```

### 2.2 identity

```sql
-- 复用 Phase 0 的 sys_user；无新增表
-- 约束：username 唯一（大小写不敏感）、teacher_id 唯一（非空时一对一）
CREATE UNIQUE INDEX uq_sys_user_teacher ON sys_user (teacher_id) WHERE teacher_id IS NOT NULL;
CREATE UNIQUE INDEX uq_sys_user_username_lower ON sys_user (lower(username));
```

### 2.3 exchange（应用模块支撑表）

```sql
CREATE TYPE import_status AS ENUM ('COMPLETED','PARTIAL','FAILED');

import_batch (
  batch_id uuid pk,
  module text not null,
  filename text not null,
  size_bytes int not null,
  total int not null,
  success int not null,
  failed int not null,
  status import_status not null,
  errors jsonb not null default '[]', -- 最多保留 1000 条明细
  operator_id uuid not null,
  operator_name text not null,
  created_at
);

CREATE TYPE paper_size AS ENUM ('A4','A3');
CREATE TYPE paper_orientation AS ENUM ('PORTRAIT','LANDSCAPE');

print_template (
  template_id uuid pk,
  name text not null unique,
  paper_size paper_size not null default 'A4',
  orientation paper_orientation not null default 'LANDSCAPE',
  margin_mm jsonb not null,           -- { top, right, bottom, left }
  title text,
  logo_data_uri text,                 -- PNG ≤2 MB
  header_text text,
  footer_text text,
  is_preset boolean not null default false,
  version int not null default 0,
  created_at, updated_at, deleted_at
);
```

> 导出文件不落库；导出不属七类关键操作，只写安全审计 `sys_audit_log`，不写 `operation_log`。

---

## 3. API

### 3.1 治理（D07）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/operation-logs?operatorId=&from=&to=&module=&page=&pageSize=` | 日志查询，按时间倒序 |
| GET | `/operation-logs/:logId` | 详情 |
| POST | `/semesters/:id/archive` | 学期存档 |
| GET | `/semesters/:id/archive` | 存档信息 |
| POST | `/semesters/:id/switch` | 切换当前学期（含草稿守卫） |
| GET | `/archive-status?semesterId=` | 存档前置检查（是否有 PUBLISHED） |

**存档**

请求：`{ "confirm": true }`（前端已完成二次确认）

前置：当前学期存在 `PUBLISHED` 方案；否则 `409 STATE_CONFLICT`，提示「请先发布正式课表再存档」。

事务内：学期 `→ ARCHIVED`；当前 `PUBLISHED` 方案 `→ ARCHIVED`；写 `semester_archive`；写操作日志；追加 `bc.timetable.plan.archived` 与 `bc.registry.semester.status-changed`。

**切换学期**

请求：

```json
{ "draftResolution": "SAVE", "planVersion": 12 }
```

`draftResolution ∈ SAVE / DISCARD / CANCEL`。

| 场景 | 行为 |
|------|------|
| 当前学期无草稿 | 直接切换，忽略该字段 |
| 有草稿且 `SAVE` | 保存草稿（校验 `planVersion`）后切换 |
| 有草稿且 `DISCARD` | 丢弃未保存编辑；从未保存的草稿删除；切换 |
| 有草稿且 `CANCEL` | 不切换、不写任何数据，返回 `200` |
| 有草稿但未传字段 | `409 DRAFT_EXISTS`，`details` 返回草稿 id/名称，前端弹三选一 |

切换成功后更新 `semester.is_current`（同一事务内先清旧值）；写日志；追加状态事件。目标学期为 `ARCHIVED` 时拒绝。

**日志规则**

- 只追加，无更新/删除 API，无自动清理任务。
- `content` 必须中文可读，例如「发布 2026 秋季正式课表（方案 2026秋-v4）」。
- 按操作人、时间范围、模块筛选；空结果给出友好空状态。

### 3.2 身份（D08）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/users?role=&status=&keyword=&page=` | 用户列表 |
| GET | `/users/:userId` | 详情 |
| POST | `/users` | 新建用户 |
| PATCH | `/users/:userId` | 编辑姓名（`version`） |
| PATCH | `/users/:userId/role` | 分配角色（`version`） |
| POST | `/users/:userId/disable` | 停用（撤销会话） |
| POST | `/users/:userId/enable` | 启用 |
| POST | `/users/:userId/reset-password` | 重置为随机密码（一次性返回） |
| POST | `/teachers/:teacherId/provision-account` | 一键开通 Teacher 账号 |
| POST | `/teachers/provision-accounts/batch` | 批量开通，返回一次性凭据 CSV |

规则：

1. `username` 全局唯一（大小写不敏感）；教师账号 `username = employeeNo`；`teacherId` 一对一。
2. `role=TEACHER` 必须提供 `teacherId`；`role=ADMIN` 必须为空。该约束由数据库检查约束与服务端双重保证。
3. 重复开通幂等：返回既有账号并标记 `alreadyExists=true`，不新增。
4. 初始密码随机 ≥12 位，仅响应中返回一次；`must_change_password=true`；不写日志明文。
5. 角色仅 `ADMIN` / `TEACHER`；每次请求从数据库读取角色（A-18）。
6. 不允许停用/降级最后一个启用中的 Admin；不允许停用自己。
7. 停用账号立即撤销其全部会话；角色变更在下一请求生效。
8. 所有账号操作写安全审计；教师退校事件联动停用账号（M-22），复职不自动启用。

**新建用户请求**

```json
{ "username": "T1003", "displayName": "王老师", "role": "TEACHER", "teacherId": "uuid" }
```

### 3.3 导入（D09）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/import/templates/:module` | 下载固定模板（XLSX） |
| POST | `/import/:module/preview` | 解析并返回前 20 行 + 表头校验结果，不写库 |
| POST | `/import/:module` | 上传并执行（multipart，≤20 MB） |
| GET | `/import/batches/:batchId` | 批次结果 |
| GET | `/import/batches/:batchId/errors` | 错误报告 CSV（UTF-8 BOM，一次性） |

`module ∈ SEMESTERS / GRADES / CLASSES / SUBJECTS / TEACHERS / ASSIGNMENTS / VENUES`。

规则（A-07 / H-04）：

- XLSX 为主，接受 UTF-8 CSV；不接受 GBK。
- 首行表头，按列名匹配，顺序可变；未知列忽略并在报告中提示。
- 数据行 >5000 或文件 >20 MB → 整份拒绝，零写入，返回行数与上限。
- 必填列缺失 → 整份拒绝。
- ≤5000 行：逐行校验，合法行提交，非法行跳过；重复键按非法行处理，不做 upsert。
- 数据库故障 → 整批回滚，批次状态 `FAILED`。
- 结果返回 `total/success/failed/status/errors/errorReportUrl`；错误含行号、列名、原值、中文原因。
- 导入提交属七类关键操作，前端二次确认后调用；写 `operation_log`（module=`IMPORT`）。

### 3.4 导出（D10）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/exports/options` | 可用维度、学期、列字典 |
| POST | `/exports` | 生成并直接返回文件（`application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`） |
| GET | `/exports/columns?dimension=` | 列名与顺序 |

请求：

```json
{
  "dimension": "TIMETABLE",
  "semesterId": "uuid",
  "timetableDimension": "CLASS",
  "objectIds": ["uuid"],
  "parity": "ALL"
}
```

维度：

| dimension | sheet |
|-----------|-------|
| `MASTER_DATA` | 学期、年级、班级、科目、教师、任课、场地、合班（按实体分 sheet） |
| `TIMETABLE` | 按视图分 sheet（班级/教师/全校/场地/任课） |
| `STATISTICS` | 工作量统计 |

规则（H-04）：

- XLSX；只导出值；日期 `YYYY-MM-DD`，时间 `HH:mm`；空值为空单元格；冻结表头。
- 列名/顺序来自 `COLUMN_DICTIONARY`，与页面逐字段一致。
- 文件名 `{维度}_{学期}_{YYYYMMDDHHmm}.xlsx`。
- 1000 行 × 12 列，服务端生成并落盘 p95 ≤3 秒（H-03）。
- 导出操作写安全审计（非七类关键操作，不要求二次确认）。

### 3.5 打印（D10）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/print-templates` | 模板列表 |
| POST | `/print-templates` | 新建模板 |
| PATCH | `/print-templates/:id` | 编辑（`version`） |
| DELETE | `/print-templates/:id` | 逻辑删除（预设模板不可删） |
| POST | `/print-templates/:id/logo` | 上传 PNG ≤2 MB |
| POST | `/print/preview` | 返回 PDF（`application/pdf`），用于预览 |
| POST | `/print/render` | 返回同一 PDF，用于下载/打印 |

请求：

```json
{
  "templateId": "uuid",
  "dimension": "CLASS",
  "objectId": "uuid",
  "semesterId": "uuid",
  "parity": "ALL"
}
```

规则：

- 预览与打印调用同一 HTML 模板与同一 `renderPdf`，输出同一份 PDF（H-04）。
- 纸张 A4/A3、横/纵向、边距可配；校徽 PNG ≤2 MB，以 data URI 内嵌。
- 打印页通过一次性签名 token 访问受保护 HTML，有效期 60 秒。
- 打印任务写安全审计。

---

## 4. 领域事件

| 事件 | 生产者 | 消费者 |
|------|--------|--------|
| `bc.registry.semester.status-changed` | D07（调用 registry 生命周期服务） | timetable、governance |
| `bc.timetable.plan.archived` | D07 | governance、registry |
| `bc.governance.operation.logged` | D07 | — |
| `bc.identity.user.created` | D08 | — |
| `bc.identity.user.disabled` | D08 | — |
| `bc.identity.user.role-changed` | D08 | — |
| `bc.resource.teacher.account-provisioned` | D08 | resource |
| `bc.exchange.import.completed` | D09 | governance |
| `bc.exchange.export.completed` | D10 | governance |
| `bc.exchange.print.rendered` | D10 | governance |

---

## 5. 前端路由

| 路由 | 页面 | 卡片 | 角色 |
|------|------|------|------|
| `/logs` | 操作日志 | D07 | Admin |
| `/archive` | 多学期存档与切换 | D07 | Admin |
| `/import` | 批量导入 | D09 | Admin |
| `/export` | Excel 导出 | D10 | Admin |
| `/print` | 模板打印 | D10 | Admin |
| `/users` | 用户与角色 | D08 | Admin |

---

## 6. 跨域事务边界

| 用例 | 事务边界 |
|------|----------|
| 学期存档 | 一个事务：semester 状态 + plan 状态 + archive 记录 + operation_log + outbox |
| 切换学期 | 一个事务：草稿保存（可选）+ is_current 切换 + operation_log + outbox |
| 导入单行 | 每行独立保存；整批记录在批次事务中更新；基础设施失败整批回滚 |
| 教师开通账号 | 一个事务：sys_user 插入 + teacher 关联 + 安全审计 + outbox |
| 删除保护 | 先查询引用（各域 query-service），再在同一事务内逻辑删除 |

> 跨域只调用对方导出的应用服务或查询服务；禁止直接写对方表。

---

## 7. 集成收口（INT-01）

INT-01 不新增业务能力，只做跨卡验收：

1. **七类二次确认**：删除类、发布、覆盖方案、切换学期、批量导入提交、学期存档、调课保存，逐一验证「未确认零变更、确认后生效」。
2. **跨域引用保护**：模板被学期钉扎、教师有任课/班主任/账号、科目有任课、场地被课次占用、年级有班级时删除均被拒绝并提示引用关系。
3. **并发**：同一方案两个并发保存，先提交成功，后提交 409 且零写入；主数据单记录同样。
4. **权限**：Teacher 对全部管理 API 返回 403；五视图/空闲查询的本人范围；角色变更下一请求生效。
5. **D15 全链路**：从主数据 → 生成 → 发布 → 五视图 → 导出，逐格一致。
6. **学期隔离**：切换学期后列表、课表、统计、日志无串扰。
7. **存档只读**：存档后全部写接口 409，查看与导出可用。
8. **日志一致性**：关键操作次数与日志条数一一对应。

---

## 8. 完成判定

- 存档前置、覆盖发布、草稿守卫均有接口测试与前端二次确认。
- 日志无删除路径，跨重启可查询；导出/打印可复现。
- 导入超限零写入；部分成功行级错误可下载。
- 所有错误返回中文 `code + message`，前端展示「发生了什么 + 怎么办」。
- INT-01 清单全项有可执行验证脚本（本轮只设计，不运行）。

---

## 9. 冻结与状态刷新（INT-02 / INT-03）

**INT-02 冻结归档**

- 产出 `contracts/` 六件套最终版并校验 OpenAPI。
- 记录 `docs/trace/runs/v1/spac.md`、`agent_plane.md`、`issues.yaml` 的最终版本号。
- 标签命名：`v1.0-design-freeze`（本轮不创建，仅登记）。
- 归档输入快照哈希（PRD、原型、DDD、测试文档），写入 `docs/memory/2026-10-19.md`。

**INT-03 状态刷新**

- 刷新 `README.md` 的「本轮状态」与文档索引。
- 核对 `issues.yaml` 卡片状态全部为 `design`，无 `in_progress`。
- 核对每张卡的 `test-results/{card-id}.md` 存在且执行状态均为「未执行」。
- 输出最终交付清单与偏差说明（子技能未安装等）。
