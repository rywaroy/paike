# 智能排课系统 V1.0

面向中小学教务处的本地化排课系统：以「学期 + 作息模板」为排课上下文，完成基础数据维护、一键智能排课、课表可视化调课、冲突校验、工作量统计、导入导出打印、操作留痕与多学期存档。

- 产品需求唯一真相：`input/v1.0/PRD/12-V1.0封版PRD.md`
- 架构设计：`docs/trace/runs/v1/spac.md`
- 开发卡片：`docs/trace/runs/v1/issues.yaml`
- 首轮规划总览：`docs/trace/runs/v1/agent_plane.md`

## 1. 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| 前端 | Vue 3 + TypeScript + Vite + Pinia + Vue Router + Element Plus | 桌面优先，最小宽度 1280px |
| 后端 | Node.js 20 + Express 4 + TypeScript | 分层：HTTP → 应用服务 → 领域 → 仓储 |
| 数据库 | PostgreSQL 16 | 纯 SQL 迁移，不使用 ORM |
| 认证 | 服务端 Session（`express-session` + PostgreSQL Store） | HttpOnly + SameSite=Lax；Argon2id |
| 表格 | SheetJS（`xlsx`） | XLSX 导入导出 |
| 打印 | Playwright（无头 Chromium） | HTML/CSS → PDF，A4/A3 |
| 校验 | Zod | 请求体、环境变量、导入行 |
| 日志 | Pino | 结构化日志 |
| 测试 | Vitest + Supertest + Playwright | 单元 / 接口 / 端到端 |

## 2. 快速启动

### 2.1 前置条件

- Node.js ≥ 20
- PostgreSQL ≥ 16
- 无头 Chromium（打印功能）：`npx playwright install chromium`

### 2.2 安装与初始化

```bash
npm install
cp .env.example .env
# 按 docs/knowledge/config-contract.md 填写数据库连接
npm run db:migrate
npm run db:seed
npm run dev
```

默认访问地址：`http://localhost:5173`（前端开发服务器），后端 `http://localhost:3000`。

### 2.3 默认管理员

| 项 | 值 |
|----|----|
| 用户名 | `admin` |
| 初始密码 | 由 `PAIKE_ADMIN_INITIAL_PASSWORD` 注入；未注入时首次启动在服务端控制台**仅输出一次** |
| 首次登录 | 强制修改密码（≥8 位，大写/小写/数字/符号至少 3 类） |

> 初始密码不得写入任何日志文件、不得提交到版本库。

### 2.4 常用命令

```bash
npm run dev            # 同时启动前后端（Vite 代理 /api → 3000）
npm run build          # 前后端生产构建
npm start              # 启动后端（生产）
npm run db:migrate     # 执行数据库迁移
npm run db:seed        # 写入 seed 锚点数据
npm run test           # Vitest 单元 + 接口测试
npm run test:e2e       # Playwright 端到端测试
npm run perf:schedule  # 50 班排课性能基准（H-03）
npm run perf:export    # 1000×12 导出性能基准（H-03）
npm run lint           # ESLint + Prettier 检查
npm run typecheck      # 前后端 TypeScript 类型检查
```

## 3. 目录结构

```
backend/
  src/
    main.ts                  # 进程入口
    app.ts                   # Express 装配
    config/                  # 环境配置读取（config-contract 唯一入口）
    shared/                  # 共享内核（见 shared-kernel-manifest.yaml）
      db/ auth/ http/ errors/ validation/ events/ audit/
      import/ export/ pdf/ time/ upload/
    modules/
      registry/              # bc-registry：学期、模板、年级、班级、科目、校历
      resource/              # bc-resource：教师、任课、场地、合班、走班
      timetable/             # bc-timetable：排课引擎、方案、课次、冲突、调权
      governance/            # bc-governance：操作日志、存档、学期切换
      identity/              # bc-identity：账号、角色、会话
  migrations/                # 顺序 SQL 迁移
  tests/                     # Vitest + Supertest
frontend/
  src/
    router/ stores/ api/ shared/ views/ components/
    views/
      auth/ registry/ resource/ timetable/ governance/ identity/
e2e/                         # Playwright
docs/
  knowledge/
    config-contract.md
    dependency-graph.yaml
    shared-kernel-api.md
    module-template.md
    phase-contracts/
  trace/runs/v1/
    spac.md
    agent_plane.md
    issues.yaml
    test-results/            # 每张卡片的测试案例对比验证
conventions.md
schema-shared.sql
seed-anchors.sql
shared-kernel-manifest.yaml
roles.md
scenes.md
```

## 4. 环境变量

完整清单与默认值见 `docs/knowledge/config-contract.md`。最小集合：

```dotenv
NODE_ENV=development
PORT=3000
DATABASE_URL=postgres://paike:paike@localhost:5432/paike
SESSION_SECRET=<32 字节以上随机串>
PAIKE_ADMIN_INITIAL_PASSWORD=
PAIKE_SESSION_IDLE_HOURS=8
PAIKE_SESSION_ABSOLUTE_DAYS=7
PAIKE_LOGIN_MAX_FAILURES=5
PAIKE_LOGIN_LOCK_MINUTES=15
PAIKE_UPLOAD_DIR=./var/uploads
PAIKE_EXPORT_TMP_DIR=./var/exports
PAIKE_PRINT_BASE_URL=http://localhost:3000
```

## 5. 页面与功能对照

| 路由 | 页面 | 功能 |
|------|------|------|
| `/login` | 登录 | F20 认证 |
| `/change-password` | 强制改密 | F20 |
| `/` | 系统概览 | 学期状态、快捷入口、最近日志 |
| `/semesters` | 学期管理 | F1 |
| `/schedule-templates` | 作息模板 | F2 |
| `/grades-classes` | 班级·年级 | F3 |
| `/subjects` | 科目与课时规则 | F4 |
| `/teachers` | 教师与任课 | F5 |
| `/venues` | 场地·功能室 | F6 |
| `/combined-classes` | 合班课 | F7 |
| `/walking-groups` | 走班配置 | F10 |
| `/scheduling` | 一键排课 | F8 / F9 |
| `/scheduling/pre` | 预排与锁定 | F9 |
| `/timetables` | 多维度课表 | F11 |
| `/timetables/adjust` | 拖拽调课 | F12 |
| `/idle-slots` | 空闲时段 | F13 |
| `/statistics` | 工作量统计 | F14 |
| `/export` | Excel 导出 | F15 |
| `/print` | 模板打印 | F16 |
| `/conflicts` | 冲突校验中心 | F17 |
| `/logs` | 操作日志 | F19 |
| `/archive` | 多学期存档 | F19 |
| `/users` | 用户与角色 | F20 |
| `/me/timetable` | 我的课表（Teacher） | F11 |
| `/me/idle-slots` | 我的空闲时段（Teacher） | F13 |

## 6. 角色与权限

完整权限矩阵见 `roles.md`。要点：

- Admin：全部配置、排课、调课、统计、导入导出打印、日志存档、用户管理。
- Teacher：仅本人课表、本人关联班级课表、本人空闲时段；所有管理入口与 API 均拒绝。
- 权限在**服务端每个请求**重新判定，前端隐藏只作为体验优化。

## 7. 数据与接口约定

- 所有写接口需要 `X-CSRF-Token`（`GET /api/v1/auth/csrf` 获取）。
- 所有写接口携带乐观版本 `version`；版本不一致返回 `409 VERSION_CONFLICT`。
- 响应统一为 `{ "data": ... }` 或 `{ "error": { "code", "message", "details" } }`。
- 所有面向用户的文案为中文，禁止使用技术黑话（详见 `conventions.md` §8）。

## 8. 文档索引

| 文档 | 内容 |
|------|------|
| `docs/trace/runs/v1/spac.md` | 架构设计 §1-§11 |
| `docs/trace/runs/v1/agent_plane.md` | 卡片规划、差距报告、校验清单、依赖图 |
| `docs/trace/runs/v1/issues.yaml` | 首轮全部开发卡片 |
| `docs/trace/runs/v1/test-results/` | 逐卡片测试案例对比验证（设计态，未执行） |
| `conventions.md` | 9 类跨卡片共享技术约定 + 枚举速查 |
| `schema-shared.sql` | 8 张共享基础设施表 |
| `seed-anchors.sql` | 跨域共享测试数据锚点 |
| `shared-kernel-manifest.yaml` | 共享内核文件与 import 路径 |
| `roles.md` | 角色权限定义 |
| `scenes.md` | 场景链路分析 |
| `docs/knowledge/config-contract.md` | 环境变量唯一真相 |
| `docs/knowledge/dependency-graph.yaml` | 域依赖拓扑 |
| `docs/knowledge/shared-kernel-api.md` | 共享内核 API |
| `docs/knowledge/module-template.md` | 模块骨架模板 |
| `docs/knowledge/phase-contracts/` | 各 Phase 契约摘要 |

## 9. 本轮状态

本轮为首轮**设计态**交付：完成架构设计与 Issue 拆解，**不包含代码实现，不执行任何测试**。所有测试对比结论均为设计推演，执行状态一律为「未执行」。
