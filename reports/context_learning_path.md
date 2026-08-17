# 从 0 学习并重建 chapter1/context 实验系统

> 面向目标：不是"读懂代码"，而是**能从零独立设计并实现一个可做消融实验的 ReAct Agent**。
> 配套代码：`chapter1/context/`（实验本体）+ `agentbook/providers/`（共享基础设施）。
> 本文是学习路径 + 设计实现方案，分为六部分，每部分都可独立实操。

---

## 第一部分：整体架构拆解

### 1.1 这个系统在解决什么问题

一句话：**用"逐组件剪除上下文"的对照实验，证明 Agent 的哪些上下文组件（历史、推理、工具定义、工具结果）对任务成败起关键作用——并且让结论可以被机器验证，而不是凭感觉讲故事。**

由此推出两条设计主线（整个架构都围绕它们展开）：

1. **可消融**：Agent 的每次模型请求，其上下文由哪几部分组成必须清晰可控，且每个部分都能单独"剪掉"。
2. **可审计**：每次请求实际发出去什么、模型回什么，必须被完整记录，事后能据此验证"剪掉的确实是那部分"。

### 1.2 核心功能模块（三层 + 证据链）

```
┌─ 编排层（实验流程）────────────────────────────────────┐
│ main.py                 CLI 入口：single / ablation / interactive │
│ run_experiment_1_1.py   严格五臂实验运行器（产出证据）              │
│ create_sample_pdf.py    生成测试用 PDF 夹具                       │
└────────────────────────────┬───────────────────────────┘
                             │ 调用 execute_task / 读取 result
┌─ 核心层（Agent 本体）──────▼───────────────────────────┐
│ agent.py   ContextMode / ToolRegistry / ContextAwareAgent │
│ config.py  Config 类 + provider 导入（双路径兜底）           │
└────────────────────────────┬───────────────────────────┘
                             │ from config import resolve_backend
┌─ 基础设施层（Provider 抽象）─▼───────────────────────────┐
│ agentbook/providers/  registry(数据) + resolution(策略)   │
│                       + openrouter(映射) + legacy(兼容)   │
└───────────────────────────────────────────────────────────┘
```

- **编排层**：管"实验怎么做"——跑哪几个模式、用什么任务、产出什么文件。
- **核心层**：管"Agent 怎么跑"——ReAct 循环、消融拦截点、工具执行。
- **基础设施层**：管"请求发给谁"——provider 元数据、凭据解析、模型 id 映射。

### 1.3 模块依赖关系

- **严格单向**：编排层 → 核心层 → 基础设施层 → OpenAI SDK。核心层绝不反向依赖编排层。
- 核心层通过 `config.py` 间接引用 providers（`from config import resolve_backend`），config 里做了 `try: from agentbook.providers ... except ImportError:` 的**双路径导入兜底**——即使 agentbook 没安装成包，也能把仓库根目录塞进 `sys.path` 继续跑。
- 新增 provider **只改注册表一处**（`registry.py` 的 `PROVIDERS`），CLI 的 `--provider`、`Config.get_api_key`、`resolve_backend` 全部自动生效——这就是"注册表模式"的收益。

### 1.4 数据流向（证据链）

```
规范任务 CANONICAL_TASK
  → ContextAwareAgent.execute_task()
      每轮真实 HTTP 请求/响应 → _json_snapshot 深拷贝 → trajectory.api_turns
  → result { final_answer, trajectory, iterations, completed, task_success: None }
  → summarize_arm() 展开为行为指标
  → evaluate_context_contract() 逐模式校验 api_turns 快照
  → analyze() 四重门控 → experiment_execution_accepted
  → evidence.json + evidence.sha256 + validation/latest.json
  → 退出码 0/1（机器可判定）
```

**一句话记忆**：`任务 → 执行 → 快照 → 汇总 → 验证 → 门控 → 证据`。中间任何一环都是"可审计"的。

---

## 第二部分：循序渐进学习路线（8 阶段）

> 每阶段都有**动手任务**和**验收标准**。建议每个阶段半天到一天，不要跳步。

### 阶段 0 · 地基概念（0.5 天）

**目标**：理解 ReAct 与 function calling，跑通"直连 LLM API"的最小示例。

| 项 | 内容 |
|---|---|
| 学习重点 | ① OpenAI SDK 的 `chat.completions.create` 消息格式（system/user/assistant/tool）；② function calling 协议（`tools` 参数 + `tool_choice` + 响应的 `tool_calls`）；③ ReAct 范式（Reason→Act→Observe 循环） |
| 动手任务 | 用任意一家 OpenAI 兼容 provider 写 20 行脚本：发一条 user 消息，打印完整响应 JSON |
| 验收标准 | 能说出一次 function-calling 请求/响应里每个字段的含义；能在 1 分钟内切换到第二家 provider |
| 参考文件 | `book/chapter1.md` 实验 1-1 正文；`tests/manual/` 下的冒烟脚本 |

### 阶段 1 · 最小 Agent v0（0.5 天）

**目标**：实现一个"无工具"的对话 Agent，理解消息历史管理。

| 项 | 内容 |
|---|---|
| 学习重点 | `conversation_history` 的累积方式；system prompt 设计（"FINAL ANSWER:" 标记的作用）；`reset()` 语义 |
| 动手任务 | 自己写 40 行：一个类，含 `conversation_history` 列表 + `execute_task`（单次调用 + 打印回复） |
| 验收标准 | 能解释为什么系统 prompt 要求"明确输出 FINAL ANSWER:"（答案提取锚点） |
| 参考文件 | `agent.py` 的 `_init_system_prompt` / `_extract_final_answer` |

### 阶段 2 · ReAct 循环骨架（1 天）

**目标**：实现带工具调用的循环，掌握**两个终止条件**。

| 项 | 内容 |
|---|---|
| 学习重点 | ① 消息回填协议：assistant 的 `tool_calls` 消息必须原样入历史，然后追加 `role:"tool"` 消息（`tool_call_id` 必须对应）；② 终止条件一：模型返回无 tool_calls 的文本 → 结束；③ 终止条件二：`max_iterations` 安全上限；④ `timeout` 处理 |
| 动手任务 | 自己写 80 行循环：调用 → 判 `has_tool_calls` → 执行 → 回填 → 再调用 |
| 验收标准 | 能解释"为什么终止条件一不能只认 FINAL ANSWER:"（普通聊天回复也会被无限重发） |
| 参考文件 | `agent.py` `execute_task`（L685–941）；`test_main_result_semantics.py`（completed 语义） |

### 阶段 3 · 工具注册表（1 天）

**目标**：实现工具的三层解耦，独立写出两个工具。

| 项 | 内容 |
|---|---|
| 学习重点 | ① schema 层（`_get_tools_description`，LLM 可见）；② 实现层（`ToolRegistry` 静态方法）；③ 分发桥（`_execute_tool` 的 `tool_map`）；④ 工具契约：try/except 返回 `{"error":...}` 而非抛异常 |
| 动手任务 | 独立实现 `convert_currency`（含货币符号归一化）和 `calculate`（eval 沙箱）；再给 ToolRegistry 加一个 `web_search` 工具（三个层次都要加） |
| 验收标准 | 能解释"符号按长度降序剥离"的原因；能说出 eval 沙箱为什么把 `__builtins__` 置空 |
| 参考文件 | `agent.py` L64–365；`test_agent.py`（字符串金额回归测试） |

### 阶段 4 · 消融机制（核心理解，1.5 天）★

**目标**：真正理解"消融 = 只改模型能看到什么，不改工具真实执行"。

| 项 | 内容 |
|---|---|
| 学习重点 | ① `ContextMode` 枚举 5 模式；② 四个拦截点的精确位置：`_prepare_messages_for_api`（NO_HISTORY）、`_prepare_assistant_message`（NO_REASONING）、请求组装时（NO_TOOL_CALLS：不传 `tools`/`tool_choice`）、结果回填时（NO_TOOL_RESULTS：占位符）；③ "滑动窗口也是历史"的实验纯度论证 |
| 动手任务 | 画出 5 种模式下"模型每轮看到的 messages 结构"对照表（从 api_turns 快照里截取真实数据） |
| 验收标准 | 不看代码能说出：NO_HISTORY 模式下每轮请求的 roles 恰为 `["system","user"]` |
| 参考文件 | `agent.py` L518–676；`test_experiment_1_1.py` |

### 阶段 5 · 轨迹与证据（1 天）

**目标**：实现轨迹记录与"契约验证"——本系统最有教学价值的思想。

| 项 | 内容 |
|---|---|
| 学习重点 | ① `AgentTrajectory`（reasoning_steps / tool_calls / api_turns / context_mode）；② `_json_snapshot` 深拷贝的意义（防证据被后续变更污染）；③ `evaluate_context_contract`：**验证真实请求而非 CLI flag**；④ NO_REASONING 的"双向验证"（provider 确实生成了 reasoning + 历史里已剥离）防假阳性 |
| 动手任务 | 写一个 `assert_mode_contract(mode, turns)`：对 5 种模式各断言 1–3 条请求形状不变量 |
| 验收标准 | 能解释"为什么契约验证必须看 api_turns 快照而不是看 CLI 传入的 mode" |
| 参考文件 | `run_experiment_1_1.py` L116–233 |

### 阶段 6 · Provider 抽象（1 天）

**目标**：实现注册表 + 解析优先级链，让"任意 provider 一行接入"。

| 项 | 内容 |
|---|---|
| 学习重点 | ① `Provider`/`Backend` dataclass 字段含义；② `resolve_backend` 四级优先级链；③ `map_model_to_openrouter` 的 `substitute_unknown` 双语义；④ `legacy.py` 兼容层的存在理由 |
| 动手任务 | 在 `PROVIDERS` 里新增一个 provider（如 `zhipu` 已存在，可自选一家），跑通 `resolve_backend("新名字")` |
| 验收标准 | 能画出优先级链并解释"顺序即行为"；能说出"重路由时未映射模型为何原样发送" |
| 参考文件 | `agentbook/providers/` 全部 5 个模块 |

### 阶段 7 · 实验运行器与测试（1.5 天）

**目标**：把前面所有能力组装成"可验收"的完整实验，产出证据产物。

| 项 | 内容 |
|---|---|
| 学习重点 | ① `analyze()` 四重门控（5 臂齐全 / 契约全过 / 直连真实 API / FULL baseline 正确）；② `completed` vs `task_success` 语义分离；③ `evidence.json` 内容（含 git commit、依赖版本、SHA-256）；④ 退出码即结论 |
| 动手任务 | 用便宜/免费 provider（见第三部分）跑通 `run_experiment_1_1.py`，解读自己的 `evidence.json`；再运行 `python -m pytest tests` 全绿 |
| 验收标准 | 能解释"为什么 FULL 臂答案错误时整个实验必须判失败"；能解读自己实验里的 `manuscript_behavior_claims` |
| 参考文件 | `run_experiment_1_1.py` L317–459；`validation/latest.json`（官方验收产物） |

---

## 第三部分：前置环境、依赖与配置

### 3.1 环境要求

- **Python 3.10+**（代码使用了 `str | None` 等 3.10 语法）
- 推荐 `uv`（项目根目录统一管理），或直接用 pip

### 3.2 安装依赖

```bash
# 方式 A（推荐）：仓库根目录统一环境
cd /Users/chenzhen/git/ai-agent-book
uv sync --locked --extra ch1
source .venv/bin/activate

# 方式 B：单目录兼容路径
cd chapter1/context
python -m pip install -r requirements.txt
```

`requirements.txt` 核心依赖（按用途分组理解）：

| 依赖 | 用途 | 能否替代 |
|---|---|---|
| `openai>=1.0` | LLM 调用（OpenAI 兼容协议） | 几乎所有国产 provider 都兼容 |
| `requests` | parse_pdf 下载远程 PDF | 标准库 urllib |
| `PyPDF2` | PDF 文本抽取 | pdfplumber/pymupdf（更强） |
| `reportlab` | 生成测试 PDF 夹具 | 任意 PDF 文件 |
| `numpy`/`matplotlib` | 消融结果可视化 | 可省（纯装饰） |
| `tabulate` | 控制台表格 | 可省（手动格式化） |
| `python-dotenv` | 加载 .env | 可省（export 环境变量） |
| `pytest` | 回归测试 | 必备 |

### 3.3 配置 .env

```bash
cd chapter1/context
cp env.example .env
```

至少填**一个** provider 的 key，优先级建议：

1. **零成本方案**：`OLLAMA` 本地模型（`--provider ollama`，无需任何 key）；或 `OPENROUTER_API_KEY` + `OPENROUTER_MODEL=某:free模型`。
2. **低成本方案**：`DEEPSEEK_API_KEY`（性价比高，`deepseek-v4-flash`）。
3. **常规方案**：`DASHSCOPE_API_KEY`（阿里百炼）、`SILICONFLOW_API_KEY`、`MOONSHOT_API_KEY`（Kimi）、`ARK_API_KEY`（豆包）。

```bash
# .env 关键项示例
LLM_PROVIDER=deepseek
DEEPSEEK_API_KEY=sk-xxx
# 兜底（可选）：主 key 缺失时自动走 OpenRouter
OPENROUTER_API_KEY=sk-or-xxx
```

### 3.4 验证环境

```bash
# 单元测试（不花 API 钱）
python -m pytest tests -q

# 冒烟测试（花一点点钱，推荐先做这一步）
python tests/manual/check_deepseek.py        # 或对应你配置的 provider

# 最小端到端
python main.py --mode single \
  --task "Convert $1000 USD to EUR, GBP, and JPY. Calculate the average." \
  --provider deepseek
```

---

## 第四部分：设计思路

### 4.1 技术选型理由

| 决策 | 理由 |
|---|---|
| **OpenAI SDK 而非各家原生 SDK** | 国产 provider（百炼/硅基流动/火山/月之暗面/DeepSeek）几乎全部提供 OpenAI 兼容 `/v1` 端点，一套客户端通吃全部 provider，Provider 抽象因此只需要"换 base_url + key + model id" |
| **eval/exec 沙箱做计算工具** | 教学场景的明确取舍：`calculate` 用 `eval(expr, {"__builtins__": {}}, math白名单)`；`code_interpreter` 用受限 builtins 的 `exec` + stdout 重定向。注释坦诚"生产不可接受，须容器化"。**取舍点写进代码比藏着更好** |
| **dataclass + Enum** | 零依赖即可表达领域模型（`ContextMode`/`ToolCall`/`AgentTrajectory`/`Backend`），frozen dataclass 天然不可变，符合"证据不可篡改"的意图 |
| **PyPDF2 + requests** | 轻量、够用；复杂版式失败的局限在 README 里明说 |
| **json 全链路** | 工具参数、工具结果、api_turns 快照、evidence 全部 JSON——可序列化即等于可审计 |

### 4.2 目录结构划分（为什么这样分）

```
chapter1/context/                 ← 实验本体（可独立运行，含双路径导入兜底）
├── agent.py                      ← Agent 核心 + 工具 + 消融（966 行，先读这个）
├── config.py                     ← 配置 + provider 导入桥（不存业务逻辑）
├── main.py                       ← CLI 编排（demo 级，含 AblationTestSuite）
├── run_experiment_1_1.py         ← 严格实验运行器（教学价值最高，先读这个）
├── create_sample_pdf.py          ← 夹具生成
├── fixtures/pdfs/                ← 测试资产
├── tests/ + test_*.py            ← 单元测试（conftest.py 做路径 bootstrap）
├── validation/                   ← evidence.json + sha256 + latest.json
└── env.example / requirements.txt

agentbook/providers/              ← 共享基础设施（所有章节复用，与实验解耦）
├── registry.py   数据（PROVIDERS 表 + 别名）
├── models.py     值类型（Provider/Backend dataclass）
├── resolution.py 策略（resolve_backend 优先级链）
├── openrouter.py 专用（模型 id 映射 + 常量）
└── legacy.py     兼容（旧 4-tuple 接口）
```

**划分原则**：凡"所有章节都要用"的能力（provider 解析）下沉到 `agentbook/providers`；凡"本实验独有"的逻辑（消融、契约验证）留在 `context/`。这样实验可以独立复制走，又不复制 provider 基础设施。

### 4.3 核心接口设计

```python
# Agent 门面（核心层）
ContextAwareAgent(api_key, context_mode=ContextMode.FULL,
                  provider="siliconflow", model=None, verbose=True)
result = agent.execute_task(task, max_iterations=None)
# result 契约：{final_answer, trajectory, iterations,
#              completed, task_success, success, provider, model, base_url}

# 工具（实现层，静态方法，失败返回 error dict）
ToolRegistry.convert_currency(amount, from_currency, to_currency) -> Dict
ToolRegistry.calculate(expression) -> Dict
ToolRegistry.code_interpreter(code) -> Dict
ToolRegistry.parse_pdf(url) -> Dict

# Provider 解析（基础设施层）
Backend = resolve_backend(provider, model=None, api_key=None)
# Backend: {api_key, base_url, model, provider, using_openrouter}

# 契约验证（编排层）
evaluate_context_contract(mode, turns) -> {passed: bool, ...}
```

**接口设计要点**：
- `execute_task` 的返回值是**自描述的**：`completed`（循环终止）与 `task_success`（答案正确）分开，前者 Agent 能判断，后者只能由有 rubric 的调用方判断 → 返回 `None` 也不撒谎。
- 工具层方法签名都是 `(输入) -> Dict`，把"结果 + 错误"统一在一个返回类型里，模型和代码都能处理。

### 4.4 核心数据结构

```python
class ContextMode(Enum):            # 消融变量：唯一的实验自变量
    FULL / NO_HISTORY / NO_REASONING / NO_TOOL_CALLS / NO_TOOL_RESULTS

@dataclass
class ToolCall:                     # 单次工具调用记录
    tool_name: str; arguments: Dict; result: Any; timestamp: str

@dataclass
class AgentTrajectory:              # 全量轨迹（可审计的核心）
    reasoning_steps: List[str]
    tool_calls: List[ToolCall]
    api_turns: List[Dict]           # 每轮真实请求/响应快照（深拷贝、脱敏）
    context_mode: ContextMode

@dataclass(frozen=True)
class Provider:                     # 注册表条目
    name; base_url; default_model; key_vars; requires_key; namespaces_models

@dataclass(frozen=True)
class Backend:                      # 解析结果
    api_key; base_url; model; provider; using_openrouter
    def __iter__(self): ...         # 兼容旧 4-tuple 解包
```

---

## 第五部分：关键模块实现逻辑与要点

> 这一部分讲"为什么这么写"，帮助理解而非照抄。

### 5.1 ReAct 循环的 5 个关键决策点（agent.py execute_task）

**决策 1：消息回填必须"原样 + 追加"**。模型的 `tool_calls` 消息要**原样**写回历史（模型后续推理需要看到自己发出的调用），然后**逐条追加**对应的 `role:"tool"` 结果消息（`tool_call_id` 必须匹配）。这是 function-calling 协议的死规矩，漏掉任何一条都会报错或丢失上下文。

**决策 2：终止条件"无 tool_calls 的文本回复"优先**。早期版本只认 `FINAL ANSWER:` 标记，导致模型回一句普通聊天（如 "hi"）也会被反复重发直到撞上 `max_iterations`——浪费 API 且结果荒谬。现在的语义：只要模型这轮没请求工具，说明它认为任务已完成（或无法继续），循环就终止。`FINAL ANSWER:` 只是**答案提取锚点**，不是终止条件。

**决策 3：坏 JSON 参数不炸循环**。模型偶尔会生成非法的工具参数 JSON。此时把错误信息本身作为 tool 结果写回对话（"Invalid tool arguments (not valid JSON): ..."），让模型看到错误后自行修正。配套测试 `test_malformed_tool_json.py` 用 `SimpleNamespace` 伪造响应锁定此行为——**Agent 系统必须对"模型会犯错"免疫**。

**决策 4：DeepSeek V4 特例注入 thinking**。消融实验需要 `reasoning_content` 才能做 NO_REASONING 剥离。DeepSeek V4 默认不输出推理，所以在非 OpenRouter 路由时注入 `extra_body={"thinking": {"type": "enabled"}}`。**这是"为实验变量补齐数据"的工程细节，不是可有可无的 hack**——没有它，no_reasoning 臂就无从剥离。

**决策 5：超时是安全的最后一层**。单轮 `timeout=180`；超时/异常路径返回 `completed=False, task_success=False` 并记录错误快照，而不是把异常抛出上层。实验运行器据此把该臂标记为失败，而不是让整个进程崩溃。

### 5.2 消融拦截点：为什么选这 4 个位置

核心原则：**消融只改"模型能看到什么"，工具真实执行逻辑完全不变**。这样观察到的行为差异 100% 归因于"缺了哪块上下文"，而不是"工具坏了"。

| 模式 | 拦截点 | 实现 | 模型看到的效果 |
|---|---|---|---|
| NO_HISTORY | 发送前（`_prepare_messages_for_api`） | 只留 `[system, 最后一条 user]` | 每轮从零开始 → 重复第一个动作 |
| NO_REASONING | assistant 消息写回前（`_prepare_assistant_message`） | `pop("reasoning_content")` | 看不到自己上轮的思考 |
| NO_TOOL_CALLS | 请求组装时 | 不传 `tools`/`tool_choice` | 不知道有工具可用 |
| NO_TOOL_RESULTS | tool 消息回填时 | content 替换为占位符 | 知道调用了工具但看不到结果 |

注意 NO_HISTORY 的"实验纯度"论证：**任何形式的滑动窗口都还是历史**（模型仍能看到最近的决策），会实质收窄实验结论，所以实现选择"字面意义上的每轮清空"。

### 5.3 契约验证：为什么验证请求快照而非 CLI flag

实验结论要成立，前提是"消融真的生效了"。如果只看 CLI 传入的 `--context-mode`，就无法发现实现 bug 或 provider 行为差异（比如某 provider 悄悄改了请求结构）。

所以 `evaluate_context_contract` 直接检查 `trajectory.api_turns` 里**每轮真实发出的请求**：
- `NO_HISTORY` → 每轮 messages roles 必须**恰好**是 `["system","user"]`；
- `NO_TOOL_CALLS` → 请求里 `"tools" not in r and "tool_choice" not in r`（精确到 key 存在性）；
- `NO_REASONING` → **双向验证**：响应的 `reasoning_content` 非空（证明 provider 真生成了推理）+ 历史 assistant 消息里无 `reasoning_content`（证明确实被剥离）——双向验证排除了"provider 本来就不给推理"的假阳性。

这套"验证请求而非 flag"的思想，是本系统对 AI 实验方法学最值得迁移的贡献。

### 5.4 解析优先级链：顺序即行为（resolution.py）

`resolve_backend` 的 4 步顺序是**整个行为本身**，交换任何两步都会静默改变请求端点：

```
1. gpt-5* 且非 openai provider 且有 OpenRouter key
   → 强制走 OpenRouter（直连 OpenAI 需要组织验证，读者大多没有）
2. 自身 key 存在（或 requires_key=False，如 ollama 用占位 key "not-needed"）
   → 直连 provider
3. OPENROUTER_API_KEY 存在 → 通用兜底，映射模型 id 后重路由
4. 否则 ValueError，列出所需环境变量 + 零成本提示
```

第 2 步里的细节：若 provider 是**聚合商**（`namespaces_models=True`，如 OpenRouter 本身），裸模型 id（如 `gpt-4o`）会被 `map_model_to_openrouter(..., substitute_unknown=True)` 映射——聚合商场景下"能用的默认"优于"必败的请求"。

第 3 步的细节：**凭据重路由时 `substitute_unknown=False`**，未映射的模型 id 原样发送给 OpenRouter 让它报错——"宁可见到错误，也不静默换成别家模型"。同一个映射函数在两种场景下策略相反，这就是 `substitute_unknown` 参数存在的意义。

### 5.5 工具契约：对模型错误免疫的设计哲学

- 每个工具 try/except 兜底，失败返回 `{"error": str}`——模型拿到 error 字典后可以自我纠正。
- `code_interpreter` 返回 `variables` 快照（非 callable 变量）供模型检查中间量，序列化用 `default=str` 兜底（set/dict views 等非 JSON 类型不会炸任务）。
- `convert_currency` 的符号归一化（`$`/`US$`/`S$`/`A$`/`C$` 等 → 标准码）和字符串金额清洗，是"为模型可能以任意格式书写输入"准备的鲁棒性。
- 未知工具名返回 `{"error": f"Unknown tool: {tool_name}"}` 而非抛异常。

### 5.6 核心循环伪代码（30 行理解全书）

```
def execute_task(task, max_iterations):
    history.append(user(task))
    for i in range(max_iterations):
        api_messages = prepare_messages_for_api(history, mode)   # 消融在此生效
        kwargs = {model, messages: api_messages,
                  tools: None if mode==NO_TOOL_CALLS else tool_schemas,
                  tool_choice: "auto", temperature: safe(model, 0.3)}
        resp = client.chat.completions.create(**kwargs)
        snapshot(api_turns, request, response)                    # 证据链
        msg = resp.choices[0].message
        if not msg.tool_calls:                                    # 终止条件 1
            history.append(strip_reasoning(msg, mode))            # NO_REASONING 在此
            return {final_answer: extract_final(msg.content), completed: True}
        history.append(strip_reasoning(msg, mode))
        for tc in msg.tool_calls:
            args = safe_json_loads(tc.function.arguments)         # 坏 JSON 容错
            result = execute_tool(tc.function.name, args)         # 分发桥
            history.append(tool(tc.id,
                content if mode!=NO_TOOL_RESULTS else "[Tool result hidden]"))
    return {completed: False}                                     # 终止条件 2
```

---

## 第六部分：实践练习与扩展方向

### 6.1 六个递进练习

**练习 1：加一个新工具 `web_search`（1 天）**
- 任务：贯穿三层——`_get_tools_description` 加 schema、`ToolRegistry` 加实现（可用 `requests` 打一个免费搜索 API 或 mock）、`_execute_tool` 的 `tool_map` 加分发。
- 要点：先写单元测试（含"失败返回 error dict"用例），再接入。
- 检验：`pytest` 新增用例全绿；交互模式下模型能调用它。

**练习 2：新增消融模式 `NO_SYSTEM_PROMPT`（0.5 天）**
- 任务：在 `ContextMode` 加枚举；在 `_prepare_messages_for_api` 里把 system 前缀也剪掉；给 `evaluate_context_contract` 加对应断言。
- 检验：契约验证器能断言"每轮请求无 system 角色"；思考这个模式的预期行为（无指令约束的模型会怎样）。

**练习 3：汇率换实时 API（0.5 天）**
- 任务：把 `ToolRegistry.convert_currency` 的硬编码汇率表换成 `exchangerate-api` 之类的免费接口；注意同时修掉 `config.py EXCHANGE_RATES` 的重复硬编码（顺带消除已知风险点）。
- 检验：新增网络失败时的缓存回退逻辑（测"API 挂了还能用上次汇率"）。

**练习 4：滑动窗口 vs 严格消融对照实验（1 天）**
- 任务：实现一个"窗口大小=2 步"的 `_prepare_messages_for_api` 变体，与严格 NO_HISTORY 各跑 5 次同一任务，对比重复动作率与成本。
- 要点：理解为什么 README/注释强调"滑动窗口仍是历史"——你会用数据亲身体会。
- 检验：写一段 markdown 记录两组实验的 `tool_action_count` 对比。

**练习 5：给 `code_interpreter` 加资源限制（1 天）**
- 任务：加超时（signal/threading）与输出大小上限；把结果截断信息返回给模型。
- 要点：这是把"教学沙箱"推向"生产安全"的第一步，也是面试高频题。
- 检验：写一个死循环代码用例，断言工具在 N 秒内返回 error。

**练习 6：多任务 × 多模式矩阵实验（1–2 天）**
- 任务：参照 `my_ablation.json`（3 任务 × 5 模式），扩展 `run_experiment_1_1.py` 支持多任务；对每个任务给出独立 rubric。
- 检验：跑出矩阵后，按"组件重要性排序"写 5 行结论，并与 `ablation_study_summary.md` 里的排序对照。

### 6.2 扩展方向（进阶）

1. **记忆系统**：把 `conversation_history` 换成"长期记忆（摘要）+ 短期记忆（窗口）"两层，观察对 no_history 消融的影响。
2. **多 Agent 协作**：把 `execute_task` 拆成"规划器 + 执行器"两个 Agent（规划器决定用哪个工具，执行器跑工具），对比单 Agent 在 no_reasoning 模式下的退化。
3. **流式输出**：`client.chat.completions.create(stream=True)` 支持逐 token 输出，注意 reasoning_content 在流式下的处理。
4. **评估体系**：把 `canonical_answer_correct` 泛化为"rubric 注册表"（每个任务一个判定函数），接入 `analyze` 门控。
5. **生产化**：把 eval/exec 工具迁到子进程/容器；加限流与重试；把汇率与密钥外部化——对照 README 的 Limitations 逐条消掉。

### 6.3 学习成果自测清单（全部答"是"即通关）

- [ ] 我能画出三层架构图与证据链，说出每层职责
- [ ] 我能不看代码写出 30 行 ReAct 循环伪代码，含双终止条件
- [ ] 我能说出 4 个消融拦截点的精确位置与"只改模型所见"原则
- [ ] 我能解释契约验证为什么看 `api_turns` 快照而非 CLI flag
- [ ] 我能画出 `resolve_backend` 优先级链并解释 `substitute_unknown` 双语义
- [ ] 我能解释 `completed` ≠ `task_success` 的设计动机
- [ ] 我独立实现过至少 1 个新工具并跑通全链路
- [ ] 我能独立解读一份 `evidence.json`（含 `manuscript_behavior_claims`）

---

*学习建议：阶段 0–3 用"最小实现"打底（自己写，再对照源码），阶段 4–7 用"改造扩展"深化（在源码上改，跑真实实验）。每阶段结束时做一次自测清单，再进入下一阶段。*
