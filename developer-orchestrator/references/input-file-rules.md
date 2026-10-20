# 输入文件必要性论证规则

> 本文档定义开发流程编排中每个输入文件的论证框架。核心原则：**不假定、不推测、不模糊**——每个文件的必要性必须附具体理由和缺失后果。

---

## 论证四问（两种模式通用）

对每个候选输入文件，必须回答以下四个问题。回答必须是**可验证的事实陈述**，不是主观意见：

| 问 | 说明 | 正确示例 | 错误示例 |
|----|------|---------|---------|
| **是什么** | 文件路径和内容描述 | `contracts/openapi.yaml` — 从实际后端路由文件提取的 OpenAPI 3.0 规范，含全部已有 API 端点路径、方法、请求体、响应结构 | "API 文档" |
| **为什么需要** | 在本次开发中该文件被哪个步骤消费、用于做出什么决策 | "Step 4 路径冲突检测：提取新域卡片中所有 API 路径 → 与 openapi.yaml 中已有 paths 交叉比对 → 命名冲突则标记阻断偏差" | "方便了解 API" |
| **缺了会怎样** | 缺少此文件时，哪项具体检查或决策无法执行，导致什么可观测的错误 | "新域 POST /api/v1/registrations 可能与已有 POST /api/v1/leads/:id/register 路径冲突 → 后端路由挂载时报 `Duplicate route` 或请求被错误路由 → 404/405" | "可能导致问题" |
| **验证方式** | 如何确认此文件内容是最新的（反映实际代码状态，非过期的设计文档） | "扫描 `backend/modules/*/api/*.routes.ts` 提取全部 `router.{method}('{path}',...)` → 与 openapi.yaml 中的 paths 比对 → 偏差列表" | "看起来是新的" |

---

## 输入文件分级

### 首轮模式

首轮没有「唯一真相」可消费——输入是用户提供的源文件。**缺失的类别不阻塞**：由 `architecture-design-generator` PART 1.2「缺失类别的处理」自动推断，但编排器必须向用户说明「缺了 XX → 将如何推断」。

| 类别 | 典型特征 | 缺失时的处理（子 skill 推断） |
|------|---------|------------------------------|
| **DDD 领域模型** | `.json`，含 `stereotype`/`AggregateRoot`/`DomainEvent`/`commands`/`events`；或**多文件标注目录**（`boundedContexts.json`/`aggregates.json`/`commands.json`/`domainEvents.json`/`stateMachines.json` 等，字段用 `subdomainType`/`aggregateRoot`/`raisedBy`/`raises`/`scope`） | 从路由结构、组件分组、API 端点聚类反推领域边界 |
| **用户故事** | `.json`，含 `asA`/`iWant`/`soThat`/`acceptanceCriteria`/`businessRules`/`flows` | 从 DDD 命令/事件/状态机与页面任务反推验收条件与业务规则，但 AC/BR **降级为推断**（非权威，静默缺失不可检测） |
| **数据库 Schema** | 含 `CREATE TABLE`/`ALTER TABLE` 的 `.sql` | 从 DDD 聚合属性或组件数据绑定设计表结构 |
| **路由配置** | 引入 `vue-router`（`createRouter`/`createWebHistory`）的文件；原型路由 `createMemoryHistory` 属参考 | 从组件目录结构反推路由 |
| **页面信息架构 / 页面地图** | Markdown `page_map.md`/`page_information_architecture.md` 或 JSON `page_split.json` | 从 UI 组件分组与原型路由（`routeRecords`/`navigationItems`）反推页面→导航→上下文映射 |
| **状态管理** | Pinia `defineStore` / Vuex `createStore` | 从组件数据依赖反推 Store 需求 |
| **API 定义** | `axios`/`fetch` 封装、含 baseURL + endpoint | 从 Store action 和组件需求设计 RESTful 端点 |
| **UI 组件** | `.vue`/`.jsx`/`.tsx` | 从领域分析设计页面级组件层级 |
| **类型定义** | `interface`/`type`/`enum`，`.d.ts` | 从 DDL 列类型或 DDD 属性推断 |

### 增量模式

#### 必须（MANDATORY）

缺失任一项 = **无法开始**增量设计。Step 0 必须向用户明确列出缺失文件及影响，等待用户补充后再继续。

| 文件 | 为什么是必须的 | 缺了会怎样 |
|------|-------------|-----------|
| **DDD 模型** (`ddd/{domain}.json`) | 定义新增域的全部实体、属性、状态机、事件、跨域引用——是业务需求的唯一结构化来源 | 不知道要构建什么——无法生成增量架构设计，无法拆解卡片 |
| **contracts/openapi.yaml** | 已有域的 API 接口清单——新端点路径冲突检测的唯一参照 | 新 API 路径可能与已有路径静默冲突 → 路由挂载时 Express 报 `Duplicate route` 或请求被错误路由到已有端点 |
| **contracts/schema.sql** | 已有数据库表结构——新表外键引用、migration 编号接续的唯一参照 | 新表外键引用指向不存在的列名或类型 → migration 执行失败；migration 编号冲突 → 文件被跳过或覆盖 |
| **contracts/naming.yaml** | 跨卡命名契约表（类型名、Store 导出名、API 函数名、事件名、DB 列名）——新域命名冲突检测的唯一参照 | 新域类型名/Store 名/API 函数名/事件名与已有命名冲突 → 跨域引用时 import 到错误模块或类型不匹配 |
| **contracts/routes.yaml** | 前端路由事实全集（path、name、component、meta、菜单 moduleId/label/entryRoutePath/order）——新域前端路由冲突检测的唯一参照 | 新域前端路由 path 与已有路由冲突 → 路由不可达或被错误匹配 |
| **shared-kernel-manifest.yaml** | 共享基础设施的 import 路径权威来源——新域 Agent 的 import 语句必须从此文件硬编码 | Agent 自行推断 import 路径 → `Cannot find module` 编译错误；或 import 了 internal/ 实现细节破坏模块边界 |
| **conventions.md** | 全栈命名格式、路由注册方式、apiClient 信封消费规则、UUID v4 要求等——新域代码必须与已有代码风格一致 | camelCase/snake_case 混用 → 前端字段绑定 undefined；路由导出格式不统一 → 自动发现失败；`response.data` 单层取值 → 拿到信封而非业务数据 |
| **docs/knowledge/config-contract.md** | 环境变量唯一真相（DB_HOST/CORS_ORIGIN/HOST_*_PORT 等）——新域环境变量追加与冲突检测的唯一参照 | 新域环境变量与已有配置冲突或重复定义 → 服务间通信端口错乱、CORS 失效 |
| **docs/knowledge/dependency-graph.yaml** | 域调用/事件收发依赖拓扑——增量设计判定「改 A 影响 B」的唯一拓扑清单 | 无法快速判断新域接入影响哪些已有域/事件 → 漏测跨域回归 |
| **docs/knowledge/phase-contracts/** | 已有域**实际接口**（表/API/事件/权限点）的唯一来源——增量设计的权限点去重、已有域接口内联、跨域依赖判断都依赖它 | 新域权限点与已有权限点重名 → 前端权限控制混乱；上游契约无法内联 → 跨域调用签名/表结构错误 |

#### 条件必须（CONDITIONAL）

仅在特定场景需要。若不适用，标注"不适用——本场景无需此文件"。

| 文件 | 适用场景 | 为什么需要 | 如何判断是否需要 |
|------|---------|-----------|---------------|
| **contracts/events.yaml** | 新域发布或消费事件（DDD 含 DomainEvent / 订阅已有事件） | ① 新事件名不能与已有事件重名（socket.io 事件无命名空间隔离）② 了解已有事件 payload 格式 ③ 新域可能需要订阅已有事件 | 检查 DDD JSON 是否有 DomainEvent class（发布）或订阅已有事件（消费） |
| **seed-anchors.sql** | 新域 seed 数据需要引用已有用户/角色/权限等锚点 | 新 seed INSERT 中的外键值必须引用种子锚点中已定义的 ID → 否则外键约束失败 | 新域 seed 数据是否含外键引用已有表（users/roles 等锚点表，即有上游依赖）——检查新域 DDD 的 `references` / 表设计是否含 FK 指向已有表 |
| **已有域源码** (`backend/modules/{existing}/` + `frontend/src/views/{existing}/`) | 需要了解代码模式作为参考（文件组织、import 模式、代码风格）；需确认已有域的 index.ts 门面导出内容 | **无需用户手动提供。** Skill 自动执行：① 列出目录结构 ② 读取关键文件（routes.ts、menu.ts、permissions.ts、index.ts）③ 从 contracts/ 获取已有 API 签名。用户只需提供已有域的名称 | 所有增量开发场景都需要——Skill 自动发现 |

#### 可选（OPTIONAL）

有则更好，无则不阻塞。标注"未提供，跳过相关检查"。

| 文件 | 用途 | 缺了怎么办 |
|------|------|-----------|
| 原型/设计稿 | 页面布局参考 | 按 conventions.md 中的通用组件样式（btn/input/card/badge/table/modal）自行设计 |
| 用户故事文件 | 验收条件细化 | 从 DDD JSON 的 stateTransitions 和 constraints 推导验收条件 |

---

## 输入文件发现流程

### 首轮模式

```
1. 用户声明开发目标（项目名 + 源文件位置）
   ↓
2. 扫描用户提供的源文件，按 PART 1.1 输入分类表分类（含用户故事 / 页面信息架构 / 多文件 DDD 标注等）
   ↓
3. 识别缺失类别 → 标注「将由子 skill 推断」+ 推断方式
   ↓
4. 检查目标目录 docs/trace/runs/v1/ 是否已存在部分文件（半成品续接）
   ↓
5. 向用户展示输入文件分析报告（Step 0 输出格式）
   ↓
6. 用户确认后 → 进入 Step 1（环境前置检查）
```

### 增量模式

```
1. 用户声明增量作用域（新增什么域 / 修改什么域）
   ↓
2. 定位 DDD JSON 文件（ddd/{domain}.json）
   ↓
3. 读取 DDD JSON → 识别：
   ├── references 非空？ → 需要 phase-contracts
   ├── 有 DomainEvent class？ → 需要 contracts/events.yaml
   ├── 有 Command class？ → 需要 contracts/events.yaml（事件发布）
   ├── 订阅已有事件（DDD 含 subscribesTo/consumes 对已有域事件的引用）？ → 需要 contracts/events.yaml（事件消费）
   └── 有跨域查询？ → 需要相关域的 phase-contracts
   ↓
4. 检查 contracts/ 是否存在且最新
   ├── 存在 → Step 1 状态刷新检查
   └── 不存在 → 标记：Step 1 将执行全量刷新（从实际代码重建六件套）；若实际代码也不存在，提示改用首轮模式
   ↓
5. 向用户展示输入文件分析报告（Step 0 输出格式）
   ↓
6. 用户确认后 → 进入 Step 1
```

---

## 常见场景输入文件需求矩阵

| 模式 | 场景 | 必须输入 | 条件输入 | 典型卡片数 |
|------|------|---------|---------|-----------|
| 首轮 | **新项目从零开发** | 源文件（DDD/SQL/路由/Store/API/组件任几类） | — | 8-20 |
| 增量 | **新增独立域**（无上下游依赖） | DDD + openapi + schema + naming + routes + manifest + conventions + phase-contracts + 已有源码参考 | — | 4-8 |
| 增量 | **新增域（有上游依赖）** | 上述全部 | seed-anchors | 4-8 |
| 增量 | **新增域（发布事件）** | 上述全部 | events.yaml | 4-8 |
| 增量 | **新增域（发布+消费事件）** | 上述全部 | events.yaml | 4-8 |
| 增量 | **修改既有域** | 该域的 DDD（若有增量版本）+ openapi + schema + naming + routes + manifest + conventions + 该域源码 | events.yaml（若新增事件） | 4-5 |
| 增量 | **跨域集成** | 涉及的全部域的 phase-contracts + openapi + events + 涉及域源码 | seed-anchors（若需新 seed） | 5-7 |

---

## 禁止行为

| 禁止 | 原因 |
|------|------|
| 在未读取 contracts/ 的情况下开始增量设计 | 不知道已有系统的 API 路径、表结构、事件名 → 冲突无法检测 |
| 用设计文档（spac.md）替代 contracts/ 作为已有系统的接口来源 | spac.md 是设计预期，contracts/ 是实际状态——两者可能已偏离 |
| 对用户说"建议提供 XXX"而不说明缺了会怎样 | 用户无法判断是否值得花时间提供该文件 |
| 假定已有域的代码结构而不实际列出目录 | 代码结构可能与设计文档的描述不一致 |
| 跳过 Step 0 直接进入设计 | 用户不知道你用了哪些文件做决策依据 |
| 首轮模式下向用户索要不必要的源文件 | 缺失类别可由子 skill 推断——首轮输入是「有多少用多少」，不是「缺一不可」 |
