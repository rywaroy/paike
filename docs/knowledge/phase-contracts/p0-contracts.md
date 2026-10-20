# Phase 0 契约摘要（p0-contracts.md）

> Phase 0 产出：数据库与迁移、认证会话、共享内核、前端骨架、Seed、契约冻结、Hub 集成、登录界面。
> Phase 1+ 全部卡片只能消费本文件声明的能力，不得重复实现。

---

## 1. 产出卡片

| 卡片 | 产出 |
|------|------|
| P0-01 | PostgreSQL 连接池、迁移运行器、`schema-shared.sql` 8 张共享表 |
| P0-02 | 登录/退出/改密/会话/CSRF/RBAC/锁定 |
| P0-03 | 响应封装、错误、校验、事件发件箱、审计、时间、导入导出打印骨架 |
| P0-04 | Vue 应用骨架、布局、路由守卫、API 客户端、共享组件、文案 |
| P0-05 | `seed-anchors.sql`：管理员、受控词表、D15 锚点 |
| P0-06 | `contracts/` 六件套 |
| P0-07 | Hub 自动扫描、ESLint 边界规则、类型检查门 |
| P0-08 | 登录页、强制改密页、403/404 页、会话失效处理 |

---

## 2. 数据库

共享表（P0-01）：

| 表 | 用途 |
|----|------|
| `sys_migration` | 迁移账本 |
| `sys_user` | 本地账号 |
| `sys_session` | 服务端会话 |
| `sys_login_attempt` | 登录失败/锁定 |
| `sys_config` | 非敏感运行配置 |
| `sys_controlled_vocabulary` | 受控词表与同义词 |
| `sys_outbox_event` | 事件发件箱 |
| `sys_audit_log` | 安全审计 |

迁移约定：

- 文件 `migrations/NNNN_name.sql`，序号在卡片中声明。
- 领域表由领域卡创建，不在 `schema-shared.sql`。
- 所有迁移幂等（`IF NOT EXISTS` / `ON CONFLICT`）。

---

## 3. 认证 API

| 方法 | 路径 | 说明 | 权限 |
|------|------|------|------|
| GET | `/api/v1/auth/csrf` | 获取 CSRF Token | 公开 |
| POST | `/api/v1/auth/login` | 登录 | 公开 |
| POST | `/api/v1/auth/logout` | 退出 | 已登录 |
| GET | `/api/v1/auth/me` | 当前用户 | 已登录 |
| POST | `/api/v1/auth/change-password` | 改密 | 已登录 |

登录请求：

```json
{ "username": "admin", "password": "********" }
```

登录成功：

```json
{
  "data": {
    "user": {
      "userId": "...",
      "username": "admin",
      "displayName": "教务管理员",
      "role": "ADMIN",
      "teacherId": null,
      "mustChangePassword": true
    }
  }
}
```

失败：

| 场景 | HTTP | code | message |
|------|------|------|---------|
| 账号或密码错误 | 401 | `UNAUTHENTICATED` | 用户名或密码错误 |
| 账号停用 | 403 | `FORBIDDEN` | 账号已停用，请联系管理员 |
| 锁定 | 423 | `ACCOUNT_LOCKED` | 登录失败次数过多，请 15 分钟后再试 |
| 非强制改密期间访问其他接口 | 403 | `STATE_CONFLICT` | 请先修改初始密码 |

---

## 4. 会话与安全

| 项 | 值 |
|----|----|
| Cookie | `paike.sid`；HttpOnly；SameSite=Lax；生产 Secure |
| 空闲超时 | 8 小时（活动滑动续期） |
| 绝对过期 | 7 天 |
| 退出 | 服务端置 `sys_session.revoked_at` |
| 角色 | 每请求从数据库读取 |
| 停用账号 | 下一请求 401，会话撤销 |
| 登录失败 | 同用户名+IP 15 分钟内 5 次 → 锁定 15 分钟 |
| 密码哈希 | Argon2id（memory 64 MiB, time 3, parallelism 1） |
| 密码策略 | ≥8 位，大写/小写/数字/符号至少 3 类 |
| CSRF | 所有非 GET 请求必须带 `X-CSRF-Token` |

---

## 5. 共享内核导出

完整签名见 `docs/knowledge/shared-kernel-api.md`。Phase 1+ 必用的：

| 模块 | import |
|------|--------|
| 连接池 | `@/shared/db/pool` |
| 事务 | `@/shared/db/transaction` |
| 会话 | `@/shared/auth/session` |
| 权限 | `@/shared/auth/rbac` |
| 响应 | `@/shared/http/envelope` |
| 错误 | `@/shared/errors/app-error`、`@/shared/errors/codes` |
| 校验 | `@/shared/validation/common` |
| 事件 | `@/shared/events/outbox` |
| 操作日志 | `@/shared/audit/operation-log` |
| 安全审计 | `@/shared/audit/security-audit` |
| 时钟 | `@/shared/time/clock` |
| 周次 | `@/shared/time/academic-week` |
| 时段 | `@/shared/time/slot-expression` |
| 前端 HTTP | `@/shared/api/http` |
| 前端会话 | `@/shared/stores/session` |
| 前端学期 | `@/shared/stores/semester` |
| 前端确认 | `@/shared/composables/useConfirm` |
| 前端文案 | `@/shared/text/messages` |

---

## 6. 契约冻结产物

`contracts/` 六件套：

| 文件 | 内容 |
|------|------|
| `openapi.yaml` | 全部 Phase 1+ 端点、请求/响应 schema、错误码 |
| `schema.sql` | 全部表 DDL（共享 + 领域） |
| `events.yaml` | 全部领域事件名、payload、生产者/消费者 |
| `naming.yaml` | 枚举、命名、错误码、字段字典 |
| `routes.yaml` | 前端路由、菜单、角色 |
| `cross-context-writes.md` | 跨域写入点与事务边界 |

---

## 7. 完成判定

- `npm run db:migrate` 在空库成功。
- `npm run db:seed` 成功；`admin` 可登录并强制改密。
- `GET /api/v1/health` 返回 `{ data: { status: 'ok', db: true } }`。
- 未登录访问受保护接口返回 401。
- 前端可启动，未登录跳 `/login`，登录后进入概览。
- `contracts/` 六件套存在且通过 OpenAPI 校验。
