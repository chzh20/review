# AI Agent 消融实验系统：设计与实验总结

> 基于 `chapter1/context/agent.py`（ContextAwareAgent 系统）与 `my_ablation.json`（实验 1-1 消融实验结果）的完整分析。
> 文档日期：2026-08-17

---

## 一、系统定位与设计目标

这是一个 **AI Agent 教科书第一章（实验 1-1）** 的配套代码，核心目标不是"做一个好用的 Agent"，而是**通过消融实验（Ablation Study）定量证明上下文各组件对 Agent 性能的影响**。这个定位决定了它的很多设计选择。

### 文件职责划分

| 文件 | 职责 | 代码规模 |
|------|------|---------|
| `agent.py` | 核心 Agent 类 + 工具注册表 + 轨迹追踪 | ~967 行 |
| `config.py` | 环境变量加载 + Provider 解析委托 | ~219 行 |
| `main.py` | CLI 入口 + 交互模式 + 消融实验编排 + 可视化 | ~1229 行 |
| `run_experiment_1_1.py` | 规范实验运行器 + 证据持久化 + 合约验证 | ~464 行 |
| `agentbook/providers/` | 多 Provider 注册表 + OpenRouter 兜底 | 模块化 |

---

## 二、系统架构设计

系统采用三层架构：

```
┌─────────────────────────────────────────────────┐
│ 编排层：main.py / run_experiment_1_1.py        │
│   CLI 入口 · 消融实验编排 · 证据持久化 · 合约验证 │
├─────────────────────────────────────────────────┤
│ 核心层：agent.py                                │
│   ReAct 循环 · 工具注册表 · 轨迹追踪 · 消融裁剪  │
├─────────────────────────────────────────────────┤
│ 基础设施：config.py + agentbook/providers/      │
│   Provider 注册表 · OpenRouter 兜底 · 配置加载   │
└─────────────────────────────────────────────────┘
```

### 核心设计亮点

1. **ReAct 双终止条件**：文本回复（无 tool_calls）即终止，或 `max_iterations` 安全上限强制终止。代码注释明确指出，旧版本只认 `FINAL ANSWER:` 标记导致空转浪费 API 调用。
2. **`completed` vs `task_success` 刻意区分**：`completed` 表示"循环正常终止了"，`task_success` 为 `None` 表示"通用 Agent 无法判断答案是否正确"。只有实验运行器通过数值 rubric 才能判定 `task_success`。
3. **实验完整性验证**：`evaluate_context_contract()` 不信任 CLI flag，而是检查实际发出的 HTTP 请求（`trajectory.api_turns` 快照）验证消融确实生效。
4. **证据可审计**：每轮 LLM 调用的完整 request/response 被深拷贝快照保存（不含 API key），最终生成 `evidence.json` + SHA-256 校验。

---

## 三、消融实验机制（ContextMode）

5 种上下文模式，分别裁剪上下文的不同组件：

| 模式 | 裁剪了什么 | 实现方式 | 预期实验现象 |
|------|-----------|---------|-------------|
| `FULL` | 无（baseline） | 完整历史 + tools + results | 正确完成任务 |
| `NO_HISTORY` | 历史轨迹 | 每轮只发 system+user，丢弃所有 assistant/tool 消息 | 重复调用相同工具 |
| `NO_REASONING` | 推理过程 | 从 assistant 消息中移除 `reasoning_content` 字段 | 可能降低规划质量 |
| `NO_TOOL_CALLS` | 工具定义 | 不传 `tools` 和 `tool_choice` 字段 | 无法调用任何工具 |
| `NO_TOOL_RESULTS` | 工具结果 | tool message 内容替换为占位符 | 盲目重复调用 |

### 4 个消融拦截点的精确位置

| 拦截点 | 代码位置 | 拦截了什么 | 效果 |
|--------|---------|-----------|------|
| **NO_HISTORY** | `_prepare_messages_for_api()` | 每轮只发 `[system, user]` | 模型不知道之前调过什么工具，无限重复 |
| **NO_TOOL_CALLS** | `create_kwargs` 构建 | 不传 `tools` 和 `tool_choice` | 模型不知道有工具，用内部知识估算 |
| **NO_REASONING** | `_prepare_assistant_message()` | `pop('reasoning_content')` | 模型看不到之前的推理过程 |
| **NO_TOOL_RESULTS** | tool message 构建 | content 替换为占位符 | 工具照常执行，但模型看不到返回值 |

**设计精髓**：4 个拦截点都在"消息进入 conversation_history 之前"或"消息发送给模型之前"做裁剪，**不改变工具的实际执行逻辑**。无论哪种消融模式，Python 工具代码都会真正执行——被消融的只是"模型能看到什么"，不是"系统做了什么"。

---

## 四、消融实验结果分析

### 实验设计

5 种消融模式 × 3 个任务场景 = 15 组实验：

| 任务 | 复杂度 | baseline 正确答案 |
|------|--------|------------------|
| 💱 Currency Conversion | 简单（3 次汇率换算+求均值） | €920, £790, ¥149,500, avg=50,403.33 |
| 💰 Complex Financial Analysis | 中等（4 季度多币种收入汇总） | Total=$9,602,895.73 |
| 🌍 Multi-Currency Budget Planning | 复杂（5 项多币种预算+百分比+削减） | Total=$248,779.29 |

### 逐模式分析

#### 1. `no_history` — 影响等级：CRITICAL（灾难性）

| 指标 | Currency | Financial | Budget |
|------|----------|-----------|--------|
| 执行时间 | 94.18s | 119.04s | 141.37s |
| 迭代次数 | **10 (max)** | **10 (max)** | **10 (max)** |
| 工具调用 | **30** | **30** | **42** |
| 产出答案 | 无 | 无 | 无 |

**三个任务全部崩溃**。由于每轮都丢弃历史消息，Agent 看不到之前工具调用的结果，不断重复调用相同工具，直到撞上 `max_iterations=10` 强制终止。**历史轨迹是 Agent 正常运作的必要条件**。

#### 2. `no_reasoning` — 影响等级：minimal（几乎无影响）

| 指标 | Currency | Financial | Budget |
|------|----------|-----------|--------|
| 执行时间 | 26.36s | 33.8s | 50.12s |
| 迭代次数 | 3 | 3 | 3 |
| 工具调用 | 4 | 4 | 5 |
| 答案正确性 | ✓ 精确 | ✓ 精确 | ✓ 精确 |

**三个任务全部精确通过**。移除 `reasoning_content` 对性能几乎无影响——迭代次数、工具调用、答案数值都与 baseline 完全一致。

#### 3. `no_tool_calls` — 影响等级：HIGH（答案全部偏差）

模型完全不使用工具，直接用内部知识估算。三个任务都"完成"了（`success=true`），但**数值全部不精确**：

- Currency：¥150,000 vs 正确 ¥149,500；均值 50,570 vs 50,403.33
- Financial：Total ≈$9,587,333 vs 正确 $9,602,895.73（偏差 ~0.16%）
- Budget：Total ≈$245,407 vs 正确 $248,779.29（偏差 ~1.4%）

关键风险：**模型会给出看似合理的答案，但实际数值是错的**，答案中甚至附带了 "Exchange rates change constantly" 的免责声明。

#### 4. `no_tool_results` — 影响等级：MODERATE（任务复杂度相关）

Agent 仍然调用工具（4~5 次），但看不到返回结果：

- **简单任务（Currency）答对了**：模型用内部记忆的常见汇率（$1=€0.92, £0.79, ¥149.5）"猜"对了
- **复杂任务（Financial/Budget）答错了**：Financial 给出 $9,791,156（正确 $9,602,895.73，偏差 2%）；Budget 给出 $245,389（正确 $248,779.29，偏差 1.4%），模型幻觉了不同的汇率

### 关键发现

1. **`success` 字段具有误导性**：`success: true` ≠ 答案正确。`no_tool_calls` 和 `no_tool_results` 全部标记 `success: true`，但实际答案全部偏差。`task_success` 全部为 `null`，证实通用 Agent 无法自评正确性。

2. **上下文组件重要性排序**：
   ```
   历史轨迹 (CRITICAL) > 工具定义 (HIGH) > 工具结果 (MODERATE) > 推理过程 (minimal)
   ```

3. **任务复杂度与消融敏感性正相关**：复杂任务涉及更多币种和计算步骤，模型内部知识偏差会累积放大；简单任务模型靠记忆就能"蒙对"。

4. **`no_history` 的资源浪费**：平均工具调用 34 次（baseline 4.67 次，7.3 倍）；平均执行时间 118.2s（baseline 41.1s，2.9 倍）。全部以失败告终，是 API 成本浪费最严重的模式。

---

## 五、ReAct 循环与工具编排机制

### 工具三层解耦设计

| 层 | 载体 | 职责 | 可见性 |
|----|------|------|--------|
| 工具定义 | `_get_tools_description()` | OpenAI function calling schema | LLM 可见 |
| 工具实现 | `ToolRegistry`（4 个 @staticmethod） | 实际 Python 逻辑 | 仅 Python 可见 |
| 分发桥接 | `_execute_tool()` 的 `tool_map` | 名字字符串 → 方法查找 | 内部 |

耦合仅限工具名字符串与参数 JSON。schema 中的 `name` 必须与 `tool_map` 的 key 一致，这是唯一约定。

### ReAct 循环时序

```
execute_task(task)
  └─ append user task to conversation_history
  └─ while iteration < max_iterations:
       ├─ 1. _prepare_messages_for_api()   ← NO_HISTORY 拦截点
       ├─ 2. build create_kwargs           ← NO_TOOL_CALLS 拦截点（tools/tool_choice）
       ├─ 3. client.chat.completions.create(**create_kwargs)
       ├─ 4. snapshot req/resp → trajectory.api_turns
       ├─ 5. has_tool_calls?
       │     ├─ No  → 提取 FINAL ANSWER → break（终端路径）
       │     └─ Yes → for each tool_call:
       │             ├─ 解析 JSON 参数
       │             ├─ _prepare_assistant_msg   ← NO_REASONING 拦截点
       │             ├─ _execute_tool(name, args) → ToolRegistry 分发
       │             ├─ 构建 tool message         ← NO_TOOL_RESULTS 拦截点
       │             └─ append 到 history
       └─ loop back（history 已追加 assistant + tool 结果）
```

**关键机制**：

1. **`tool_choice: "auto"`**：工具选择完全由 LLM 自主决定，Agent 代码不做任何工具选择逻辑。
2. **`tool_call_id` 关联键**：tool message 必须带上 `tool_call_id` 与 assistant 消息中的 tool_call 配对，否则 API 报错。
3. **工具结果经 conversation history 回传**：这是 ReAct 核心——Reason（模型推理）→ Act（工具执行）→ Observe（结果入历史）→ Reason again。
4. **多 tool_call 并行**：一个 response 可能包含多个 tool_call，内层 for 循环逐个执行。

---

## 六、设计模式总结

| 模式 | 体现位置 | 评价 |
|------|---------|------|
| **ReAct** | `execute_task` 循环 | 标准实现，清晰易懂 |
| **Registry** | `agentbook/providers` | 优秀的单一数据源设计 |
| **Strategy** | `ContextMode` enum + `_prepare_messages_for_api` | 消融实验的核心机制 |
| **Trajectory/Observer** | `AgentTrajectory` | 证据持久化，可审计 |
| **Fallback** | OpenRouter 兜底链路 | 提高实验可复现性 |
| **Template Method** | `_get_tools_description` + `_execute_tool` | 工具定义与执行分离 |

---

## 七、值得改进的点

1. **`_build_context()` 是死代码**：注释明确说它不在请求路径上，`_prepare_messages_for_api` 才是真正生效的。保留可能造成混淆。
2. **`request_data` 和 `create_kwargs` 冗余**：两者字段大量重叠但略有不同（如 `timeout` 只在后者中），可以合并。
3. **汇率硬编码在两处**：`ToolRegistry.convert_currency` 和 `Config.EXCHANGE_RATES` 各有一份，不同步。
4. **`_reasoning_safe_temperature` 重复定义**：`agent.py` 和 `config.py` 各定义了一遍。
5. **`process()` 方法未被使用**：简化接口，但 `main.py` 全部使用 `execute_task()`，疑似遗留代码。

---

## 八、结论

这是一个**教学导向的 Agent 系统设计**，在以下方面表现出色：

- **实验设计严谨**：消融模式的实现精确到 request 级别验证，而非仅凭 flag
- **证据可审计**：api_turns 快照 + SHA-256 校验，满足学术复现要求
- **Provider 抽象成熟**：注册表 + 兜底链路，添加新 provider 零代码修改
- **语义边界清晰**：`completed`（循环终止）与 `task_success`（任务正确）刻意分离

实验数据清晰地揭示了上下文各组件对 Agent 决策的影响权重：**历史轨迹是生命线，工具定义决定能力边界，工具结果保障数值精度，推理过程在此类任务上可被替代**。它的定位不是生产系统，而是教读者理解"上下文对 Agent 决策的影响"这一核心概念的实验框架。从教学设计角度看，这是一个高质量的实现。
