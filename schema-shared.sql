-- =============================================================================
-- 智能排课系统 V1.0 — 共享基础设施表（Phase 0 · P0-01）
-- 8 张共享表：迁移账本、账号、会话、登录尝试、运行配置、受控词表、事件发件箱、安全审计
-- 约定：UUID 主键、timestamptz、snake_case、updated_at 触发器
-- 本文件由 P0-01 执行；领域表由各领域卡迁移创建，不在此文件。
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- 0. 共享触发器函数
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 1. sys_migration — 迁移账本
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_migration (
  migration_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  filename       text        NOT NULL UNIQUE,
  checksum       text        NOT NULL,
  applied_at     timestamptz NOT NULL DEFAULT now(),
  duration_ms    integer     NOT NULL DEFAULT 0,
  applied_by     text        NOT NULL DEFAULT current_user
);

COMMENT ON TABLE sys_migration IS '已执行的数据库迁移文件账本；只追加，不修改历史记录';

-- -----------------------------------------------------------------------------
-- 2. sys_user — 本地账号（bc-identity 的持久化载体）
--    登录名 = 工号（教师）或 admin（管理员）；手机号不是登录名（A-06）
-- -----------------------------------------------------------------------------
CREATE TYPE user_role AS ENUM ('ADMIN', 'TEACHER');
CREATE TYPE account_status AS ENUM ('ENABLED', 'DISABLED');

CREATE TABLE IF NOT EXISTS sys_user (
  user_id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username                text           NOT NULL,
  display_name            text           NOT NULL,
  password_hash           text           NOT NULL,
  role                    user_role      NOT NULL,
  status                  account_status NOT NULL DEFAULT 'ENABLED',
  must_change_password    boolean        NOT NULL DEFAULT true,
  teacher_id              uuid           NULL,
  last_login_at           timestamptz    NULL,
  password_changed_at     timestamptz    NULL,
  version                 integer        NOT NULL DEFAULT 1,
  created_at              timestamptz    NOT NULL DEFAULT now(),
  updated_at              timestamptz    NOT NULL DEFAULT now(),
  CONSTRAINT uq_sys_user_username UNIQUE (username),
  CONSTRAINT ck_sys_user_username_format CHECK (username ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$'),
  CONSTRAINT ck_sys_user_teacher_link CHECK (
    (role = 'TEACHER' AND teacher_id IS NOT NULL)
    OR (role = 'ADMIN' AND teacher_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sys_user_teacher
  ON sys_user (teacher_id)
  WHERE teacher_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sys_user_role_status
  ON sys_user (role, status);

CREATE TRIGGER trg_sys_user_updated_at
  BEFORE UPDATE ON sys_user
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE sys_user IS '本地账号；Argon2id 哈希；首次登录强制改密；停用账号下一请求即拒绝';
COMMENT ON COLUMN sys_user.teacher_id IS 'Teacher 账号关联的教师主数据；Admin 为空';

-- -----------------------------------------------------------------------------
-- 3. sys_session — 服务端会话（express-session 持久化）
--    空闲 8h / 绝对 7d；活动滑动续期；退出/停用立即失效
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_session (
  sid         text PRIMARY KEY,
  user_id     uuid        NULL REFERENCES sys_user(user_id) ON DELETE CASCADE,
  data        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_sys_session_user
  ON sys_session (user_id)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sys_session_expires
  ON sys_session (expires_at);

COMMENT ON TABLE sys_session IS '服务端会话；退出或停用账号时置 revoked_at；绝对过期由 expires_at 控制';

-- -----------------------------------------------------------------------------
-- 4. sys_login_attempt — 登录失败与锁定
--    同一用户名 + IP，15 分钟内失败 5 次，锁定 15 分钟
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_login_attempt (
  attempt_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username      text        NOT NULL,
  ip_address    inet        NOT NULL,
  success       boolean     NOT NULL,
  failure_reason text       NULL,
  attempted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sys_login_attempt_lookup
  ON sys_login_attempt (username, ip_address, attempted_at DESC);

COMMENT ON TABLE sys_login_attempt IS '登录尝试审计；用于失败计数与锁定判定；不记录密码';

-- -----------------------------------------------------------------------------
-- 5. sys_config — 运行期配置（非机密）
--    机密配置只走环境变量，不入库
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_config (
  config_key    text PRIMARY KEY,
  config_value  jsonb       NOT NULL,
  description   text        NOT NULL DEFAULT '',
  updated_by    uuid        NULL REFERENCES sys_user(user_id),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_sys_config_updated_at
  BEFORE UPDATE ON sys_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE sys_config IS '非敏感运行配置；机密配置（数据库密码、Session Secret）只允许环境变量';

-- -----------------------------------------------------------------------------
-- 6. sys_controlled_vocabulary — 受控词表与同义词
--    type: SUBJECT / GRADE / VENUE / SUBJECT_SYNONYM
--    用于科目/年级/场地名称受控校验与同义不同名拦截（M-23）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_controlled_vocabulary (
  vocabulary_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vocab_type     text        NOT NULL,
  canonical_name text        NOT NULL,
  synonym_of     text        NULL,
  sort_order     integer     NOT NULL DEFAULT 0,
  is_active      boolean     NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vocab_type CHECK (vocab_type IN ('SUBJECT', 'GRADE', 'VENUE', 'SUBJECT_SYNONYM')),
  CONSTRAINT ck_vocab_synonym CHECK (
    (vocab_type = 'SUBJECT_SYNONYM' AND synonym_of IS NOT NULL)
    OR (vocab_type <> 'SUBJECT_SYNONYM')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_vocab_type_name
  ON sys_controlled_vocabulary (vocab_type, canonical_name);

CREATE INDEX IF NOT EXISTS idx_vocab_type_active
  ON sys_controlled_vocabulary (vocab_type, is_active, sort_order);

CREATE TRIGGER trg_sys_vocab_updated_at
  BEFORE UPDATE ON sys_controlled_vocabulary
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE sys_controlled_vocabulary IS '受控名称与同义词；新增科目/年级/场地时校验；同义词命中即拒绝';

-- -----------------------------------------------------------------------------
-- 7. sys_outbox_event — 领域事件发件箱
--    与业务写入同事务；提交后由 dispatcher 投递；表名/事件名见 contracts/events.yaml
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_outbox_event (
  event_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name     text        NOT NULL,
  schema_version integer     NOT NULL DEFAULT 1,
  aggregate_type text        NOT NULL,
  aggregate_id   uuid        NOT NULL,
  payload        jsonb       NOT NULL,
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  occurred_by    uuid        NULL REFERENCES sys_user(user_id),
  published_at   timestamptz NULL,
  attempt_count  integer     NOT NULL DEFAULT 0,
  last_error     text        NULL
);

CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
  ON sys_outbox_event (occurred_at)
  WHERE published_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
  ON sys_outbox_event (aggregate_type, aggregate_id);

COMMENT ON TABLE sys_outbox_event IS '事务性发件箱；未发布事件按 occurred_at 顺序投递；至少一次语义';

-- -----------------------------------------------------------------------------
-- 8. sys_audit_log — 安全审计（追加写）
--    与业务操作日志 operation_log 分离：本表记录登录/权限/账号安全事件
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sys_audit_log (
  audit_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id      uuid        NULL REFERENCES sys_user(user_id),
  actor_name    text        NULL,
  action        text        NOT NULL,
  target_type   text        NULL,
  target_id     uuid        NULL,
  result        text        NOT NULL,
  ip_address    inet        NULL,
  user_agent    text        NULL,
  detail        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_audit_result CHECK (result IN ('SUCCESS', 'FAILURE', 'DENIED'))
);

CREATE INDEX IF NOT EXISTS idx_audit_actor_time
  ON sys_audit_log (actor_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_action_time
  ON sys_audit_log (action, occurred_at DESC);

COMMENT ON TABLE sys_audit_log IS '安全审计日志；只追加；无更新/删除 API；记录登录、锁定、改密、角色变更、越权';

-- -----------------------------------------------------------------------------
-- 9. 基础配置种子（非业务数据）
-- -----------------------------------------------------------------------------
INSERT INTO sys_config (config_key, config_value, description)
VALUES
  ('session.idleHours', '8'::jsonb, '会话空闲超时（小时）'),
  ('session.absoluteDays', '7'::jsonb, '会话绝对过期（天）'),
  ('login.maxFailures', '5'::jsonb, '15 分钟内允许的最大失败次数'),
  ('login.lockMinutes', '15'::jsonb, '锁定分钟数'),
  ('import.maxRows', '5000'::jsonb, '单次导入最大数据行'),
  ('import.maxFileMb', '20'::jsonb, '单次导入最大文件大小（MB）'),
  ('password.minLength', '8'::jsonb, '密码最小长度'),
  ('password.requiredClasses', '3'::jsonb, '密码至少包含的字符类别数')
ON CONFLICT (config_key) DO NOTHING;
