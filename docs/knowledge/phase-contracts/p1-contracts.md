# Phase 1 契约摘要（p1-contracts.md）

> Phase 1 = 基础数据域：registry（D01、D02）与 resource（D03、D04）。
> 全部端点 Admin only；均需会话 + CSRF；写请求携带 `version`。

---

## 1. 产出卡片

| 卡片 | 域 | 聚合/表 |
|------|----|---------|
| D01 | registry | Semester、ScheduleTemplate、ScheduleTemplateVersion、CalendarException |
| D02 | registry | Grade、Class、Subject、SubjectPeriodRule（含受控词表消费） |
| D03 | resource | Teacher、TeachingAssignment |
| D04 | resource | Venue、CombinedClass、WalkingGroup |

---

## 2. 表结构（摘要）

### 2.1 registry

```sql
semester (
  semester_id uuid pk,
  name text, academic_year text, term term_enum,
  start_date date, end_date date,
  status semester_status,
  schedule_template_version_id uuid fk,
  is_current boolean,
  version int, created_at, updated_at, deleted_at
)

schedule_template (
  template_id uuid pk, name text unique, status template_status,
  latest_version_no int, version int, created_at, updated_at, deleted_at
)

schedule_template_version (
  version_id uuid pk, template_id uuid fk, version_no int,
  open_weekdays smallint[], periods jsonb,
  status template_status, created_at
) -- 不可变：无 updated_at；唯一 (template_id, version_no)

calendar_exception (
  exception_id uuid pk, semester_id uuid fk,
  type calendar_exception_type, start_date date, end_date date,
  makeup_weekday smallint null, note text,
  version int, created_at, updated_at
)

grade (grade_id uuid pk, name text unique, sort_order int, version int, deleted_at)

class (
  class_id uuid pk, grade_id uuid fk, name text, serial_no smallint,
  head_teacher_id uuid null, student_count int,
  version int, deleted_at, unique (grade_id, serial_no)
)

subject (subject_id uuid pk, name text unique, version int, deleted_at)

subject_period_rule (
  rule_id uuid pk, subject_id uuid unique fk,
  weekly_periods int,
  consecutive_preference consecutive_preference_enum,
  forbidden_slots jsonb, time_slot_preference time_slot_preference_enum,
  period_balance_enabled boolean, am_pm_balance_enabled boolean,
  fixed_slot_rule_enabled boolean,
  version int, updated_at
)
```

### 2.2 resource

```sql
teacher (
  teacher_id uuid pk, employee_no text unique, name text,
  gender gender_enum, phone text, status teacher_status,
  version int, created_at, updated_at, deleted_at
)

teaching_assignment (
  assignment_id uuid pk, teacher_id uuid fk, subject_id uuid fk,
  class_id uuid fk, venue_id uuid null fk,
  weekly_periods int,
  consecutive_preference consecutive_preference_enum,
  forbidden_slots jsonb, exempted_slots jsonb,
  version int, deleted_at
)

venue (
  venue_id uuid pk, name text unique, type venue_type,
  capacity int, status venue_status,
  version int, deleted_at
)

combined_class (
  combined_class_id uuid pk, name text unique,
  teacher_id uuid fk, venue_id uuid null fk,
  period_constraint jsonb, version int, deleted_at
)
combined_class_member (combined_class_id uuid, class_id uuid, primary key (combined_class_id, class_id))

walking_group (
  walking_group_id uuid pk, name text, subject_id uuid fk,
  teacher_id uuid fk, venue_id uuid fk,
  version int, deleted_at
)
walking_group_member (walking_group_id uuid, class_id uuid, primary key (walking_group_id, class_id))
```

---

## 3. API

### 3.1 学期（D01）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/semesters` | 列表；`?includeArchived=true` |
| GET | `/semesters/current` | 当前学期 |
| POST | `/semesters` | 新增（必须带模板版本） |
| PATCH | `/semesters/:id` | 编辑（已存档拒绝） |
| DELETE | `/semesters/:id` | 逻辑删除（有业务数据拒绝） |
| GET | `/semesters/:id/calendar-exceptions` | 校历列表 |
| POST | `/semesters/:id/calendar-exceptions` | 新增停课/调休 |
| DELETE | `/semesters/:id/calendar-exceptions/:exceptionId` | 删除校历项 |

新增学期请求：

```json
{
  "name": "2026 秋季学期",
  "academicYear": "2026-2027",
  "term": "FALL",
  "startDate": "2026-09-01",
  "endDate": "2027-01-31",
  "scheduleTemplateVersionId": "uuid"
}
```

> 存档（`POST /semesters/:id/archive`）与切换（`POST /semesters/:id/switch`）需要同时检查排课方案状态与草稿，由 D07 以治理用例编排（见 `p3-contracts.md` §3.1）；D01 只提供 `SemesterLifecycleService` 供其调用。

### 3.2 作息模板（D01）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/schedule-templates` | 模板列表（含最新版本） |
| POST | `/schedule-templates` | 新建模板 v1 |
| GET | `/schedule-templates/:id/versions` | 版本列表 |
| POST | `/schedule-templates/:id/versions` | 基于指定版本保存新版本 |
| GET | `/schedule-templates/versions/:versionId` | 版本详情 |
| POST | `/schedule-templates/versions/:versionId/validate` | 节次规则校验 |
| DELETE | `/schedule-templates/:id` | 逻辑删除（引用保护） |

校验规则（A-08）：

- 节次编号从 1 连续；
- 单节 `startTime < endTime`；
- 同日节次不重叠；
- 全部时间在 `00:00-24:00`；
- `openWeekdays` 为非空 1-7 子集。

### 3.3 年级/班级（D02）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/grades` | 列表（含班级数） |
| POST | `/grades` | 新增（受控词表） |
| PATCH | `/grades/:id` | 重命名（受控） |
| DELETE | `/grades/:id` | 引用保护 |
| GET | `/classes` | 列表；`?gradeId=` |
| POST | `/classes` | `{ gradeId, serialNo, headTeacherId?, studentCount }` |
| PATCH | `/classes/:id` | 编辑（名称重新生成） |
| DELETE | `/classes/:id` | 引用保护 |

班级名称由服务端生成：`{grade.name}（{serialNo}）班`；序号 1-99 整数。

### 3.4 科目（D02）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/subjects` | 列表（含规则） |
| POST | `/subjects` | 新增（受控词表 + 同义词） |
| PATCH | `/subjects/:id` | 重命名 |
| PUT | `/subjects/:id/period-rule` | 保存课时规则 |
| GET | `/controlled-vocabularies?type=SUBJECT` | 受控词表 |

### 3.5 教师（D03）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/teachers` | 列表 |
| POST | `/teachers` | 新增；`provisionAccount?: boolean` |
| PATCH | `/teachers/:id` | 编辑（工号不可改） |
| POST | `/teachers/:id/deactivate` | 退校（保留主数据、停用账号） |
| DELETE | `/teachers/:id` | 引用保护 |
| GET | `/teachers/:id/assignments` | 任课列表 |
| POST | `/teaching-assignments` | 新增任课 |
| PATCH | `/teaching-assignments/:id` | 编辑 |
| DELETE | `/teaching-assignments/:id` | 删除 |

### 3.6 场地（D04）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/venues` | 列表 |
| POST | `/venues` | 新增（受控名称、类型二值） |
| PATCH | `/venues/:id` | 编辑 |
| DELETE | `/venues/:id` | 引用保护 |

### 3.7 合班 / 走班（D04）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/combined-classes` | 列表 |
| POST | `/combined-classes` | 新增 |
| PATCH | `/combined-classes/:id` | 编辑 |
| DELETE | `/combined-classes/:id` | 删除 |
| GET | `/walking-groups` | 列表 |
| POST | `/walking-groups` | 新增 |
| PATCH | `/walking-groups/:id` | 编辑 |
| DELETE | `/walking-groups/:id` | 删除 |

---

## 4. 领域事件

| 事件 | 生产者 | 消费者 |
|------|--------|--------|
| `bc.registry.semester.created` | D01 | governance |
| `bc.registry.semester.status-changed` | D01 | timetable、governance |
| `bc.registry.schedule-template.version-created` | D01 | timetable |
| `bc.registry.grade.created` | D02 | — |
| `bc.registry.class.created` | D02 | timetable |
| `bc.registry.subject.rule-configured` | D02 | timetable |
| `bc.resource.teacher.created` | D03 | — |
| `bc.resource.teacher.deactivated` | D03 | identity、timetable |
| `bc.resource.assignment.configured` | D03 | timetable |
| `bc.resource.venue.created` | D04 | timetable |
| `bc.resource.combined-class.configured` | D04 | timetable |
| `bc.resource.walking-group.configured` | D04 | timetable |

---

## 5. 前端路由

| 路由 | 页面 | 卡片 |
|------|------|------|
| `/semesters` | 学期管理（含校历） | D01 |
| `/schedule-templates` | 作息模板与版本 | D01 |
| `/grades-classes` | 年级·班级 | D02 |
| `/subjects` | 科目与课时规则 | D02 |
| `/teachers` | 教师与任课 | D03 |
| `/venues` | 场地·功能室 | D04 |
| `/combined-classes` | 合班课 | D04 |
| `/walking-groups` | 走班配置 | D04 |

---

## 6. 完成判定

- 全部端点有 OpenAPI 描述并通过 Supertest。
- 引用保护、命名受控、状态守卫均有接口测试。
- D15 锚点数据可经 API 读取。
- 所有页面文案中文、空状态与错误提示友好。
- 关键删除操作二次确认并写日志。
