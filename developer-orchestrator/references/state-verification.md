# 状态刷新前置检查

> 本文档定义增量开发 Step 1 的前置检查流程。核心原则：**contracts/ 必须反映实际代码状态，非设计文档中的预期状态。** 若 Round N-1 之后有代码修改（bug 修复、格式调整、热修复等），contracts 可能已过期——必须先刷新再进入增量设计。
>
> 本前置检查只做「新鲜度判定 + 委托」。**8 项一致性检查的执行细节与八步刷新流程由 `architecture-design-generator` 的状态刷新模式承担**（唯一执行体，见其 `references/state-refresh-procedure.md`）——本编排器不复制、不复述（原则 3：子 skill 是唯一执行体）。

---

## 为什么需要状态刷新

增量设计的输入是 contracts/（API 路径、表结构、事件、import 路径），不是 spac.md（设计文档）。原因：

| 用设计文档做输入 | 用 contracts/ 做输入 |
|-----------------|-------------------|
| 设计预期可能与实际实现偏离 | contracts/ 从实际代码提取——是唯一真相 |
| 设计文档不记录热修复变更 | contracts/ 刷新后包含所有实际变更 |
| 路径可能已被占用 | contracts/ 列出实际已注册的路径 |
| 表列名可能与 DDL 不一致 | contracts/ 从 migration 文件提取 |

---

## 与状态刷新卡的关系（职责边界）

状态刷新在系统中存在三个触发点，职责不同、互不覆盖：

| 触发点 | 位置 | 职责 | 产出 |
|--------|------|------|------|
| **状态刷新卡** | 每轮末尾（blocked_by 封版归档卡） | 全量八步刷新，反写 contracts 等设计 artifact | `docs/trace/runs/v{N}/state-refresh-report.md` |
| **本前置检查（Step 1）** | 下一轮增量开始前 | 仅做新鲜度判定；发现过期才委托子 skill 最小化刷新 | `docs/trace/runs/v{N}/state-precheck-report.md`（仅异常时） |
| **独立「状态刷新」模式** | 手动触发 | 等价于状态刷新卡 | `docs/trace/runs/v{N}/state-refresh-report.md` |

> 正常流程下，上轮状态刷新卡已保证 `contracts/` 最新，本 Step 1 只做快速新鲜度判断；只有轮间存在未经卡片流程的改动（热修复、手动调整等）时才触发最小化刷新。**两份报告用不同文件名区分**：状态刷新卡写 `state-refresh-report.md`（全量，每轮末尾必写），本 Step 1 写 `state-precheck-report.md`（最小化，仅异常时写），避免同轮内互相覆盖。

---

## 新鲜度判定

编排器只判断「contracts/ 是否最新」，不亲自执行一致性检查。分两层：

1. **快速新鲜度检查**（优先）：对比 `contracts/openapi.yaml` 的 mtime 与上轮刷新报告中的 `refreshed_at` 时间——见 SKILL.md Step 1「快速新鲜度检查」。
2. **8 项一致性检查**：当快速检查无法判断（无刷新报告、mtime 存疑）时，委托子 skill 状态刷新模式执行。8 项覆盖 `contracts/` 六件套（openapi/events/schema/routes/naming/cross-context-writes）+ `shared-kernel-manifest.yaml` + `conventions.md`（涌现约定）+ `docs/knowledge/phase-contracts/` + `roles.md` 与**实际代码状态**的一致性。

> 检查项清单、扫描范围、判定标准、八步刷新执行步骤，一律以子 skill `state-refresh-procedure.md` 为准。

---

## 刷新决策

```
新鲜度判定结果？
├── contracts/ 全缺失 → 委托 architecture-design-generator 状态刷新模式执行全量刷新（八步全部）
├── 部分过期 → 委托状态刷新模式执行最小化刷新（仅过期项对应步骤，映射见子 skill「子集刷新（最小化模式）」表）
└── 最新 → 跳过刷新，直接进入 Step 2
```

- **最小化刷新**产出 `docs/trace/runs/v{N}/state-precheck-report.md`（仅异常时写）；**全量刷新**（状态刷新卡 / 独立模式）产出 `state-refresh-report.md`（每轮末尾必写）。
- 刷新报告格式、偏差登记（deviation.yaml `stage: refresh`）见子 skill `state-refresh-procedure.md`「刷新报告模板」「deviation.yaml 约定」。

---

## 常见过期场景

| 场景 | 典型原因 | 影响 |
|------|---------|------|
| Round 1 后有热修复 | 路由文件中的 `isUUID()` 从 regex 恢复、seed UUID 修复为 v4 | openapi.yaml 中记录的 UUID 校验方式是 regex（已过期） |
| conventions 更新 | Round 1 后 skill 规则增强（如新增 redirect 约束、menu.ts 格式契约） | conventions.md §13 可能缺少新域特有的枚举值 |
| 中间件调整 | 新增/移除共享中间件 | shared-kernel-manifest.yaml 中的导出清单过时 |
| 数据库 migration 追加 | 新增 seed 执行 migration（如 004-seed-anchors.sql） | schema.sql 可能缺失新表 |

---

## 禁止行为

| 禁止 | 原因 |
|------|------|
| 跳过状态刷新检查直接进入增量设计 | 增量设计基于过期 contracts → 路径冲突检测失效、外键引用错误 |
| 假设 contracts 是最新的 | Round 1 之后可能有代码修改——只有检查结果能证明一致性 |
| 部分过期时全量重写 contracts/ | 全量重写会覆盖掉手动的精确调整——仅在 contracts/ 全缺失时才全量刷新 |
| 刷新后不记录日志 | 下一轮增量开发需要知道本次刷新做了什么 |
| 本编排器亲自执行 8 项检查或八步刷新 | 违反原则 3（子 skill 是唯一执行体）——检查与刷新一律委托 architecture-design-generator 状态刷新模式 |
