# 智能排课系统 V1.0 系统架构设计（SPAC）

| 项 | 值 |
|----|----|
| 项目 | 智能排课系统（paike） |
| 轮次 | v1 / 首轮开发（设计态） |
| 设计日期 | 2026-10-19 |
| 输入真相 | `input/v1.0/PRD/12-V1.0封版PRD.md`（唯一真相） |
| 辅助输入 | `input/v1.0/DDD/`、`input/v1.0/需求梳理/06-V1.0高保真交互原型.html`、`output/v1.0/`（冲突裁决） |
| 本轮边界 | 只做架构与任务设计；**不写代码、不运行任何测试** |
| 交付物 | 本文件、`agent_plane.md`、`issues.yaml`、`test-results/*.md` 及根目录共享约定文件 |

**信任层级**：PRD > 高保真原型（仅界面参考）> DDD 模型 > 裁决文档。冲突时以 PRD 为准；PRD 未定义处依次取原型、DDD、已生效裁决（A-01~A-22、M-01~M-23、H-01~H-05）。

---

## §1 项目概述

### 1.1 目标

为中小学教务处提供一套本地部署的排课系统，覆盖「基础数据 → 一键排课 → 课表查看/调课 → 冲突处置 → 统计 → 导入导出打印 → 留痕与存档 → 账号权限」的完整闭环。核心价值是：在 50 个班规模下 5 秒内产出一份**无三类核心冲突**的课表，并让教务人员可以可视化微调、追溯与复用。

### 1.2 功能范围（PRD F1-F20）

| 编号 | 功能 | 主要承载卡片 |
|------|------|--------------|
| F1 | 学期管理（含校历、切换、状态） | D01 / D07 |
| F2 | 作息模板与版本 | D01 |
| F3 | 年级与班级 | D02 |
| F4 | 科目与课时规则 | D02 |
| F5 | 教师与任课约束 | D03 |
| F6 | 场地与功能室 | D04 |
| F7 | 合班课 | D04 / D05 |
| F8 | 一键智能排课 | D05 |
| F9 | 预排与锁定 | D05 |
| F10 | 走班与复杂场景 | D04 / D05 |
| F11 | 多维度课表（班级/教师/全校/场地/任课） | D06 |
| F12 | 拖拽调课与撤销重做 | D06 |
| F13 | 空闲时段查询 | D06 |
| F14 | 教师工作量统计 | D11 |
| F15 | Excel 导出 | D10 |
| F16 | 模板打印 | D10 |
| F17 | 冲突校验与处置 | D05 |
| F18 | 批量导入 | D09 |
| F19 | 操作日志与多学期存档 | D07 |
| F20 | 用户、角色与登录 | P0-02 / P0-08 / D08 |

### 1.3 验收边界（PRD §7 V-1~V-5）

| 编号 | 边界 |
|------|------|
| V-1 | 三类核心冲突（教师时间、班级同节多课、场地占用）为零 |
| V-2 | 50 班固定数据集，服务端排课 p95 ≤ 5 秒 |
| V-3 | 课表五视图与统计口径一致，教师仅见本人及关联班级 |
| V-4 | 关键操作二次确认且 100% 留痕；存档后只读 |
| V-5 | D15 公共基准逐格一致（PRD 附件 A） |

### 1.4 不在 V1.0 范围

- 学生/家长端、移动端 App、消息推送。
- 选课、考勤、成绩、收费等教务外业务。
- 多校区/多学校租户、跨校排课。
- 加班课时计算细则（V1.0 仅占位展示）。
- 自动合并式并发编辑（V1.0 采用乐观版本 + 刷新提示）。

### 1.5 角色

| 角色 | 枚举 | 能力摘要 |
|------|------|----------|
| 教务管理员 | `ADMIN` | 全部配置、排课、调课、统计、导入导出打印、日志存档、用户管理 |
| 普通教师 | `TEACHER` | 本人课表、本人关联班级课表、本人空闲时段；管理端一律拒绝 |

完整矩阵见 `roles.md`；服务端每请求判定，前端隐藏不作为安全边界。

---

## §2 输入分析与冲突裁决

### 2.1 输入清单

| 输入 | 用途 | 处理原则 |
|------|------|----------|
| `PRD/12-V1.0封版PRD.md` | 功能、规则、验收、权限、D15 基准 | 唯一真相；与任何文档冲突以其为准 |
| `DDD/*.json` | 5 个限界上下文、12 个聚合、命令/事件、47 条规则、2 个状态机 | 作为领域词汇与边界依据；缺失处由 PRD 与裁决补齐 |
| `需求梳理/06-V1.0高保真交互原型.html` | 页面结构、表单字段、表格列、文案语气 | 仅界面参考；非用户操作内容全部剔除 |
| `output/v1.0/*` | 测试案例、静态结果、产品裁决、人工裁决、孤儿用例 | 作为验收输入与冲突裁决；不改变 PRD 优先级 |

### 2.2 原型剔除清单

原型中以下内容**不属于系统功能**，设计时不实现、不出现在导航与页面：

| 原型内容 | 剔除理由 |
|----------|----------|
| 顶部「需求条目」面板、F1-F20 覆盖说明 | 需求管理辅助信息，非教务用户操作 |
| 页面切换器 / 原型导航浮层 | 原型演示工具 |
| 「演示登录」「一键填充」按钮 | 演示便利功能，真实系统无此入口 |
| 写死的示例统计、模拟 Toast、前端假数据 | 非真实业务数据，改为服务端读取 |
| 前端 `runAutoSchedule()` 等模拟排课脚本 | 排课必须由服务端确定性引擎完成 |
| 标注「原型示意」「暂不实现」的占位交互 | 不属于 V1.0 验收范围 |
| 与 PRD 冲突的字段名/流程 | 以 PRD 为准，保留原型视觉结构 |

保留：页面层级、表格列与顺序、表单字段与分组、按钮位置与语气、空状态与错误提示的呈现方式。

### 2.3 已生效裁决的使用方式

- `产品裁决结论.md` A-01~A-22：产品口径（视图、统计、导入、权限、并发提示等）。
- `人工裁决.md` H-01~H-05：均选方案 A，本设计全部采纳：
  - H-01：方案级乐观版本 + 409 刷新提示，无锁、无 TTL。
  - H-02：最小安全基线（Argon2id、服务端会话、8h/7d、5 次锁定 15 分钟、首次强制改密）。
  - H-03：固定 50 班数据集 + 服务端 p95；排课 ≤5s，1000×12 导出 ≤3s。
  - H-04：XLSX 为主、固定模板、服务端 PDF、导入 ≤5000 行/20MB。
  - H-05：停课周占周序号，奇偶继续推进。
- `M-01~M-23`：模型补全项，已落到对应卡片（见 §11.2）。

### 2.4 输入缺口与设计处置

| 缺口 | 处置 |
|------|------|
| 原型缺 08 号页面（用户与角色） | 按 PRD F20 与权限矩阵直接设计，采用与全站一致的表格 + 抽屉表单 |
| DDD 未定义导入/导出/打印上下文 | 设计为 `exchange` 应用模块（非限界上下文），只经查询服务与共享内核工作 |
| DDD 未定义统计上下文 | 设计为 `statistics` 应用模块，读 `WorkloadQueryService` |
| DDD 规则 R-047 未选定并发策略 | 采用 H-01 裁决 A：乐观版本 + 刷新提示 |
| DDD Account 缺密码/会话字段 | 由 P0-01/P0-02 以共享表 `sys_user`/`sys_session` 扩展，D08 复用 |
| 子技能 `architecture-design-generator`、`plane-issue-decomposer`、`bmad-review`、`bmad-deep-recon` 未安装 | 由主流程直接完成等价工作；偏差记录于 `docs/memory/2026-10-19.md` 与 `agent_plane.md` |

---

## §3 架构总览

### 3.1 架构风格

采用**模块化单体**：一个 Node.js 进程承载 5 个限界上下文与 2 个应用模块，共享一个 PostgreSQL。理由：

1. 单校本地部署，运维能力有限，微服务带来的部署/可观测成本不划算。
2. 排课需要在一个事务内读取多域快照并写入方案，单体更易保证一致性。
3. 通过目录、依赖规则与查询服务强制边界，保留未来拆分可能。

### 3.2 技术栈

| 层 | 选型 |
|----|------|
| 前端 | Vue 3 + TypeScript + Vite + Pinia + Vue Router + Element Plus |
| 后端 | Node.js 20 + Express 4 + TypeScript |
| 数据库 | PostgreSQL 16，`pg` 连接池，纯 SQL 迁移，无 ORM |
| 会话 | `express-session` + PostgreSQL Store；`paike.sid` Cookie |
| 密码 | Argon2id（64 MiB / time 3 / parallelism 1） |
| 表格 | SheetJS（`xlsx`） |
| 打印 | Playwright 无头 Chromium，HTML/CSS → PDF |
| 校验 | Zod（请求体、环境变量、导入行） |
| 日志 | Pino 结构化 JSON |
| 测试 | Vitest + Supertest（真实 PostgreSQL）+ Playwright |

### 3.3 运行时拓扑

```
浏览器 (Vue SPA)
   │ HTTPS / JSON / Cookie
   ▼
Nginx（静态资源 + 反向代理，生产）
   │
   ▼
Node.js / Express（单进程）
   ├─ HTTP 层：路由、鉴权、CSRF、校验、响应封装
   ├─ 应用层：5 上下文 + exchange + statistics
   ├─ 领域层：聚合、不变量、状态机、排课引擎
   ├─ 基础设施：仓储(SQL)、outbox、审计、文件、PDF
   ▼
PostgreSQL 16
```

本地开发：Vite `5173` 代理 `/api` 到后端 `3000`；生产由 Nginx 同源提供，避免跨域 Cookie 问题。

### 3.4 分层与依赖规则

```
backend/src/
  main.ts / app.ts
  config/                 # 环境变量唯一入口
  shared/                 # 共享内核，禁止依赖 modules/
  modules/
    registry/ resource/ timetable/ governance/ identity/
    exchange/             # 应用模块
    statistics/           # 应用模块
```

规则（由 ESLint `import/no-restricted-paths` 强制）：

1. `shared/` 不得 import `modules/`。
2. 领域内分层单向：router → controller → application service → domain/repository。
3. 跨上下文只可 import 对方的 `*.query-service.ts` / `*.app-service.ts` / `events/`；禁止 repository、domain、mapper。
4. `exchange`/`statistics` 不得被领域上下文反向依赖。
5. 前端 `views/<context>` 不得互相直接引用；共享组件放 `shared/components/`。

### 3.5 非功能目标

| 维度 | 目标 |
|------|------|
| 排课性能 | 50 班固定数据集服务端 p95 ≤ 5s（H-03） |
| 导出性能 | 1000 行 × 12 列 p95 ≤ 3s（H-03） |
| 普通接口 | 列表/详情 p95 ≤ 500ms（本地 4C8G） |
| 可用性 | 单校 ≤200 并发用户；会话失效友好回跳 |
| 数据安全 | 密码 Argon2id；日志脱敏；CSRF 双提交；会话服务端可撤销 |
| 可追溯 | 关键操作 100% 留痕，日志只追加、不清理 |
| 可复现 | 排课同输入同版本同锁定集逐格一致；打印预览与输出同一 PDF |
| 可维护 | 单文件 ≤400 行；领域逻辑无 SQL；SQL 只在 repository |

---

## §4 限界上下文与领域模型

### 4.1 上下文清单

| 上下文 | 中文 | 类型 | 聚合 | 职责 |
|--------|------|------|------|------|
| `bc-registry` | 教务主数据 | Core | Semester、ScheduleTemplate、Grade、Class、Subject、CalendarException | 学期、模板版本、年级班级、科目规则、校历 |
| `bc-resource` | 资源与任课 | Core | Teacher、Venue、CombinedClass、WalkingGroup、TeachingAssignment | 教师、场地、任课约束、合班、走班 |
| `bc-timetable` | 排课与调课 | Core | TimetablePlan（含 Lesson、UnscheduledLesson、ConflictDetail、AdjustmentHistory） | 排课引擎、方案生命周期、冲突、调课、五视图、空闲 |
| `bc-governance` | 治理与留痕 | Supporting | OperationLog、SemesterArchive | 操作日志、学期存档/切换编排 |
| `bc-identity` | 身份与权限 | Generic | Account | 账号、角色、会话、登录安全 |

应用模块（**不是**限界上下文，无独立领域模型）：

| 模块 | 职责 | 依赖 |
|------|------|------|
| `exchange` | 批量导入、Excel 导出、打印模板与 PDF | registry/resource/timetable 查询与应用服务 |
| `statistics` | 教师工作量统计 | timetable `WorkloadQueryService`、resource `TeacherQueryService` |

### 4.2 上下文映射

| 上游 | 下游 | 模式 | 说明 |
|------|------|------|------|
| registry | resource | Customer/Supplier | 任课引用班级/科目；resource 只读查询 |
| registry | timetable | Customer/Supplier | 学期、模板、班级、科目、校历作为排课输入 |
| resource | timetable | Customer/Supplier | 教师、场地、任课、合班、走班作为排课单元 |
| registry + timetable | governance | 编排（应用服务） | 存档/切换由 governance 调双方生命周期服务，不直接写表 |
| resource | identity | Customer/Supplier | 开通账号读取教师工号/姓名；退校事件联动停用 |
| registry/resource/timetable | exchange | 只读 + 应用服务 | 导入经各域应用服务落库；导出/打印只读 |
| timetable/resource | statistics | 只读 | 统计只读正式课表与教师信息 |

禁止边：registry→resource、registry→timetable、resource→timetable、任何上下文→governance 仓储。详见 `docs/knowledge/dependency-graph.yaml`。

### 4.3 聚合与不变量

| 聚合 | 关键不变量 |
|------|------------|
| Semester | 必须绑定一个模板版本；状态四值；已存档不可写；至多一个 `is_current` |
| ScheduleTemplate | 版本不可变；节次连续、时间合法、开放星期非空 |
| Grade / Class | 年级名受控；班级名由「年级（序号）班」生成；序号 1-99 |
| Subject | 名称受控且同义词不并存；课时规则冲突必须显式提示 |
| Teacher | 工号 `T+数字` 唯一；`LEFT` 与删除语义分离；有任课不可删 |
| Venue | 名称受控唯一；容量参与硬约束 |
| CombinedClass / WalkingGroup | 成员非空；教师、场地、科目必填；作为一个排课单元 |
| TeachingAssignment | 班级/科目/教师必填；周课时 ≥1；免排与禁排分开存储 |
| TimetablePlan | 方案级事务边界；每学期至多一个 `PUBLISHED`；锁定课次不可移动；存档只读 |
| OperationLog | 只追加，无更新/删除路径 |
| Account | 用户名大小写不敏感唯一；教师一对一；角色仅 ADMIN/TEACHER |

### 4.4 命令与事件（摘要）

DDD 提供 29 组命令/事件，本设计全部保留并补充实现细节：

- 命令示例：`CreateSemester`、`PublishTemplateVersion`、`ConfigureSubjectRule`、`CreateTeacher`、`ConfigureAssignment`、`CreateCombinedClass`、`GeneratePlan`、`PublishPlan`、`ArchiveSemester`、`ProvisionTeacherAccount`。
- 事件全部经 `sys_outbox_event` 同事务落库，提交后由 dispatcher 投递；事件名遵循 `bc.<context>.<entity>.<past-tense>`。
- 关键事件：`bc.timetable.plan.generated`、`plan.published`、`plan.archived`、`lesson.moved`、`conflict.ignored-once`、`bc.registry.semester.status-changed`、`bc.resource.teacher.deactivated`、`bc.identity.user.*`。

事件消费者仅用于审计与缓存失效，不承担业务正确性；业务一致性仍由同事务写入保证。

---

## §5 数据架构

### 5.1 数据分层

| 层 | 内容 | 建立卡片 |
|----|------|----------|
| 共享基础设施 | `sys_migration`、`sys_user`、`sys_session`、`sys_login_attempt`、`sys_config`、`sys_controlled_vocabulary`、`sys_outbox_event`、`sys_audit_log` | P0-01 |
| registry | semester、schedule_template、schedule_template_version、calendar_exception、grade、class、subject、subject_period_rule | D01 / D02 |
| resource | teacher、teaching_assignment、venue、combined_class(+member)、walking_group(+member) | D03 / D04 |
| timetable | timetable_plan、lesson、lesson_class、unscheduled_lesson、conflict_detail、conflict_ignore、adjustment_history | D05 / D06 |
| governance | operation_log、semester_archive | D07 |
| exchange | import_batch、print_template | D09 / D10 |

完整 DDL 以 `schema-shared.sql`（共享 8 表）与各 Phase 契约（`docs/knowledge/phase-contracts/`）为准，契约冻结卡 P0-06 汇总为 `contracts/schema.sql`。

### 5.2 主键、版本、时间、删除

- 主键统一 `uuid`，应用层 `crypto.randomUUID()` 生成；测试锚点固定 UUID。
- 可编辑聚合带 `version int NOT NULL DEFAULT 1`；更新 `WHERE id=$1 AND version=$2`。
- 时间戳 `timestamptz`；业务日期 `date`；`updated_at` 由触发器维护。
- 主数据软删除 `deleted_at`；删除前显式引用检查；已存档数据不参与删除判定。
- 迁移文件 `NNNN_snake_case.sql`，只追加；每张领域卡在卡片中声明序号段，避免冲突。

### 5.3 枚举（数据库 / API / 前端三处一致）

| 枚举 | 值 |
|------|----|
| `semester_status` | `NOT_STARTED` / `IN_PROGRESS` / `ENDED` / `ARCHIVED` |
| `term` | `FALL` / `SPRING` |
| `template_status` | `ACTIVE` / `RETIRED` |
| `teacher_status` | `ACTIVE` / `LEFT` |
| `venue_type` | `CLASSROOM` / `FUNCTION_ROOM` |
| `venue_status` | `AVAILABLE` / `UNAVAILABLE` |
| `consecutive_preference` | `NONE` / `PREFERRED` / `REQUIRED` |
| `time_slot_preference` | `NONE` / `MORNING` / `AFTERNOON` |
| `plan_status` | `DRAFT` / `PUBLISHED` / `SUPERSEDED` / `ARCHIVED` |
| `week_parity` | `ALL` / `ODD` / `EVEN` |
| `scheduling_unit_type` | `ASSIGNMENT` / `COMBINED_CLASS` / `WALKING_GROUP` |
| `conflict_type` | `TEACHER_OVERLAP` / `CLASS_OVERLAP` / `VENUE_OVERLAP` / `CAPACITY_EXCEEDED` / `LOCKED_VIOLATION` / `RULE_VIOLATION` |
| `conflict_resolution` | `UNRESOLVED` / `IGNORED_ONCE` / `CONFIG_CHANGED` / `RESOLVED` |
| `import_status` | `COMPLETED` / `PARTIAL` / `FAILED` |
| `operation_module` | `DELETE` / `PUBLISH` / `OVERWRITE` / `SWITCH_SEMESTER` / `IMPORT` / `ARCHIVE` / `ADJUST` |

### 5.4 状态机

**TimetablePlanLifecycle（DDD 状态机 1）**

```
                 SaveAsPlan / CreateDraft
                           │
                           ▼
                        ┌──────┐   PublishPlan（无正式方案）   ┌───────────┐
                        │ DRAFT│ ─────────────────────────────▶│ PUBLISHED │
                        └──────┘                                └─────┬─────┘
                           │                                        │
             DeleteDraft   │                     PublishPlan(新方案)│  ArchivePlan
             (仅草稿)       ▼                                        ▼
                        deleted                          ┌────────────┐
                                                         │ SUPERSEDED │（只读）
                                                         └────────────┘
                                                         ┌──────────┐
                                                         │ ARCHIVED │（只读）
                                                         └──────────┘
```

| 迁移 | 触发 | 守卫 | 卡片 |
|------|------|------|------|
| `∅ → DRAFT` | 新建空方案 / 生成 / 另存 | 学期存在且未存档 | D05 |
| `DRAFT → PUBLISHED` | 发布 | 无未处理冲突；`version` 匹配；学期未存档 | D05 |
| `PUBLISHED → SUPERSEDED` | 覆盖发布 | 同事务：新方案发布成功 | D05 |
| `PUBLISHED → ARCHIVED` | 学期存档 | 学期存在 `PUBLISHED`；用户确认 | D07 |
| `DRAFT → deleted` | 删除草稿 | 仅 `DRAFT`；未被引用 | D05 |

补充约束：`SUPERSEDED`/`ARCHIVED` 只读；`ARCHIVED` 不可删；覆盖发布在同一事务内完成旧→新状态切换。

**LessonLockState（DDD 状态机 2）**

```
          LockLesson                UnlockLesson
UNLOCKED ──────────▶ LOCKED ──────────────────▶ UNLOCKED
   ▲                    │
   │  RegeneratePlan    │  MoveLesson / RegeneratePlan
   └────────────────────┘  （被禁止：返回 409，位置不变）
```

| 迁移 | 触发 | 守卫 | 卡片 |
|------|------|------|------|
| `UNLOCKED → LOCKED` | 管理员锁定课次 | 方案为 `DRAFT`/`PUBLISHED` 且未存档 | D05 |
| `LOCKED → UNLOCKED` | 管理员解锁 | 未存档；写操作日志 | D05 |
| `LOCKED` 下 `MoveLesson` | 拖拽/批量调课 | 拒绝整批，提示「课程已锁定，请先解锁」 | D06 |
| `LOCKED` 下 `RegeneratePlan` | 重新生成 | 保留锁定课次位置；冲突进入未排清单 | D05 |

**Semester（补充状态机）**：`NOT_STARTED → IN_PROGRESS → ENDED → ARCHIVED`。前三值由起止日期实时推导（R-046），`ARCHIVED` 为命令驱动的只读存储态；存档前置为存在 `PUBLISHED` 方案。

**Account（补充状态机）**：`ENABLED ⇄ DISABLED`；停用立即撤销会话；教师退校联动停用。

### 5.5 周次、日期与节假日

- 周首固定周一；`weekday` 1-7。
- 第 1 教学周 = 学期开始日期所在自然周（周一对齐）。
- 停课周**占用周序号**，奇偶继续推进（H-05）；调休上课日按 `makeup_weekday` 映射。
- `weekParity ∈ ALL/ODD/EVEN`；`ALL` 每周上课。
- 时区统一 `Asia/Shanghai`；服务端存 `timestamptz`。

### 5.6 并发与一致性

- 并发聚合根：`TimetablePlan`；主数据为单记录。
- 所有写请求携带读取时 `version`；不匹配返回 `409 VERSION_CONFLICT`，零写入。
- 发布/覆盖/存档在同一事务内校验版本与状态。
- 不采用行级锁、不自动合并（H-01 A）。
- 导入逐行独立提交；数据库故障整批回滚。

### 5.7 存档与只读

- 存档事务：学期 `→ARCHIVED`、当前 `PUBLISHED → ARCHIVED`、写 `semester_archive`、写操作日志、写 outbox。
- 存档后：全部写接口 `409 STATE_CONFLICT`；查看、导出、打印可用。
- 模板/学期后续编辑不影响已存档快照。

### 5.8 D15 锚点数据

`seed-anchors.sql` 固定写入：

| 锚点 | UUID 后缀 |
|------|-----------|
| 学期 2026 秋 | `...0101` |
| 作息模板 / 版本（周一至周三，4 节） | `...0102` / `...0103` |
| 年级 | `...0104` |
| A 班 / B 班 | `...0105` / `...0106` |
| 数学 / 英语 | `...0107` / `...0108` |
| 张老师 / 李老师 | `...0109` / `...010a` |
| 301 功能室 | `...010b` |
| 四条任课 | `...010c` ~ `...010f`（或由唯一键推导） |
| 管理员账号 | 由 seed 以 `admin` 幂等创建 |

锚点数据用于 D15 逐格断言（TB-AP-017），任何环境不得修改其语义。

---

## §6 API 设计

### 6.1 通用约定

- 前缀 `/api/v1`；资源复数 kebab-case；动作端点 `POST /资源/:id/动作`。
- 成功 `{ "data": ... }`；列表 `{ "data": { "items", "page", "pageSize", "total" } }`；失败 `{ "error": { "code", "message", "details", "requestId" } }`。
- 所有非 GET 请求要求 `X-CSRF-Token`；写请求要求 `version`。
- 分页 `page` 从 1，`pageSize` 默认 20、最大 100；排序白名单。
- 错误码：`VALIDATION_ERROR` / `UNAUTHENTICATED` / `FORBIDDEN` / `NOT_FOUND` / `VERSION_CONFLICT` / `DUPLICATE` / `REFERENCE_PROTECTED` / `STATE_CONFLICT` / `DRAFT_EXISTS` / `FILE_TOO_LARGE` / `IMPORT_ROW_ERROR` / `ACCOUNT_LOCKED` / `INTERNAL_ERROR`。
- 用户可见 `message` 必须中文且说明「发生了什么 + 怎么办」；`code` 仅供程序判断。

### 6.2 认证与会话（P0-02 / P0-08）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/auth/csrf` | 获取 CSRF Token |
| POST | `/auth/login` | 登录；失败统一「用户名或密码错误」 |
| POST | `/auth/logout` | 退出，服务端撤销会话 |
| GET | `/auth/me` | 当前用户与角色 |
| POST | `/auth/change-password` | 改密；首次登录强制 |

登录响应含 `mustChangePassword`；为 `true` 时除改密/退出外全部接口返回 `403 STATE_CONFLICT`，文案「请先修改初始密码」。

### 6.3 Phase 1：主数据（D01-D04）

| 资源 | 端点摘要 |
|------|----------|
| 学期 | `GET/POST /semesters`、`GET /semesters/current`、`PATCH/DELETE /semesters/:id`、`GET/POST/DELETE /semesters/:id/calendar-exceptions` |
| 模板 | `GET/POST /schedule-templates`、`GET/POST /schedule-templates/:id/versions`、`GET /schedule-templates/versions/:versionId`、`POST .../validate` |
| 年级班级 | `GET/POST /grades`、`PATCH/DELETE /grades/:id`、`GET/POST /classes`、`PATCH/DELETE /classes/:id` |
| 科目 | `GET/POST /subjects`、`PATCH /subjects/:id`、`PUT /subjects/:id/period-rule`、`GET /controlled-vocabularies?type=` |
| 教师任课 | `GET/POST /teachers`、`PATCH/DELETE /teachers/:id`、`POST /teachers/:id/deactivate`、`GET /teachers/:id/assignments`、`POST/PATCH/DELETE /teaching-assignments` |
| 场地 | `GET/POST /venues`、`PATCH/DELETE /venues/:id` |
| 合班走班 | `GET/POST/PATCH/DELETE /combined-classes`、`/walking-groups` |

存档与切换不在 Phase 1 暴露（见 §6.5）。

### 6.4 Phase 2：排课、课表、统计（D05 / D06 / D11）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST | `/timetable-plans` | 方案列表 / 新建空草稿 |
| GET/PATCH/DELETE | `/timetable-plans/:planId` | 详情 / 重命名 / 删除草稿 |
| POST | `/timetable-plans/:planId/generate` | 生成/重新生成；`preserveLocked` |
| POST | `/timetable-plans/:planId/save-as` | 另存为新草稿 |
| POST | `/timetable-plans/:planId/publish` | 发布；`confirmOverwrite` |
| GET | `/timetable-plans/:planId/conflicts` | 冲突明细 |
| GET | `/timetable-plans/:planId/unscheduled` | 未排课时清单 |
| POST | `.../conflicts/:conflictId/ignore-once` | 只本次忽略（需理由） |
| POST | `.../conflicts/:conflictId/resolve-config` | 记录「去修改配置」，返回跳转路由 |
| POST | `.../moves/validate` | 只校验不写入 |
| POST | `.../adjustments` | 批量保存调课（一个撤销单元） |
| POST | `.../adjustments/undo` / `redo` | 撤销 / 重做 |
| POST | `.../lessons/:lessonId/lock` / `unlock` | 锁定 / 解锁 |
| POST/DELETE | `.../lessons` / `.../lessons/:lessonId` | 预排 / 删除预排课次 |
| GET | `/timetables` | 五视图统一查询 |
| GET | `/my/timetable`、`/my/classes`、`/my/classes/:classId/timetable` | 教师本人视图 |
| GET | `/idle-slots`、`/my/idle-slots` | 空闲时段 |
| GET | `/statistics/workload` | 工作量统计 |

### 6.5 Phase 3：治理、身份、数据交换（D07-D10）

| 域 | 端点摘要 |
|----|----------|
| 治理 | `GET /operation-logs`、`GET /operation-logs/:logId`、`POST/GET /semesters/:id/archive`、`POST /semesters/:id/switch`、`GET /archive-status?semesterId=` |
| 身份 | `GET/POST /users`、`GET/PATCH /users/:userId`、`PATCH /users/:userId/role`、`POST /users/:userId/disable|enable|reset-password`、`POST /teachers/:teacherId/provision-account`、`POST /teachers/provision-accounts/batch` |
| 导入 | `GET /import/templates/:module`、`POST /import/:module/preview`、`POST /import/:module`、`GET /import/batches/:batchId`、`GET /import/batches/:batchId/errors` |
| 导出 | `GET /exports/options`、`GET /exports/columns?dimension=`、`POST /exports` |
| 打印 | `GET/POST /print-templates`、`PATCH/DELETE /print-templates/:id`、`POST /print-templates/:id/logo`、`POST /print/preview`、`POST /print/render` |

### 6.6 视图查询语义（五视图不摊平）

`GET /timetables?semesterId=&dimension=&objectId=&parity=`

| 参数 | 取值 | 说明 |
|------|------|------|
| `semesterId` | uuid | 必填；切换学期后不串扰 |
| `dimension` | `CLASS` / `TEACHER` / `SCHOOL` / `VENUE` / `ASSIGNMENT` | 视图维度 |
| `objectId` | uuid | `SCHOOL` 时可省略；其他维度必填 |
| `parity` | `ALL` / `ODD` / `EVEN` | `ODD` 返回 `ALL+ODD`，`EVEN` 返回 `ALL+EVEN` |

响应：

```json
{
  "data": {
    "semesterId": "uuid",
    "dimension": "CLASS",
    "objectId": "uuid",
    "parity": "ALL",
    "weekdays": [1, 2, 3, 4, 5],
    "periods": [{ "periodNo": 1, "startTime": "08:00", "endTime": "08:45" }],
    "cells": [
      {
        "weekday": 1,
        "period": 1,
        "lessonId": "uuid",
        "subjectName": "数学",
        "teacherName": "张老师",
        "classNames": ["七年级（1）班"],
        "venueName": "301 功能室",
        "weekParity": "ALL",
        "locked": true
      }
    ]
  }
}
```

规则：

1. 五视图共享同一查询服务与同一数据源，禁止各自拼装（A-21）。
2. `cells` 只返回有课格子；空格由前端按 `weekdays × periods` 渲染。
3. 教师请求非本人对象返回 `403`；`SCHOOL` 视图教师不可访问。
4. 空闲时段 = 模板开放槽位 − 该对象已占用槽位；与课表互补。
5. 课表只展示当前学期 `PUBLISHED`（或指定草稿预览）的方案。

### 6.7 权限与数据范围

- 所有管理端接口 `requireRole('ADMIN')`。
- 教师接口 `requireAuth` + 服务端过滤：`teacherId = session.teacherId`。
- 角色每请求从数据库读取；停用账号下一请求 401。
- 前端路由守卫按 `meta.roles`；仅作体验优化。

### 6.8 性能与幂等

- 排课接口同步返回（≤5s）；超过 4.5s 引擎停止搜索并返回部分结果 + 未排清单。
- 登录、发布、生成、导入提交支持请求级幂等键（可选 `Idempotency-Key`），重复提交返回同一结果。
- 导出/打印同步生成，临时文件 10 分钟后清理。

---

## §7 前端架构

### 7.1 路由与布局

- 布局：左侧导航 + 顶部学期选择器/用户菜单 + 内容区；最小宽度 1280px。
- 管理员路由：概览、基础数据、排课、课表、调课、空闲、统计、冲突、导入、导出、打印、日志、存档、用户。
- 教师路由：`/me/timetable`、`/me/idle-slots`、`/change-password`、退出。
- 守卫顺序：会话 → 强制改密 → 角色 → 页面。

### 7.2 状态管理

| Store | 内容 |
|-------|------|
| `useSessionStore` | 当前用户、角色、`mustChangePassword` |
| `useSemesterStore` | 当前学期、可选学期列表；切换后广播 `semester-changed` |
| `useTimetableStore` | 当前方案、视图维度、编辑会话的撤销/重做栈（内存） |

服务端数据不长期驻留；页面用 `useXxx()` 组合式函数拉取。写成功后刷新查询，不做乐观更新。

### 7.3 共享组件

| 组件 | 用途 |
|------|------|
| `AppLayout` / `SideNav` | 布局与角色化导航 |
| `ConfirmDialog` | 七类关键操作二次确认，含影响与可撤销说明 |
| `DataTable` | 分页、排序、空状态、批量选择 |
| `FormDrawer` | 新增/编辑抽屉，字段级校验 |
| `TimetableGrid` | 五视图网格，支持单双周标签、冲突图标、锁定标识 |
| `ConflictBadge` | 图标 + 文案 + 颜色三载体 |
| `EmptyState` / `ErrorState` | 原因 + 下一步 |
| `ImportWizard` | 上传 → 预览 → 结果 → 错误 CSV |
| `PrintSettings` | 模板、纸张、方向、边距、校徽 |

### 7.4 用户友好文案（强制）

| 场景 | 要求 |
|------|------|
| 按钮 | 动词短语：「保存学期」「发布课表」「确认调课」，禁止裸「确定」 |
| 二次确认 | 操作名、对象、影响范围、是否可撤销；确认按钮与操作同名 |
| 空状态 | 说明为什么空 + 下一步按钮：「还没有学期，点击『新增学期』开始配置」 |
| 加载 | >300ms 显示骨架；排课显示「正在为 48 个班级安排课程，预计 5 秒内完成」 |
| 错误 | 「发生了什么 + 怎么办」，不显示堆栈/错误码/SQL |
| 冲突 | 图标 + 中文说明 + 颜色，不用颜色作唯一信息 |
| 锁定 | 「课程已锁定，请先解锁后再调整」 |
| 未排课时 | 「有 6 节课暂时无法安排，请查看未排课时清单并调整约束」 |
| 版本冲突 | 「数据已被他人修改，请刷新页面后重试」；保留未提交内容直到确认刷新 |

### 7.5 登录与账号界面（P0-08 / D08）

- `/login`：用户名、密码、登录按钮；错误统一「用户名或密码错误」；锁定提示剩余分钟。
- `/change-password`：旧密码、新密码、确认新密码；实时策略提示；成功后重新登录。
- 首次登录强制跳转改密页，其他路由不可达。
- 会话失效：任意 401 → 清除本地会话 → 跳登录并携带 `redirect`，提示「登录已失效，请重新登录」。
- 用户管理页：列表（用户名、姓名、角色、状态、关联教师）、新建/编辑抽屉、角色切换、停用/启用、重置密码（一次性展示）、教师一键开通/批量开通（下载凭据 CSV）。
- 初始密码只在创建/重置响应中出现一次，界面明示「关闭后无法再次查看」。

### 7.6 可访问性与交互

- 全操作可 Tab 到达；对话框焦点陷阱；Esc 关闭。
- 危险操作红色按钮 + 二次确认。
- 表格支持键盘上下移动；拖拽调课提供等价的「选择目标节次」下拉作为无障碍替代。
- 单双周、锁定、冲突均有文字标签，不只靠颜色。

---

## §8 横切设计

### 8.1 认证、会话与安全

- `express-session` + PG Store；Cookie `paike.sid`，HttpOnly、SameSite=Lax、生产 Secure。
- 空闲 8h 滑动续期；绝对 7d；退出置 `revoked_at`。
- 登录失败：同用户名 + IP 15 分钟内 5 次 → 锁定 15 分钟；统一错误文案，避免枚举账号。
- Argon2id；密码 ≥8 位且四类中至少三类；首次登录与重置后强制改密。
- CSRF 双提交：`csrf` Cookie + `X-CSRF-Token`；所有非 GET 校验。
- 角色每请求读库；停用账号立即 401；最后一个 Admin 不可停用/降级；不可停用自己。
- 安全审计：登录成功/失败、锁定、退出、改密、账号启停、角色变更、越权尝试。

### 8.2 日志与审计

| 日志 | 表 | 内容 | 保留 |
|------|----|------|------|
| 业务操作日志 | `operation_log` | 七类关键操作，中文可读 | 永久，只追加 |
| 安全审计 | `sys_audit_log` | 认证、账号、越权 | 永久 |
| 应用日志 | Pino stdout/文件 | 请求、错误、耗时 | 按运维策略轮转 |

- 业务日志与业务写入同事务；`operator_name` 存快照。
- 不记录密码、Cookie、CSRF Token、完整手机号。
- 每请求 `requestId`，响应头 `X-Request-Id`。

### 8.3 事件发件箱

- 业务事务内写 `sys_outbox_event`；提交后 dispatcher 轮询投递。
- 至少一次投递；消费者按 `eventId` 幂等。
- 事件不承载跨域强一致；跨域强一致走应用服务同事务。

### 8.4 导入

- XLSX 为主，接受 UTF-8 CSV（含/不含 BOM），拒绝 GBK。
- ≤5000 数据行且 ≤20MB；超限整份拒绝、零写入。
- 首行表头按列名匹配；未知列忽略并提示；必填列缺失整份拒绝。
- 逐行校验；合法行入库，非法行跳过；重复键按非法行处理，不做 upsert。
- 部分成功返回 `total/success/failed/errors/errorReportUrl`；错误含行号、列名、原值、中文原因。
- 数据库故障整批回滚，批次 `FAILED`。

### 8.5 导出

- SheetJS 生成 XLSX；一个工作簿按维度分 sheet。
- 只导出值；日期 `YYYY-MM-DD`；时间 `HH:mm`；空值为空；冻结表头。
- 列名/顺序来自 `COLUMN_DICTIONARY`，与页面逐字段一致。
- 文件名 `{维度}_{学期}_{YYYYMMDDHHmm}.xlsx`。
- 1000×12 p95 ≤3s；导出写安全审计，不要求二次确认。

### 8.6 打印

- 服务端 Playwright 渲染同一 HTML 模板 → PDF；预览与打印同一份。
- 纸张 A4/A3、横/纵向、边距可配；校徽 PNG ≤2MB 以 data URI 内嵌。
- 受保护 HTML 用一次性签名 token，60 秒有效。
- 预设模板不可删除；打印写安全审计。

### 8.7 冲突引擎

- 硬约束 H1-H12、软约束 S1-S6（详见 `p2-contracts.md` §3.2）。
- 确定性：固定种子、稳定排序、无随机数；同输入逐格一致。
- MRV 选单元 + 有界回溯（单单元 200 次、总 4.5s）；超限转未排清单。
- 三类核心冲突零容忍；D15 为唯一公共断言基准，禁止改期望表迁就算法。
- 冲突处置：配置修改 / 只本次忽略（仅可归因规则，记审计，不改配置）。

### 8.8 调课与撤销

- 拖拽先调 `moves/validate` 实时提示；保存时整批事务校验。
- 一个撤销单元 = 一次保存；栈上限 50；按「方案 + 用户 + 编辑会话」维护，离开清空。
- 撤销/重做服务端重校验；锁定、容量、存档任一不满足整组拒绝。
- 每次保存写 `adjustment_history`、`operation_log(ADJUST)`、`lesson.moved`。

### 8.9 错误处理

- 领域错误映射为 `AppError(code, message, details)`；HTTP 层统一封装。
- 预期错误（校验、冲突、引用、版本）不打印堆栈；未预期错误记录 `requestId` 并返回通用文案。
- 前端按 `code` 决定交互（刷新、跳转配置、重试），按 `message` 展示。

### 8.10 配置

- 环境变量唯一入口 `backend/src/config`，Zod 启动校验；清单见 `docs/knowledge/config-contract.md`。
- 非敏感运行配置存 `sys_config`（如受控词表开关、导出临时目录），不存密码。
- 受控词表与同义词存 `sys_controlled_vocabulary`，运行期可配置。

---

## §9 关键场景与流程

### 9.1 场景总览

| 场景 | 链路 | 主卡片 |
|------|------|--------|
| S1 首次启动与登录 | 初始化 admin → 登录 → 强制改密 → 概览 | P0-02/P0-05/P0-08 |
| S2 学期与模板 | 建模板版本 → 建学期并钉扎 → 校历 → 切换当前学期 | D01 |
| S3 基础数据 | 年级班级/科目/教师任课/场地/合班走班 | D02/D03/D04 |
| S4 一键排课 | 快照 → 引擎 → 冲突/未排 → 草稿 | D05 |
| S5 发布与覆盖 | 二次确认 → 发布 → 旧方案 SUPERSEDED | D05 |
| S6 调课 | 拖拽 → 校验 → 批量保存 → 撤销/重做 | D06 |
| S7 查看与统计 | 五视图 / 我的课表 / 空闲 / 工作量 | D06/D11 |
| S8 冲突处置 | 冲突中心 → 去配置 / 只本次忽略 | D05 |
| S9 导入导出打印 | 模板 → 预览 → 导入；导出；打印 | D09/D10 |
| S10 存档与切换 | 前置检查 → 存档 → 只读；切换草稿守卫 | D07 |
| S11 账号权限 | 教师一键开通 → 首登改密；停用/重置 | D08 |

### 9.2 D15 全链路（V-5 核心）

1. `seed-anchors.sql` 写入 D15 固定 UUID。
2. D01/D02/D03/D04 通过 API 可读取全部锚点。
3. D05 以固定种子生成，逐格断言 PRD 附件 A：
   - A 班：周一 1 数学张、周一 2 数学张（连堂）、周一 3 英语李@301。
   - B 班：周一 1 数学李、周二 3 英语张@301、周三 1 数学李。
   - 其余格子为空。
4. 发布后五视图与导出逐格一致。
5. 同一输入连续生成 3 次逐格一致。

禁止为通过断言修改期望表、放宽约束或写死特例；失败时定位引擎排序/回溯。

### 9.3 排课时序（摘要）

```
Admin → POST /timetable-plans/:id/generate
  → TimetableService 读快照（各域 QueryService）
  → SchedulerEngine.solve(snapshot, lockedLessons, seed)
      → 单元排序 → 槽位扫描 → 硬约束过滤 → 软约束评分 → 有界回溯
  → 事务：清空旧结果 → 写 lesson/lesson_class/unscheduled/conflict → 更新 plan 统计 → outbox
  → 返回 conflictCount/unscheduledCount/durationMs
```

### 9.4 发布/覆盖时序

```
Admin → 确认对话框（影响：覆盖现有正式课表，旧方案只读保留）
  → POST publish { version, confirmOverwrite:true }
  → 事务：校验版本 → 校验冲突 → 若无正式：DRAFT→PUBLISHED
                        → 若有正式：旧 PUBLISHED→SUPERSEDED，新 DRAFT→PUBLISHED
  → 写 operation_log(PUBLISH 或 OVERWRITE) + outbox
```

### 9.5 存档与切换时序

```
Admin → GET /archive-status → 有 PUBLISHED？
  → 确认存档 → POST /semesters/:id/archive
  → 事务：学期 ARCHIVED + 方案 ARCHIVED + semester_archive + 日志 + outbox
  → 全部写接口 409；查看/导出可用
```

切换学期若当前有未保存草稿：未传 `draftResolution` → `409 DRAFT_EXISTS` → 前端三选一（保存/丢弃/取消），`CANCEL` 不写任何数据。

### 9.6 调课时序

```
拖拽 → POST moves/validate → 冲突？
  是 → 网格标红 + 中文冲突说明；不落库
  否 → POST adjustments { version, unitId, operations[] }
      → 整批事务校验（锁/容量/存档/版本）
      → 全部通过：写 lesson、adjustment_history、operation_log、outbox，version+1
      → 任一失败：409 + 冲突明细，零写入
```

---

## §10 实施计划与卡片

### 10.1 Phase 与卡片

| Phase | 卡片 | 目标 |
|-------|------|------|
| P0 基座 | P0-01 ~ P0-08 | 数据库、认证、共享内核、前端骨架、seed、契约冻结、Hub、登录界面 |
| P1 主数据 | D01 ~ D04 | 学期/模板/年级班级/科目/教师任课/场地/合班走班 |
| P2 排课 | D05、D06、D11 | 引擎、方案、五视图、调课、统计 |
| P3 治理与收口 | D07 ~ D10、INT-01 ~ INT-03 | 日志存档、账号、导入导出打印、集成、冻结、状态刷新 |

### 10.2 依赖波次

| 波次 | 可并行卡片 |
|------|------------|
| W0 | P0-01 |
| W1 | P0-02、P0-03、P0-05 |
| W2 | P0-04、P0-06、P0-08 |
| W3 | P0-07 |
| W4 | D01、D02、D03、D04 |
| W5 | D05、D08（D08 依赖 D03/P0-06） |
| W6 | D06、D07、D09、D11 |
| W7 | D10（依赖 D05/D06/D11） |
| W8 | INT-01 |
| W9 | INT-02 → INT-03 |

关键路径：P0-01 → P0-02 → P0-06 → D01 → D05 → D06 → INT-01 → INT-02 → INT-03。

### 10.3 每卡完成定义

- 实现与卡片「任务」逐项对应；无越界改动。
- `## 验证` 中至少 2 条可执行检查全部通过（本轮只设计，不执行）。
- 迁移可在空库重复执行；接口与 `contracts/` 一致。
- 用户可见文案中文、友好；关键操作二次确认并留痕。
- `test-results/<card-id>.md` 已按设计态填写，执行状态为「未执行」。

---

## §11 设计决策、规则执行点与残余风险

### 11.1 产品裁决索引（A-01~A-22）

| 编号 | 决策 | 落点 |
|------|------|------|
| A-01~A-05 | 学期/模板状态与版本钉扎、校历口径 | D01 |
| A-06 | 受控词表与同义词运行期配置 | D02 / P0-05 |
| A-07 | 导入格式、上限、部分成功 | D09 |
| A-08 | 模板节次校验规则 | D01 |
| A-09~A-12 | 任课、合班、走班字段与排课单元语义 | D03 / D04 / D05 |
| A-13~A-15 | 方案草稿、覆盖发布、撤销栈 | D05 / D06 |
| A-16 | 统计口径（合班>连堂>常规，加班占位） | D11 |
| A-17 | 冲突忽略仅本次、需理由、留痕 | D05 |
| A-18 | 角色每请求读取、停用即时生效 | D08 / P0-02 |
| A-19 | 存档只读、导出可用 | D07 |
| A-20 | 操作日志只追加、不清理 | D07 / P0-03 |
| A-21 | 五视图同源、教师关联班级定义 | D06 |
| A-22 | V1.1 范围边界与加班占位 | D11 |

### 11.2 模型补全项（M-01~M-23）

| 组 | 补全内容 | 落点 |
|----|----------|------|
| M-01~M-05 | 学期状态、模板版本、校历、班级命名、科目同义词 | D01 / D02 |
| M-06~M-10 | 教师退校、任课约束、场地容量、合班/走班成员 | D03 / D04 |
| M-11~M-16 | 方案版本、覆盖发布、锁定、调课历史、冲突明细、未排清单 | D05 / D06 |
| M-17~M-20 | 统计四类、导入批次、打印模板、日志字段 | D11 / D09 / D10 / D07 |
| M-21~M-23 | 账号开通、教师退校联动、初始密码策略 | D08 / P0-02 |

### 11.3 规则执行点（R-001~R-047）

| 规则 | 摘要 | 执行点 | 卡片 |
|------|------|--------|------|
| R-001 | 学期必须绑定一个作息模板 | 学期创建/编辑服务校验 `schedule_template_version_id` | D01 |
| R-002 | 学期状态四值 | `semester_status` 枚举 + 状态推导 | D01 |
| R-003 | 模板编辑生成新版本，历史不变 | 版本表不可变；学期钉扎版本 id | D01 |
| R-004 | 年级名受控 | 受控词表校验 | D02 |
| R-005 | 年级被引用不可删 | 引用检查 → `REFERENCE_PROTECTED` | D02 |
| R-006 | 班级名受控格式、序号 1-99 | 服务端生成名称 + Zod 校验 | D02 |
| R-007 | 科目名受控、同义词不并存 | 词表 + 同义词表校验 | D02 |
| R-008 | 科目三类软约束默认关闭 | `subject_period_rule` 默认值；引擎 S3/S4 | D02 / D05 |
| R-009 | 课时规则冲突显式提示 | 保存规则时冲突检测 + 中文提示 | D02 |
| R-010 | 工号 `T+数字` 唯一 | 正则 + 唯一索引 | D03 |
| R-011 | 删除与退校语义区分 | `DELETE` vs `POST /deactivate` | D03 |
| R-012 | 有任课教师不可删 | 引用检查 | D03 |
| R-013 | 免排与禁排语义区分 | `exempted_slots` / `forbidden_slots` 两个字段 | D03 / D05 |
| R-014 | 场地名受控唯一 | 词表 + 唯一索引 | D04 |
| R-015 | 班级人数 > 容量禁排 | 硬约束 H4 | D05 |
| R-016 | 场地同节重复占用拦截 | 硬约束 H3 + 冲突校验 | D05 |
| R-017 | 合班字段受控、作为排课单元 | 聚合不变量 + H8 | D04 / D05 |
| R-018 | 三类核心冲突为零 | 发布前校验 + D15/集成断言 | D05 |
| R-019 | 草稿→发布→存档、每学期一份正式 | 状态机 + 部分唯一索引 | D05 |
| R-020 | 50 班排课 ≤5s | 固定数据集 p95 基准 | D05 |
| R-021 | 锁定优先、不可移动/覆盖 | 锁定状态机 + 引擎保留 | D05 |
| R-022 | 单双周按周序号奇偶、第 1 周单周 | 周次计算共享内核；`week_parity` | P0-03 / D05 |
| R-023 | 走班跨班排入目标场地 | 走班单元 H8 | D04 / D05 |
| R-024 | 跨年级授课放开 | 任课不限制年级；无额外校验 | D03 |
| R-025 | 管理员全视图、教师本人及关联班 | RBAC + 数据范围过滤 | D06 / D08 |
| R-026 | 视图随学期切换不串扰 | 所有查询强制 `semesterId`；切换广播刷新 | D06 / D07 |
| R-027 | 调课二次确认并记日志 | 保存前确认 + `operation_log(ADJUST)` | D06 |
| R-028 | 调课撤销/重做、成组 | `adjustment_history` + 批次单元 | D06 |
| R-029 | 微调复用拖拽能力 | 同一调课服务与校验 | D06 |
| R-030 | 空闲查询：教师本人、管理员任意 | 接口数据范围过滤 | D06 |
| R-031 | 连堂按节次、合班按 1 节、加班占位 | 统计互斥分类 | D11 |
| R-032 | 导出字段与系统逐字段一致 | `COLUMN_DICTIONARY` 单一来源 | D10 |
| R-033 | 打印预览所见即所得 | 预览/打印同一 HTML + `renderPdf` | D10 |
| R-034 | 只本次忽略不改配置、不静默 | `conflict_ignore` + `IGNORED_ONCE` + 计数字段 | D05 |
| R-035 | 七类关键操作二次确认 | `ConfirmDialog` + 前端逐页接入 | P0-04 / 各卡 |
| R-036 | 被引用数据删除保护 | 各域引用检查 | D01~D04 |
| R-037 | 学期/模板删除不影响存档 | 存档快照独立；删除只影响未存档 | D07 |
| R-038 | 导入 ≤5000 行/20MB | 上传前与解析后双重校验 | D09 |
| R-039 | 关键操作 100% 留痕、永久 | `operation_log` 同事务、只追加 | D07 / P0-03 |
| R-040 | 状态流转全量留痕 | 发布/覆盖/存档/切换均写日志 | D05 / D07 |
| R-041 | 存档先决已发布、存档后只读 | 存档前置检查 + 状态守卫 | D07 |
| R-042 | 本地账号、内置管理员初始化 | seed 幂等创建 admin + 首次改密 | P0-02 / P0-05 |
| R-043 | Admin 全权、Teacher 仅本人相关 | 权限矩阵 + 服务端守卫 | D08 / D06 |
| R-044 | 角色变更即时生效 | 每请求读库 | D08 |
| R-045 | 新增教师可一键开通账号 | 开通应用服务 + 幂等 | D08 |
| R-046 | 前三态按日期推导、存档为存储态 | 状态计算服务 + 命令驱动存档 | D01 / D07 |
| R-047 | 并发采用弱控制、最终一致 | H-01 裁决 A：方案级乐观版本 + 409 刷新提示；零部分写入 | P0-03 / D05 / D06 |

### 11.4 状态机可追溯表

| 状态机 | 状态 | 迁移 | 持久化 | 验证卡片 |
|--------|------|------|--------|----------|
| TimetablePlanLifecycle | DRAFT / PUBLISHED / SUPERSEDED / ARCHIVED | 新建/生成、发布、覆盖、存档、删除草稿 | `timetable_plan.status` + 部分唯一索引 | D05 / D07 / INT-01 |
| LessonLockState | UNLOCKED / LOCKED | 锁定、解锁、移动、重新生成 | `lesson.locked` | D05 / D06 / INT-01 |
| Semester | NOT_STARTED / IN_PROGRESS / ENDED / ARCHIVED | 日期推导、存档 | `semester.status` | D01 / D07 |
| Account | ENABLED / DISABLED | 停用、启用、退校联动 | `sys_user.status` | D08 / P0-02 |

两个 DDD 状态机均有明确的命令入口、守卫、持久化字段与验收卡片；不存在未处理的非法迁移（被拒绝并返回 `409 STATE_CONFLICT`）。

### 11.5 残余风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| 约束过密导致引擎超时 | 出现未排课时 | 4.5s 上限 + 未排清单 + 可操作建议；禁止制造冲突凑数 |
| D15 期望表与通用算法 tie-break 不一致 | 基准失败 | 固定排序与种子；以逐格断言定位；禁止特例写死 |
| 50 班性能在低配机器不达标 | V-2 失败 | 固定数据集基准 + 排序优化 + 快照只读；不引入随机重启 |
| 乐观锁导致用户丢失未保存内容 | 体验下降 | 409 时保留表单内容；明确「刷新后重试」；不自动合并 |
| 导入脏数据 | 主数据质量 | 模板 + 预览 + 行级错误 CSV + 重复键拒绝 |
| 存档后仍有写请求 | 数据被改 | 服务端状态守卫 + 前端只读态 + 集成测试 |
| 打印字体/分页差异 | 预览与输出不一致 | 同一 HTML/引擎；固定字体；A4/A3 固定边距 |
| 浏览器多标签并发编辑 | 后写覆盖 | 版本冲突拒绝；提示刷新；不做静默合并 |
| 日志表增长 | 查询变慢 | 索引 `(created_at desc)`、按时间范围查询；V1.0 不做清理 |

### 11.6 契约冻结声明

- 本文件与 `agent_plane.md`、`issues.yaml`、`docs/knowledge/phase-contracts/*` 共同构成 v1 首轮设计基线。
- 全部接口、枚举、状态机、表结构以 `contracts/` 六件套（P0-06 产出）为实现唯一依据。
- 实现阶段如需偏离，必须先更新设计与契约并记录理由，不得静默偏离。
- 本轮**未执行任何测试**；`test-results/*.md` 中所有执行状态均为「未执行」，结论均为设计态静态推演。
