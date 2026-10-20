# 环境配置契约（config-contract.md）

> **唯一真相**：所有环境变量的名称、类型、默认值、读取位置、校验规则以本文件为准。
> 代码中只允许 `backend/src/config/index.ts` 读取 `process.env`；其他文件必须 `import { config } from '@/config'`。
> 违反者视为卡片缺陷。

---

## 1. 加载与校验

1. 启动时用 Zod 校验全部环境变量；校验失败**拒绝启动**并输出缺失/非法项（不输出值）。
2. `.env` 仅用于本地开发；生产使用进程环境变量。
3. 机密值（数据库密码、Session Secret）不得写入 `sys_config`、日志、前端包。
4. 配置只在启动时读取一次；修改后需重启。

---

## 2. 变量清单

### 2.1 运行时

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `NODE_ENV` | `development \| test \| production` | `development` | 是 | 生产启用 Secure Cookie |
| `PORT` | integer 1-65535 | `3000` | 否 | 后端监听端口 |
| `APP_BASE_URL` | url | `http://localhost:5173` | 是 | 前端地址；用于登录回跳、打印页访问 |
| `API_BASE_PATH` | string | `/api/v1` | 否 | API 前缀 |
| `LOG_LEVEL` | `fatal\|error\|warn\|info\|debug\|trace` | `info` | 否 | Pino 级别 |
| `TZ` | string | `Asia/Shanghai` | 否 | 业务时区；周次计算依赖 |

### 2.2 数据库

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `DATABASE_URL` | postgres URL | — | 是 | 例：`postgres://paike:paike@localhost:5432/paike` |
| `DATABASE_POOL_MAX` | integer | `10` | 否 | 连接池上限 |
| `DATABASE_POOL_IDLE_MS` | integer | `30000` | 否 | 空闲连接回收 |
| `DATABASE_STATEMENT_TIMEOUT_MS` | integer | `15000` | 否 | 单语句超时；排课事务单独放宽 |

### 2.3 认证与会话（H-02）

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `SESSION_SECRET` | string ≥32 | — | 是 | 会话签名密钥 |
| `SESSION_COOKIE_NAME` | string | `paike.sid` | 否 | Cookie 名 |
| `SESSION_IDLE_HOURS` | integer | `8` | 否 | 空闲超时 |
| `SESSION_ABSOLUTE_DAYS` | integer | `7` | 否 | 绝对过期 |
| `PAIKE_ADMIN_INITIAL_PASSWORD` | string | 空 | 否 | 管理员初始密码；空则启动时随机生成并仅控制台输出一次 |
| `PASSWORD_MIN_LENGTH` | integer | `8` | 否 | 密码最小长度 |
| `PASSWORD_REQUIRED_CLASSES` | integer 1-4 | `3` | 否 | 大写/小写/数字/符号中至少几类 |
| `LOGIN_MAX_FAILURES` | integer | `5` | 否 | 失败阈值 |
| `LOGIN_FAILURE_WINDOW_MINUTES` | integer | `15` | 否 | 失败统计窗口 |
| `LOGIN_LOCK_MINUTES` | integer | `15` | 否 | 锁定时长 |
| `ARGON2_MEMORY_KIB` | integer | `65536` | 否 | Argon2id 内存 |
| `ARGON2_TIME_COST` | integer | `3` | 否 | Argon2id 迭代 |
| `ARGON2_PARALLELISM` | integer | `1` | 否 | Argon2id 并行度 |

### 2.4 上传 / 导入导出（H-04）

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `UPLOAD_DIR` | path | `./var/uploads` | 否 | 上传临时目录 |
| `EXPORT_TMP_DIR` | path | `./var/exports` | 否 | 导出临时目录 |
| `IMPORT_MAX_ROWS` | integer | `5000` | 否 | 导入数据行上限 |
| `IMPORT_MAX_FILE_MB` | integer | `20` | 否 | 文件大小上限 |
| `IMPORT_TMP_TTL_MINUTES` | integer | `60` | 否 | 临时文件保留时长 |
| `EXPORT_PAGE_SIZE` | integer | `1000` | 否 | 导出分批大小 |

### 2.5 打印（H-04）

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `PRINT_ENGINE` | `playwright` | `playwright` | 否 | 渲染引擎 |
| `PRINT_BASE_URL` | url | `http://localhost:3000` | 是 | 打印页访问地址 |
| `PRINT_TIMEOUT_MS` | integer | `30000` | 否 | 单次渲染超时 |
| `PRINT_MAX_LOGO_MB` | integer | `2` | 否 | 校徽大小上限 |
| `PRINT_TMP_DIR` | path | `./var/prints` | 否 | PDF 临时目录 |

### 2.6 排课引擎

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `SCHEDULER_TIME_BUDGET_MS` | integer | `4500` | 否 | 引擎软时间预算（留 0.5s 给 IO） |
| `SCHEDULER_MAX_BACKTRACK_STEPS` | integer | `200000` | 否 | 回溯步数上限 |
| `SCHEDULER_DEFAULT_SEED` | integer | `20260901` | 否 | 缺省随机种子（保证确定性） |
| `SCHEDULER_MAX_UNDO_STEPS` | integer | `50` | 否 | 撤销栈上限（A-15） |

### 2.7 性能基准（H-03）

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `PERF_DATASET_CLASSES` | integer | `50` | 否 | 基准班级数 |
| `PERF_DATASET_TEACHERS` | integer | `120` | 否 | 基准教师数 |
| `PERF_DATASET_SUBJECTS` | integer | `15` | 否 | 基准科目数 |
| `PERF_DATASET_VENUES` | integer | `60` | 否 | 基准场地数 |
| `PERF_DATASET_LESSONS` | integer | `1500` | 否 | 基准课次 |
| `PERF_SCHEDULE_P95_MS` | integer | `5000` | 否 | 排课 p95 门槛 |
| `PERF_EXPORT_P95_MS` | integer | `3000` | 否 | 导出 p95 门槛 |

### 2.8 测试

| 变量 | 类型 | 默认 | 必须 | 说明 |
|------|------|------|:----:|------|
| `TEST_DATABASE_URL` | postgres URL | — | 测试时是 | 测试库；每个测试文件独立 schema |
| `E2E_BASE_URL` | url | `http://localhost:5173` | 测试时是 | Playwright 基地址 |
| `E2E_ADMIN_PASSWORD` | string | — | 测试时是 | E2E 管理员密码（测试环境专用） |

---

## 3. 读取示例

```ts
// backend/src/config/index.ts
import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().url(),
  SESSION_SECRET: z.string().min(32),
  SESSION_IDLE_HOURS: z.coerce.number().int().positive().default(8),
  SESSION_ABSOLUTE_DAYS: z.coerce.number().int().positive().default(7),
  // ... 其余项
});

const parsed = EnvSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('环境配置不完整，请检查 config-contract.md：');
  for (const issue of parsed.error.issues) {
    console.error(`- ${issue.path.join('.')}: ${issue.message}`);
  }
  process.exit(1);
}

export const config = Object.freeze(parsed.data);
```

---

## 4. 生产部署检查

| 检查 | 要求 |
|------|------|
| HTTPS | 生产必须启用；`NODE_ENV=production` 时 Cookie `Secure` |
| Session Secret | ≥32 字节随机；不得使用示例值 |
| 管理员初始密码 | 通过环境变量注入或控制台一次性获取；首次登录强制改密 |
| 数据库备份 | 每日备份；日志表无删除路径 |
| 时区 | 容器与数据库均 `Asia/Shanghai` |
| 端口 | 仅内网暴露；反向代理终止 TLS |
| 文件目录 | `var/` 可写且不对外静态暴露 |
