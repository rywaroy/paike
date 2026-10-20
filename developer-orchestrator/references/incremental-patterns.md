# 增量场景模式

> 本文档定义增量开发的三种典型场景及其卡片生成模式。每种场景定义：特征识别、输入文件需求、卡片类型与结构、Hub 文件修改策略、验证要点。
>
> ⚠️ **卡片 description 九段模板**：本文档所有卡片 YAML 的 `description` 均为**场景特有段节选**，实际生成时按 `plane-issue-decomposer/references/description-template.md` 的**九段模板**逐字内联——含 `## 目标` / `## 验收标准` / `## 相关背景` / `## 约束` / `## 当前阶段` / `## 任务` / `## 验证` / `## 在开始改动之前` / `## 完成改动之后`。任何卡片不得省略 `## 验收标准` 与 `## 验证` 两段（单卡正确性由 Step 4「单卡验证段完整」复核）。

---

## Phase 编号派生规则（三场景通用）

增量卡片结构中的 `{新域Phase号}` / `{集成层Phase号}` / `{刷新层Phase号}` 占位符按以下规则从上一轮派生（保证 phase-contracts 文件名、卡片 ID、Plane Phase 跨轮一致）：

| 占位符 | 派生规则 |
|--------|---------|
| `{新域Phase号}` | `max(已有 docs/knowledge/phase-contracts/ 中 p{k} 的 k) + 1`；多个新域依次 +1 |
| `{集成层Phase号}` | 新域最大 Phase 号 + 1 |
| `{刷新层Phase号}` | 集成层 Phase 号 + 1 |

> 无新域场景（修改既有域 / 跨域集成）没有 `{新域Phase号}`，此时 `{集成层Phase号}` = `max(已有 p{k}) + 1`（集成层直接接在已有域之后），`{刷新层Phase号}` = `{集成层Phase号} + 1`。修改既有域的功能增强卡沿用 `{已有域Phase号}`。

新域 phase-contracts 文件名 = `p{新域Phase号}-contracts.md`；已有域 Phase 号保持不变（不重新分配）。

---

## 场景 1: 新增独立域

### 特征

- 全新限界上下文，独立的 `backend/modules/{domain}/` 和 `frontend/src/views/{domain}/`
- 有自己的数据库表、API 端点、前端页面
- 可能引用已有域的数据（外键），但不修改已有域代码

### 输入文件需求

| 分类 | 文件 | 用途 |
|------|------|------|
| 必须 | DDD JSON | 实体、属性、状态机、事件定义 |
| 必须 | contracts/openapi.yaml | API 路径冲突检测 |
| 必须 | contracts/schema.sql | 外键引用验证、migration 编号接续 |
| 必须 | shared-kernel-manifest.yaml | import 路径硬编码 |
| 必须 | conventions.md | 代码风格一致性 |
| 必须 | phase-contracts（全部已有域） | 权限点去重、已有域接口内联 |
| 条件 | contracts/events.yaml | 若新域发布或消费事件（DDD 含 DomainEvent / 订阅已有事件） |
| 条件 | seed-anchors.sql | 若新域有 seed 数据 |
| 可选 | 原型文件 | 页面布局参考 |

### 增量卡片结构

```yaml
issues:
  # 卡片 1: 新增域全栈卡
  - id: EOS-P{新域Phase号}-I00
    name: {域中文名}全栈实现
    phase: {新域Phase号}
    priority: high
    labels: [fullstack, domain]
    estimate_point: 4-5
    blocked_by: []  # 基础设施已存在，无需等待
    description: |
      ## 目标
      {域描述}全栈交付：后端 {N} 个 API 端点 + 前端 {M} 个页面 + Pinia Store。

      ## 相关背景
      - 必读：spac.md §5-§6
      - 必读：docs/knowledge/phase-contracts/p{k}-contracts.md
      - 必读：docs/knowledge/shared-kernel-api.md
      - 必读：conventions.md §1-§13
      - 上游契约（从 contracts/ 提取）：
        {列出依赖的上游 API 端点、表结构}
      - 共享内核 import 路径从 shared-kernel-manifest.yaml 硬编码

      ## 约束
      - [命名] 全栈命名遵循 conventions.md §1
      - [前端字段] Vue 模板和 Store 接口字段名必须使用 camelCase
      - [边界] 只可 import 共享内核与其他上下文 index.ts 导出
      - [枚举] 所有枚举值与 conventions.md §13 一致
      - [路由] 后端路由导出格式：export default router
      - [菜单] menu.ts 导出单个对象 { moduleId, label, entryRoutePath, order }
      - [UUID] 种子数据 UUID 必须符合 UUID v4 格式（版本位=4）
      - [已有域] 已有域代码只读。若需修改已有域代码，仅限追加新端点/新事件
      - [集成] 新增 API 路径已在 spac.md 中确认不与已有路径冲突

      ## 任务
      ### 后端 — 门面
      1. 创建 backend/modules/{domain}/index.ts — 导出 DTO/Enum

      ### 后端 — Repository
      2. 创建 backend/modules/{domain}/internal/{entity}.repository.ts

      ### 后端 — Service
      3. 创建 backend/modules/{domain}/internal/{entity}.service.ts

      ### 后端 — 路由
      4. 创建 backend/modules/{domain}/api/{resource}.routes.ts — {N} 个端点

      ### 后端 — Seed
      5. 创建 backend/db/seeds/{NN}-{domain}.sql

      ### 前端 — Store
      6. 创建 frontend/src/stores/{domain}.ts

      ### 前端 — 页面
      7. 创建 frontend/src/views/{domain}/{Page}.vue
      8. 创建 frontend/src/views/{domain}/routes.ts
      9. 创建 frontend/src/views/{domain}/menu.ts
      10. 创建 frontend/src/views/{domain}/permissions.ts

  # 卡片 2: 集成闭环卡（完整三阶段逐项模板以 plane-issue-decomposer/references/iteration-mode.md「集成闭环卡模板」为唯一权威，本卡 description 据此逐字内联）
  - id: EOS-P{集成层Phase号}-I99
    name: 集成闭环 — Round {N} 三阶段验证与自愈
    phase: {集成层Phase号}
    priority: high
    labels: [integration, testing]
    estimate_point: 4
    blocked_by: [全部新增领域全栈卡 + 全部集成增强卡]
    description: |
      ## 目标
      Round {N} 新增域 ↔ 已有域的三阶段闭环（同一 Agent 内闭环：发现 → 验证 → 修复 → 重验）。

      ## 任务（阶段一 6 项 / 阶段二 8 项 / 阶段三 3 项）
      完整逐项任务 + 三类确定性修复规则（路径冲突/import 断裂/事件名不匹配）见
      plane-issue-decomposer/references/iteration-mode.md「集成闭环卡模板」——本卡生成时逐字内联，不得删减。

      ## 偏差登记约定
      - 本卡追加偏差条目带 stage: integration；封版归档卡为 stage: freeze；状态刷新卡为 stage: refresh
      - deviation.yaml 只追加不覆盖，每条含 stage/type/target/description/designed/actual/resolved_by/status

  # 卡片 3: 封版归档卡
  - id: EOS-P{集成层Phase号}-I96
    name: 封版归档 — Round {N}
    phase: {集成层Phase号}
    priority: medium
    labels: [infrastructure]
    estimate_point: 1
    blocked_by: [EOS-P{集成层Phase号}-I99]

  # 卡片 4: 状态刷新卡（刷新层，最后 Phase 之后）
  - id: EOS-P{刷新层Phase号}-I00
    name: 状态刷新 — Round {N} → 为 Round {N+1} 准备
    phase: {刷新层Phase号}
    priority: medium
    labels: [infrastructure]
    estimate_point: 1
    blocked_by: [EOS-P{集成层Phase号}-I96]
```

### Hub 文件修改策略

新增域的文件通过**约定式扫描自动发现**，Hub 文件修改量最小：

| Hub 文件 | 是否需要修改 | 如何修改 |
|---------|------------|---------|
| `backend/app.ts` | ❌ 否 | `fs.readdirSync` 自动扫描 `modules/*/api/*.routes.ts`，新域路由文件创建后自动挂载 |
| `frontend/src/router/index.ts` | ❌ 否 | `import.meta.glob('@/views/*/routes.ts')` 自动汇聚，新域 routes.ts 创建后自动注册 |
| `frontend/src/components/AppLayout.vue` | ❌ 否 | `import.meta.glob('@/views/*/menu.ts')` 自动汇聚菜单，前提是 menu.ts 导出单个对象 |
| `docker-compose.yml` | ❌ 否 | 容器服务定义不变 |
| `backend/db/migrations/` | ✅ 追加 | 新 migration 文件按编号接续（如 `005-{domain}.sql`） |
| `backend/db/seeds/` | ✅ 追加 | 新 seed 文件按编号接续（如 `03-{domain}.sql`） |
| `backend/package.json` | ⚠️ 可能 | 若新域需要新的 npm 包（如特定文件处理库），追加到 dependencies |

---

## 场景 2: 修改既有域

### 特征

- 在已有域模块中追加新功能（新端点、新页面、新字段）
- 不修改已有 API 签名、不破坏已有表结构
- 可能新增 migration（ALTER TABLE ADD COLUMN）

### 输入文件需求

| 分类 | 文件 | 用途 |
|------|------|------|
| 必须 | 该域的 DDD JSON（若有增量版本） | 新增功能的需求定义 |
| 必须 | 该域的源码 | 了解当前实际代码结构——不能只靠设计文档 |
| 必须 | contracts/openapi.yaml | 确认新增端点路径不与已有路径冲突 |
| 必须 | contracts/schema.sql | 确认新增列的类型和约束 |
| 必须 | shared-kernel-manifest.yaml | import 路径 |
| 必须 | conventions.md | 代码风格 |

### 修改约束

| 规则 | 说明 |
|------|------|
| **只追加不破坏** | 新增端点追加到已有 routes 文件末尾；新增方法追加到已有 repository/service |
| **不修改已有端点签名** | 已有端点的路径、方法、请求体、响应结构不变——已有前端页面依赖它们 |
| **不修改已有表结构的关键列** | 可 ADD COLUMN（允许 NULL 或有 DEFAULT），不可 DROP COLUMN、不可修改已有列类型 |
| **新增 migration 编号接续** | 如已有 001-005 → 新增 006 |
| **新增 seed 追加到已有 seed 文件末尾** | 不覆盖已有 seed 数据，使用 `INSERT ... ON CONFLICT DO NOTHING` 防重复 |

### 增量卡片结构

```yaml
issues:
  - id: EOS-P{已有域Phase号}-I01
    name: {域名}功能增强 — {新增功能简述}
    phase: {已有域Phase号}
    priority: high
    labels: [fullstack, enhancement]
    estimate_point: 1-2
    blocked_by: []
    description: |
      ## 目标
      在已有 {domain} 模块中追加 {功能描述}。

      ## 修改范围
      - 后端：追加 {N} 个端点、{M} 个 repository 方法
      - 前端：追加 {K} 个页面组件、扩展 Store

      ## 约束
      - [已有域修改限制] 仅可追加，不修改已有端点签名和表结构
      - [已有域修改限制] 新增列必须允许 NULL 或有 DEFAULT
      - [已有域修改限制] 新增端点追加到已有 routes 文件末尾

      ## 任务
      ### 后端
      1. 在已有 backend/modules/{domain}/internal/{entity}.repository.ts 中追加方法
      2. 在已有 backend/modules/{domain}/api/{resource}.routes.ts 中追加端点
      3. 创建 backend/db/migrations/{NNN}-{change}.sql（ALTER TABLE ADD COLUMN...）

      ### 前端
      4. 在已有 frontend/src/stores/{domain}.ts 中追加 action
      5. 创建 frontend/src/views/{domain}/{NewPage}.vue
      6. 更新 frontend/src/views/{domain}/routes.ts（追加新路由）
      7. 更新 frontend/src/views/{domain}/permissions.ts（追加新权限码）
```

---

## 场景 3: 跨域集成

### 特征

- 两个或多个既有域之间新增数据/事件/API 联动
- 不创建新域，但需要修改既有域以暴露新接口或消费新事件

### 输入文件需求

| 分类 | 文件 | 用途 |
|------|------|------|
| 必须 | 涉及的全部域的 phase-contracts | 了解各域的实际接口（非设计文档） |
| 必须 | contracts/openapi.yaml | 确认新路径 |
| 必须 | contracts/events.yaml | 确认事件名、payload |
| 必须 | 涉及域的源码 | 了解当前代码结构 |

### 增量卡片结构

```yaml
issues:
  # 卡片 1: 域 A 集成增强卡
  - id: EOS-P{集成层Phase号}-I02
    name: "{域A} 集成增强 — 为 {域B} 暴露 {接口}"
    phase: {集成层Phase号}
    priority: high
    labels: [backend, integration]
    estimate_point: 1
    blocked_by: []
    description: |
      ## 目标
      在已有 {域A} 模块中新增 {端点/事件}，供 {域B} 使用。

      ## 约束
      - [已有域修改限制] 仅可追加新端点/新事件，禁止修改已有端点签名
      - [已有域修改限制] 不修改已有表结构

  # 卡片 2: 域 B 集成增强卡
  - id: EOS-P{集成层Phase号}-I03
    name: "{域B} 集成增强 — 消费 {域A} 的 {事件/API}"
    phase: {集成层Phase号}
    priority: high
    labels: [backend, frontend, integration]
    estimate_point: 1-2
    blocked_by: [EOS-P{集成层Phase号}-I02]
    description: |
      ## 目标
      在 {域B} 中消费 {域A} 新增的 {事件/API}。

      ## 约束
      - [跨域消费] 通过 {域A} 的 index.ts 门面 import 接口/DTO
      - [跨域消费] 禁止 import {域A} 的 internal/ 实现

  # 卡片 3: 事件对齐卡
  - id: EOS-P{集成层Phase号}-I04
    name: "事件对齐 — {域A} ↔ {域B}"
    phase: {集成层Phase号}
    priority: medium
    labels: [integration]
    estimate_point: 1
    blocked_by: [EOS-P{集成层Phase号}-I02, EOS-P{集成层Phase号}-I03]
    description: |
      ## 目标
      验证 {域A} 发布的事件被 {域B} 正确消费。
      验证事件 payload 字段名一致、数据可串联。

  # 卡片 4（条件）: 契约冲突消解卡 — 仅当 spac.md §11 记录了「需修改已有域路径/命名」的冲突时生成
  - id: EOS-P{集成层Phase号}-I05
    name: "契约冲突消解 — {冲突点简述}"
    phase: {集成层Phase号}
    priority: high
    labels: [integration]
    estimate_point: 1
    blocked_by: []
    description: |
      ## 目标
      按 spac.md §11 记录的冲突，统一调整冲突的 API 路径/命名（唯一允许修改已有域路径/命名的场景）。

      ## 约束
      - [已有域修改限制] 仅限移动路径/重命名，不改变端点行为与请求/响应签名
      - [契约变更请求] 调整后同步更新 contracts/openapi.yaml + contracts/routes.yaml + contracts/naming.yaml
      - [前端同步] 若调整前端路由 path，同步 navigation.ts 对应 child 的 routePath

      ## 任务
      1. 读取 spac.md §11 记录的冲突项及消解决策
      2. 按决策调整冲突路径/命名
      3. 同步 contracts/ 对应条目（+ navigation.ts，如涉及前端路由）
      4. 在 docs/trace/deviation.yaml 追加 stage: integration 条目记录本次消解
```

> ⚠️ **收口卡照常生成**：场景 3 除上述集成增强卡 / 事件对齐卡（及条件生成的契约冲突消解卡）外，还须按场景 1 相同结构追加收口卡——集成闭环卡（`blocked_by: [全部集成增强卡 + 事件对齐卡 + 契约冲突消解卡（如有）]`）、封版归档卡（`blocked_by: [集成闭环卡]`）、状态刷新卡（`blocked_by: [封版归档卡]`），验证范围限定为「集成域之间」。与 `iteration-mode.md`「收口卡照常生成」规则一致。

---

## 三种场景的对比总结

| 维度 | 新增域 | 修改既有域 | 跨域集成 |
|------|--------|----------|---------|
| **卡片数** | 4-8 | 4-5 | 5-7 |
| **blocked_by** | 全栈卡 blocked_by=[] | 增强卡 blocked_by=[] | 消费卡 blocked_by 生产卡 |
| **新建文件** | 10+ 个（完整的模块+视图） | 1-3 个（追加/更新） | 0-2 个（追加） |
| **修改已有文件** | 0（Hub 文件自动扫描） | 2-4（routes/repo/store/perms） | 1-3（追加端点/事件订阅） |
| **迁移文件** | 新增 migration | 新增 migration（ALTER TABLE） | 通常不需要 |
| **种子数据** | 新增 seed 文件 | 追加到已有 seed 文件 | 通常不需要 |
| **Phase 0 卡** | ❌ 不生成 | ❌ 不生成 | ❌ 不生成 |
| **集成验证范围** | 新域 ↔ 全部已有域 | 修改域 ↔ 相关域 | 集成域之间 |
| **风险** | 路径/事件命名冲突 | 已有功能退化 | 事件丢失/时序问题 |

---

## 通用验证清单（所有场景适用）

每轮增量开发完成后必须验证：

| # | 检查项 | 验证方法 |
|---|--------|---------|
| 1 | 新 API 路径不与已有路径冲突 | 扫描全部 routes 文件 → 交叉比对路径 |
| 2 | 新事件名不与已有事件名冲突 | 对比 contracts/events.yaml |
| 3 | 新 seed 数据外键引用有效 | 在 Docker 中执行 seed → 无外键约束错误 |
| 4 | 前端构建零错误 | `cd frontend && npm run build` |
| 5 | 后端编译零错误 | `cd backend && npx tsc --noEmit` |
| 6 | 菜单正确汇聚 | 检查浏览器中导航菜单显示新域入口 |
| 7 | 已有功能未退化 | 已有域的页面仍可正常访问和操作 |
| 8 | docker compose up 三服务健康 | `docker compose up -d` → 健康检查通过 |
