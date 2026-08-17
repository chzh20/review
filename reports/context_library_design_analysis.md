# chapter1/context 实验系统：库函数实现与整体设计分析

> 分析对象：`chapter1/context/`（实验运行器 + Agent 核心 + 配置）与 `agentbook/providers/`（共享 Provider 基础设施）
> 本文基于对全部源码的实际阅读，引用具体函数名与代码行作为依据。

---

## 一、重要库函数实现细节

系统按职责分为四个层次，逐层分析核心函数。

### 1. 工具层：`ToolRegistry`（agent.py L64–365）

四个 `@staticmethod` 工具，全部采用 **"try/except 包裹、失败返回 `{"error": ...}` 而非抛异常"** 的契约——模型拿到 error 字典后可以自我纠正，不会中断 ReAct 循环。

#### 1.1 `convert_currency(amount, from_currency, to_currency)` —— 货币转换

- **功能**：将金额从一种货币转换为另一种，以 USD 为锚。
- **关键算法**：
  1. **字符串金额清洗**（L144–159）：若 `amount` 是字符串，先去逗号，再按长度降序依次剥离货币符号（`"USD$"` > `"U.S.$"` > `"US$"` > `"$"`，`S$`/`A$`/`C$` 同理）。**按长度降序排序是为了避免短符号提前吃掉长符号的子串**（如 `"US$"` 若先被 `"$"` 替换会残留 `"US"`）。
  2. **货币代码归一化 `_normalize_code`**（L175–209）：先查符号映射表（`"$"→USD`、`"S$"→SGD`、`"A$"→AUD`、`"C$"→CAD`、`"€"→EUR`、`"£"→GBP`、`"₹"→INR`）；未命中再对 `X$` 形式做前缀推断（`"CA"`/`"C"`→CAD、`"AU"`/`"A"`→AUD）。这样 LLM 传 `"US$"`、`"S$"` 或 `"USD"` 都能被正确解析——**这是为"模型可能以任意格式书写货币"设计的鲁棒性**。
  3. **汇率换算**（L219–221）：`usd_amount = amount / rates[from]` 然后 `converted = usd_amount * rates[to]`，即**以 USD 为中间锚的双步换算**，避免为每对货币维护交叉汇率。
- **数据结构**：硬编码 10 种货币汇率字典（L162–173）。注意：`Config.EXCHANGE_RATES`（config.py L96–107）是**同一份表的重复硬编码**，两处不同步是已知风险。
- **输入输出**：输入 `(float|str, str, str)`；输出 `{original_amount, from_currency, to_currency, converted_amount, exchange_rate, timestamp}` 或 `{"error": str}`。

#### 1.2 `calculate(expression)` —— 数学表达式求值

- **功能**：对字符串表达式求值。
- **关键算法（沙箱）**（L253–263）：
  - 白名单：`math.__dict__` 中所有非 `__` 开头的名字 + `abs/round/min/max`；
  - `eval(expression, {"__builtins__": {}}, allowed_names)`：**globals 里显式禁用全部 builtins**，仅允许 math 模块与少数内建函数；
  - `expression.replace("^", "**")`：把用户/模型习惯的幂符号归一为 Python 幂运算符。
- **安全评估**：相比裸 `eval` 已大幅收敛，但 `eval` 本身 + `math` 模块仍存在理论风险（如 `math` 下无危险函数，白名单足够干净）。这是"教学实验可接受、生产不可接受"的典型。
- **输入输出**：输入 `str`；输出 `{expression, result, type}` 或 `{"error": str}`。

#### 1.3 `code_interpreter(code)` —— Python 代码执行

- **功能**：执行模型生成的 Python 代码，用于多步聚合计算（对实验任务中的"四个季度求和"至关重要）。
- **关键算法**：
  1. **受限 builtins 命名空间**（L290–317）：显式列出 22 个安全内建（`abs/sum/len/list/dict/...`），**不包含 `open`、`__import__`、`eval`、`exec`**，并挂载 `math` 模块；
  2. **stdout 捕获**（L323–333）：`io.StringIO` + `contextlib.redirect_stdout` 包裹 `exec`，把 `print` 输出收进缓冲区；
  3. **结果提取**（L335–343）：先取命名空间中的 `result` 变量，未命中再按 `['total', 'sum', 'output', 'answer', 'final']` 顺序探测常用变量名——**为"模型不一定叫 result"做了宽容**；
  4. **变量快照**（L345–349）：返回所有非内置、非 callable 的变量，供模型检查中间量。
- **输入输出**：输入 `str`；输出 `{code, result, output, variables, success}` 或 `{code, error, success: False}`。

#### 1.4 `parse_pdf(url)` —— 多来源 PDF 解析

- **功能**：从 `file://`、本地路径（绝对/相对/Windows 盘符）或 HTTP(S) URL 读取 PDF 并抽取文本。
- **关键逻辑**（L78–102）：按前缀/首字符分诊三类来源：`file://` 剥前缀；`/`、`./`、`../` 或盘符视为本地路径；否则 `requests.get(url, timeout=30)` 下载。全部统一为 bytes 后交给 `PyPDF2.PdfReader`。
- **数据结构**：输出 `{url, num_pages, content: [{page, text}], metadata}`——**按页组织的列表结构**，方便模型逐页阅读财报。
- **协同**：`create_sample_pdf.py` 用 reportlab 生成 `fixtures/pdfs/` 下的两个测试 PDF，供本工具与离线测试使用。

### 2. 核心层：`ContextAwareAgent`（agent.py L368–966）

#### 2.1 `__init__` —— 后端解析与客户端构造

- 调用 `resolve_backend(provider, model, api_key)`（见 4.1）拿到 `Backend`（frozen dataclass），解出 `api_key/base_url/model/using_openrouter` 四个字段，再构造 OpenAI 客户端。
- **关键设计**：`using_openrouter` 标志被记在 agent 上并在每轮 api_turns 快照中保留——实验运行器靠它判断"是否直连了真实 provider"（`direct_real_api` 校验）。

#### 2.2 `execute_task(task, max_iterations)` —— ReAct 主循环（本书核心）

- **流程**：`while iteration < max_iterations`（L731）：
  1. `_prepare_messages_for_api()` 构造本轮实际发送的消息（消融在此生效，见 2.3）；
  2. 组装 `request_data`（日志用）与 `create_kwargs`（真正请求用）：除 `NO_TOOL_CALLS` 外都带 `tools` + `tool_choice="auto"`；`temperature` 经 `_reasoning_safe_temperature(model, 0.3)` 处理；`timeout=180`；
  3. **DeepSeek V4 特例**（L766–768）：`provider == "deepseek"` 且未走 OpenRouter 时注入 `extra_body={"thinking": {"type": "enabled"}}`，**保证 reasoning_content 存在**——否则 NO_REASONING 消融臂就没有可剥离的东西（与其他默认开 thinking 的 provider 对齐）；
  4. `client.chat.completions.create(**create_kwargs)`，响应经 `model_dump()/dict()` 双兼容转为 dict，**`_json_snapshot()` 深拷贝后存入 `trajectory.api_turns`**（L780–788，证据链起点）；
  5. 分支判断（L805）：
     - **终止路径**：`not has_tool_calls` 且文本非空 → 提取 `FINAL ANSWER:` 后的内容（`_extract_final_answer`），`break`。**注意：纯聊天回复（如 "hi"）也会终止循环**——这是刻意的语义修正，避免"没有 FINAL ANSWER 标记就无限重发浪费 API"；
     - **继续路径**：有 `tool_calls` → 逐个 `json.loads` 参数 → `_execute_tool` 执行 → 结果按 `NO_TOOL_RESULTS` 决定原样写入还是替换为占位符 → 追加 `role: "tool"` 消息 → 循环。
- **坏 JSON 参数容错**（L829–848）：`json.JSONDecodeError` 时不抛异常，而是把错误信息本身作为 tool 结果写回对话，**让模型看到"参数非法"并自行修正**——`test_malformed_tool_json.py` 专门锁定此行为。
- **双终止条件**：① 无 tool_calls 的文本回复（正常完成）；② 达到 `max_iterations`（安全上限，防 NO_TOOL_RESULTS 等模式下的死循环）。
- **结果语义（重要）**（L704–713, L927–941）：
  - `completed` = 循环收到非空终止文本（**不等于答案正确**）；
  - `task_success` = `None` —— **通用 Agent 无法从任意自然语言任务推断对错**，正确性判定下放到有 rubric 的实验运行器（`canonical_answer_correct`）；
  - `success` = `completed` 的向后兼容别名。
  - 这个语义分离是本项目最值得称道的设计决策之一。

#### 2.3 `_prepare_messages_for_api()` —— NO_HISTORY 消融的落点

- **功能**：构造"实际发给模型"的消息列表。
- **逻辑**（L662–676）：非 `NO_HISTORY` 模式直接返回完整 `conversation_history`；`NO_HISTORY` 模式下：保留所有 `system` 消息作为静态前缀，再锚定**最后一条 `user` 消息**追加——**之前轮次的任何 assistant 决策、tool_call、tool_result 全部丢弃**。
- **注释明确**（L653–657）：这是"字面意义上的实验 1-1 消融"——模型每轮都从零开始，因此倾向于反复发出相同动作；**"单步滑动窗口"仍算历史，会实质收窄实验**。测试 `test_experiment_1_1.py` 专门断言 `no_history` 拒绝 sliding window。

#### 2.4 `_prepare_assistant_message(message)` —— NO_REASONING 消融的落点

- 把响应对象转 dict（`dict()` / `model_dump()` 双兼容），若处于 `NO_REASONING` 模式则 `pop("reasoning_content")`（L532–533）。
- 配套静态方法 `_reasoning_content(message)`（L537–547）**以 SDK 无关的方式**取推理文本：先试属性 `reasoning_content`，再查 `model_extra` 里的 `reasoning_content`/`reasoning`（兼容不同 provider 的形状差异）。

#### 2.5 `_execute_tool(tool_name, arguments)` —— 分发桥

- **工具三层解耦**：
  1. `_get_tools_description()`（L437–516）：生成 OpenAI function-calling schema（**LLM 可见的声明层**）；
  2. `_execute_tool` 的 `tool_map`（L632–637）：名字→方法引用字典（**分发桥接层**）；
  3. `ToolRegistry` 静态方法（**Python 实现层**）。
- 未知工具返回 `{"error": f"Unknown tool: {tool_name}"}`，不抛异常。

#### 2.6 `_json_snapshot(value)` —— 证据快照

- `json.loads(json.dumps(value, ensure_ascii=False, default=str))`：**深拷贝 + 脱敏**（default=str 兜底非 JSON 类型，如 set/生成器），把 API 证据对象从后续内存变更中"分离"出来——保证 api_turns 里记录的是请求发出时的真实快照。
- **脱敏**：`run_experiment_1_1.py` 中 `credential_value_recorded: False`，证据文件不含任何密钥。

#### 2.7 其他值得注意的成员

- `_build_context()`（L554–585）：**死代码**——注释明确"不在请求路径上"，请求路径是 `_prepare_messages_for_api`；保留仅用于调试。
- `process()`（L949–966）：遗留简化接口，未被 `main.py` 使用。

### 3. 实验运行器：`run_experiment_1_1.py`（463 行，本书最有教学价值的文件）

#### 3.1 `evaluate_context_contract(mode, turns)` —— 契约验证器

- **思想**：**验证实际发出的 HTTP 请求，而非信任 CLI flag**。`turns` 来自 `trajectory.api_turns`（真实请求/响应快照）。
- **逐模式断言**（L126–227）：
  - `FULL`：`tools_present_every_turn`（每轮都带 tools）+ `history_present_after_first_turn`（第 2 轮起 messages 含 assistant+tool）+ `reasoning_retained_after_first_turn`；
  - `NO_TOOL_CALLS`：`tools_absent_every_turn`（请求里**既无 `tools` 也无 `tool_choice`**，`"tools" not in r` 精确到 key 存在性）；
  - `NO_TOOL_RESULTS`：`tool_calls_retained`（assistant 的 tool_calls 仍在）+ `tool_results_hidden`（所有 tool 消息 content 恰为占位符）；
  - `NO_REASONING`：`provider_generated_reasoning`（响应里确实有 reasoning——**证明 provider 真生成了**）+ `reasoning_removed_from_history`（历史里已剥离）——这个"双向验证"是最精妙的设计，防止"provider 本来就没给推理"造成的假阳性；
  - `NO_HISTORY`：`only_static_prefix_and_user_every_turn`（每轮角色序列**恰为** `["system", "user"]`）+ `tools_still_present`。
- **输出**：`{has_provider_response_ids, turn_count, request_roles, ...各模式专属指标, required_checks, passed}`；`passed = all(required)`。

#### 3.2 `canonical_answer_correct(final_answer)` —— 数值 rubric

- `normalized_number_text` 去掉逗号/`$`/空格后，检查 `EXPECTED_NUMBERS = ("9602895.73", "2400723.93")` 是否都出现在最终答案中。
- **设计意图**（docstring L240–246）：**刻意放在 Agent 类之外**——"通用 Agent 无法推断正确性，而本实验有显式答案 rubric"，所以正确性判定属于实验运行器而非 Agent。

#### 3.3 `summarize_arm(mode, result, elapsed)` —— 单臂汇总

- 把 trajectory 展开为可 JSON 序列化的证据：`tool_calls`（含时间戳）、`call_signatures`（`工具名:规范化参数JSON`）、`repeated_tool_calls`（签名总数 - 去重数，**重复动作检测**）、`reasoning_steps`、`api_turns`。
- 计算 `completed`（兼容 `success` 别名）与 `task_success`（走 rubric）。
- `behavior` 字典（L282–287）：`tool_action_count` / `has_repeated_tool_action` / `hit_iteration_ceiling` / `canonical_answer_correct` —— **消融的因果观察指标**。

#### 3.4 `analyze(arms)` —— 全局门控

- 四重校验（L317–363）：
  1. `exact_five_arms_present`：5 臂齐全；
  2. `all_context_contracts_passed`：每臂契约验证通过；
  3. `direct_real_api`：**未走 OpenRouter 兜底**且每轮响应都有真实 `id`（排除 mock/转发）；
  4. `full_baseline_correct`：FULL 臂答案必须正确（**baseline 本身错了则整个实验无效**）。
- `behavior` 再汇总四条"书稿主张"（`without_tool_definitions_no_tool_action`、`without_tool_results_repeated_action`、`without_history_repeated_action`、`without_reasoning_degraded`）。
- **`experiment_execution_accepted` 是退出码依据**（L459：`0 if accepted else 1`），把"实验是否可信"变成机器可判定的布尔值。

#### 3.5 `main()` —— 证据产物

- 逐模式串行执行 → `evidence.json`（含 schema_version、命令、`credential_source_env` 而非密钥值、host/python/deps、**git commit/branch/worktree_dirty**、全部 arms + analysis）→ **SHA-256 摘要**写入 `evidence.sha256` → 复制到 `validation/latest.json`。
- **可复现性**：证据记录了仓库 commit 与依赖版本，配合 sha256，任何人都能核对实验确凿性。

### 4. Provider 基础设施：`agentbook/providers/`（5 模块）

#### 4.1 `resolve_backend(provider, model, api_key)` —— 解析策略（resolution.py L113–191）

四级优先级链（**顺序即行为**，docstring 明言"交换两步会静默改变端点"）：
1. **gpt-5 强制 OpenRouter**（L166–167）：`_needs_openrouter_for_gpt5` 判定 `gpt-5*` 且非 `openai` provider 且有关键 → 直接走 OpenRouter，**避开 OpenAI 组织验证**（读者大多没有）；
2. **自身凭据**（L170–184）：有 key 或 `requires_key=False`（ollama 用占位 key `"not-needed"`）→ 直连；若 provider 是聚合商（`namespaces_models`），裸模型 id 会被 `map_model_to_openrouter(..., substitute_unknown=True)` 映射（聚合商场景下"能用的默认"优于"必败的请求"）；
3. **OpenRouter 通用兜底**（L187–188）：有 `OPENROUTER_API_KEY` 则 `build_openrouter_backend` 重路由（此处 `substitute_unknown=False`——**重路由时未映射 id 原样发送，让读者在报错里看到自己选的模型不可用，而不是被静默换成别的厂商模型**）；
4. **报错**（L191）：`ValueError` 列出所需环境变量 + `ZERO_COST_HINT`（提示 ollama 免费 / `:free` 模型）。

#### 4.2 `map_model_to_openrouter(model, substitute_unknown)`（openrouter.py L81–132）

- 映射规则（顺序敏感）：含 `/` 原样返回 → `gpt-*/o1-*/o3-*/o4-*`→`openai/<id>` → `claude-*`（按 sonnet/haiku/其他映射到固定版本）→ `kimi-*`→`moonshotai/kimi-k2.6`（**kimi-k3 不被 OpenRouter 托管，注释明示**）→ `deepseek-*`→`deepseek/<id>` → `qwen*`→`qwen/<id>`。
- **`substitute_unknown` 的双语义**是模块级的精妙权衡：直连聚合商时"替换为默认"（保证可用）；凭据重路由时"原样保留"（保证诚实）。
- `is_openrouter_key()`（`sk-or-` 前缀）**故意不被 resolve_backend 使用**——文档解释了原因：在 `api_key` 参数语义是"本 provider 凭据"的地方按值推断路由，会在前缀冲突时把凭据发错主机。

#### 4.3 值类型（models.py）

- `Provider`（frozen dataclass）：`name/base_url/default_model/key_vars/base_url_var/requires_key/namespaces_models`；`api_key()` 按序取首个非空环境变量；`resolved_base_url()` 支持环境变量覆盖。
- `Backend`（frozen dataclass）：`api_key/base_url/model/provider/using_openrouter`；**`__iter__` 兼容旧 4-tuple 解包**，让未迁移调用点无感升级。

#### 4.4 `lookup` / `canonical_provider`（registry.py）

- `PROVIDERS`：9 个 provider 条目的**单一数据源**；`_ALIASES` 归一化别名（moonshot→kimi、ark→doubao、google→gemini、qwen/bailian→dashscope）。
- **新增 provider 只改注册表一处**，`--provider` CLI 选项、`Config.get_api_key`、`resolve_backend` 全部自动可用——注册表模式的收益。

#### 4.5 `legacy.resolve_llm_backend`（legacy.py）

- 返回旧 4-tuple 的**兼容 shim**，内部复用 `build_openrouter_backend` 防止与 `resolve_backend` 漂移；未迁移的章节模块仍 import 它，删除会破坏其他章节。

---

## 二、项目整体架构与设计

### 2.1 目录结构与模块划分

```
chapter1/context/
├── agent.py                  # 966 行：ContextMode 枚举 / ToolRegistry / ContextAwareAgent
├── config.py                 # 218 行：Config 类 + providers 导入（双路径兜底）
├── main.py                   # 1228 行：AblationTestSuite / CLI 交互 / 可视化
├── run_experiment_1_1.py     # 463 行：严格五臂实验运行器（证据产物）
├── create_sample_pdf.py      # 274 行：reportlab 生成测试 PDF
├── fixtures/pdfs/            # 测试 PDF 资产
├── tests/                    # 单元测试（含 conftest.py 路径 bootstrap、manual/ 冒烟脚本）
├── test_agent.py / test_experiment_1_1.py / test_main_result_semantics.py / test_malformed_tool_json.py
├── validation/               # evidence.json + evidence.sha256 + latest.json
├── task_result_full.json     # 单次任务结果示例
└── env.example / requirements.txt

agentbook/providers/          # 共享基础设施（所有章节复用）
├── __init__.py / models.py / registry.py / resolution.py / openrouter.py / legacy.py
```

### 2.2 三层分层与严格单向依赖

```
┌─ 编排层 ──────────────────────────────────────────────┐
│  main.py · run_experiment_1_1.py · create_sample_pdf.py │
│  （实验流程、CLI、证据产物、PDF 夹具）                    │
└──────────────────────┬────────────────────────────────┘
                       │ 调用
┌─ 核心层 ─────────────▼────────────────────────────────┐
│  agent.py · config.py                                  │
│  （ReAct 循环、消融拦截点、工具注册表、配置）              │
└──────────────────────┬────────────────────────────────┘
                       │ import + resolve_backend
┌─ 基础设施层 ──────────▼────────────────────────────────┐
│  agentbook/providers/（注册表 + 解析策略 + 模型映射）      │
│  agentbook/providers.py  ←── 第三方 OpenAI SDK          │
└────────────────────────────────────────────────────────┘
```

依赖严格单向：编排层→核心层→基础设施层→SDK。**核心层不反向依赖编排层**；基础设施层被 agent.py 以 `from config import resolve_backend` 间接引用（config 做双路径导入兜底，保证未安装 agentbook 的裸仓库也能跑）。

### 2.3 数据流向（完整证据链）

```
task (CANONICAL_TASK)
  → ContextAwareAgent.execute_task()
      → 每轮真实 HTTP 请求/响应 → _json_snapshot 深拷贝 → trajectory.api_turns
  → result {final_answer, trajectory, iterations, completed, task_success=None}
  → run_experiment_1_1.summarize_arm()
      → behavior 指标 + evaluate_context_contract(校验 api_turns 快照)
  → analyze() 四重门控 → experiment_execution_accepted
  → evidence.json + evidence.sha256 + validation/latest.json
  → 退出码 0/1
```

**关键点**：契约验证基于 `api_turns`（真实请求快照）而非 CLI flag——"验证请求而非 flag"是全书实验方法学的核心思想。

### 2.4 设计模式运用

| 模式 | 落点 | 说明 |
|---|---|---|
| **注册表模式** | `registry.py` PROVIDERS / `_ALIASES` | provider 元数据单一数据源，新增 provider 零代码扩散 |
| **策略模式** | `resolution.py resolve_backend` | 解析规则与数据分离（"rules own data"）；`map_model_to_openrouter` 的 `substitute_unknown` 是参数化策略 |
| **观察者/轨迹模式** | `AgentTrajectory` + `api_turns` | 运行时全量记录请求/响应/工具调用，供事后审计（契约验证的素材） |
| **模板方法** | `execute_task` 主循环 | ReAct 循环骨架固定，消融以拦截点钩子方式插入（`_prepare_messages_for_api` / `_prepare_assistant_message` / tools 注入条件） |
| **兼容适配器** | `legacy.py`、`Backend.__iter__`、`success` 别名 | 新旧接口平滑过渡 |
| **门控模式（Gate）** | `analyze()` 四重校验 | 证据不完整则实验整体判失败 |

### 2.5 设计亮点

1. **证据链闭环**：从"请求快照"→"契约验证"→"门控判定"→"sha256 固化"，实验可审计、可复现、可机器判定（退出码即结论）。
2. **语义分离**：`completed`（循环终止）≠ `task_success`（答案正确），正确性判定权下放给有 rubric 的运行器。
3. **消融只改"模型能看到什么"**：工具真实执行逻辑不变，4 个拦截点全部在消息组装处，实验变量纯净。
4. **NO_REASONING 的双向验证**：既验证 provider 生成了推理，又验证历史里剥除了推理——排除"本来就没推理"的假阳性。
5. **诚实重路由**：凭据兜底时未映射模型原样发送，宁可见错误也不静默换模型。
6. **鲁棒工具契约**：所有工具 try/except 返回 error dict、坏 JSON 参数不炸循环、`default=str` 序列化兜底，全链路对"模型会犯错"免疫。
7. **SDK 形状双兼容**：`model_dump()`/`dict()`、`dict()`/`model_extra` 多处兼容不同 SDK 版本。

### 2.6 不足与可改进点

| 问题 | 位置 | 影响 |
|---|---|---|
| 汇率表重复硬编码 | `config.py EXCHANGE_RATES` vs `ToolRegistry.convert_currency` | 两处不同步风险（改一处忘一处） |
| `_reasoning_safe_temperature` 重复定义 | config.py 与 agent.py 各一份 | DRY 违反；应统一 import |
| `_build_context()` 死代码 | agent.py L554 | 误导读者（看似请求路径） |
| `request_data` / `create_kwargs` 冗余 | execute_task 内 | 两套几乎相同的 dict，`verbose=False` 时 request_data 纯浪费 |
| `temperature=0.3` 硬编码 | agent.py L745/L762 | 未与 `Config.MODEL_TEMPERATURE` 打通 |
| `process()` 遗留接口 | agent.py L949 | 未使用，增加认知负担 |
| `token_usage` 汇总无分摊 | run_experiment_1_1.py L291 | 仅报告总量，未按臂/轮次分布 |
| 汇率/币种白名单不可配置 | ToolRegistry | 教学场景可接受，生产需外部数据源 |

---

## 三、补充说明

### 3.1 设计权衡

- **`legacy.py` 为何不能删**：`chapter1/context/config.py` 及未迁移章节仍 import `resolve_llm_backend`，删除即破坏兼容——保留 shim 并让内部复用 `build_openrouter_backend`，是"不漂移"的妥协方案。
- **OpenRouter 兜底 vs 静默换模型**：作者在两个场景给了相反策略（聚合商直连→替换；凭据重路由→保留），取舍标准是"调用者的意图是否指向具体模型"。
- **`task_success=None` 的哲学**：宁可让下游"不知道对错"，也不让通用 Agent 谎报正确——正确性只属于有 rubric 的判定者。

### 3.2 性能与成本考量

- `NO_HISTORY` 臂模型每轮从零开始，实测 34 次平均工具调用、严重重复动作（`has_repeated_tool_action`）——这是**消融的预期现象**，但也意味着该臂 API 成本最高；`max_iterations` 默认 5 是成本/效果的平衡点。
- `timeout=180` 单轮 + 5 臂串行，全实验可能耗时数分钟；`main.py` 的 `--max-iterations` 下限 2 防止空跑。

### 3.3 安全

- `.env` 已被 `.gitignore` 的 `.*` 规则排除，未被 git 跟踪；
- `evidence.json` 记录 `credential_source_env`（环境变量名）而非密钥值，`credential_value_recorded: False`；
- `code_interpreter` 的 builtins 白名单排除 `open/__import__/eval/exec`，但 `exec` 沙箱在 Python 中并非绝对安全——教学用途可接受，生产须容器化。

### 3.4 一句话总结

> 这套系统把"上下文消融"做成了一条**可审计的证据流水线**：Agent 负责执行并留下原始快照，运行器负责验证快照与判定正确性，Provider 层负责把"任意 provider 可用"收敛成一行注册。实验结论因此是机器可验证的，而非叙事性的。
