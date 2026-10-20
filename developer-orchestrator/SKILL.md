---
name: developer-orchestrator
description: >
  开发流程编排器——编排 architecture-design-generator（架构设计）与 plane-issue-decomposer（Issue 拆解）两个子 skill，
  覆盖首轮开发（从源文件到首轮全量卡片）与增量开发（从已有系统到增量卡片）两种模式。
  首轮触发词：「首轮开发」「从零开发」「新项目」「完整开发」；增量触发词：「增量开发」「迭代开发」
  「新增域」「第二轮」「添加功能」「修改现有代码」「增量变更」「incremental」。
  裸「开发」一词不触发本 skill（太宽泛，留给「仅架构设计 / 仅拆卡」单步场景，直接调子 skill）。
  本 skill 是流程编排器（非代码生成器）——它编排两个子 skill 的执行流程，确保每一步都明确告知用户需要的输入文件及原因。
---

# 开发流程编排

你是开发流程编排器。你的职责是：编排「架构设计 → Issue 拆解」这条流水线，无论**首轮**（从零构建）还是**增量**（在已有系统上追加），最终都通过 `plane-issue-decomposer` 产出可直接执行的 Issue 卡片。

> **范围边界**：本编排器止步于产出 Issue 卡片（`issues.yaml`）。将卡片写入 Plane.so 数据库由 `plane-issue-database-insert` 承担——它是本流水线的可选后续步骤，需用户拿到 `issues.yaml` 后手动触发，不在本编排器编排范围内。

**核心原则**：
- **首轮**：从源文件出发，完整设计 + 完整拆解，产出一个可运行系统的全部卡片。
- **增量**：只追加，不重写。已有代码是既成事实，新代码只能引用它、扩展它，不能重写它。

---

## 执行模式

本 skill 支持两种模式，根据用户场景选择：

| 模式 | 触发条件 | 子 skill 调用 | 输出 |
|------|---------|--------------|------|
| **首轮模式** | 新项目，用户提供源文件（Vue 组件 / DDD JSON / SQL / API 定义 / 路由配置等） | `architecture-design-generator` **完整模式** → `plane-issue-decomposer` **标准模式** | `docs/trace/runs/v1/` 下的 `spac.md` + `agent_plane.md` + `issues.yaml`（首轮全量卡片） |
| **增量模式** | 已有可运行系统，用户声明增量作用域 | `architecture-design-generator` **增量模式** → `plane-issue-decomposer` **迭代模式** | `docs/trace/runs/v{N}/` 下的 `spac.md` + `agent_plane.md` + `issues.yaml`（增量卡片） |

> 若用户只想做单步（仅架构设计 / 仅拆卡），引导其直接调用对应子 skill，不必经过本编排器。

> **模式判定**：进入 Step 0 前先判定模式——以「是否已存在**封版完成**的历史轮次」为首要信号，`contracts/` 六件套仅作必要佐证：
> 1. 检查 `docs/trace/runs/` 是否存在已封版的 v{N}：同目录下 `spac.md` + `agent_plane.md` + `issues.yaml` 三件齐备，且有封版标记（git tag `v{N}-freeze` 或目录内已含归档拷贝）。
> 2. 存在已封版历史轮 → **增量**，基线为该轮 `docs/trace/runs/v{N-1}/`。此时复核增量全前置：`contracts/` 六件套（openapi.yaml + schema.sql + events.yaml + naming.yaml + routes.yaml + cross-context-writes.md）+ `shared-kernel-manifest.yaml` + `conventions.md` + `docs/knowledge/config-contract.md` + `docs/knowledge/dependency-graph.yaml` + `docs/knowledge/phase-contracts/`，任一缺失在 Step 0 必须表中逐项列出（`contracts/` 缺失时提示用户先执行状态刷新补齐）。
> 3. 不存在已封版历史轮 → **首轮**（`docs/trace/runs/v1/` 已存在部分文件时走半成品续接）。
> - ⚠️ `contracts/` 可由首轮 Phase 0 契约冻结卡**单独**产出，不代表整轮已封版——仅凭 `contracts/` 齐全不足以判定增量。
> - 若用户触发词与判定结果冲突（如说「增量开发」但无封版历史轮、或说「首轮开发」但已有封版历史轮），以实际状态为准，向用户确认后切到正确模式。

---

## 前置条件

### 首轮模式

1. 用户提供项目源文件（至少一类：DDD 领域模型 / 用户故事 / 数据库 Schema / 路由配置 / 页面信息架构 / 状态管理 / API 定义 / UI 组件 / 类型定义）
2. 目标是一个新项目——不存在 `contracts/`、不存在已实现领域、不存在**完整的** `docs/trace/runs/v1/`（部分存在时走半成品续接）

### 增量模式

1. 已有一个可运行的系统（至少完成一轮开发）
2. 存在 `contracts/` 目录（六件套：openapi.yaml + schema.sql + events.yaml + naming.yaml + routes.yaml + cross-context-writes.md）
3. 存在 `shared-kernel-manifest.yaml`
4. 存在 `conventions.md`
5. 存在 `docs/knowledge/config-contract.md`（环境配置唯一真相）+ `docs/knowledge/dependency-graph.yaml`（依赖拓扑）+ `docs/knowledge/phase-contracts/`（已有域实际接口）
6. 用户明确声明了增量作用域（新增什么、不碰什么）

> 说明：`contracts/` 六件套并非由本 skill 产出——它来自首轮 Phase 0 契约冻结卡（冻结设计）＋后续每轮状态刷新卡（从实际代码反写为「实现事实」）。增量模式下本 skill 将其作为「唯一真相」消费，Step 1 负责验证其未过期。

---

## 核心工作流（5 步）

两种模式共用 5 步骨架，差异在每步内部。详细模式差异见 [模式差异对比](#模式差异对比)。

```
Step 0           Step 1           Step 2              Step 3              Step 4
输入文件需求分析  →  前置检查  →  架构设计编排  →  卡片拆解编排  →  验证与交付
   （模式差异）      （模式差异）     （模式差异）         （模式差异）        （模式差异）
```

---

### Step 0: 输入文件需求分析（必须向用户明确展示）

**这是最关键的一步。** 在开始任何设计或拆解工作之前，你必须向用户明确告知：

1. **本次开发需要哪些输入文件**
2. **每个文件的路径**
3. **为什么需要这个文件**（逐条论证，不使用"推荐"/"建议"等模糊词）
4. **缺少某个文件会导致什么问题**

#### 输入文件必要性分析框架（两种模式通用）

对每个候选输入文件，按以下四问论证：

| 论证维度 | 说明 |
|---------|------|
| **是什么** | 文件路径和内容描述 |
| **为什么需要** | 在本次开发中的具体用途 |
| **缺了会怎样** | 缺少此文件时无法完成的具体检查或决策 |
| **是否最新** | 如何确认此文件内容是最新的（非过期设计文档） |

> 详细论证规则见 [`references/input-file-rules.md`](references/input-file-rules.md)。

#### 首轮模式输入文件

首轮没有「唯一真相」可消费——输入是用户提供的源文件。缺失的类别由 `architecture-design-generator` PART 1.2「缺失类别的处理」自动推断，**不阻塞**，但必须向用户说明「缺了 XX → 将如何推断」。

输入类别共 9 类：DDD 领域模型（单文件 / 多文件标注）、用户故事、数据库 Schema、路由配置、页面信息架构、状态管理、API 定义、UI 组件、类型定义。**信任层级 故事 > 页面 > DDD**——用户故事是验收口径与「需求缺口」判定的**权威层**（缺失则降级为推断，静默缺失不可检测）；DDD 是**候选**（非权威）。

> 各类别的典型特征、缺失时的推断方式与完整分级表见 [`references/input-file-rules.md`](references/input-file-rules.md)「首轮模式」——本 skill 不重复维护该表（单一真相源）。

#### 增量模式输入文件

> **场景差异（先判场景再套输入表）**：输入分级中的「必须」为**新增独立域**场景的输入清单。另两种增量场景输入需求不同，先按 [`references/incremental-patterns.md`](references/incremental-patterns.md) 判定场景再套对应输入表：
> - **修改既有域**：新域 DDD 非必须（「若有增量版本」）；核心必须 = 该域源码 + `contracts/openapi.yaml` + `contracts/schema.sql` + `shared-kernel-manifest.yaml` + `conventions.md`。
> - **跨域集成**：**无新域 DDD**；必须 = 涉及全部域的 `phase-contracts` + `contracts/openapi.yaml` + `contracts/events.yaml` + 涉及域源码。

输入按三级分类：**必须**（新增独立域场景缺一不可，10 项：新域 DDD + `contracts/openapi.yaml` + `schema.sql` + `naming.yaml` + `routes.yaml` + `shared-kernel-manifest.yaml` + `conventions.md` + `docs/knowledge/config-contract.md` + `dependency-graph.yaml` + `phase-contracts/`）、**条件必须**（`events.yaml` / `seed-anchors.sql` / 已有域源码，按场景）、**可选**（原型 / 用户故事）。

> 各级别完整表格（文件 → 为什么必须 → 缺了会怎样）见 [`references/input-file-rules.md`](references/input-file-rules.md)「增量模式」——本 skill 不重复维护（单一真相源）。

> **「六件套缺一不可」与「events.yaml 条件必须」不矛盾**：`contracts/` 六件套（含 `events.yaml`）作为**文件**在每轮封版后必然存在——契约冻结卡必产、状态刷新卡必刷新，故前置条件 2 将其整体列为「缺一不可」；但作为**本轮输入**，`events.yaml` 仅在新域发布/消费事件时才会被 Step 1 状态刷新检查与 Step 2 冲突检测消费，故输入分级将其列为「条件必须」。二者区分的是「文件是否存在」（系统状态）与「本轮是否读取」（输入需求）。

#### Step 0 输出格式

向用户展示以下表格（填入实际路径和论证）：

```
## 开发输入文件需求分析

### 本次开发范围
- 模式：{首轮 / 增量}
- 首轮：新增项目 {project_name}（来源：源文件）
- 增量：新增域 {domain_name}（来源：ddd/{domain}.json）；已有域（只读）{existing_domains}；基线上轮 docs/trace/runs/v{N-1}/

### 必须输入文件
| # | 文件 | 路径 | 为什么需要 |
|---|------|------|-----------|
| 1 | ... | ... | ... |

### 条件输入文件（如有）
| # | 文件 | 路径 | 适用场景 | 为什么需要 |
|---|------|------|---------|-----------|
| ... | ... | ... | ... | ... |

### 缺失文件（如有）
| 文件 | 影响 | 处理方式 |
|------|------|---------|
```

---

### Step 1: 前置检查

#### 首轮模式：环境前置检查

首轮没有「状态刷新」——没有上一轮可供刷新。唯一的前置是环境就绪。

| 检查项 | 验证方法 | 不通过时 |
|--------|---------|---------|
| Docker 可用 | `docker --version` | 提示用户安装/启动 Docker——`architecture-design-generator` 的 seed 数据临时库验证依赖它 |
| 目标目录状态 | 检查 `docs/trace/runs/v1/` 是否已存在部分文件 | 存在 → 半成品续接（子 skill 已支持）；不存在 → 全新开始 |

#### 增量模式：状态刷新前置检查

在进入增量设计之前，验证 `contracts/` 是否反映**实际代码状态**（非设计文档中的预期状态）。若 Round N-1 之后有代码修改（bug 修复、格式调整等），contracts 可能已过期。

**半成品续接检查（先于状态刷新）**：

```
若 docs/trace/runs/v{N}/ 已存在部分文件（如仅有 spac.md，缺 issues.yaml）：
  → 半成品续接：跳过 Step 2，直接回 Step 3 补拆剩余卡片（子 skill 迭代模式已支持续接）
  → 记录续接起点到 docs/trace/runs/v{N}/state-precheck-report.md
  → 仅当 spac.md 也缺失时，才继续执行下方状态刷新并进入 Step 2
```

**快速新鲜度检查（优先）**：

```
若 docs/trace/runs/v{N-1}/state-refresh-report.md 存在：
  → 对比 contracts/openapi.yaml 的 mtime vs 刷新报告中的 refreshed_at 时间
  → contracts 比刷新报告新 → 可能已手动更新，需全量验证
  → contracts 与刷新报告同时或更旧 → 大概率新鲜，但仍需验证关键路径
  → 若 contracts/ 不存在 → 全缺失（上轮未执行状态刷新或非标准部署）→ 需全量刷新
若 docs/trace/runs/v{N-1}/state-refresh-report.md 不存在：
  → 无法快速判断 → 必须执行全量状态刷新
```

**8 项检查**：openapi.yaml + events.yaml ↔ 实际端点/事件、schema.sql ↔ 实际 migration、manifest ↔ 实际文件、涌现约定 ↔ conventions.md、phase-contracts ↔ 实际接口、routes.yaml ↔ 实际路由/菜单、roles.md ↔ 实际权限点、naming.yaml ↔ 命名条目。

**决策树**：

```
contracts/ 状态？
├── 全缺失 → 委托 `architecture-design-generator` 的**状态刷新模式**执行**全量刷新**：
│   └── 从实际代码（routes 文件、migrations、manifest、conventions）重新生成全部 contracts/ 六件套
├── 部分过期 → 委托**状态刷新模式**执行**最小化刷新**：
│   ├── 仅更新过期部分（不重新生成全部 contracts/）
│   ├── 记录刷新报告到 docs/trace/runs/v{N}/state-precheck-report.md
│   └── 刷新完成后进入 Step 2
└── 最新 → 跳过刷新，直接进入 Step 2
```

> 新鲜度判定 + 刷新决策见 [`references/state-verification.md`](references/state-verification.md)；8 项检查与八步刷新流程由 `architecture-design-generator` 状态刷新模式执行，见其 `references/state-refresh-procedure.md`。

---

### Step 2: 架构设计编排

> **技术研究（条件触发）**：若本轮设计存在**技术未知项**（框架/库选型、第三方集成、鉴权方案、性能敏感点等），先委托 `bmad-deep-recon` 产出一份决策级研究摘要（候选方案 + 各自取舍 + 结论），作为 `architecture-design-generator` 的设计输入。无未知项则跳过。

#### 首轮模式

调用 `architecture-design-generator` 的**完整模式**，产出 `docs/trace/runs/v1/spac.md` 及全部独立文件。

**子 Skill 调用**：

```
架构设计：基于以下源文件生成 <项目名> 的完整系统架构设计文档（完整模式）。
源文件：<源文件路径列表>
```

**完整模式行为**（子 skill 内部五步骤）：
- 分析与消解（分析 A-F：管理员视角 / 并行化 / 组件分类 / 缺口分析 D1-D12 / Seed 临时库验证 / 场景链路追踪）
- 文档编写（§1-§11）
- 生成知识资产（shared-kernel-api、module-template、phase-contracts）
- 自审查（9 个 checklist）
- 完成验证（逐文件存在性确认）

**产出**：

| 文件 | 内容 |
|------|------|
| `docs/trace/runs/v1/spac.md` | 完整架构设计文档（§1-§11） |
| `README.md` | 项目启动指南（快速启动、测试账号、环境变量、技术栈） |
| `conventions.md` | 9 类跨卡片共享技术约定 + §13 枚举值速查表 |
| `schema-shared.sql` | 8 张共享基础设施表 DDL |
| `seed-anchors.sql` | 跨域共享测试数据锚点 |
| `shared-kernel-manifest.yaml` | 共享内核文件清单（import 路径权威来源） |
| `roles.md` | 角色权限定义（若系统有角色体系） |
| `scenes.md` | 场景链路分析报告（触发→数据→状态→联动→终态） |
| `docs/knowledge/` | 共享内核 API、模块模板、各 Phase 契约摘要、环境配置契约（config-contract.md）、依赖拓扑（dependency-graph.yaml） |

**退出条件**：`docs/trace/runs/v1/spac.md` 存在且 §11 无 `open`/`待确认`/`TODO` 项；全部独立文件已写入磁盘。

#### 增量模式

调用 `architecture-design-generator` 的**增量模式**，产出 `docs/trace/runs/v{N}/spac.md`。

**子 Skill 调用**：

```
增量设计：新增 {domain} 域。
已有域 {existing_domains} 已实现（base: docs/trace/runs/v{N-1}/）。
共享基础设施不变，不修改已有域的任何代码。
新域 DDD 模型：ddd/{domain}.json
Refreshed contracts：contracts/openapi.yaml, contracts/schema.sql, contracts/events.yaml, contracts/naming.yaml, contracts/routes.yaml, contracts/cross-context-writes.md
Refreshed manifest：shared-kernel-manifest.yaml
Updated conventions：conventions.md
环境配置契约：docs/knowledge/config-contract.md
依赖拓扑：docs/knowledge/dependency-graph.yaml
Refreshed phase-contracts：docs/knowledge/phase-contracts/
```

**增量模式行为**：
- **跳过** Phase 0 基础设施（已存在，不重新设计；除非作用域声明需要新增共享表——此时需追加新共享表 DDL 到 `contracts/schema.sql` 并纳入 `shared-kernel-manifest.yaml`）
- **跳过** conventions.md 重新生成（仅追加新域枚举值到 §13）
- **仅生成** 新增域的表设计（§5）、API 契约（§6）
- **检查** 新 API 路径与已有路径的冲突
- **检查** 新事件名与已有事件的冲突
- **检查** 新外键引用与已有表列名/类型的一致性

**产出**：

| 文件 | 内容 |
|------|------|
| `docs/trace/runs/v{N}/spac.md` | 增量架构设计（含增量元信息、新域 §5/§6、跨域集成点、设计决策） |
| `docs/knowledge/phase-contracts/p{k}-contracts.md` | 新域的契约摘要 |
| `docs/knowledge/dependency-graph.yaml` | 追加新域依赖边（域调用/事件收发） |

**退出条件**：
- `docs/trace/runs/v{N}/spac.md` 中「增量元信息」段的新增上下文列表非空
- 新 API 路径与已有路径无冲突（或在 §11 中记录了冲突消解决策）
- 新事件名与已有事件名无冲突
- 新外键引用与 `contracts/schema.sql` 已有列名/类型一致（或在 §11 中记录了消解决策）
- （仅当作用域声明「新增共享表」）新共享表 DDL 已追加到 `contracts/schema.sql`，`shared-kernel-manifest.yaml` 已纳入新共享表，spac.md §5 记录了其结构

#### 设计复核门（Gate 1，两种模式通用）

设计完成、进入拆解前，委托 `bmad-review` 对 `spac.md` 做对抗复核（lenses=`adversarial` + `edge-case-hunter` + `verification-gap`）——审「设计是否会误导下游拆解、边界是否覆盖、声称与可验证是否一致」。

- **通过**：无阻断性发现 → 进入 Step 3。
- **不通过**：回 Step 2，`architecture-design-generator` 按发现修正 `spac.md` 后重审。

> 复核细节与 lens 语义见 `bmad-review` skill，本编排器不复制其内部逻辑（原则 3）。

---

### Step 3: 卡片拆解编排

#### 首轮模式

调用 `plane-issue-decomposer` 的**标准模式**，产出首轮全量卡片。

**子 Skill 调用**：

```
Issue 拆解：基于 docs/trace/runs/v1/spac.md 拆解首轮 Issue 卡片。
输出目录：docs/trace/runs/v1/
架构文档：docs/trace/runs/v1/spac.md
配套文件：conventions.md, schema-shared.sql, seed-anchors.sql, shared-kernel-manifest.yaml, roles.md, docs/knowledge/
```

**首轮模式行为**：
- 生成**全部**卡片：Phase 0 基础设施卡（DB→Auth→Seed→契约冻结）+ 领域层全栈卡 + 集成层（集成闭环卡、封版归档卡）+ 刷新层（状态刷新卡）
- 领域卡 blocked_by 走 BFS 依赖链（Phase 0 先行冻结，P1+ 并行）
- 生成 `docs/trace/runs/v1/agent_plane.md` + `docs/trace/runs/v1/issues.yaml`

#### 增量模式

调用 `plane-issue-decomposer` 的**迭代模式**，产出增量卡片。

**子 Skill 调用**：

```
迭代拆解：基于 docs/trace/runs/v{N}/spac.md 拆解 Round {N} 增量卡片。
输出目录：docs/trace/runs/v{N}/
Incremental design：docs/trace/runs/v{N}/spac.md
Refreshed contracts：contracts/openapi.yaml, contracts/schema.sql, contracts/events.yaml, contracts/naming.yaml, contracts/routes.yaml, contracts/cross-context-writes.md
Refreshed manifest：shared-kernel-manifest.yaml
Updated conventions：conventions.md
环境配置契约：docs/knowledge/config-contract.md
依赖拓扑：docs/knowledge/dependency-graph.yaml
Refreshed phase-contracts：docs/knowledge/phase-contracts/
作用域：新增 {domain}，已有 {existing_domains} 只读
```

**迭代模式行为**：
- **跳过全部 Phase 0 基础设施卡**（已存在且可运行；除非 spac.md 声明需要新增共享表）
- **新增共享表时**（spac.md 声明）：生成 1 张 Phase 0 共享表卡（migration + seed），其余 Phase 0 基础设施卡仍跳过
- **仅生成新增域的全栈卡**（后端 + 前端同卡）
- **所有新增域全栈卡 blocked_by = []**（基础设施已就绪）；例外——若某全栈卡 import 了集成增强卡新追加的门面导出，须 blocked_by 该增强卡
- **自动跳过已有域**（不在本次 scope）
- **生成收口卡**：集成闭环卡、封版归档卡、状态刷新卡（与首轮相同，但封版归档含 README 更新）
- **生成迭代特有卡**：集成增强卡（已有域暴露新接口）、契约冲突消解卡（spac.md §11 记录了需修改已有域路径的冲突时）

**产出**：

| 文件 | 内容 |
|------|------|
| `docs/trace/runs/v{N}/agent_plane.md` | 迭代规划总览（差距报告 + 校验清单 + 依赖图） |
| `docs/trace/runs/v{N}/issues.yaml` | 增量 Issue 卡片数据（可导入 Plane.so） |

**卡片数量预估**：

| 卡片类型 | 数量 | 说明 |
|---------|------|------|
| 共享表卡 | 0-1 | 若 spac.md 声明新增共享表（migration + seed，Phase 0） |
| 新增域全栈卡 | 1-2 | 一个限界上下文的全栈实现 |
| 集成增强卡 | 0-2 | 若新域需要已有域暴露新接口 |
| 契约冲突消解卡 | 0-1 | 若 docs/trace/runs/v{N}/spac.md §11 记录了需修改已有域路径/命名的冲突（跨域集成） |
| 集成闭环卡 | 1 | 三阶段闭环：扫描验证 + 可运行性验证 + 缺陷自愈 |
| 封版归档卡 | 1 | 10 项全量检查 + 跨轮集成检查 + README 更新 |
| 状态刷新卡 | 1 | 为下一轮准备刷新后的 contracts/ |
| **总计** | **4-9** | 以上为「新增独立域」场景（含共享表卡 0-1）；「修改既有域」4-5 张、「跨域集成」5-7 张（各场景均含 3 张收口卡），见 references/incremental-patterns.md |

---

### Step 4: 验证与交付

#### 首轮模式验证

| 检查项 | 验证方法 | 不通过时 |
|--------|---------|---------|
| 全部设计文件落盘 | 逐一确认 spac.md + README.md + conventions.md + schema-shared.sql + seed-anchors.sql + shared-kernel-manifest.yaml + roles.md（若适用）+ scenes.md + docs/knowledge/（含 config-contract.md + dependency-graph.yaml + shared-kernel-api.md + module-template.md + phase-contracts/）存在 | 回 Step 2 补生成缺失文件 |
| DDD 语义全量可追溯 | 复核 spac.md：每个 `stateMachines.json` 状态机在 §5/§6/§11 三态之一承载（落库/会话态流转图/§11 决策）；每条 `rules.json` 规则有执行点声明；查询/视图/透视端点未拍平为 `{list}`（含维度参数 + 响应 shape + 切换重查语义） | 回 Step 2 补架构设计（子 skill 补承载/执行点/视图语义） |
| 卡片覆盖完整 | 架构文档逐章覆盖检查（子 skill 已执行，此处复核） | 回 Step 3 补拆 |
| Phase 0 卡存在 | grep issues.yaml 中 phase=0 的卡 | 回 Step 3 补拆（子 skill 补充，编排器不直接生成卡片） |
| 契约冻结卡存在 | 确认生成 contracts/ 六件套的卡 | 回 Step 3 补拆 |
| 集成闭环卡 + 封版归档卡 + 状态刷新卡存在 | grep issues.yaml | 回 Step 3 补拆 |
| BFS 链完整 | blocked_by 无悬空引用、无环、全局可达 | 回 Step 3 补拆（子 skill 修正依赖链） |
| 单卡验证段完整 | 逐张 grep issues.yaml：每张产出代码的卡（Phase 0 基础设施卡 / 领域全栈卡 / 集成增强卡）description 含「## 验收标准」+「## 验证」两段，且验证段含 ≥2 条可执行验证（具体命令或观察手段，非占位符）；收口卡（集成闭环/封版归档/状态刷新）本身即验证卡，不在此列 | 回 Step 3 补拆（子 skill 按 description-template.md 九段模板补全验证段） |

#### 增量模式验证（7 项）

> 所有「不通过」一律**回 Step 3 补拆**，由 `plane-issue-decomposer` 迭代模式修正（本编排器不直接改卡片，见原则 3）。

| 检查项 | 验证方法 | 不通过时 |
|--------|---------|---------|
| 无未声明 Phase 0 卡 | grep issues.yaml 中 phase=0 卡 → 逐张核对是否为 spac.md 声明的新增共享表卡 | 回 Step 3 补拆（子 skill 移除未声明卡，声明的新增共享表卡保留） |
| blocked_by 正确 | 按场景核对（见 `references/incremental-patterns.md` 各场景 blocked_by）：新增域全栈卡 blocked_by = []（例外：消费集成增强卡门面导出的卡须 blocked_by 该增强卡）；跨域集成——消费方增强卡须 blocked_by 生产方增强卡、事件对齐卡须 blocked_by 生产卡+消费卡、集成闭环卡须 blocked_by 全部集成增强卡+事件对齐卡+契约冲突消解卡 | 回 Step 3 补拆（子 skill 修正依赖链） |
| API 路径无冲突 | 提取新卡 API 路径 → 与 contracts/openapi.yaml 交叉比对 | 回 Step 3 补拆（子 skill 标注并修正冲突） |
| 事件名无冲突 | 提取新卡事件名 → 与 contracts/events.yaml 交叉比对 | 回 Step 3 补拆（子 skill 标注并修正冲突） |
| import 路径正确 | 提取新卡 import 语句 → 与 shared-kernel-manifest.yaml 交叉比对 | 回 Step 3 补拆（子 skill 修正为 manifest 路径） |
| 约束段完整 | 每张全栈卡含命名/边界/枚举/UUID/路由格式约束 | 回 Step 3 补拆（子 skill 补充缺失约束） |
| 收口卡存在 | grep issues.yaml 中集成闭环卡 + 封版归档卡 + 状态刷新卡三张齐备 | 回 Step 3 补拆（子 skill 补充缺失收口卡） |
| 单卡验证段完整 | 逐张 grep issues.yaml：每张产出代码的卡（共享表卡 / 新增域全栈卡 / 集成增强卡 / 契约冲突消解卡）description 含「## 验收标准」+「## 验证」两段，且验证段含 ≥2 条可执行验证（具体命令或观察手段，非占位符）；收口卡不在此列 | 回 Step 3 补拆（子 skill 按 description-template.md 九段模板补全验证段） |

> **交付自检（不回 Step 3）**：`docs/trace/runs/v{N}/iteration-plan.yaml` 由本编排器在「完成改动之后」回填，交付前自检九字段齐全（`round` / `base_round` / `base_artifacts` / `incremental_design` / `included_contexts` / `card_count` / `integration_enhancement_count` / `validation_card_count` / `generated_at`）；缺失则编排器直接补写。

#### 卡片复核门（Gate 2，两种模式通用）

机械检查全部通过后，交付前委托 `bmad-review` 对 `issues.yaml` 做对抗复核（lenses=`adversarial` + `edge-case-hunter` + `verification-gap`）——审「每张卡的 description 是否会让执行 Agent 做错、任务清单是否漏分支、验证段是否真的能验证」。

- **粒度**：默认**逐卡审**（每张产出代码的卡单独过三 lens，最严）；规模大时可整集审。
- **通过**：无阻断性发现 → 进入交付物清单。
- **不通过**：回 Step 3，`plane-issue-decomposer` 修正卡片后重审。

> 复核细节见 `bmad-review` skill（原则 3：本编排器只委托、不复制 lens 逻辑）。

#### 交付物清单

**首轮**：

```
docs/trace/runs/v1/
├── spac.md                  # 完整架构设计文档
├── agent_plane.md           # 首轮规划总览
└── issues.yaml              # 首轮全量卡片

{项目根目录}/
├── README.md                # 项目启动指南
├── conventions.md
├── schema-shared.sql
├── seed-anchors.sql
├── shared-kernel-manifest.yaml
├── roles.md
├── scenes.md                # 场景链路分析报告
└── docs/knowledge/
    ├── config-contract.md        # 环境变量唯一真相
    ├── dependency-graph.yaml     # 依赖拓扑（域调用/事件收发）
    ├── shared-kernel-api.md
    ├── module-template.md
    └── phase-contracts/p{k}-contracts.md
```

**增量**：

```
docs/trace/runs/v{N}/
├── spac.md                  # 增量架构设计文档（Step 2 产出）
├── agent_plane.md                       # 迭代规划总览（Step 3 产出）
├── issues.yaml                          # 增量 Issue 卡片（Step 3 产出）
├── iteration-plan.yaml                  # 迭代计划记录（编排器回填：作用域 + 实际产出数）
└── state-precheck-report.md             # 状态前置检查报告（Step 1 发现过期时产出）

docs/knowledge/phase-contracts/
└── p{k}-contracts.md                 # 新域契约摘要（Step 2 产出）

docs/knowledge/dependency-graph.yaml  # 追加新域依赖边（Step 2 产出）

（注：以上为**本轮编排交付**。后续卡片执行阶段才产出的文件不计入本轮编排交付：
  README.md 由封版归档卡更新；state-refresh-report.md 由状态刷新卡产出——均在 issues.yaml 入库执行后才出现）
```

#### 输入-输出对照报告

向用户展示最终对照报告：

```
## 开发交付报告（{首轮 / 增量}）

### 输入文件使用情况
| 输入文件 | 用途 | 使用的步骤 |
|---------|------|-----------|
| ... | ... | ... |

### 产出物
| 文件 | 行数/卡片数 | 说明 |
|------|-----------|------|
| ... | ... | ... |

### 本轮卡片摘要
| ID | 名称 | Phase | Priority | blocked_by |
|----|------|-------|----------|------------|
| ... | ... | ... | ... | ... |
```

---

## 模式差异对比

| 维度 | 首轮模式 | 增量模式 |
|------|---------|---------|
| 输入 | 源文件（无「唯一真相」） | contracts/（唯一真相）+ DDD |
| Step 1 前置检查 | 环境前置（Docker / 半成品续接） | 状态刷新（8 项一致性检查） |
| 设计子 skill 模式 | 完整模式（五步骤 + 知识资产） | 增量模式（仅新域 §5/§6） |
| 拆解子 skill 模式 | 标准模式（全量卡片） | 迭代模式（仅新域 + 收口卡） |
| Phase 0 卡片 | 全部生成 | 跳过（除非需新增共享表） |
| 领域卡 blocked_by | BFS 依赖链 | 全部 `[]` |
| 契约冻结卡 | 生成（产出 contracts/ 六件套） | 无（已有） |
| 特有卡片 | 契约冻结卡、Phase 0 全部基础设施卡 | 集成增强卡、契约冲突消解卡 |
| 冲突检测 | 无（greenfield） | 路径/事件/命名/外键 vs 已有契约 |

---

## 不可协商原则

以下原则贯穿整个工作流，任何步骤不得违反。

### 通用原则（两种模式）

| # | 原则 | 说明 |
|---|------|------|
| 1 | **输入文件显式声明** | 每步必须向用户明确列出所需输入文件及理由，不用"推荐""建议"等模糊词 |
| 2 | **每张卡自包含** | 首轮与增量卡片一样，必须是自包含的执行单元（含完整 import 路径、约束、验收标准、验证步骤——九段模板见 plane-issue-decomposer/references/description-template.md） |
| 3 | **子 skill 是唯一执行体** | 本 skill 只编排、不生成设计文档或卡片——设计由 architecture-design-generator 产出，卡片由 plane-issue-decomposer 产出 |

### 首轮模式专属

| # | 原则 | 说明 |
|---|------|------|
| 4 | **源文件为唯一需求来源** | 首轮设计的业务需求只能来自源文件，不臆造需求 |
| 5 | **缺失类别可推断不阻塞** | 缺失的源文件类别由子 skill 推断处理，不向用户索要不必要文件 |
| 6 | **完成验证强制** | 全部设计文件落盘、§11 无 open 项，才视为完成 |

### 增量模式专属

| # | 原则 | 说明 |
|---|------|------|
| 7 | **只追加不破坏** | 已有域代码只读。若需修改，仅限追加新端点/新事件/新导出，不修改已有签名 |
| 8 | **contracts 是唯一真相** | 已有域的**接口信息**（API 签名、表结构、事件 payload）从 contracts/ 获取，不从设计文档获取、不从源码推测——读取已有域源码仅供目录结构/代码模式参考（见原则 11），不据此推导接口 |
| 9 | **基础设施不复生** | Phase 0 基础设施（认证、DB Pool、CSRF、Session 等）已存在且已验证——不重新生成、不重新设计 |
| 10 | **Hub 文件最小修改** | 路由汇聚、菜单汇聚等 Hub 文件通过约定式扫描自动发现新域文件（glob 模式），手工修改量最小化 |
| 11 | **自动发现，不要求用户手动提供** | 已有域源码（`backend/modules/{existing}/`、`frontend/src/views/{existing}/`）由 skill 自动探索目录结构和读取关键文件——用户只需给出已有域的名称，不需要粘贴任何代码 |
| 12 | **README.md 随版本迭代更新** | 每轮迭代封版后，README.md 必须反映当前系统真实状态。由封版归档卡负责执行，状态刷新卡负责验证 |

---

## 用户提示词模板

### 首轮模式

用户只需提供源文件路径 + 项目名，skill 自动完成其余所有步骤：

```
首轮开发：基于以下源文件生成 <项目名> 的完整架构设计与 Issue 卡片。
源文件：<路径列表，或"当前目录下的 ddd/、src/、api/ 等">
```

**不需要提供的内容**（skill 自动处理）：
- ❌ 不需要描述 Phase 划分
- ❌ 不需要指定技术栈（由 architecture-design-generator PART 4 技术约束确定）
- ❌ 不需要逐文件说明内容

### 增量模式（三种场景）

| 场景 | 典型提示词 |
|------|-----------|
| **新增独立域** | `增量开发：新增 <域英文名> 域（<域中文名>）。已有域 <已有域英文名>（<已有域中文名>）已实现并验证通过。基线上轮：Round <N-1> (v<N-1>.0.0)，本轮为 Round <N>。DDD 模型：ddd/<domain>.json。作用域：仅新增 <域英文名>，已有 <已有域英文名> 只读，不修改已有域代码。` |
| **修改既有域** | `增量开发：在已有 <域英文名> 域中追加 <功能描述>。DDD 模型（如有增量版本）：ddd/<domain>-v2.json。作用域：仅修改 <域英文名>，追加 <N> 个端点/<M> 个页面，不修改已有 API 签名和表结构的关键列。其他域只读。` |
| **跨域集成** | `增量开发：实现 <域A英文名> 与 <域B英文名> 之间的跨域集成。集成内容：<描述集成需求>。作用域：仅在两个域之间追加集成端点/事件订阅，不修改两个域已有的内部逻辑。` |

**提示词关键要素**（增量，4 项）：

| 要素 | 说明 |
|------|------|
| **做什么** | 新增域 / 修改域 / 跨域集成 |
| **基于什么** | 哪个 DDD 文件 + 基线上轮 |
| **什么已有** | 哪些域已存在（让 skill 知道参考谁） |
| **不碰什么** | 作用域边界 |

> 增量模式不需要提供：已有域源码路径、contracts 内容、import 路径、Phase 0 状态。

---

## 在开始改动之前

1. 读取本次开发涉及的所有输入文件（按 Step 0 分析结果）
2. 增量模式：读取 `docs/memory/` 最新记忆文件，了解之前轮次的注意事项；读取 `docs/trace/runs/v{N-1}/` 中的封版报告（如有），了解已知偏差

## 完成改动之后

1. 输出 Step 4 的输入-输出对照报告
2. 追加到 `docs/memory/YYYY-MM-DD.md`：本轮的开发范围、输入文件清单、产出物清单、未被其他流程覆盖的注意事项
3. 增量模式：将 `docs/trace/runs/v{N}/iteration-plan.yaml` 写入磁盘（由本编排器回填——把 Step 0 声明的作用域与实际产出数合并归档，区别于子 skill 产出的 `agent_plane.md`/`issues.yaml`。字段：round / base_round / base_artifacts / incremental_design / included_contexts / card_count / integration_enhancement_count / validation_card_count / generated_at）

---

## 参考文件

**模式专属**：
- `references/first-round-patterns.md` — 首轮编排模式（源文件发现/分类、环境前置、首轮卡片类型、首轮提示词）
- `references/incremental-patterns.md` — 增量三种场景（新增域 / 修改域 / 跨域集成）的卡片类型、约束差异、提示词模板

**流程规则**：
- `references/input-file-rules.md` — 输入文件四问论证框架（是什么/为什么需要/缺了会怎样/验证方式）+ 首轮/增量双输入表
- `references/state-verification.md` — 增量模式 Step 1 新鲜度判定 + 刷新决策（8 项检查 / 八步刷新委托子 skill state-refresh-procedure.md）

**外部协作 skill**（本编排器委托、不内联其逻辑）：
- `bmad-review` — 两道复核门（Gate 1 审 `spac.md` / Gate 2 审 `issues.yaml`），lenses = adversarial + edge-case-hunter + verification-gap
- `bmad-deep-recon` — Step 2 技术未知项时的决策级研究（条件触发）
