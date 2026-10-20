-- =============================================================================
-- 智能排课系统 V1.0 — 跨域共享测试数据锚点（seed-anchors.sql）
--
-- 用法：
--   1) Phase 0（P0-05）：仅执行「第一节 共享锚点」；此时领域表尚不存在。
--   2) 领域卡完成后：可重复执行本文件，第二节会在领域表存在时补齐 D15 锚点。
--   3) 所有 UUID 固定，测试不得依赖自增 ID；所有 INSERT 幂等（ON CONFLICT DO NOTHING）。
--
-- 约定：
--   - 本文件不包含大规模演示数据；50 班性能数据集由 scripts/perf/generate-dataset.ts 生成。
--   - 管理员初始密码不在此文件硬编码；由启动引导脚本写入 Argon2id 哈希。
-- =============================================================================

-- =============================================================================
-- 第一节：共享锚点（Phase 0 可执行）
-- =============================================================================

-- 1.1 默认管理员账号（H-02）
-- password_hash 占位符由 `npm run db:seed` 的引导逻辑替换为 Argon2id 哈希；
-- 若未替换，应用拒绝启动并提示执行引导脚本。
INSERT INTO sys_user (
  user_id, username, display_name, password_hash, role, status, must_change_password
) VALUES (
  '00000000-0000-4000-8000-000000000100',
  'admin',
  '教务管理员',
  '__BOOTSTRAP_ADMIN_PASSWORD__',
  'ADMIN',
  'ENABLED',
  true
)
ON CONFLICT (username) DO NOTHING;

-- 1.2 受控词表：年级
INSERT INTO sys_controlled_vocabulary (vocabulary_id, vocab_type, canonical_name, sort_order)
VALUES
  ('00000000-0000-4000-8000-000000000120', 'GRADE', '七年级', 10),
  ('00000000-0000-4000-8000-000000000121', 'GRADE', '八年级', 20),
  ('00000000-0000-4000-8000-000000000122', 'GRADE', '九年级', 30)
ON CONFLICT (vocab_type, canonical_name) DO NOTHING;

-- 1.3 受控词表：科目
INSERT INTO sys_controlled_vocabulary (vocabulary_id, vocab_type, canonical_name, sort_order)
VALUES
  ('00000000-0000-4000-8000-000000000130', 'SUBJECT', '语文', 10),
  ('00000000-0000-4000-8000-000000000131', 'SUBJECT', '数学', 20),
  ('00000000-0000-4000-8000-000000000132', 'SUBJECT', '英语', 30),
  ('00000000-0000-4000-8000-000000000133', 'SUBJECT', '物理', 40),
  ('00000000-0000-4000-8000-000000000134', 'SUBJECT', '化学', 50),
  ('00000000-0000-4000-8000-000000000135', 'SUBJECT', '生物', 60),
  ('00000000-0000-4000-8000-000000000136', 'SUBJECT', '体育', 70),
  ('00000000-0000-4000-8000-000000000137', 'SUBJECT', '音乐', 80),
  ('00000000-0000-4000-8000-000000000138', 'SUBJECT', '美术', 90)
ON CONFLICT (vocab_type, canonical_name) DO NOTHING;

-- 1.4 受控词表：科目同义词（命中即拒绝，M-23）
INSERT INTO sys_controlled_vocabulary (vocabulary_id, vocab_type, canonical_name, synonym_of)
VALUES
  ('00000000-0000-4000-8000-000000000140', 'SUBJECT_SYNONYM', '语', '语文'),
  ('00000000-0000-4000-8000-000000000141', 'SUBJECT_SYNONYM', '语文课', '语文'),
  ('00000000-0000-4000-8000-000000000142', 'SUBJECT_SYNONYM', '数', '数学'),
  ('00000000-0000-4000-8000-000000000143', 'SUBJECT_SYNONYM', '数学课', '数学'),
  ('00000000-0000-4000-8000-000000000144', 'SUBJECT_SYNONYM', '英', '英语'),
  ('00000000-0000-4000-8000-000000000145', 'SUBJECT_SYNONYM', '英语课', '英语')
ON CONFLICT (vocab_type, canonical_name) DO NOTHING;

-- 1.5 受控词表：场地
INSERT INTO sys_controlled_vocabulary (vocabulary_id, vocab_type, canonical_name, sort_order)
VALUES
  ('00000000-0000-4000-8000-000000000150', 'VENUE', '301', 10),
  ('00000000-0000-4000-8000-000000000151', 'VENUE', '实验室1', 20),
  ('00000000-0000-4000-8000-000000000152', 'VENUE', '音乐教室', 30),
  ('00000000-0000-4000-8000-000000000153', 'VENUE', '美术教室', 40),
  ('00000000-0000-4000-8000-000000000154', 'VENUE', '操场', 50)
ON CONFLICT (vocab_type, canonical_name) DO NOTHING;

-- =============================================================================
-- 第二节：D15 最小确定性验收样例锚点（领域迁移完成后执行）
-- 来源：PRD 附件 A；固定 UUID 供 TC-AP-017 逐格断言
-- =============================================================================

DO $$
BEGIN
  IF to_regclass('public.schedule_template_version') IS NULL
     OR to_regclass('public.semester') IS NULL
     OR to_regclass('public.class') IS NULL
     OR to_regclass('public.teacher') IS NULL
     OR to_regclass('public.subject') IS NULL
     OR to_regclass('public.venue') IS NULL
     OR to_regclass('public.teaching_assignment') IS NULL THEN
    RAISE NOTICE '领域表尚未创建，跳过 D15 锚点（第二节）。领域卡完成后可重复执行本文件。';
    RETURN;
  END IF;

  -- 2.1 作息模板 + 版本：周一至周三，每天 4 节
  INSERT INTO schedule_template (template_id, name, status, latest_version_no)
  VALUES ('00000000-0000-4000-8000-000000000101', 'D15-基准作息', 'ACTIVE', 1)
  ON CONFLICT (name) DO NOTHING;

  INSERT INTO schedule_template_version (
    version_id, template_id, version_no, open_weekdays, periods, status
  ) VALUES (
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000101',
    1,
    ARRAY[1,2,3]::smallint[],
    '[
      {"periodNo":1,"startTime":"08:00","endTime":"08:45","label":"第 1 节"},
      {"periodNo":2,"startTime":"08:55","endTime":"09:40","label":"第 2 节"},
      {"periodNo":3,"startTime":"09:55","endTime":"10:40","label":"第 3 节"},
      {"periodNo":4,"startTime":"10:50","endTime":"11:35","label":"第 4 节"}
    ]'::jsonb,
    'ACTIVE'
  )
  ON CONFLICT (template_id, version_no) DO NOTHING;

  -- 2.2 学期：绑定模板版本（M-01 钉扎版本）
  INSERT INTO semester (
    semester_id, name, academic_year, term, start_date, end_date,
    status, schedule_template_version_id, is_current
  ) VALUES (
    '00000000-0000-4000-8000-000000000103',
    'D15-基准学期', '2026-2027', 'FALL', '2026-09-07', '2026-09-25',
    'IN_PROGRESS', '00000000-0000-4000-8000-000000000102', true
  )
  ON CONFLICT (semester_id) DO NOTHING;

  -- 2.3 年级
  INSERT INTO grade (grade_id, name, sort_order)
  VALUES ('00000000-0000-4000-8000-000000000104', '七年级', 10)
  ON CONFLICT (name) DO NOTHING;

  -- 2.4 班级 A/B
  INSERT INTO class (class_id, grade_id, name, serial_no, student_count)
  VALUES
    ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-000000000104', '七年级（1）班', 1, 40),
    ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-000000000104', '七年级（2）班', 2, 40)
  ON CONFLICT (grade_id, serial_no) DO NOTHING;

  -- 2.5 科目 数学 / 英语
  INSERT INTO subject (subject_id, name)
  VALUES
    ('00000000-0000-4000-8000-000000000107', '数学'),
    ('00000000-0000-4000-8000-000000000108', '英语')
  ON CONFLICT (name) DO NOTHING;

  -- 2.6 教师 张老师 / 李老师（工号受控 T+数字）
  INSERT INTO teacher (teacher_id, employee_no, name, gender, phone, status)
  VALUES
    ('00000000-0000-4000-8000-000000000109', 'T1001', '张老师', 'MALE', '13800001001', 'ACTIVE'),
    ('00000000-0000-4000-8000-00000000010a', 'T1002', '李老师', 'FEMALE', '13800001002', 'ACTIVE')
  ON CONFLICT (employee_no) DO NOTHING;

  -- 2.7 功能室 301（英语专用；容量 45 ≥ 班级人数 40）
  INSERT INTO venue (venue_id, name, type, capacity, status)
  VALUES ('00000000-0000-4000-8000-00000000010b', '301', 'FUNCTION_ROOM', 45, 'AVAILABLE')
  ON CONFLICT (name) DO NOTHING;

  -- 2.8 任课约束：
  --   A 班数学×2（张，必须连堂）；A 班英语×1（李，301）
  --   B 班数学×2（李）；B 班英语×1（张，301）
  --   免排：李 周二第 1 节；张 周三第 4 节
  INSERT INTO teaching_assignment (
    assignment_id, teacher_id, subject_id, class_id, venue_id, weekly_periods,
    consecutive_preference, forbidden_slots, exempted_slots
  ) VALUES
    ('00000000-0000-4000-8000-00000000010c',
     '00000000-0000-4000-8000-000000000109', '00000000-0000-4000-8000-000000000107',
     '00000000-0000-4000-8000-000000000105', NULL, 2, 'REQUIRED', '[]'::jsonb, '[]'::jsonb),
    ('00000000-0000-4000-8000-00000000010d',
     '00000000-0000-4000-8000-00000000010a', '00000000-0000-4000-8000-000000000108',
     '00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-00000000010b', 1,
     'NONE', '[]'::jsonb, '[]'::jsonb),
    ('00000000-0000-4000-8000-00000000010e',
     '00000000-0000-4000-8000-00000000010a', '00000000-0000-4000-8000-000000000107',
     '00000000-0000-4000-8000-000000000106', NULL, 2, 'NONE', '[]'::jsonb, '[]'::jsonb),
    ('00000000-0000-4000-8000-00000000010f',
     '00000000-0000-4000-8000-000000000109', '00000000-0000-4000-8000-000000000108',
     '00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-00000000010b', 1,
     'NONE', '[]'::jsonb, '[]'::jsonb)
  ON CONFLICT (assignment_id) DO NOTHING;

  -- 2.9 免排时段（附着于任课记录：teacher + weekday + period）
  --     李 周二第 1 节免排：作用于其两门任课（A 英语、B 数学）
  UPDATE teaching_assignment
     SET exempted_slots = '[{"weekday":2,"period":1}]'::jsonb
   WHERE assignment_id IN (
     '00000000-0000-4000-8000-00000000010d',
     '00000000-0000-4000-8000-00000000010e'
   );

  --     张 周三第 4 节免排：作用于其两门任课（A 数学、B 英语）
  UPDATE teaching_assignment
     SET exempted_slots = '[{"weekday":3,"period":4}]'::jsonb
   WHERE assignment_id IN (
     '00000000-0000-4000-8000-00000000010c',
     '00000000-0000-4000-8000-00000000010f'
   );

  -- 2.10 科目规则：英语禁排周三第 3~4 节（PRD 附件 A 约束②）
  INSERT INTO subject_period_rule (
    rule_id, subject_id, weekly_periods, consecutive_preference,
    forbidden_slots, time_slot_preference,
    period_balance_enabled, am_pm_balance_enabled, fixed_slot_rule_enabled
  ) VALUES (
    '00000000-0000-4000-8000-000000000110',
    '00000000-0000-4000-8000-000000000108',
    1, 'NONE',
    '[{"weekday":3,"period":3},{"weekday":3,"period":4}]'::jsonb,
    'NONE', false, false, false
  )
  ON CONFLICT (subject_id) DO NOTHING;

  RAISE NOTICE 'D15 锚点已写入（固定 UUID）。';
END;
$$;
