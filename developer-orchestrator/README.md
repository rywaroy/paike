# developer-orchestrator

> 开发流程编排器 — 编排「架构设计 → Issue 拆解」流水线，覆盖**首轮开发**（源文件 → 首轮全量卡片）与**增量开发**（已有系统 → 增量卡片）两种模式。

本 skill 是**流程编排器**（非代码生成器）：它编排 `architecture-design-generator`（架构设计）与 `plane-issue-decomposer`（卡片拆解）两个子 skill 的执行流程，自己**不生成**设计文档或卡片，止步于产出 `issues.yaml`（入库由 `plane-issue-database-insert` 可选承接）。

---

## 执行模式

| 模式 | 触发条件 | 子 skill 调用 | 输出 |
|------|---------|--------------|------|
| **首轮模式** | 新项目，用户提供源文件 | `architecture-design-generator` 完整模式 → `plane-issue-decomposer` 标准模式 | `docs/trace/runs/v1/`：spac.md + agent_plane.md + issues.yaml |
| **增量模式** | 已有可运行系统，用户声明增量作用域 | `architecture-design-generator` 增量模式 → `plane-issue-decomposer` 迭代模式 | `docs/trace/runs/v{N}/`：spac.md + agent_plane.md + issues.yaml + iteration-plan.yaml |

> 完整工作流（5 步，含两道 bmad-review 复核门）、模式判定、不可协商原则、提示词模板、交付物清单 —— 见 [`SKILL.md`](SKILL.md)（skill 触发时自动加载）。

---

## 目录结构

```
developer-orchestrator/
├── SKILL.md                              # 主 skill 文件（触发时加载到上下文）
├── README.md                             # 本文件（索引）
└── references/
    ├── input-file-rules.md               # 输入文件四问论证框架 + 首轮/增量输入分级表
    ├── first-round-patterns.md           # 首轮卡片类型、编排差异、常见陷阱
    ├── state-verification.md             # 增量 Step 1 新鲜度判定 + 刷新决策（检查/刷新委托子 skill）
    └── incremental-patterns.md           # 增量三场景（新增域/修改域/跨域集成）
```

| 文件 | 作用 | 何时读取 |
|------|------|---------|
| `SKILL.md` | 双模式 5 步工作流、三组原则、提示词模板 | skill 触发时自动加载 |
| `references/input-file-rules.md` | 四问论证框架 + 首轮/增量输入分级表（单一真相源） | Step 0 输入分析时读取 |
| `references/first-round-patterns.md` | 首轮卡片类型、编排差异、常见陷阱 | 首轮模式 Step 3/4 时读取 |
| `references/state-verification.md` | 增量 Step 1 新鲜度判定 + 刷新决策（检查/刷新委托子 skill） | 增量 Step 1 不通过时读取 |
| `references/incremental-patterns.md` | 增量三场景卡片类型、约束差异、提示词模板 | 增量模式判断场景时读取 |

---

## 与其他 skill 的关系

```
                developer-orchestrator
                （开发流程编排器）
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
   Step 2 调用               Step 3 调用
   architecture-            plane-issue-
   design-generator         decomposer
   （完整 / 增量模式）        （标准 / 迭代模式）
          │                         │
          ▼                         ▼
    spac.md + 独立文件        agent_plane.md + issues.yaml
                            （all in docs/trace/runs/v{N}/）
```

| skill | 角色 | 被调用模式 |
|------|------|-----------|
| **developer-orchestrator** | 流程编排器 | — |
| **architecture-design-generator** | 架构设计生成 | 完整模式（首轮）/ 增量模式（增量） |
| **plane-issue-decomposer** | Issue 卡片拆解 | 标准模式（首轮）/ 迭代模式（增量） |
| **plane-issue-database-insert** | Issue 入库（可选后续步骤） | 编排器交付 issues.yaml 之后手动触发 |
| **bmad-review** | 设计/卡片对抗复核（两道门） | Gate 1 审 spac.md / Gate 2 审 issues.yaml（adversarial + edge-case + verification-gap） |
| **bmad-deep-recon** | 技术研究（条件触发） | Step 2 设计存在技术未知项时产出决策级研究 |

> 编排器止步于产出 `issues.yaml`。入库由 `plane-issue-database-insert` 承担——用户拿到 `issues.yaml` 后自行触发，不在本编排器范围内。

---

## 迭代专项约束（增量模式，经多轮实践验证）

增量模式下追加了以下专项约束，防止已知的增量开发陷阱：

| 约束 | 防止的陷阱 | 落点 |
|------|-----------|------|
| **Docker 卷持久化迁移补执行** | pgdata 卷已存在 → 新 migration 被 docker-entrypoint-initdb.d 静默跳过 → 新表不存在（500） | `plane-issue-decomposer/references/coverage-check.md` |
| **种子数据 FK 锚点引用验证** | Agent 自编 UUID 段 → 与实际 seed-anchors.sql 不一致 → FK 约束违反 | 同上 |
| **UUID v4 验证逐文件覆盖** | 验证段只检查部分文件 → 未覆盖文件生成 variant≠4 UUID → isUUID() 拒绝（400） | 同上 |
| **README.md 随版本迭代更新** | 每轮新增域后项目文档未更新 → README 与系统实际状态脱节 | 用户反馈 |

> 这些约束已写入 `plane-issue-decomposer/references/coverage-check.md` 与 `iteration-mode.md`，由迭代模式下的覆盖检查自动执行。
