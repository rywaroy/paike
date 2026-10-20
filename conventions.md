# 跨卡片共享技术约定（conventions.md）

> 本文件是全部开发卡片的**强制技术约定**。每张卡片执行时必须以本文件为准；卡片内与本文件冲突的表述视为卡片缺陷。
>
> 适用轮次：v1（首轮）。维护者：架构设计卡 P0-06（契约冻结）与各领域卡；状态刷新卡 INT-03 负责回写实际实现。

---

## 1. 命名约定

### 1.1 文件与目录

| 对象 | 规则 | 示例 |
|------|------|------|
| 后端模块目录 | 小写复数或上下文名 | `modules/registry/` |
| 后端分层文件 | `<聚合或用例>.<layer>.ts` | `semester.service.ts`、`semester.repository.ts` |
| 前端视图 | PascalCase + `View.vue` | `SemesterListView.vue` |
| 前端组件 | PascalCase | `ConfirmDialog.vue` |
| 共享工具 | kebab-case | `idle-slot.ts` |
| 测试文件 | 与被测文件同名 + `.test.ts` | `conflict.service.test.ts` |
| 迁移文件 | `NNNN_snake_case.sql`，四位序号 | `0012_create_timetable_plan.sql` |

### 1.2 数据库

| 对象 | 规则 | 示例 |
|------|------|------|
| 表 | 小写 snake_case，单数 | `timetable_plan` |
| 主键 | `<实体>_id` | `semester_id` |
| 外键 | 引用表主键同名 | `semester_id` |
| 布尔 | `is_` / `has_` / `_enabled` | `is_locked` |
| 时间戳 | `_at` 后缀，`timestamptz` | `created_at` |
| 软删除 | `deleted_at timestamptz NULL` | — |
| 乐观版本 | `version integer NOT NULL DEFAULT 1` | — |
| 索引 | `idx_<table>_<columns>` | `idx_lesson_plan_weekday_period` |
| 唯一约束 | `uq_<table>_<columns>` | `uq_semester_published` |
| 枚举 | PostgreSQL 原生 enum，`<domain>_<name>` | `semester_status` |

### 1.3 API

| 对象 | 规则 | 示例 |
|------|------|------|
| 基础路径 | `/api/v1` | — |
| 资源 | 复数、kebab-case | `/combined-classes` |
| 子资源 | 两级以内 | `/plans/:planId/lessons` |
| 动作端点 | `POST /资源/:id/动作` | `/plans/:id/publish` |
| 查询参数 | camelCase | `?weekParity=ODD` |
| 请求/响应字段 | camelCase | `scheduleTemplateVersionId` |

### 1.4 事件

| 对象 | 规则 | 示例 |
|------|------|------|
| 领域事件 | `bc.<context>.<entity>.<past-tense>` | `bc.registry.semester.created` |
| 事件负载 | camelCase，含 `eventId` / `occurredAt` / `occurredBy` | — |
| 事件版本 | `schemaVersion: 1` | — |

### 1.5 代码标识符

- TypeScript：变量/函数 camelCase，类型/接口 PascalCase，常量 UPPER_SNAKE_CASE。
- 禁止拼音缩写（`bj`、`js`）；领域词使用英文标准译名（见 §13）。
- 用户可见文案一律中文，不得直接把枚举值、字段名、错误码展示给用户。

---

## 2. 目录结构与模块边界

### 2.1 后端模块内部分层

```
modules/<context>/
  <context>.router.ts       # 路由注册（仅装配，无业务逻辑）
  <context>.controller.ts   # HTTP 解析/响应
  <aggregate>.service.ts    # 应用服务（事务边界、编排）
  <aggregate>.repository.ts # 仓储（SQL）
  <aggregate>.domain.ts     # 领域实体/值对象/不变量
  <aggregate>.mapper.ts     # DB 行 ↔ 领域对象
  dto/                      # Zod schema + 类型
  events/                   # 本域发布的领域事件
```

### 2.2 边界规则

1. **跨域只经应用服务或事件**：不得直接 import 其他域的 repository / domain。
2. **跨域读数据**：通过对方暴露的查询服务（`XxxQueryService`），不得直连对方表。
3. **共享内核只读复用**：`shared/` 不依赖任何 `modules/`。
4. **前端按域分目录**：`views/<context>/`，跨域组件放 `shared/components/`。
5. **Hub 文件约定式扫描**：`backend/src/modules/index.ts` 与 `frontend/src/router/index.ts` 通过 glob 扫描 `*.router.ts` / `routes.ts` 自动装配，禁止逐域手工追加。

### 2.3 事务

- 一个应用服务方法 = 一个数据库事务（`withTransaction`）。
- 领域事件写入 `sys_outbox_event` 与业务写入同事务；提交后由 dispatcher 投递。
- 调课保存、发布、覆盖、存档必须同时写业务数据与 `operation_log`，同一事务。

---

## 3. API 契约约定

### 3.1 响应封装

成功：

```json
{ "data": { "...": "..." } }
```

列表：

```json
{
  "data": {
    "items": [],
    "page": 1,
    "pageSize": 20,
    "total": 0
  }
}
```

失败：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "保存失败，请检查输入内容",
    "details": [
      { "field": "serialNo", "message": "班级序号必须是 1-99 的整数" }
    ],
    "requestId": "..."
  }
}
```

### 3.2 错误码

| HTTP | code | 用户文案（默认） | 何时使用 |
|------|------|------------------|----------|
| 400 | `VALIDATION_ERROR` | 保存失败，请检查输入内容 | 字段校验失败 |
| 401 | `UNAUTHENTICATED` | 登录已失效，请重新登录 | 无会话/会话过期 |
| 403 | `FORBIDDEN` | 您没有权限执行此操作 | 角色/数据范围不允许 |
| 404 | `NOT_FOUND` | 未找到该数据，可能已被删除 | 资源不存在 |
| 409 | `VERSION_CONFLICT` | 数据已被他人修改，请刷新后重试 | 乐观锁失败 |
| 409 | `DUPLICATE` | 该名称已存在，请更换后重试 | 唯一键冲突 |
| 409 | `REFERENCE_PROTECTED` | 该数据正被使用，暂时无法删除 | 引用保护 |
| 409 | `STATE_CONFLICT` | 当前状态不允许此操作 | 状态机守卫 |
| 413 | `FILE_TOO_LARGE` | 文件超过 20 MB，请拆分后重试 | 上传超限 |
| 422 | `IMPORT_ROW_ERROR` | 文件中有无法导入的行 | 导入部分失败 |
| 423 | `ACCOUNT_LOCKED` | 登录失败次数过多，请 15 分钟后再试 | 账号锁定 |
| 500 | `INTERNAL_ERROR` | 系统暂时不可用，请稍后重试 | 未预期异常 |

> 错误码只用于程序判断；界面展示 `message`，不得直接展示 `code`。

### 3.3 鉴权与 CSRF

- 所有 `/api/v1/**`（除 `/auth/login`、`/auth/csrf`、健康检查）要求有效会话。
- 所有非 GET 请求要求 `X-CSRF-Token`，与 `csrf` Cookie 双提交校验。
- 会话 Cookie 名 `paike.sid`；`HttpOnly`、`SameSite=Lax`、生产 `Secure`。
- 每个请求从数据库/会话存储读取当前用户角色与状态；停用账号立即拒绝。

### 3.4 并发

- 所有可编辑聚合带 `version`。
- 更新请求必须携带读取时的 `version`；服务端 `UPDATE ... WHERE id = $1 AND version = $2`。
- 影响行数为 0 → `409 VERSION_CONFLICT`，不写入任何数据、不写业务日志。
- 批量操作逐条校验；任一失败整批回滚并返回失败明细。

### 3.5 分页、筛选、排序

- `page` 从 1 开始，`pageSize` 默认 20，最大 100。
- 排序参数 `sort=field:asc|desc`，只允许白名单字段。
- 列表默认按业务顺序：学期按开始日期倒序；日志按时间倒序；课次按星期、节次升序。

---

## 4. 数据库约定

### 4.1 主键与时间

- 主键统一 `uuid`，由应用层生成（`crypto.randomUUID()`），便于测试固定锚点。
- 所有表含 `created_at timestamptz NOT NULL DEFAULT now()`、`updated_at timestamptz NOT NULL DEFAULT now()`。
- `updated_at` 由触发器 `set_updated_at()` 自动维护。
- 业务日期使用 `date`；时刻使用 `timestamptz`；周次/节次使用 `smallint`。

### 4.2 软删除与引用保护

- 主数据表使用 `deleted_at` 逻辑删除；查询默认过滤 `deleted_at IS NULL`。
- 删除前必须显式检查引用：
  - 作息模板版本被学期引用 → 拒绝（`REFERENCE_PROTECTED`）。
  - 教师存在任课/合班/班主任引用 → 拒绝。
  - 科目存在任课/合班引用 → 拒绝。
  - 场地存在课次/合班引用 → 拒绝。
  - 年级存在班级引用 → 拒绝。
- 已存档学期的数据一律不参与删除判定，且逻辑删除不影响存档快照。
- 学期物理删除仅允许「未开始且无任何业务数据」的学期；其余走逻辑删除。

### 4.3 唯一约束

| 约束 | 说明 |
|------|------|
| `sys_user.username` | 登录名唯一（=工号或 admin） |
| `teacher.employee_no` | 工号唯一（未删除记录） |
| `grade.name` | 年级名唯一（未删除记录） |
| `subject.name` | 科目名唯一（未删除记录） |
| `venue.name` | 场地名唯一（未删除记录） |
| `class (grade_id, serial_no)` | 同年级序号唯一 |
| `schedule_template.name` | 模板名唯一 |
| 每学期唯一 Published 方案 | 部分唯一索引 `WHERE status = 'PUBLISHED'` |

### 4.4 JSONB 使用

- `periods`（节次时间表）、`forbidden_slots`（禁排时段）、`exempted_slots`（免排时段）使用 `jsonb`。
- JSON 结构必须在 `docs/knowledge/shared-kernel-api.md` §时段表达式中定义，写入前由 Zod 校验。
- 禁止把可查询的业务字段塞进 JSONB。

### 4.5 迁移

- 迁移只追加，不修改已执行文件。
- 每个领域卡新增自己的迁移文件，序号在卡片中显式声明，避免冲突。
- 迁移必须可重复执行于空库；禁止依赖手工步骤。

---

## 5. 领域与状态约定

### 5.1 聚合与事务边界

| 上下文 | 聚合 | 事务边界 |
|--------|------|----------|
| bc-registry | Semester / ScheduleTemplate / Grade / Class / Subject | 单聚合 |
| bc-resource | Teacher / Venue / CombinedClass / WalkingGroup / TeachingAssignment | 单聚合 |
| bc-timetable | TimetablePlan（含 Lesson / UnscheduledLesson / ConflictDetail / AdjustmentHistory） | 方案级 |
| bc-governance | OperationLog / SemesterArchive | 追加写 |
| bc-identity | Account（共享表 `sys_user`） | 单账号 |

### 5.2 状态机

**TimetablePlan**

```
DRAFT ──publish──▶ PUBLISHED ──publish(new)──▶ SUPERSEDED
  │                     │
  │                     └──archive──▶ ARCHIVED
  └──discard/delete（仅 DRAFT）
```

- 每学期至多一个 `PUBLISHED`。
- 发布新方案时，旧 `PUBLISHED` 变 `SUPERSEDED`，同事务完成。
- `ARCHIVED` 只读，不可再变更。

**LessonLock**

```
UNLOCKED ⇄ LOCKED
```

- 自动排课保留 `LOCKED` 课次。
- 拖拽/微调拒绝移动 `LOCKED` 课次。

**Semester**

```
NOT_STARTED → IN_PROGRESS → ENDED → ARCHIVED
```

- 允许管理员手动推进；`ARCHIVED` 为终态。
- 存档前置：存在 `PUBLISHED` 方案。

**Account**

```
ENABLED ⇄ DISABLED
```

- `DISABLED` 会话下一请求被拒绝。
- 删除教师不删除账号，账号置 `DISABLED`。

### 5.3 时间与周次

- 周首固定**周一**；`weekday` 取值 1-7（1=周一，7=周日）。
- 第 1 教学周 = 学期 `start_date` 所在自然周（周一对齐）。
- 停课周占用周序号，奇偶继续推进。
- 单周 = 周序号奇数；双周 = 偶数。
- `weekParity` ∈ `ALL | ODD | EVEN`；`ALL` 表示每周都上。
- 所有日期以学校本地时区（`Asia/Shanghai`）解释；服务端存储 `timestamptz`。

### 5.4 冲突

三类核心冲突，零容忍：

| type | 判定 |
|------|------|
| `TEACHER_OVERLAP` | 同一教师同一 `(weekday, period, weekParity)` 出现两节课（奇偶交集非空即冲突） |
| `CLASS_OVERLAP` | 同一班级同一 `(weekday, period, weekParity)` 出现两节课 |
| `VENUE_OVERLAP` | 同一场地同一 `(weekday, period, weekParity)` 出现两节课 |
| `CAPACITY_EXCEEDED` | 班级人数超过场地容量 |
| `LOCKED_VIOLATION` | 试图移动或覆盖已锁定课次 |
| `RULE_VIOLATION` | 违反教师免排/禁排、科目禁排、固定时段等可配置规则 |

- 合班/走班按「排课单元」参与判定：单元内班级两两不互斥，但与单元外课程互斥。
- 「只本次忽略」不改变任何配置，只写 `conflict_ignore` 审计记录；下次生成仍会再次报告。
- 冲突处理状态 `conflict_resolution` ∈ `UNRESOLVED | IGNORED_ONCE | CONFIG_CHANGED | RESOLVED`；只有 `UNRESOLVED` 计入发布阻断数。

---

## 6. 前端约定

### 6.1 路由与守卫

- 路由元信息 `meta.roles: ['ADMIN']` 或 `['ADMIN','TEACHER']`。
- 全局前置守卫：未登录 → `/login?redirect=...`；角色不符 → `/403`。
- 教师登录后默认落地 `/me/timetable`。
- 强制改密期间仅允许 `/change-password` 与 `/logout`。

### 6.2 状态管理

- Pinia store 按域拆分：`useSessionStore`、`useSemesterStore`、`useTimetableStore`。
- 服务端数据不长期驻留 store；页面级数据由组合式函数 `useXxx()` 拉取。
- 学期上下文（当前学期）放 `useSemesterStore`，切换后广播 `semester-changed` 事件，所有列表重新拉取。

### 6.3 API 客户端

- `shared/api/http.ts` 统一处理：CSRF、401 跳转、409 冲突提示、错误 message 提取。
- 禁止在组件中直接 `fetch`；必须经 `shared/api/<domain>.api.ts`。
- 所有写请求成功后刷新相关查询，不做乐观更新（V1.0 以一致性优先）。

### 6.4 交互与文案

- 所有按钮使用动词短语：「保存学期」「发布课表」「确认调课」，禁止「提交」「确定」单独出现。
- 危险操作按钮使用红色，并在二次确认中说明**影响范围**与**是否可撤销**。
- 二次确认对话框必须包含：操作名称、对象、影响、取消/确认按钮；确认按钮文案与操作一致（如「确认发布」）。
- 空状态必须说明原因与下一步：「还没有学期，点击『新增学期』开始配置」。
- 加载态：超过 300ms 显示骨架屏/加载文案；排课显示「正在为 48 个班级安排课程，预计 5 秒内完成」。
- 错误提示：说明「发生了什么 + 怎么办」，不显示堆栈、错误码、SQL。
- 表单校验：字段下方就地提示；保存失败聚焦第一个错误字段。
- 键盘可达：所有操作可 Tab 到达；对话框焦点陷阱；Esc 关闭。
- 颜色不作为唯一信息载体：冲突同时有图标 + 文案 + 颜色。

### 6.5 教师端

- 导航仅保留「我的课表」「我的空闲时段」「退出登录」。
- 不显示任何管理入口；即使手工输入 URL，服务端与前端守卫均拒绝。
- 课表只显示本人课程与本人关联班级课程。

---

## 7. 审计与日志约定

### 7.1 业务操作日志（`operation_log`）

七类关键操作必须留痕：

| 模块值 | 触发 |
|--------|------|
| `DELETE` | 删除类操作 |
| `PUBLISH` | 发布方案 |
| `OVERWRITE` | 覆盖正式课表 |
| `SWITCH_SEMESTER` | 切换当前学期 |
| `IMPORT` | 批量导入提交 |
| `ARCHIVE` | 学期存档 |
| `ADJUST` | 调课保存 |

字段：`operator_id`、`operator_name`、`module`、`action`、`content`（中文可读）、`target_type`、`target_id`、`occurred_at`。

- 追加写，无更新/删除 API。
- 日志写入与业务写入同事务。
- 日志查询仅 Admin。

### 7.2 安全审计（`sys_audit_log`）

记录：登录成功/失败、锁定、退出、改密、账号启停、角色变更、越权尝试。字段含 `actor_id`、`action`、`ip`、`user_agent`、`result`、`occurred_at`。

### 7.3 应用日志

- Pino JSON；不记录密码、Cookie、CSRF Token、完整手机号（脱敏为 `138****1234`）。
- 每个请求带 `requestId`，响应头 `X-Request-Id`。

---

## 8. 导入导出与打印约定

### 8.1 导入

- 格式：XLSX 为主；UTF-8 CSV（含/不含 BOM）；不接受 GBK。
- 上限：5000 数据行且文件 ≤20 MB；超限整份拒绝、零写入。
- 表头首行，按列名匹配，顺序可变；未知列忽略并在报告中提示。
- 重复键按非法行处理，不做 upsert。
- 部分成功：合法行入库，非法行跳过；返回总数/成功/失败；错误报告 CSV（行号、列名、原值、原因）。
- 数据库故障整批回滚。

### 8.2 导出

- XLSX；一个工作簿按维度分 sheet；只导出值；日期 `YYYY-MM-DD`，时间 `HH:mm`；空值为空单元格；冻结表头。
- 文件名：`{维度}_{学期}_{YYYYMMDDHHmm}.xlsx`。
- 字段名、顺序、取值与页面逐字段一致；列字典由 `docs/knowledge/shared-kernel-api.md` §导出字段字典维护。

### 8.3 打印

- 服务端 Playwright 渲染 HTML/CSS → PDF；预览与打印为同一 PDF。
- 纸张 A4/A3、横/纵向；校徽 PNG ≤2 MB。
- 模板存 `print_template` 表；预览接口返回 PDF 流。

---

## 9. 测试与验证约定

1. **测试分层**：领域单测（Vitest）→ 应用/接口测试（Supertest + 真实 PostgreSQL）→ E2E（Playwright）。
2. **D15 是引擎第一基准**：任何引擎改动必须先通过 `TC-AP-017` 逐格断言。
3. **测试数据**：使用 `seed-anchors.sql` 的固定 UUID；测试内不得依赖自增 ID 或当前时间。
4. **时间注入**：所有「当前时间」经 `Clock` 接口注入，测试使用固定时钟。
5. **随机种子**：排课引擎接受 `seed` 参数；同一输入 + 同一 seed 必须产出同一课表。
6. **不静默跳过**：测试不得 `skip` 后计为通过；未执行一律标记「未执行」。
7. **性能**：按 H-03 固定数据集、4 vCPU/8GB、预热 1 次、5 次 p95。
8. **测试与卡片对应**：每张卡片的 `## 测试案例对比验证` 与 `docs/trace/runs/v1/test-results/<card-id>.md` 必须一致；不得声称执行过未执行的测试。

---

## 10. 枚举值速查表

> §13 对应本表；所有枚举在数据库、API、前端三处拼写完全一致。

### 10.1 身份与权限

| 枚举 | 值 | 中文 |
|------|----|------|
| `user_role` | `ADMIN` / `TEACHER` | 管理员 / 教师 |
| `account_status` | `ENABLED` / `DISABLED` | 启用 / 停用 |
| `gender` | `MALE` / `FEMALE` / `UNSPECIFIED` | 男 / 女 / 未填写 |

### 10.2 学期与作息

| 枚举 | 值 | 中文 |
|------|----|------|
| `semester_status` | `NOT_STARTED` / `IN_PROGRESS` / `ENDED` / `ARCHIVED` | 未开始 / 进行中 / 已结束 / 已存档 |
| `term` | `FALL` / `SPRING` | 秋季学期 / 春季学期 |
| `template_status` | `ACTIVE` / `RETIRED` | 启用 / 停用 |
| `calendar_exception_type` | `STOP` / `MAKEUP` | 停课 / 调休上课 |

### 10.3 主数据

| 枚举 | 值 | 中文 |
|------|----|------|
| `teacher_status` | `ACTIVE` / `LEFT` | 在职 / 退校 |
| `venue_type` | `CLASSROOM` / `FUNCTION_ROOM` | 教室 / 功能室 |
| `venue_status` | `AVAILABLE` / `UNAVAILABLE` | 可用 / 不可用 |
| `consecutive_preference` | `NONE` / `PREFERRED` / `REQUIRED` | 无偏好 / 尽量连堂 / 必须连堂 |
| `time_slot_preference` | `NONE` / `MORNING` / `AFTERNOON` | 无 / 上午优先 / 下午优先 |

### 10.4 排课

| 枚举 | 值 | 中文 |
|------|----|------|
| `plan_status` | `DRAFT` / `PUBLISHED` / `SUPERSEDED` / `ARCHIVED` | 草稿 / 正式课表 / 已被覆盖 / 已存档 |
| `week_parity` | `ALL` / `ODD` / `EVEN` | 每周 / 单周 / 双周 |
| `scheduling_unit_type` | `ASSIGNMENT` / `COMBINED_CLASS` / `WALKING_GROUP` | 常规任课 / 合班 / 走班 |
| `conflict_type` | `TEACHER_OVERLAP` / `CLASS_OVERLAP` / `VENUE_OVERLAP` / `CAPACITY_EXCEEDED` / `LOCKED_VIOLATION` / `RULE_VIOLATION` | 教师时间冲突 / 班级同节多课 / 场地占用 / 容量超限 / 锁定冲突 / 规则冲突 |
| `conflict_resolution` | `UNRESOLVED` / `IGNORED_ONCE` / `CONFIG_CHANGED` / `RESOLVED` | 待处理 / 本次已忽略 / 配置已变更 / 已解决 |
| `unscheduled_reason` | `NO_FEASIBLE_SLOT` / `TEACHER_EXHAUSTED` / `CLASS_EXHAUSTED` / `VENUE_EXHAUSTED` / `CAPACITY` / `LOCK_CONFLICT` / `TIME_LIMIT` | 无可行时段 / 教师时段耗尽 / 班级时段耗尽 / 场地时段耗尽 / 容量不足 / 锁定冲突 / 计算超时 |
| `adjustment_action` | `APPLY` / `UNDO` / `REDO` | 保存调课 / 撤销 / 重做 |

### 10.5 导入导出与日志

| 枚举 | 值 | 中文 |
|------|----|------|
| `import_module` | `SEMESTERS` / `GRADES` / `CLASSES` / `SUBJECTS` / `TEACHERS` / `ASSIGNMENTS` / `VENUES` | 学期 / 年级 / 班级 / 科目 / 教师 / 任课 / 场地 |
| `import_batch_status` | `COMPLETED` / `PARTIAL` / `FAILED` | 全部成功 / 部分成功 / 失败 |
| `export_dimension` | `MASTER_DATA` / `TIMETABLE` / `STATISTICS` | 基础数据 / 课表 / 工作量统计 |
| `timetable_dimension` | `CLASS` / `TEACHER` / `SCHOOL` / `VENUE` / `ASSIGNMENT` | 班级 / 教师 / 全校 / 场地 / 任课 |
| `operation_module` | `DELETE` / `PUBLISH` / `OVERWRITE` / `SWITCH_SEMESTER` / `IMPORT` / `ARCHIVE` / `ADJUST` | 删除 / 发布 / 覆盖 / 切换学期 / 导入 / 存档 / 调课 |
| `print_paper_size` | `A4` / `A3` | A4 / A3 |
| `print_orientation` | `PORTRAIT` / `LANDSCAPE` | 纵向 / 横向 |

---

## 11. 文案规范（用户友好）

| 场景 | 禁止 | 推荐 |
|------|------|------|
| 删除保护 | `FK constraint violation` | 该年级下还有 3 个班级，请先调整班级所属年级 |
| 版本冲突 | `409 VERSION_CONFLICT` | 数据已被他人修改，请刷新页面后重试 |
| 导入失败 | `Row 12 invalid` | 第 12 行「班级序号」必须为 1-99 的整数，本行未导入 |
| 排课失败 | `No solution` | 有 6 节课暂时无法安排，请查看未排课时清单并调整约束 |
| 权限不足 | `Forbidden` | 您没有权限访问此页面，请联系教务管理员 |
| 会话过期 | `Unauthorized` | 登录已超过 8 小时未操作，请重新登录 |
| 空列表 | `No data` | 还没有配置作息模板，点击「新建模板」开始 |

> 产品界面不展示任何英文枚举、错误码、HTTP 状态码、SQL、堆栈。

---

## 12. 版本与契约冻结

- `contracts/` 六件套由 P0-06 契约冻结卡一次性产出：`openapi.yaml`、`schema.sql`、`events.yaml`、`naming.yaml`、`routes.yaml`、`cross-context-writes.md`。
- 领域卡实现必须与 `contracts/` 一致；如需偏离，先修改设计并更新契约，不得静默偏离。
- 状态刷新卡 INT-03 从实际代码反写 `contracts/`，作为下一轮唯一真相。
