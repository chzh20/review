# 一个月 Python 工程实践课程：从工程级库到 LLM 源码阅读

这套课程不是“重新学一遍 Python 语法”，而是利用你已有的调试、代码评审和系统设计能力，快速建立 **Python 工程心智模型**，最后能够：

1. 设计、实现、测试和发布一个结构清晰的 Python 库。
2. 理解 Python 项目中的动态机制、类型系统、抽象边界和运行时行为。
3. 沿实际调用链阅读 PyTorch、Transformers 和 vLLM 源码。
4. 对 tokenizer、Transformer forward、attention、batching、KV cache 建立可运行、可验证的理解。

建议每天投入 **1.5～2.5 小时**：

* 30～45 分钟：阅读与概念。
* 60～90 分钟：编码。
* 15～30 分钟：测试、复盘、记录源码调用链。

***

# 贯穿项目：`mini-infer`

整个课程围绕一个逐步演进的 Python 库展开：

> **mini-infer：一个可扩展的迷你 LLM 推理流水线框架。**

它不追求训练大模型，而是用较小的实现覆盖真实推理系统的关键抽象：

```text
文本
  ↓
Tokenizer
  ↓
TokenBatch / Padding
  ↓
Model.forward()
  ↓
KV Cache
  ↓
Sampler
  ↓
Decode
  ↓
输出文本
```

最终工程结构：

```text
mini-infer/
├── pyproject.toml
├── README.md
├── LICENSE
├── src/
│   └── mini_infer/
│       ├── __init__.py
│       ├── config.py
│       ├── exceptions.py
│       ├── logging.py
│       ├── protocols.py
│       ├── tokenizer/
│       │   ├── base.py
│       │   ├── whitespace.py
│       │   └── adapter.py
│       ├── model/
│       │   ├── attention.py
│       │   ├── transformer.py
│       │   └── cache.py
│       ├── engine/
│       │   ├── request.py
│       │   ├── scheduler.py
│       │   └── engine.py
│       ├── sampling/
│       │   ├── base.py
│       │   ├── greedy.py
│       │   └── top_k.py
│       └── cli.py
├── tests/
│   ├── unit/
│   ├── integration/
│   └── conftest.py
├── benchmarks/
├── examples/
└── docs/
```

工程约束：

* 使用 `src` layout。
* 使用 `pyproject.toml`。
* 核心公共 API 必须有类型标注。
* 所有功能先定义行为，再写测试。
* 第三方组件通过 Adapter 隔离。
* 不为模式而使用模式。
* 每周至少做一次 code review。
* 阅读开源源码时固定到具体 tag 或 commit，避免路径随版本变化。

Python 类型标注本身不会在运行时自动执行业务类型检查，它主要服务于类型检查器、IDE 和代码理解，因此课程会同时训练“静态契约”和“运行时校验”的边界。 [\[docs.python.org\]](https://docs.python.org/3/library/typing.html)

***

# Week 1：Python 工程基础与可测试库骨架

## 本周目标

重点不是语法大全，而是理解：

* Python 的模块和包如何被加载。
* 对象、引用、可变性和作用域。
* 异常、资源管理、日志。
* `pytest` 测试组织方式。
* 一个库如何从第一天就具备工程结构。

pytest 的核心价值不只是简洁断言，还包括测试发现、fixture、参数化、临时目录、monkeypatch 和日志捕获等工程能力。 [\[docs.pytest.org\]](https://docs.pytest.org/en/stable/contents.html), [\[docs.pytest.org\]](https://docs.pytest.org/)

***

## Day 1：建立工程基线

### 学习主题

现代 Python 项目的开发环境、目录结构与质量门禁。

### 必学知识点

* Python 解释器、虚拟环境、依赖环境的区别。
* `pyproject.toml` 的作用。
* `src` layout 与直接平铺包结构的区别。
* package、module、distribution package 的区别。
* 可编辑安装：`pip install -e .`
* 基础工具链：
  * `pytest`
  * `ruff`
  * `mypy` 或 `pyright`
  * `pre-commit`

PyPA 的 Packaging User Guide 是现代 Python 打包、安装和发布流程的权威入口，课程中的项目结构以它描述的现代打包流程为基线。 [\[packaging.python.org\]](https://packaging.python.org/), [\[pypa.io\]](https://www.pypa.io/en/latest/)

### 实战练习

创建 `mini-infer` 仓库，完成：

* `src/mini_infer`
* `tests`
* `README.md`
* `pyproject.toml`
* 安装项目。
* 添加一个 `mini-infer --version` CLI。
* 配置单元测试、lint 和类型检查命令。

验收命令：

```bash
python -m pytest
python -m mypy src
python -m ruff check .
python -m mini_infer.cli --version
```

***

## Day 2：Python 对象模型与可变性

### 学习主题

从 C++/Java 工程师视角理解 Python 的引用语义。

### 必学知识点

* 名称绑定，而不是“变量盒子”。
* `is` 与 `==`。
* mutable 与 immutable。
* 浅拷贝与深拷贝。
* 默认可变参数陷阱。
* `dataclass` 的 `default_factory`。
* 参数传递的对象引用模型。

### 实战练习

实现：

* `InferenceRequest`
* `SamplingConfig`
* `GenerationResult`

编写测试证明：

* 两个请求不能共享默认 `stop_tokens`。
* 修改输入列表是否会污染配置对象。
* 配置复制后，嵌套对象是否独立。

推荐设计：

```python
from dataclasses import dataclass, field

@dataclass(frozen=True)
class SamplingConfig:
    temperature: float = 1.0
    max_tokens: int = 32
    stop_token_ids: tuple[int, ...] = field(default_factory=tuple)
```

工程思考：为什么配置对象通常适合不可变，而 request/runtime state 通常需要可变？

***

## Day 3：模块、包、导入与 API 边界

### 学习主题

理解 Python 项目最常见的结构性故障：循环依赖和公共 API 泄漏。

### 必学知识点

* 绝对导入与相对导入。
* `__init__.py` 的职责。
* `__all__`。
* import 执行时机与模块缓存。
* 循环导入产生的原因。
* import-time side effect。
* 公共 API 与内部模块。

### 实战练习

将代码拆分为：

```text
config.py
protocols.py
exceptions.py
engine/request.py
```

要求：

* 外部用户只能从 `mini_infer` 导入稳定 API。
* 内部实现不直接暴露。
* 故意制造一次循环导入，再通过依赖反转消除。
* 写一页 `docs/import-boundaries.md`，描述模块依赖方向。

***

## Day 4：异常设计与资源管理

### 学习主题

建立可诊断、可恢复的错误模型。

### 必学知识点

* 异常层级设计。
* `raise ... from ...` 保留因果链。
* EAFP 与 LBYL。
* `try/except/else/finally`。
* context manager。
* `contextlib.contextmanager`。
* 不应捕获 `Exception` 后静默忽略。

### 实战练习

建立异常层级：

```text
MiniInferError
├── ConfigurationError
├── TokenizationError
├── ModelExecutionError
└── CacheCapacityError
```

实现一个模型资源管理器：

```python
with ModelSession(config) as session:
    result = session.generate("hello")
```

测试：

* 初始化失败时资源是否释放。
* 底层异常是否通过 `raise ... from ...` 保留。
* 业务层是否只依赖领域异常。

***

## Day 5：日志与可观测性

### 学习主题

从“打印信息”升级到“可定位请求生命周期”。

### 必学知识点

* `logging.getLogger(__name__)`。
* logger、handler、formatter、level。
* 库代码为什么不应随意配置 root logger。
* 结构化字段。
* request ID / correlation ID。
* 日志和异常的职责边界。
* 避免记录 prompt、token 等敏感数据。

### 实战练习

实现日志配置模块，使一次推理能够输出：

* `request_id`
* tokenizer 耗时
* prompt token 数
* decode token 数
* cache 使用量
* 总延迟

使用 pytest 的 `caplog` 验证：

* 正常路径包含生命周期日志。
* 错误路径包含 request ID 和异常上下文。
* 日志不会记录完整 prompt。

***

## Day 6：pytest 测试设计

### 学习主题

测试行为，而不是绑定内部实现。

### 必学知识点

* Arrange–Act–Assert。
* fixture。
* 参数化测试。
* `tmp_path`。
* `monkeypatch`。
* `pytest.raises`。
* 单元测试、集成测试、契约测试。
* mock 的合理边界。

### 实战练习

为当前项目添加：

* `SamplingConfig` 参数化测试。
* tokenizer 临时词表 fixture。
* 日志捕获测试。
* 异常链测试。
* CLI 集成测试。

目标：

```text
tests/
├── unit/
│   ├── test_config.py
│   ├── test_request.py
│   └── test_logging.py
└── integration/
    └── test_cli.py
```

***

## Day 7：第一周重构与代码评审

### 学习主题

通过 code review 提升可读性和抽象质量。

### 必学知识点

* 函数是否只做一件事。
* 命名是否表达领域概念。
* 是否存在隐藏状态。
* public API 是否最小化。
* 测试是否覆盖行为而非实现。
* 异常是否携带有效上下文。
* 模块依赖方向是否单向。

### 实战练习

模拟正式评审：

1. 为项目创建 Pull Request。
2. 从下面五个维度写 review：
   * correctness
   * readability
   * testability
   * extensibility
   * observability
3. 至少识别三个设计问题并重构。
4. 记录一份 ADR：为什么选择 `src` layout。

### Week 1 输出成果

你应得到：

* 一个可安装的 Python 库骨架。
* 稳定的测试、lint、typing 命令。
* 对导入、引用语义、异常和日志的工程理解。
* 约 20～30 个有效测试。
* 一份模块依赖说明和一次正式 code review。

***

# Week 2：类型系统、抽象接口与设计模式

## 本周目标

* 使用类型定义边界，而不是给每一行“补类型”。
* 理解 ABC、Protocol、泛型和依赖注入。
* 用 composition 替代脆弱继承。
* 在项目中真正应用 Factory、Strategy、Adapter。
* 理解 Singleton 的风险和受限使用场景。

***

## Day 8：工程化类型标注

### 学习主题

将类型作为模块间契约。

### 必学知识点

* `list[str]`、`dict[str, int]`、`T | None`。
* `Sequence`、`Iterable`、`Mapping` 等抽象容器。
* `TypeAlias`。
* `TypedDict`。
* `Literal`。
* `NewType`。
* `Any` 的传播风险。
* 静态类型与运行时验证的区别。

### 实战练习

为项目引入领域类型：

```python
from typing import NewType

TokenId = NewType("TokenId", int)
RequestId = NewType("RequestId", str)
```

要求：

* 公共 API 不出现无约束的 `dict`。
* 清理 `Any`。
* 配置输入在运行时校验。
* 将 `mypy --strict` 或近似严格配置加入 CI。

***

## Day 9：Protocol、ABC 与抽象边界

### 学习主题

结构化子类型与名义子类型如何选择。

### 必学知识点

* `abc.ABC` / `@abstractmethod`。
* `typing.Protocol`。
* duck typing。
* 接口隔离。
* 依赖反转。
* 测试替身。

### 实战练习

定义 tokenizer 契约：

```python
from typing import Protocol, Sequence

class Tokenizer(Protocol):
    def encode(self, text: str) -> Sequence...
    def decode(self, token_ids: Sequence[int]) -> str: ...
```

实现：

* `WhitespaceTokenizer`
* `FakeTokenizer`

验证 `InferenceEngine` 只依赖 `Tokenizer` 协议，不依赖具体实现。

***

## Day 10：Composition 优先于继承

### 学习主题

拆分策略、状态和生命周期。

### 必学知识点

* is-a 与 has-a。
* 继承层级膨胀。
* mixin 的适用边界。
* 委托。
* 依赖注入。
* 组合根 composition root。

### 实战练习

将 Engine 组合为：

```text
InferenceEngine
├── Tokenizer
├── Model
├── Sampler
├── Scheduler
└── MetricsSink
```

禁止通过以下方式扩展：

```python
class GreedyHuggingFaceLoggedEngine(...):
    ...
```

改为构造注入。测试时替换任意一个组件。

***

## Day 11：Strategy 模式——采样算法

### 学习主题

将变化行为从 Engine 中剥离。

### 必学知识点

* Strategy 接口。
* 算法替换。
* 无状态策略与有状态策略。
* 随机数种子。
* 可重复性测试。
* 数值边界条件。

### 实战练习

实现：

* `GreedySampler`
* `TopKSampler`
* 可选：`TemperatureSampler`

```python
class Sampler(Protocol):
    def sample(self, logits: "Tensor") -> int: ...
```

测试：

* greedy 永远选择最大 logit。
* `top_k=1` 等价于 greedy。
* 固定随机种子时可重复。
* 非法 temperature 明确报错。

***

## Day 12：Factory 模式——配置到对象图

### 学习主题

集中管理对象创建，而不是隐藏全局依赖。

### 必学知识点

* simple factory。
* registry factory。
* 构造与业务逻辑分离。
* 配置驱动创建。
* 插件式扩展。
* “万能 Factory”反模式。

### 实战练习

实现：

```python
sampler = SamplerFactory.create(
    kind="top_k",
    config={"k": 10, "temperature": 0.8},
)
```

增加一个 sampler 时：

* 不修改 Engine。
* 只扩展实现和注册逻辑。
* 添加契约测试，所有 sampler 必须通过同一组测试。

***

## Day 13：Adapter 模式——接入 Hugging Face Tokenizer

### 学习主题

隔离第三方接口和版本变化。

### 必学知识点

* Adapter 与 wrapper 的差异。
* 第三方依赖隔离。
* 返回值标准化。
* 错误翻译。
* capability detection。
* slow/fast tokenizer 的差异。

Hugging Face tokenizer 主要负责文本切分、token 到 ID 的转换、encode/decode、特殊 token 管理和批量编码；fast tokenizer 还提供字符与 token 之间的对齐能力。 [\[huggingface.co\]](https://huggingface.co/docs/transformers/main_classes/tokenizer), [\[github.com\]](https://github.com/huggingface/transformers/blob/main/docs/source/en/main_classes/tokenizer.md)

### 实战练习

实现：

```python
class HuggingFaceTokenizerAdapter:
    def __init__(self, tokenizer: object) -> None:
        self._tokenizer = tokenizer

    def encode(self, text: str) -> list...

    def decode(self, token_ids: list[int]) -> str:
        ...
```

要求：

* 核心层不 import `transformers`。
* 将第三方异常翻译为 `TokenizationError`。
* 用 fake object 完成大部分测试。
* 另写一个可选的集成测试验证真实 tokenizer。

***

## Day 14：Singleton、全局状态与配置管理

### 学习主题

理解 Singleton，而不是默认采用 Singleton。

### 必学知识点

* 模块本身可以承担单实例命名空间。
* Singleton 隐式依赖。
* 全局状态导致测试互相污染。
* cache 与 singleton 的区别。
* lazy initialization。
* 进程安全与线程安全。
* dependency injection。

### 实战练习

先实现一个全局 `ModelRegistry`，然后观察：

* 测试执行顺序依赖。
* 状态清理困难。
* 并行测试风险。

再将其重构为：

```python
registry = ModelRegistry()
engine = InferenceEngine(registry=registry, ...)
```

保留一份文档：

```text
何时可使用：
- 不可变、无业务状态的进程级元数据
- 生命周期与进程完全一致
- 有明确reset机制

何时不可使用：
- request state
- 可变配置
- 测试依赖
- GPU资源生命周期
```

### Week 2 输出成果

你应达到：

* 能用 Protocol/ABC 定义稳定接口。
* 能解释何时使用 composition。
* 能将 Strategy、Factory、Adapter 应用于真实模块边界。
* 能识别 Singleton 和全局状态的测试风险。
* `mini-infer` 已支持可替换 tokenizer 和 sampler。
* 类型检查严格模式通过。

***

# Week 3：Packaging、并发、性能与 Transformer 最小实现

## 本周目标

* 把项目变为真正可构建、可发布的库。
* 掌握 Python 并发、profiling 和性能判断方法。
* 用 PyTorch 实现最小 decoder-only Transformer。
* 建立 shape-first 的源码阅读习惯。

***

## Day 15：现代 Packaging

### 学习主题

从源码目录到 wheel。

### 必学知识点

* source distribution 与 wheel。
* build backend。
* 项目 metadata。
* production dependencies 与 optional dependencies。
* semantic versioning。
* entry point。
* package data。
* editable install 与普通 install。

### 实战练习

完善 `pyproject.toml`：

* 基础依赖。
* `dev` / `torch` / `transformers` 可选依赖。
* CLI entry point。
* 构建 wheel。
* 创建干净虚拟环境安装 wheel。
* 验证用户只能通过公共 API 使用库。

验收：

```bash
python -m build
python -m venv /tmp/mini-infer-test
# 在新环境中安装 dist/*.whl 并运行 smoke test
```

***

## Day 16：CI、测试分层与发布门禁

### 学习主题

把工程规范变成自动反馈。

### 必学知识点

* 快速测试与慢测试。
* unit/integration 标记。
* 测试覆盖率的局限。
* 矩阵测试。
* reproducible build。
* API compatibility。
* CI fail-fast。

### 实战练习

配置 CI，使每次提交执行：

1. lint
2. type check
3. unit tests
4. integration tests
5. build wheel
6. smoke install

同时设置：

* `@pytest.mark.integration`
* 覆盖率阈值。
* 禁止提交未格式化代码。
* 缓存依赖但不缓存工作区产物。

***

## Day 17：Python 并发模型

### 学习主题

为 batching 和 inference scheduler 奠定基础。

### 必学知识点

* thread、process、asyncio 的区别。
* GIL 对 CPU-bound Python code 的影响。
* I/O-bound 与 compute-bound。
* queue、backpressure、timeout。
* cancellation。
* async API 与 sync API 边界。

### 实战练习

实现异步请求队列：

```python
result = await engine.submit(request)
```

要求：

* 多个请求进入队列。
* scheduler 定时取 batch。
* 支持 timeout。
* 队列满时产生明确 backpressure。
* 请求取消后不会泄漏 future。

***

## Day 18：Profiling、Benchmark 与性能假设

### 学习主题

先测量，再优化。

### 必学知识点

* `time.perf_counter`。
* `timeit`。
* `cProfile`。
* CPU time 与 wall time。
* warm-up。
* throughput 与 latency。
* p50、p95、p99。
* benchmark 噪声与重复实验。

### 实战练习

为 tokenizer 和 scheduler 写 benchmark：

* 单请求 encode latency。
* batched encode throughput。
* 不同 batch size。
* 不同 prompt 长度。
* cold start 与 steady state。

输出：

```text
benchmarks/results.json
benchmarks/report.md
```

每个结论必须包括：

* 假设。
* 环境。
* 输入。
* 重复次数。
* 结果。
* 尚未排除的变量。

***

## Day 19：PyTorch 执行模型

### 学习主题

理解 Tensor、Module 和 forward 调用路径。

### 必学知识点

* Tensor 的 shape、dtype、device、stride。
* `nn.Module`。
* parameter 与 buffer。
* `train()` / `eval()`。
* `no_grad()` / `inference_mode()`。
* `__call__` 与 `forward` 的关系。
* hook。
* `state_dict`。

### 实战练习

实现一个两层模型：

```python
class TinyModel(nn.Module):
    def __init__(self, hidden_size: int) -> None:
        super().__init__()
        self.proj_in = nn.Linear(hidden_size, hidden_size * 4)
        self.proj_out = nn.Linear(hidden_size * 4, hidden_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.proj_out(torch.relu(self.proj_in(x)))
```

调试任务：

* 打印每层输入输出 shape。
* 注册 forward hook。
* 检查 `state_dict`。
* 故意制造 dtype/device mismatch。
* 解释错误发生在什么抽象层。

***

## Day 20：从公式到 Attention 实现

### 学习主题

理解 Transformer 的核心数据流。

### 必学知识点

* Q、K、V 投影。
* `head_dim = hidden_size // num_heads`。
* reshape 与 transpose。
* scaled dot-product attention。
* causal mask。
* padding mask。
* softmax 维度。
* 数值稳定性。

PyTorch 的 `MultiheadAttention` 可作为理解多头注意力的参考实现；其核心仍是 Q/K/V 投影、分头、attention 计算、拼接和输出投影。当前实现还会在满足条件时调用优化的 scaled dot-product attention 路径。 [\[docs.pytorch.org\]](https://docs.pytorch.org/docs/main/generated/torch.nn.modules.activation.MultiheadAttention.html)

### 实战练习

不用 `nn.MultiheadAttention`，实现：

```python
scores = q @ k.transpose(-2, -1)
scores = scores / math.sqrt(head_dim)
scores = scores.masked_fill(causal_mask, float("-inf"))
weights = torch.softmax(scores, dim=-1)
output = weights @ v
```

必须测试：

* 输出 shape。
* 未来 token 的权重为零。
* 单头实现和手算结果一致。
* 与 PyTorch 参考输出进行近似比较。

***

## Day 21：最小 Decoder-only Transformer

### 学习主题

把 attention 放回完整 block。

### 必学知识点

* token embedding。
* position information。
* pre-norm 与 post-norm。
* residual connection。
* feed-forward network。
* LM head。
* logits。
* 权重共享的概念。

### 实战练习

实现：

```text
input_ids
→ Embedding
→ N × TransformerBlock
→ Norm
→ LM Head
→ logits
```

要求：

* 小词表、小 hidden size，可在 CPU 运行。
* forward 输入为 `[batch, sequence]`。
* 输出为 `[batch, sequence, vocab]`。
* 每个模块具有独立单元测试。
* 增加一张 shape-flow 图。

### Week 3 输出成果

你应得到：

* 可构建、可安装的 wheel。
* 自动化 CI。
* 可工作的异步请求队列。
* benchmark 基线。
* 一个经过测试的最小 decoder-only Transformer。
* 能从 shape 和数据流角度解释 `forward → attention → logits`。

***

# Week 4：Tokenizer、推理流程、KV Cache 与 vLLM 架构

## 本周目标

* 理解 tokenizer 的真正处理流水线。
* 手工完成 autoregressive decoding。
* 理解 prefill、decode、batching 和 KV cache。
* 从自己实现映射到 vLLM 的调度与缓存设计。

vLLM 的主要推理优化方向包括 PagedAttention、continuous batching、chunked prefill、prefix caching 和优化的 attention kernel，因此阅读时应从请求生命周期与数据流进入，而不是一开始钻入 CUDA。 [\[docs.vllm.ai\]](https://docs.vllm.ai/en/latest/), [\[pytorch.org\]](https://pytorch.org/projects/vllm/)

***

## Day 22：Tokenizer 工程流水线

### 学习主题

tokenizer 不只是 `text.split()`。

### 必学知识点

* normalization。
* pre-tokenization。
* BPE / WordPiece / Unigram 的工程角色。
* vocabulary。
* special tokens。
* encode/decode。
* padding 与 truncation。
* attention mask。
* byte fallback。
* round-trip 不一定完全恢复原始字符串。

### 实战练习

增强 `WhitespaceTokenizer`：

* `<unk>`、`<bos>`、`<eos>`、`<pad>`。
* 批量 encode。
* padding。
* attention mask。
* 保存和加载 vocabulary。

测试：

* Unicode。
* 空文本。
* 未知 token。
* 特殊 token。
* 不同长度 batch。
* encode/decode round-trip 的明确语义。

***

## Day 23：阅读 Hugging Face Tokenizer 源码

### 学习主题

用“公共 API → 基类 → 具体实现”的顺序读源码。

### 必学知识点与阅读路径

按以下顺序：

1. 从一个最小调用开始：
   ```python
   encoded = tokenizer(["hello", "world"], padding=True)
   ```
2. 查看返回的 `BatchEncoding`：
   * `input_ids`
   * `attention_mask`
3. 进入 `PreTrainedTokenizerBase.__call__`。
4. 跟踪 single/batch 分支。
5. 查看 padding、truncation 和 special token 的处理。
6. 再进入具体模型 tokenizer。
7. 最后才看 Rust-backed fast tokenizer 边界。

Hugging Face 的 `BatchEncoding` 表现得类似字典，承载 `input_ids`、`attention_mask` 等模型输入；fast tokenizer 还提供原始字符空间与 token 空间之间的映射。 [\[huggingface.co\]](https://huggingface.co/docs/transformers/main_classes/tokenizer), [\[huggingface.co\]](https://huggingface.co/docs/transformers/v4.56.1/en/main_classes/tokenizer)

### 实战练习

生成一份 `docs/hf-tokenizer-call-chain.md`，包括：

* 入口函数。
* 关键类。
* 关键数据结构。
* single 与 batch 分支。
* Python 与 Rust 的边界。
* 你的 Adapter 位于哪个层次。

再写一个测试，对比：

* `mini-infer` tokenizer 输出。
* Hugging Face tokenizer 输出。

不要求算法一致，但要求字段语义一致。

***

## Day 24：Autoregressive Generation Loop

### 学习主题

从 logits 到下一 token。

### 必学知识点

* prefill。
* decode。
* last-token logits。
* softmax 与采样。
* EOS。
* maximum tokens。
* stopping criteria。
* streaming output。
* `eval()` 与 inference mode。

### 实战练习

实现最小生成循环：

```python
token_ids = tokenizer.encode(prompt)

for _ in range(max_new_tokens):
    logits = model(input_ids)
    next_token = sampler.sample(logits[:, -1, :])
    token_ids.append(next_token)

    if next_token == eos_token_id:
        break
```

然后识别其低效点：

* 每一步重复计算所有历史 token。
* 每个请求独立执行。
* Python loop overhead。
* 无 KV cache。
* 无动态 batching。

将问题写入 `docs/naive-generation-bottlenecks.md`。

***

## Day 25：KV Cache

### 学习主题

避免 decode 阶段重复计算历史 K/V。

### 必学知识点

* attention 中历史 K/V 为什么可复用。
* prefill cache。
* decode 每步追加一个位置。
* cache shape。
* layer/head/sequence/head\_dim。
* MHA、MQA、GQA 对 cache 大小的影响。
* cache 生命周期。
* capacity 与 eviction。

### 实战练习

为 `MiniAttention` 添加：

```python
output, updated_cache = attention(
    hidden_states,
    kv_cache=previous_cache,
)
```

测试：

* 无 cache 完整计算。
* 使用 cache 逐 token 计算。
* 两种方式 logits 近似一致。
* cache sequence length 每步增加 1。
* 超过容量时产生 `CacheCapacityError`。

另外手算一次 KV cache 大小：

```text
2 × layers × kv_heads × sequence_length × head_dim × bytes_per_element
```

***

## Day 26：Batching、Padding 与 Continuous Batching

### 学习主题

从静态 batch 走向请求级调度。

### 必学知识点

* 静态 batching。
* dynamic batching。
* iteration-level/continuous batching。
* prompt length 差异。
* padding 浪费。
* active sequence。
* admission control。
* throughput/latency trade-off。
* fairness 与 starvation。

### 实战练习

扩展 scheduler：

* 每个 decode iteration 重新选择 active requests。
* 已完成请求立即离开 batch。
* 新请求可在下一 iteration 加入。
* 限制：
  * 最大请求数。
  * 最大 token budget。
  * 最大等待时间。

建立测试场景：

* 三个请求生成长度分别为 2、5、8。
* 验证短请求不会等待最长请求完成。
* 验证新请求可进入后续 iteration。
* 输出 scheduler 时间线。

***

## Day 27：Paged KV Cache 的简化实现

### 学习主题

理解逻辑 token 序列与物理 cache block 的映射。

### 必学知识点

* 连续内存预分配的问题。
* 固定大小 block。
* logical block 与 physical block。
* block table。
* free block pool。
* copy-on-write 的概念。
* prefix sharing 的可能性。
* internal fragmentation。

### 实战练习

在 CPU 上实现不含真实 tensor 的 `BlockManager`：

```text
Request A logical blocks: [0, 1, 2]
                         ↓
Physical blocks:        [7, 3, 9]
```

要求：

* 分配 block。
* 追加 token。
* 释放请求。
* block 重用。
* 容量不足。
* 可视化 block table。
* 添加随机操作的状态不变量测试。

不变量示例：

* 一个已分配物理 block 不得同时属于两个不共享的请求。
* free list 和 allocated set 不相交。
* request 释放后所有独占 block 返回 free list。

***

## Day 28：vLLM 源码阅读第一轮——架构导航

### 学习主题

建立 vLLM 请求生命周期地图。

### 必读顺序

不要从 kernel 开始。按以下顺序：

1. **示例与入口**
   * offline inference 示例。
   * `LLM.generate()` 或相应公开入口。
2. **配置与输入**
   * 模型配置。
   * sampling parameters。
   * tokenized request。
3. **Engine**
   * 请求如何进入 engine。
   * engine 每一步做什么。
4. **Scheduler**
   * waiting/running request。
   * token budget。
   * prefill/decode 决策。
5. **Model Runner**
   * batch 如何转换为 tensor。
   * forward 如何被调用。
6. **Model implementation**
   * 选择一个简单 decoder-only 模型。
7. **Attention layer**
   * Q/K/V。
   * KV cache 写入。
   * attention backend。
8. **KV cache manager / block manager**
9. 最后再进入 Triton、CUDA 或 C++ kernel。

vLLM 官方开发文档本身也将架构分为 entrypoint、LLM Engine、Worker、Model Runner、Model class hierarchy、Paged Attention 等部分，这正适合作为源码导航地图。 [\[docs.vllm.ai\]](https://docs.vllm.ai/en/v0.8.3/index.html)

### 实战练习

输出 `docs/vllm-request-lifecycle.md`：

```text
User API
→ Tokenization/Input Processing
→ Engine
→ Scheduler
→ Model Runner
→ Model.forward
→ Attention Backend
→ KV Cache
→ Sampler
→ Output Processing
```

对每个箭头记录：

* 输入类型。
* 输出类型。
* 所有权。
* 是否跨线程/进程。
* 是否位于性能关键路径。

### Week 4 输出成果

你应能够：

* 解释 tokenizer 的完整 pipeline。
* 写出基础 autoregressive generation loop。
* 解释 prefill 与 decode。
* 实现并验证简化 KV cache。
* 实现 continuous batching scheduler。
* 画出 vLLM 从 request 到 output 的主调用链。
* 解释 PagedAttention 解决的是哪类内存管理问题。

***

# Week 5：复杂源码阅读、性能对照与最终交付

## Day 29：PyTorch → Transformers → vLLM 对照阅读

### 学习主题

同一抽象在三个代码库里的不同职责。

### 源码阅读路径

#### 第一层：PyTorch 基础机制

阅读顺序：

1. `nn.Module.__call__` 附近的调用机制。
2. 一个简单 `nn.Linear`。
3. `scaled_dot_product_attention` 的 API。
4. `MultiheadAttention.forward`。
5. `state_dict` / parameter registration。
6. inference mode 和 device/dtype 转换路径。

目标：理解“框架如何执行模块”。

#### 第二层：Transformers 模型结构

选择一个结构清晰的 decoder-only 模型，按顺序阅读：

1. config class。
2. causal LM 顶层类。
3. `forward()` 参数。
4. base model。
5. decoder layer。
6. attention。
7. MLP。
8. normalization。
9. cache 输入输出。
10. generation 调用入口。

目标：理解“一个模型如何组织 forward”。

#### 第三层：vLLM 推理体系

按顺序对应：

1. Transformers 的单次 model forward。
2. vLLM 模型实现中的 forward。
3. Model Runner 如何组装 batch。
4. Scheduler 如何决定本轮 token。
5. KV cache manager 如何提供 cache。
6. attention backend 如何消费 cache metadata。
7. output processor/sampler 如何返回结果。

目标：理解“生产推理引擎如何组织大量 forward”。

### 关键模块解释

#### Tokenizer

职责是把外部字符串转换成模型输入 ID，同时处理 special token、padding、truncation 和 batch metadata。

阅读时追问：

* tokenizer 是否在主进程执行？
* 是否成为吞吐瓶颈？
* 是否缓存？
* 错误如何传播？
* token 数如何影响 scheduler admission？

#### Forward

`forward` 是从模型输入到 hidden states/logits 的计算边界，但在大型框架中，调用它的不一定是直接用户代码。

阅读时追问：

* 输入 shape 是什么？
* prefill 和 decode 是否走同一路径？
* cache 由谁传入？
* 返回 logits 还是 hidden states？
* 哪些参数只影响训练，哪些影响推理？

#### Attention

核心逻辑：

```text
hidden states
→ Q/K/V projection
→ reshape to heads
→ positional transformation
→ append/write KV cache
→ QKᵀ
→ mask
→ softmax
→ weighted V
→ output projection
```

#### KV Cache

它是跨 decode step 保留的模型中间状态，不是普通函数局部变量。

阅读时追问：

* cache 的所有权属于 model、engine 还是 cache manager？
* 逻辑序列如何映射到物理 block？
* 什么时候分配和释放？
* batch 重排后如何找到正确 block？
* prefix 是否可以共享？

### 实战练习

选择一次真实推理调用，创建“三层对照表”：

```text
概念             PyTorch          Transformers        vLLM
Module执行        __call__         Model.forward       Model Runner
Attention         SDPA/MHA         模型Attention类      Attention backend
Cache             Tensor           past_key_values     KV cache blocks
Batch             Tensor batch     padded batch        scheduled token batch
```

然后做一次调试实验：

* 在自己代码中打印 shape。
* 在 Transformers 模型中用 hook/断点观察相同 shape。
* 在 vLLM 中找到对应 metadata。
* 写出三者差异，而不是只抄类名。

***

## Day 30：最终集成、评审与能力验收

### 学习主题

把学习成果变成一个可评审的工程交付。

### 必学知识点

* API stability。
* backward compatibility。
* release checklist。
* documentation-driven design。
* 性能回归。
* threat/failure modeling。
* 技术债登记。
* 源码阅读报告的可验证性。

### 实战练习

完成 `mini-infer v0.1.0`：

#### 功能要求

* 至少两种 tokenizer：
  * 内置 tokenizer。
  * Hugging Face adapter。
* 至少两种 sampler：
  * greedy。
  * top-k。
* 最小 Transformer forward。
* naive generation。
* KV cache generation。
* dynamic/continuous batching。
* block manager。
* CLI。
* structured logging。
* 可选 benchmark 命令。

#### 质量要求

* 类型检查通过。
* unit/integration 测试分层。
* 关键行为有测试。
* wheel 可安装。
* README 包含 quick start。
* 有架构图。
* 有错误模型。
* 有性能基线。
* 没有 tokenizer、model、scheduler 的反向循环依赖。

#### 最终验证任务

设计三个实验：

1. **正确性实验**
   * cache 与 no-cache 输出是否一致。
2. **调度实验**
   * continuous batching 是否减少短请求等待。
3. **性能实验**
   * batch size 改变如何影响 throughput 和 latency。

#### 最终 code review 问题

* Engine 是否依赖具体 tokenizer？
* scheduler 是否混入模型计算细节？
* cache 的所有权是否明确？
* third-party adapter 是否泄漏外部类型？
* 测试是否过度 mock？
* 日志能否重建请求生命周期？
* 错误是否可定位、可恢复？
* benchmark 是否可复现？
* 哪些设计在真实 GPU 系统中会失效？

### Week 5 / 最终输出成果

最终应交付：

```text
mini-infer v0.1.0
├── 可安装 wheel
├── 完整 README
├── 架构设计文档
├── 50～100 个有效测试
├── 类型检查与 lint
├── CI pipeline
├── tokenizer adapter
├── Transformer forward
├── KV cache
├── continuous batching scheduler
├── block manager
├── benchmark report
└── PyTorch/Transformers/vLLM 源码阅读报告
```

***

# 推荐的源码阅读方法

## 1. 从可运行入口进入，不要从文件树漫游

每次阅读先准备最小脚本：

```python
output = model(input_ids)
```

然后只回答：

1. 当前调用了哪个方法？
2. 输入和输出类型是什么？
3. shape 如何变化？
4. 状态在哪里保存？
5. 下一层调用是谁？

***

## 2. 使用“双向阅读”

### 自顶向下

```text
Public API
→ Engine
→ Scheduler
→ Model Runner
→ Forward
→ Attention
→ Kernel
```

用于理解责任划分。

### 自底向上

```text
Tensor shape
→ Attention operation
→ Layer
→ Model
→ Batch
→ Request
```

用于理解数据如何被计算。

两条路径在 `forward/attention` 会合。

***

## 3. 建立源码阅读登记表

每次阅读记录：

```text
Repository:
Tag/commit:
Entry point:
Question:
Call chain:
Key data structures:
State ownership:
Shape changes:
Error path:
Performance-sensitive path:
Tests discovered:
Unresolved questions:
```

不要只记录“看过某文件”，而要记录可验证问题，例如：

* decode step 为什么只输入一个新 token？
* 当前版本 cache metadata 在哪里产生？
* scheduler 的 token budget 在哪里扣减？
* attention backend 如何找到逻辑序列对应的物理 block？

***

## 4. 阅读顺序：测试优先于底层实现

复杂项目建议按下列顺序：

```text
example
→ public API
→ tests
→ interface/base class
→ concrete implementation
→ optimized implementation
→ native/CUDA kernel
```

测试通常能最快说明：

* 输入约束。
* 对外行为。
* 边界条件。
* 设计者认为重要的不变量。

***

# 每周自测标准

## Week 1

不看资料，你能否：

* 创建可安装项目？
* 解释一次 import 的执行过程？
* 设计异常层级？
* 用 fixture 和参数化测试功能？
* 定位循环导入？

## Week 2

不看资料，你能否：

* 比较 ABC 与 Protocol？
* 用 composition 重构继承层级？
* 实现可替换 sampler？
* 隔离第三方 tokenizer？
* 解释 Singleton 为什么损害测试？

## Week 3

不看资料，你能否：

* 构建 wheel 并在干净环境安装？
* 写一个 async queue？
* 做可信 benchmark？
* 解释 `Module.__call__` 与 `forward`？
* 手写 causal attention？

## Week 4

不看资料，你能否：

* 画 tokenizer pipeline？
* 区分 prefill 与 decode？
* 推导 KV cache shape 和容量？
* 解释 continuous batching？
* 画出 vLLM 请求生命周期？

## 最终

给你一个不熟悉的 LLM Python 仓库，你应能在 60～90 分钟内：

1. 找到安装和运行入口。
2. 找到 public API。
3. 找到核心配置。
4. 找到 tokenizer 输入路径。
5. 找到模型 forward。
6. 找到 attention。
7. 找到 cache 数据结构。
8. 找到 scheduler 或 batching 逻辑。
9. 找到关键测试。
10. 输出一张可信的调用链图，而不是逐文件浏览笔记。

***

# 课程的核心取舍

这个月里可以暂时弱化：

* Python 冷门语法技巧。
* metaclass 深度用法。
* descriptor 的完整实现。
* 装饰器花式写法。
* 大量算法题。
* 直接阅读 CUDA kernel。
* 完整训练流程和分布式训练。

优先掌握：

```text
模块边界
→ 类型契约
→ 测试行为
→ 对象组合
→ 数据 shape
→ 状态所有权
→ 请求生命周期
→ 性能测量
→ 源码调用链
```

这条路线能把你的既有工程经验迁移到 Python，同时为 PyTorch、Transformers 和 vLLM 源码阅读建立足够坚实的落点。
