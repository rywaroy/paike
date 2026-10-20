# 共享内核 API（shared-kernel-api.md）

> 共享内核位于 `backend/src/shared/**` 与 `frontend/src/shared/**`。本文件定义对外签名与数据结构；实现由 P0-01 ~ P0-04 卡片落地。
> import 路径以 `shared-kernel-manifest.yaml` 为准。

---

## 1. 数据库（backend）

```ts
// @/shared/db/pool
export const db: Pool;
export function query<T extends QueryResultRow>(sql: string, params?: unknown[]): Promise<T[]>;
export function queryOne<T extends QueryResultRow>(sql: string, params?: unknown[]): Promise<T | null>;
export function queryMany<T extends QueryResultRow>(sql: string, params?: unknown[]): Promise<T[]>;
export function healthCheck(): Promise<boolean>;
export function closePool(): Promise<void>;

// @/shared/db/transaction
export type Tx = { query: typeof query; queryOne: typeof queryOne; queryMany: typeof queryMany };
export function withTransaction<T>(fn: (tx: Tx) => Promise<T>, options?: {
  isolation?: 'READ COMMITTED' | 'REPEATABLE READ' | 'SERIALIZABLE';
  timeoutMs?: number;
}): Promise<T>;
```

规则：

- 事务内必须使用 `tx`，不得使用全局 `db`。
- 乐观锁更新返回 0 行时抛 `VersionConflictError`。
- 事务内写 `operation_log` / `sys_outbox_event` 与业务写入同事务。

---

## 2. 错误与响应（backend）

```ts
// @/shared/errors/app-error
export class AppError extends Error {
  constructor(code: ErrorCode, httpStatus: number, message: string, details?: ErrorDetail[], cause?: unknown);
}
export class ValidationError extends AppError {}
export class NotFoundError extends AppError {}
export class ForbiddenError extends AppError {}
export class ConflictError extends AppError {}       // 409 DUPLICATE / REFERENCE_PROTECTED / STATE_CONFLICT
export class VersionConflictError extends AppError {} // 409 VERSION_CONFLICT

// @/shared/http/envelope
export function ok<T>(res: Response, data: T): void;
export function created<T>(res: Response, data: T): void;
export function noContent(res: Response): void;
export function paginated<T>(res: Response, items: T[], page: number, pageSize: number, total: number): void;
export function fail(res: Response, error: AppError): void;
```

`ErrorDetail`：

```ts
interface ErrorDetail {
  field?: string;
  message: string; // 中文、面向用户
  rowNo?: number;  // 导入错误
  column?: string;
  rawValue?: string;
}
```

---

## 3. 认证与权限（backend）

```ts
// @/shared/auth/password
export function hashPassword(plain: string): Promise<string>;
export function verifyPassword(hash: string, plain: string): Promise<boolean>;
export function validatePasswordPolicy(plain: string): { ok: true } | { ok: false; message: string };
export function generateInitialPassword(length?: number): string;

// @/shared/auth/session
export const sessionMiddleware: RequestHandler;
export function createSession(req: Request, userId: string): Promise<void>;
export function destroySession(req: Request, reason: 'LOGOUT' | 'DISABLED' | 'PASSWORD_RESET'): Promise<void>;
export function touchSession(req: Request): Promise<void>;
export function assertSessionValid(req: Request): Promise<void>;

// @/shared/auth/rbac
export const requireAuth: RequestHandler;
export function requireRole(...roles: UserRole[]): RequestHandler;
export const requireAdmin: RequestHandler;
export function loadCurrentUser(req: Request): Promise<CurrentUser>;
export function canAccessTeacherResource(user: CurrentUser, targetTeacherId: string): boolean;

// @/shared/auth/csrf
export const csrfMiddleware: RequestHandler;
export function issueCsrfToken(req: Request, res: Response): void;

// @/shared/auth/lockout
export function recordLoginAttempt(input: {
  username: string; ip: string; success: boolean; failureReason?: string;
}): Promise<void>;
export function isLocked(username: string, ip: string): Promise<boolean>;
export function lockRemainingSeconds(username: string, ip: string): Promise<number>;
export function clearFailures(username: string, ip: string): Promise<void>;
```

`CurrentUser`：

```ts
interface CurrentUser {
  userId: string;
  username: string;
  displayName: string;
  role: 'ADMIN' | 'TEACHER';
  teacherId: string | null;
  mustChangePassword: boolean;
}
```

---

## 4. 时间与时段（backend）

```ts
// @/shared/time/clock
export interface Clock { now(): Date; today(): string; } // today(): YYYY-MM-DD
export const systemClock: Clock;
export function fixedClock(iso: string): Clock;

// @/shared/time/academic-week
export function weekIndexForDate(semesterStart: string, date: string): number; // 1-based
export function parityForWeekIndex(weekIndex: number): 'ODD' | 'EVEN';
export function weeksInSemester(semesterStart: string, semesterEnd: string): number;
export function resolveWeekParity(weekIndex: number, lessonParity: 'ALL' | 'ODD' | 'EVEN'): boolean;

// @/shared/time/slot-expression
export interface Slot { weekday: 1|2|3|4|5|6|7; period: number; }
export function parseSlotExpression(input: string): Slot[];      // "周一第1-2节,周三第3节"
export function formatSlotExpression(slots: Slot[]): string;
export function overlaps(a: Slot, b: Slot): boolean;
export function slotsOverlap(a: Slot[], b: Slot[]): boolean;
```

**时段 JSON 结构**（数据库/API 通用）：

```json
[
  { "weekday": 1, "period": 1 },
  { "weekday": 1, "period": 2 },
  { "weekday": 3, "period": 3 }
]
```

**节次时间表结构**（`schedule_template_version.periods`）：

```json
[
  { "periodNo": 1, "startTime": "08:00", "endTime": "08:45", "label": "第 1 节" }
]
```

---

## 5. 事件与审计（backend）

```ts
// @/shared/events/outbox
export function appendEvent(tx: Tx, input: {
  eventName: string;
  aggregateType: string;
  aggregateId: string;
  payload: Record<string, unknown>;
  occurredBy?: string;
}): Promise<void>;
export function dispatchPendingEvents(batchSize?: number): Promise<number>;
export function registerEventHandler(eventName: string, handler: (e: OutboxEvent) => Promise<void>): void;

// @/shared/audit/operation-log
export interface OperationLogInput {
  operatorId: string;
  operatorName: string;
  module: 'DELETE' | 'PUBLISH' | 'OVERWRITE' | 'SWITCH_SEMESTER' | 'IMPORT' | 'ARCHIVE' | 'ADJUST';
  action: string;
  content: string;        // 中文、可读
  targetType: string;
  targetId: string;
}
export function writeOperationLog(tx: Tx, input: OperationLogInput): Promise<void>;

// @/shared/audit/security-audit
export interface SecurityAuditInput {
  actorId?: string;
  actorName?: string;
  action: string;         // LOGIN_SUCCESS / LOGIN_FAILURE / LOCKED / LOGOUT / PASSWORD_CHANGED / ROLE_CHANGED / ACCESS_DENIED ...
  targetType?: string;
  targetId?: string;
  result: 'SUCCESS' | 'FAILURE' | 'DENIED';
  ip?: string;
  userAgent?: string;
  detail?: Record<string, unknown>;
}
export function writeSecurityAudit(input: SecurityAuditInput): Promise<void>;
```

规则：

- 操作日志内容必须可直接展示，例如「发布 2026 秋季正式课表（方案 2026秋-v4）」。
- 所有日志写入禁止记录密码、Cookie、CSRF Token。

---

## 6. 导入（backend）

```ts
// @/shared/import/xlsx-reader
export interface TabularRow {
  rowNo: number;                       // Excel 行号（含表头，数据从 2 开始）
  values: Record<string, string | number | boolean | null>;
}
export interface TabularFile {
  headers: string[];
  rows: TabularRow[];
  unknownHeaders: string[];
}
export function readTabularFile(buffer: Buffer, filename: string): Promise<TabularFile>;

// @/shared/import/import-runner
export interface ImportRowError {
  rowNo: number;
  column?: string;
  rawValue?: string;
  reason: string;   // 中文
}
export interface ImportResult {
  batchId: string;
  total: number;
  success: number;
  failed: number;
  status: 'COMPLETED' | 'PARTIAL' | 'FAILED';
  errors: ImportRowError[];
  errorReportUrl?: string;
}
export interface ImportDefinition<T> {
  module: ImportModule;
  requiredHeaders: string[];
  maxRows: number;
  parseRow(row: TabularRow): { ok: true; value: T } | { ok: false; errors: ImportRowError[] };
  persist(tx: Tx, value: T): Promise<void>;
}
export function runImport<T>(input: {
  definition: ImportDefinition<T>;
  file: TabularFile;
  operator: CurrentUser;
  fileMeta: { name: string; sizeBytes: number };
}): Promise<ImportResult>;

// @/shared/import/error-report
export function buildErrorCsv(errors: ImportRowError[]): Buffer; // UTF-8 BOM
```

规则：

- 文件校验在解析前：大小 > 20 MB → `FILE_TOO_LARGE`；行数 > 5000 → 整份拒绝。
- 表头缺失必填列 → 整份拒绝。
- 合法行逐行事务提交；数据库故障整批回滚并重建批次状态为 `FAILED`。
- 错误报告为一次性下载，路径不入库长期保留。

---

## 7. 导出（backend）

```ts
// @/shared/export/xlsx-writer
export interface SheetDefinition {
  name: string;
  columns: ColumnDefinition[];
  rows: Array<Record<string, unknown>>;
}
export function buildWorkbook(sheets: SheetDefinition[]): Buffer;

// @/shared/export/column-dictionary
export interface ColumnDefinition {
  key: string;
  header: string;        // 中文列名
  width?: number;
  format?: 'text' | 'number' | 'date' | 'time';
  order: number;
}
export const COLUMN_DICTIONARY: Record<ExportDimension, ColumnDefinition[]>;
export function columnsFor(dimension: ExportDimension): ColumnDefinition[];
```

**列字典（摘要，完整版由 D10 实现并以合同为准）**：

| 维度 | 列 |
|------|----|
| `TIMETABLE_CLASS` | 班级、星期、节次、周次类型、科目、教师、场地、锁定状态 |
| `TIMETABLE_TEACHER` | 教师、工号、星期、节次、周次类型、科目、班级、场地 |
| `TIMETABLE_SCHOOL` | 班级、星期、节次、周次类型、科目、教师、场地 |
| `MASTER_TEACHER_ASSIGNMENT` | 工号、教师、科目、班级、场地、每周课时、免排时段、连堂偏好 |
| `MASTER_CLASS` | 年级、班级、班主任、人数 |
| `STAT_WORKLOAD` | 教师、常规、连堂、合班、加班、周汇总、学期汇总 |

规则：

- 只导出值；日期 `YYYY-MM-DD`；时间 `HH:mm`；空值为空单元格；冻结表头。
- 文件名 `{维度}_{学期}_{YYYYMMDDHHmm}.xlsx`。
- 所有维度列顺序由 `order` 决定，与页面展示一致。

---

## 8. 打印（backend）

```ts
// @/shared/pdf/pdf-renderer
export interface PdfRenderOptions {
  html: string;
  paperSize: 'A4' | 'A3';
  orientation: 'PORTRAIT' | 'LANDSCAPE';
  marginMm?: { top: number; right: number; bottom: number; left: number };
  timeoutMs?: number;
}
export function renderPdf(options: PdfRenderOptions): Promise<Buffer>;
```

规则：

- 预览与打印使用同一 HTML 模板与同一 `renderPdf`。
- 校徽以 data URI 内嵌，≤2 MB。
- 打印页通过 `PRINT_BASE_URL` 访问受保护 HTML（使用一次性签名 token，有效期 60 秒）。

---

## 9. 上传（backend）

```ts
// @/shared/upload/file-guard
export const uploadSingle: RequestHandler;   // multer memory storage，限制 20 MB
export function assertFileLimits(file: { size: number; originalname: string }): void;
```

---

## 10. 前端共享 API

```ts
// @/shared/api/http
export class ApiError extends Error {
  code: string;
  status: number;
  details?: ErrorDetail[];
}
export const http: {
  get<T>(url: string, params?: Record<string, unknown>): Promise<T>;
  post<T>(url: string, body?: unknown): Promise<T>;
  patch<T>(url: string, body?: unknown): Promise<T>;
  put<T>(url: string, body?: unknown): Promise<T>;
  delete<T>(url: string): Promise<T>;
  download(url: string, body?: unknown): Promise<Blob>;
};
export function onUnauthorized(handler: () => void): void;

// @/shared/api/query
export function useQuery<T>(key: () => string, fetcher: () => Promise<T>, options?: {
  immediate?: boolean;
  watch?: () => unknown;
}): { data: Ref<T | null>; loading: Ref<boolean>; error: Ref<ApiError | null>; refresh: () => Promise<void> };
export function useMutation<Input, Output>(fn: (input: Input) => Promise<Output>): {
  run: (input: Input) => Promise<Output>;
  loading: Ref<boolean>;
  error: Ref<ApiError | null>;
};

// @/shared/composables/useConfirm
export interface ConfirmOptions {
  title: string;
  description: string;
  impact?: string;
  confirmText: string;
  cancelText?: string;
  danger?: boolean;
}
export function useConfirm(): (options: ConfirmOptions) => Promise<boolean>;

// @/shared/composables/useAsyncAction
export function useAsyncAction<T>(fn: () => Promise<T>, options?: {
  successMessage?: string;
  onSuccess?: (result: T) => void;
}): { run: () => Promise<T | undefined>; loading: Ref<boolean>; error: Ref<ApiError | null> };

// @/shared/stores/session
export const useSessionStore: DefineStore<'session', {
  user: CurrentUser | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isTeacher: boolean;
  mustChangePassword: boolean;
  fetchMe(): Promise<void>;
  logout(): Promise<void>;
}>;

// @/shared/stores/semester
export const useSemesterStore: DefineStore<'semester', {
  current: SemesterSummary | null;
  list: SemesterSummary[];
  fetch(): Promise<void>;
  switchTo(semesterId: string): Promise<void>;
}>;
export const SEMESTER_CHANGED_EVENT = 'paike:semester-changed';

// @/shared/text/messages
export const MESSAGES: Record<string, string>;   // 错误码 → 中文文案
export function friendlyError(error: unknown): string;
```

---

## 11. 共享组件

| 组件 | 职责 | 关键 props |
|------|------|-----------|
| `AppLayout` | 顶栏、侧栏、学期切换器、角色菜单、内容区 | `navItems` |
| `PageHeader` | 页面标题、说明、主操作区 | `title`、`description`、`actions` 插槽 |
| `DataTable` | 表格、加载、空状态、分页 | `columns`、`rows`、`loading`、`emptyText` |
| `ConfirmDialog` | 二次确认；危险操作红色；说明影响与可撤销性 | `modelValue`、`options` |
| `EmptyState` | 空状态图标、原因、下一步按钮 | `title`、`description`、`actionText` |
| `ErrorBanner` | 页面级错误、重试按钮 | `message`、`retryable` |
| `StatusTag` | 枚举 → 中文标签 + 颜色 + 图标 | `type`、`value` |
| `FormField` | 标签、必填标记、错误提示、帮助文案 | `label`、`error`、`required`、`hint` |
| `LoadingBlock` | 骨架屏 / 加载文案 | `text`、`rows` |
| `ToastHost` | 全局消息队列；成功/警告/错误 | — |

---

## 12. 前端静态文案约定

`MESSAGES` 至少包含：

```ts
{
  UNAUTHENTICATED: '登录已失效，请重新登录',
  FORBIDDEN: '您没有权限执行此操作',
  NOT_FOUND: '未找到该数据，可能已被删除',
  VERSION_CONFLICT: '数据已被他人修改，请刷新页面后重试',
  DUPLICATE: '该名称已存在，请更换后重试',
  REFERENCE_PROTECTED: '该数据正被使用，暂时无法删除',
  STATE_CONFLICT: '当前状态不允许此操作',
  FILE_TOO_LARGE: '文件超过 20 MB，请拆分后重试',
  ACCOUNT_LOCKED: '登录失败次数过多，请 15 分钟后再试',
  INTERNAL_ERROR: '系统暂时不可用，请稍后重试'
}
```

> 所有面向用户的最终文案必须是中文，且说明「发生了什么 + 怎么办」。
