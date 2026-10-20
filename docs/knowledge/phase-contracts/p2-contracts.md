# Phase 2 契约摘要（p2-contracts.md）

> Phase 2 = 排课与课表域：timetable（D05、D06）与 statistics（D11）。
> 依赖 Phase 1 的主数据只读查询服务；不反向依赖 registry/resource 的写模型。
> 所有端点前缀 `/api/v1`，响应统一 `{ data, meta? }`，写请求携带 `version` 与 `X-CSRF-Token`。

---

## 1. 产出卡片

| 卡片 | 范围 |
|------|------|
| D05 | 排课引擎、方案生命周期（草稿/另存/发布/覆盖/存档）、D15、锁定、冲突明细、未排课时、D21 忽略 |
| D06 | 五视图、拖拽调课、撤销/重做、空闲时段查询、单双周展示 |
| D11 | 教师工作量统计（常规/连堂/合班/加班占位）、周/学期口径 |

---

## 2. 表结构

```sql
CREATE TYPE plan_status AS ENUM ('DRAFT','PUBLISHED','SUPERSEDED','ARCHIVED');
CREATE TYPE week_parity AS ENUM ('ALL','ODD','EVEN');
CREATE TYPE scheduling_unit_type AS ENUM ('ASSIGNMENT','COMBINED_CLASS','WALKING_GROUP');
CREATE TYPE conflict_type AS ENUM ('TEACHER_OVERLAP','CLASS_OVERLAP','VENUE_OVERLAP','CAPACITY_EXCEEDED','LOCKED_VIOLATION','RULE_VIOLATION');
CREATE TYPE conflict_resolution AS ENUM ('UNRESOLVED','IGNORED_ONCE','CONFIG_CHANGED','RESOLVED');

timetable_plan (
  plan_id uuid pk,
  semester_id uuid not null,
  name text not null,
  status plan_status not null default 'DRAFT',
  version int not null default 0,
  schedule_template_version_id uuid not null,   -- 生成时钉扎
  conflict_count int not null default 0,
  unscheduled_count int not null default 0,
  duration_ms int,
  has_manual_exemption boolean not null default false,
  generated_at timestamptz,
  generated_by uuid,
  created_at, updated_at, deleted_at
);
-- 唯一正式课表：同一学期至多一个 PUBLISHED
CREATE UNIQUE INDEX uq_plan_one_published
  ON timetable_plan (semester_id) WHERE status = 'PUBLISHED' AND deleted_at IS NULL;

lesson (
  lesson_id uuid pk,
  plan_id uuid not null,
  weekday smallint not null check (weekday between 1 and 7),
  period smallint not null check (period >= 1),
  week_parity week_parity not null default 'ALL',
  subject_id uuid not null,
  teacher_id uuid not null,
  venue_id uuid null,
  unit_type scheduling_unit_type not null,
  unit_id uuid not null,
  locked boolean not null default false,
  created_at, updated_at
);

lesson_class (lesson_id uuid, class_id uuid, primary key (lesson_id, class_id));

unscheduled_lesson (
  unscheduled_id uuid pk,
  plan_id uuid not null,
  unit_type scheduling_unit_type not null,
  unit_id uuid not null,
  class_ids uuid[] not null,
  subject_id uuid not null,
  teacher_id uuid not null,
  required_periods int not null,
  unplaced_periods int not null,
  reason_code text not null,
  reason_detail text not null,
  suggested_actions jsonb not null,   -- [{ label, route, configRef }]
  created_at
);

conflict_detail (
  conflict_id uuid pk,
  plan_id uuid not null,
  lesson_id uuid null,
  conflict_type conflict_type not null,
  teacher_id uuid null,
  class_ids uuid[],
  venue_id uuid null,
  weekday smallint,
  period smallint,
  rule_id text,
  config_ref jsonb,
  suggestion text not null,
  resolution conflict_resolution not null default 'UNRESOLVED',
  created_at
);

conflict_ignore (
  ignore_id uuid pk,
  plan_id uuid not null,
  conflict_id uuid null,
  operator_id uuid not null,
  reason text not null,
  scope text not null default 'THIS_RUN',
  created_at
);

adjustment_history (
  history_id uuid pk,
  plan_id uuid not null,
  session_id text not null,
  operator_id uuid not null,
  unit_id uuid not null,              -- 一次保存 = 一个撤销单元
  operations jsonb not null,
  action text not null,               -- APPLY / UNDO / REDO
  created_at
);
```

索引：`lesson(plan_id, weekday, period)`、`lesson(plan_id, teacher_id)`、`lesson(plan_id, venue_id)`、`lesson_class(class_id, lesson_id)`、`unscheduled_lesson(plan_id)`、`conflict_detail(plan_id, resolution)`。

---

## 3. 排课引擎契约（D05）

### 3.1 输入快照

生成时从 registry/resource 的查询服务读取一次并固定：

| 输入 | 来源 |
|------|------|
| 学期、钉扎模板版本（节次、开放星期） | SemesterQueryService / TemplateQueryService |
| 校历（停课、调休） | CalendarQueryService |
| 班级（人数、年级） | ClassQueryService |
| 科目与课时规则 | SubjectQueryService |
| 教师、任课（周课时、连堂偏好、免排/禁排） | TeacherQueryService / AssignmentQueryService |
| 场地（类型、容量、状态） | VenueQueryService |
| 合班、走班 | SchedulingUnitQueryService |
| 当前方案中已锁定课次 | timetable 自身 |

快照不落库；生成结果与 `schedule_template_version_id` 落库，保证可追溯。

### 3.2 约束

**硬约束（违反即不可放置）**

| 编号 | 约束 |
|------|------|
| H1 | 同一教师同一 `(weekday, period)` 不重叠；`ALL` 与任意周次冲突，`ODD` 与 `EVEN` 互不冲突 |
| H2 | 同一班级同一 `(weekday, period)` 不重叠（含合班/走班全部参与班级） |
| H3 | 同一场地同一 `(weekday, period)` 不重叠；未指定场地不占共享场地 |
| H4 | 班级人数 ≤ 场地容量（D19） |
| H5 | 教师免排/禁排时段不可放置（免排=主动配置，禁排=业务规则） |
| H6 | 科目禁排时段不可放置 |
| H7 | 锁定课次不得移动、不得被覆盖 |
| H8 | 合班/走班作为一个排课单元：教师 + 场地 + 全部参与班级同一时段 |
| H9 | 每个任课单元的周课时必须排满；未排满计入 `unscheduled_lesson` |
| H10 | 启用固定时段规则时，指定课程只能落在指定时段 |
| H11 | 只能落在模板开放的星期与存在的节次内 |
| H12 | 已存档学期禁止生成/调课/发布 |

**软约束（按优先级评分，不阻断）**

| 编号 | 约束 | 默认 |
|------|------|------|
| S1 | 连堂偏好：`REQUIRED` 视为硬约束，`PREFERRED` 加分 | 任课配置 |
| S2 | 时段优先（上午/下午） | 关闭 |
| S3 | 课时均衡（同一科目不连续堆叠） | 关闭 |
| S4 | 上下午均衡 | 关闭 |
| S5 | 同日同科目分散（非连堂时优先不同教学日） | 开启（引擎内部） |
| S6 | 节次靠前优先 | 开启（引擎内部） |

> S3/S4 对应 D17 的可配开关，默认关闭；S5/S6 是引擎确定性排序的一部分，不是业务规则，可在不改动结果正确性的前提下调整。

### 3.3 算法与确定性

1. 以 `(semesterId, templateVersionId)` 生成固定种子，所有遍历使用稳定排序，不使用随机数。
2. 单元排序：锁定 > 合班/走班 > `REQUIRED` 连堂 > 禁排/免排数量多 > 周课时多 > `unitId` 字典序。
3. 槽位扫描：`weekday` 1→7，`period` 1→N；先硬约束过滤，再按软约束得分排序，得分相同取最早槽位。
4. 回溯上限：单单元最多 200 次回退；总时长上限 4.5 秒（为 p95 ≤5 秒留余量）。超限后停止搜索，未放置项进入未排课时清单。
5. 结果必须满足：任何已放置课次的 H1-H11 均成立；不允许“为凑满课时而制造冲突”。
6. 同一输入、同一代码版本、同一锁定集合，输出逐格一致。
7. **D15 是唯一公共断言基准**：D15 输入必须逐格输出 PRD 附件 A 的 30 个格子；tie-break 以通过 TC-AP-017 为准，不得修改期望表迁就算法。

### 3.4 D15 输入映射

| 项 | 值 |
|----|----|
| 模板 | 周一至周三，4 节 |
| 班级 | `...0105` A 班、`...0106` B 班 |
| 教师 | `...0109` 张（T1001）、`...010a` 李（T1002） |
| 科目 | `...0107` 数学、`...0108` 英语 |
| 场地 | `...010b` 301 功能室（仅英语使用）；普通教室归班 |
| 任课 | A 数学×2 张（`REQUIRED` 连堂）、A 英语×1 李（301）、B 数学×2 李、B 英语×1 张（301） |
| 禁排 | 英语禁排周三第 3-4 节 |
| 免排 | 李 周二第 1 节；张 周三第 4 节 |

期望结果见 PRD 附件 A；逐格比对字段：`classId × weekday × period → (subjectId, teacherId, venueId)`，空格必须为空。

### 3.5 方案生命周期

```
DRAFT ──发布（二次确认；覆盖时旧 PUBLISHED→SUPERSEDED）──▶ PUBLISHED
PUBLISHED ──学期存档──▶ ARCHIVED
DRAFT/PUBLISHED/SUPERSEDED ──逻辑删除（仅未被引用且非 ARCHIVED）──▶ deleted
```

规则：

- 同一学期至多一个 `PUBLISHED`（数据库部分唯一索引 + 事务内检查）。
- 发布前必须通过冲突校验；存在 `UNRESOLVED` 冲突时拒绝发布，除非冲突已标记 `IGNORED_ONCE`（人工豁免）或 `RESOLVED`。
- 覆盖发布：同一事务内旧方案 `PUBLISHED→SUPERSEDED`、新方案 `DRAFT→PUBLISHED`；任一步失败全部回滚。
- `SUPERSEDED`/`ARCHIVED` 只读，可查看/导出，不可发布、不可删除。
- `SaveAsPlan` 复制课次、锁定状态、周次类型，生成独立 `DRAFT`；源方案不变。
- 生成新的 `DRAFT` 不自动删除旧草稿。

### 3.6 冲突与未排课时

- 每次生成/重新生成：先清空该方案的 `conflict_detail` 与 `unscheduled_lesson`，再重建。
- `conflict_count` = `resolution='UNRESOLVED'` 的冲突数；人工豁免单列 `has_manual_exemption`，不伪装为 0 冲突。
- 未排课时必须记录 `reasonCode`：`NO_FEASIBLE_SLOT` / `TEACHER_EXHAUSTED` / `CLASS_EXHAUSTED` / `VENUE_EXHAUSTED` / `CAPACITY` / `LOCK_CONFLICT` / `TIME_LIMIT`。
- `suggestedActions` 至少包含一个可跳转入口（路由 + 配置对象 id）。

### 3.7 人工豁免（D21）

- 只对可归因到 `ruleId`/`configRef` 的冲突开放「只本次忽略」。
- 容量超限、锁定课程移动、已存档写操作不提供忽略入口。
- 忽略仅对本次生成/本次保存生效：写入 `conflict_ignore` 与操作日志，不改任何配置；再次生成重新提示。
- 忽略后 `conflict_detail.resolution='IGNORED_ONCE'`，方案 `has_manual_exemption=true`；导出/统计可识别。

### 3.8 锁定（F9）

- 锁定粒度：课次。
- 锁定课次在自动排课、方案微调、拖拽调课中均不可移动；尝试移动返回 `409 STATE_CONFLICT`，提示「课程已锁定，请先解锁」。
- 解锁后可被自动调整；解锁写操作日志。
- 预排流程：创建空 `DRAFT` → 手工放置/锁定课次 → `generate?preserveLocked=true`。

---

## 4. API（D05 / D06 / D11）

### 4.1 方案与生成

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/timetable-plans?semesterId=` | 方案列表（名称/时间/冲突数/未排数/状态） |
| POST | `/timetable-plans` | 新建空草稿 |
| GET | `/timetable-plans/:planId` | 方案详情（含版本、统计） |
| PATCH | `/timetable-plans/:planId` | 重命名（`version`） |
| DELETE | `/timetable-plans/:planId` | 删除草稿（`version`；非草稿拒绝） |
| POST | `/timetable-plans/:planId/generate` | 生成/重新生成（`preserveLocked`） |
| POST | `/timetable-plans/:planId/save-as` | 另存为新草稿 |
| POST | `/timetable-plans/:planId/publish` | 发布（`version`；覆盖确认在前端） |
| GET | `/timetable-plans/:planId/conflicts` | 冲突明细 |
| GET | `/timetable-plans/:planId/unscheduled` | 未排课时清单 |
| POST | `/timetable-plans/:planId/conflicts/:conflictId/ignore-once` | 只本次忽略（`reason`） |
| POST | `/timetable-plans/:planId/conflicts/:conflictId/resolve-config` | 记录「去修改配置」并返回跳转路由 |

生成响应：

```json
{
  "data": {
    "planId": "uuid",
    "status": "DRAFT",
    "conflictCount": 0,
    "unscheduledCount": 0,
    "durationMs": 1830,
    "hasManualExemption": false
  }
}
```

发布请求：

```json
{ "version": 7, "confirmOverwrite": true }
```

已存在 `PUBLISHED` 且 `confirmOverwrite=false` → `409 STATE_CONFLICT`，`details` 返回现有正式方案名。

### 4.2 调课与锁定

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/timetable-plans/:planId/moves/validate` | 只校验不写入，返回冲突 |
| POST | `/timetable-plans/:planId/adjustments` | 批量保存调课（一个撤销单元） |
| POST | `/timetable-plans/:planId/adjustments/undo` | 撤销一个单元（客户端提交操作，服务端重校验） |
| POST | `/timetable-plans/:planId/adjustments/redo` | 重做一个单元 |
| POST | `/timetable-plans/:planId/lessons/:lessonId/lock` | 锁定 |
| POST | `/timetable-plans/:planId/lessons/:lessonId/unlock` | 解锁 |
| POST | `/timetable-plans/:planId/lessons` | 预排课次（仅草稿） |
| DELETE | `/timetable-plans/:planId/lessons/:lessonId` | 删除预排课次（仅草稿且未锁定） |

批量调课请求：

```json
{
  "version": 12,
  "unitId": "uuid",
  "operations": [
    {
      "lessonId": "uuid",
      "from": { "weekday": 1, "period": 3 },
      "to": { "weekday": 2, "period": 3 },
      "venueId": "uuid",
      "weekParity": "ALL"
    }
  ]
}
```

规则：

- 整批要么全部成功，要么全部不写；任一操作冲突 → `409` + 冲突明细。
- 保存成功后 `version+1`、写 `adjustment_history`、`operation_log`、`bc.timetable.lesson.moved` 事件。
- 撤销/重做同样整组校验；锁定、容量、存档状态任一不满足 → 整组拒绝。
- 撤销栈上限 50 个单元，按「方案 + 用户 + 编辑会话」维护；刷新/离开方案后清空（A-15）。

### 4.3 五视图与空闲

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/timetables?semesterId=&dimension=&objectId=&parity=` | 五视图统一入口 |
| GET | `/my/timetable?semesterId=&parity=` | 教师本人课表 |
| GET | `/my/classes?semesterId=` | 教师关联班级（任课 ∪ 班主任） |
| GET | `/my/classes/:classId/timetable?semesterId=&parity=` | 关联班级课表 |
| GET | `/idle-slots?semesterId=&dimension=TEACHER\|CLASS&objectId=&parity=` | 空闲时段 |
| GET | `/my/idle-slots?semesterId=&parity=` | 教师本人空闲 |

`dimension ∈ CLASS / TEACHER / SCHOOL / VENUE / ASSIGNMENT`。

课表响应：

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
        "venueName": "301",
        "weekParity": "ALL",
        "locked": true
      }
    ]
  }
}
```

规则：

- 五视图共享同一查询服务与同一数据源（A-21）。
- 教师请求非本人对象 → `403 FORBIDDEN`；前端隐藏不作为安全边界。
- `parity=ODD` 展示 `ALL+ODD`，`EVEN` 展示 `ALL+EVEN`；`ALL` 展示全部并按周次标签区分。
- 空闲槽位 = 模板开放槽位 − 该对象已占用槽位；与课表互补（TC-AT-011）。

### 4.4 统计

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/statistics/workload?semesterId=&scope=SEMESTER\|WEEK&weekIndex=` | 工作量统计 |

响应行：

```json
{
  "teacherId": "uuid",
  "teacherName": "张老师",
  "regular": 12,
  "consecutive": 4,
  "combined": 2,
  "overtime": 0,
  "total": 18
}
```

口径（A-16）：

- 每条课次只入一类，优先级：合班 > 连堂 > 常规。
- 合班按 1 节计；连堂按实际节次计；加班恒为 0，页面显示「细则 V1.1」。
- 周口径按指定教学周的 `ALL + 对应奇偶` 课次计算；学期口径按全部教学周累计。
- 统计必须来自当前正式课表（`PUBLISHED`）；无正式课表时返回空并提示「请先发布课表」。

---

## 5. 领域事件

| 事件 | 生产者 | 消费者 | payload 要点 |
|------|--------|--------|--------------|
| `bc.timetable.plan.generated` | D05 | governance | planId, semesterId, conflictCount, unscheduledCount, durationMs |
| `bc.timetable.plan.published` | D05 | governance, registry | planId, semesterId, supersededPlanId |
| `bc.timetable.plan.archived` | D07 | governance, registry | planId, semesterId |
| `bc.timetable.lesson.moved` | D06 | governance | planId, lessonId, from, to, transactionId |
| `bc.timetable.conflict.ignored-once` | D05 | governance | planId, conflictId, operatorId, reason |

> 发布覆盖产生 `supersededPlanId`；被覆盖方案只读，不删除。

---

## 6. 前端路由

| 路由 | 页面 | 卡片 | 角色 |
|------|------|------|------|
| `/scheduling` | 一键智能排课（含方案列表） | D05 | Admin |
| `/scheduling/pre` | 预排与锁定 | D05 | Admin |
| `/conflicts` | 冲突校验中心 | D05 | Admin |
| `/timetables` | 多维度课表视图 | D06 | Admin |
| `/timetables/adjust` | 拖拽调课 / 方案微调 | D06 | Admin |
| `/me/timetable` | 我的课表 | D06 | Teacher |
| `/idle-slots` | 空闲时段查询 | D06 | Admin |
| `/me/idle-slots` | 我的空闲时段 | D06 | Teacher |
| `/statistics` | 工作量统计 | D11 | Admin |

---

## 7. 完成判定

- D15 输入逐格输出与 PRD 附件 A 完全一致，三类核心冲突为 0。
- 同一输入连续生成 3 次，结果逐格一致。
- 覆盖发布后同一学期仅一个 `PUBLISHED`，旧方案为 `SUPERSEDED` 且只读。
- 任一冲突调课整批不写入；撤销/重做整组回退/重放。
- 教师越权访问五视图与统计返回 403；前端无管理入口。
- 统计四类互斥、合计正确，周/学期口径可复算。
- 所有错误提示中文、可操作；关键操作二次确认并留痕。
