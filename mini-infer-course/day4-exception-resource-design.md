# Day 4：异常设计与资源管理 — 课程方案

> 所属项目：`mini-infer`（可扩展的迷你 LLM 推理流水线框架）
> 前置基础：Day 1 工程基线 / Day 2 对象模型与可变性 / Day 3 模块、包、导入与 API 边界
> 学员画像：EDA 工程师，C++ 系统背景，熟悉 RAII、错误码、异常栈展开
> 设计依据：`roadmap.md` Day 4「建立可诊断、可恢复的错误模型」

---

## 0. 课程概览与时间分配（总时长 ≈ 2.8 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 课程目标、今日与项目的关系 | 5 min |
| 3.1 | 什么是异常 / 为什么需要异常设计（对比错误码） | 15 min |
| 3.2 | `try/except/else/finally` 与异常传播（含 EAFP vs LBYL） | 18 min |
| 3.3 | 自定义异常类的设计原则与项目实践（层级 + `raise...from...`） | 12 min |
| 3.4 | 资源管理、RAII 思想与 `with` 上下文管理器 | 18 min |
| 3.5 | `finally` / `using` / try-with-resources 对比与选择 | 8 min |
| 3.6 | 日志记录与异常信息的关联（含「不可静默吞异常」） | 8 min |
| 练习 1 | 异常层级 + 配置加载错误翻译 | 22 min |
| 练习 2 | `ModelSession` 资源管理器 + 初始化失败清理 | 28 min |
| 练习 3 | 异常边界统一 + 日志关联 + 业务层只依赖领域异常 | 22 min |
| 收尾 | 课后测验讲解 + 总结与延伸阅读 | 14 min |

> 标注为「可压缩」：3.5、3.6 可合并到 10 min；练习可按基础/进阶两档取舍。核心不可删：**异常层级、因果链、`with` 资源管理、不静默吞异常**。

---

## 1. 课程目标

学完今天，学员应当能够：

1. **说清动机**：用 C++ 错误码的经验对比，解释为什么推理框架需要异常而不是返回码。
2. **写对结构**：正确使用 `try/except/else/finally`，理解异常沿调用栈向上传播的机制，并能用 `raise...from...` 保留因果链。
3. **设计层级**：在 `mini-infer` 中落地 `MiniInferError` → 四个子类的领域异常层级，并遵循「只加语义、不加噪音」的设计原则。
4. **管好资源**：用 `with` / 上下文管理器实现「RAII 式」的资源生命周期管理，保证初始化失败或运行异常时资源一定释放。
5. **划清边界**：第三方（Hugging Face tokenizer、文件、设备）异常翻译为领域异常；业务层只依赖 `MiniInferError` 体系。
6. **关联日志**：在异常边界记录 `request_id` 与原始 cause，既不吞异常也不泄密。

---

## 2. 知识点大纲

```text
异常设计与资源管理
├── 2.1 异常的本质与动机
│      ├── 异常 vs 错误码（C++ 视角对照）
│      └── 什么时候该用异常、什么时候不该
├── 2.2 try/except/else/finally 与传播
│      ├── 四个子句语义
│      ├── 异常沿调用栈展开（unwinding）
│      └── EAFP vs LBYL
├── 2.3 自定义异常设计
│      ├── 异常层级（MiniInferError 家族）
│      ├── 设计原则（语义化、带上下文、稳定错误码）
│      └── raise...from... 保留因果链
├── 2.4 资源管理 & RAII
│      ├── 资源类型（文件 / DB / 网络 / 设备显存）
│      ├── RAII 思想与 Python 的对应物
│      └── 上下文管理器 __enter__/__exit__、contextlib.contextmanager
├── 2.5 释放机制横评
│      ├── finally（Python） / using（C#） / try-with-resources（Java）
│      └── 为什么 Python 项目首选 with
└── 2.6 日志与异常的关联
       ├── logger 在边界记录 cause + request_id
       └── 绝不 except Exception: pass
```

---

## 3. 详细讲解内容

### 3.1 什么是异常，为什么需要异常设计（对比错误码）

**类比（C++ 工程师最熟悉）**：你写过无数 `int ret = cudaMalloc(...); if (ret != 0) { ... }`。
错误码把「正常逻辑」和「错误处理」交织在一起，而且**调用方必须记得检查返回值**——忘了检查，bug 就静默潜伏。

```c++
// C++ 错误码风格：每一层都要手动透传
Status load_config(const char* path, Config* out) {
    Status s = read_file(path, &buf);
    if (!s.ok()) return s;                 // 必须检查，否则崩溃/脏数据
    s = parse_json(buf, out);
    if (!s.ok()) return s;
    return OkStatus();
}
```

异常的核心价值：**把「错误该去哪」和「正常逻辑」解耦**。错误会自动沿调用栈向上传播，直到有人处理它；没处理的异常会终止程序并给出完整栈——而不是悄悄返回一个被忽略的 `-1`。

| 维度 | 错误码 | 异常 |
|------|--------|------|
| 忘记处理 | 静默 bug | 程序终止 + 完整栈（更安全） |
| 跨多层的错误透传 | 每层手写 `if (!ok) return` | 自动 unwinding |
| 错误信息丰富度 | 一个 int，需额外查表 | 可携带消息、上下文对象、嵌套 cause |
| 性能 | 几乎零开销 | 抛出路径有开销（但「 happy path 」更干净） |

**何时不用异常**（给推理框架的提醒）：不要用异常做正常的控制流（例如用捕获异常来结束 generation loop）；不要用异常替代参数校验的提前返回（轻量校验用 `if` 即可）。异常用于**预期之外、需要跨越边界传达的失败**。

> 项目落点：`mini-infer` 的失败（配置错、分词错、模型执行错、缓存满）都跨模块边界，且调用方（CLI、engine）需要区分语义来做不同恢复——这正是异常的用武之地。

---

### 3.2 `try/except/else/finally` 与异常传播机制（含 EAFP vs LBYL）

四个子句职责边界（最容易讲混的地方）：

```python
try:
    risky_call()          # 1) 监控区：这里抛出的异常会被捕获
except SpecificError as e:
    handle(e)             # 2) 命中特定异常时执行
else:
    do_when_no_error()    # 3) 仅当 try 全程无异常才执行（成功路径收口）
finally:
    cleanup()             # 4) 无论是否异常、是否被 except、是否 re-raise，都执行
```

**常见误区**：有人把清理代码放进 `except` 和 `try` 各写一遍——错。`finally` 才是「无论如何都跑」的唯一正确位置。

**异常传播（unwinding）**：如果当前 `except` 没有捕获（或捕获后又 `raise`），异常继续向上抛给调用者，直到被捕获或抵达顶层。这点和 C++ 栈展开完全一致，可以用「冒泡」类比。

**EAFP vs LBYL**（Python 之道的直接体现，用在 tokenizer 上最直观）：

```python
# LBYL：Look Before You Leap（跳之前先看路）—— 先检查再操作
def encode_lbyl(vocab, text):
    if vocab is None:
        raise TokenizationError("分词器未初始化词表")
    out = []
    for word in text.split():
        if word not in vocab:          # 先做存在性检查
            raise TokenizationError(f"未登录词：{word}")
        out.append(vocab[word])
    return out

# EAFP：Easier to Ask Forgiveness than Permission（请求原谅比请求许可易）
def encode_eafp(vocab, text):
    out = []
    try:
        for word in text.split():
            out.append(vocab[word])     # 直接做，出错再说
    except KeyError as exc:
        raise TokenizationError(f"未登录词：{exc}") from exc
    return out
```

- 对 `dict`/`set` 这种「查不到就抛 `KeyError`」的结构，**EAFP 更 Pythonic**、更快（happy path 无额外检查）。
- 对「检查本身有副作用 / 检查与操作之间状态会变」的场景，**LBYL 更安全**。
- 关键是：无论哪种写法，捕获到标准异常后都要**翻译为领域异常**（`TokenizationError`），不要让 `KeyError` 泄漏到业务层。

---

### 3.3 自定义异常类的设计原则与项目实践

**异常层级（roadmap 给定，落在 `src/mini_infer/exceptions.py`）**：

```text
MiniInferError                # 所有领域异常的根，调用方可用 except MiniInferError 一网打尽
├── ConfigurationError        # 配置加载/校验失败
├── TokenizationError         # 分词器操作失败
├── ModelExecutionError       # 模型前向/生成执行失败
└── CacheCapacityError        # KV cache 容量不足
```

```python
# src/mini_infer/exceptions.py
"""mini-infer 的领域异常层级。

设计原则：
1. 库自身抛出的异常都继承自 MiniInferError，调用方可以统一兜底。
2. 每个子类对应一条清晰语义（配置/分词/模型/缓存），便于日志分类与恢复策略。
3. 不继承 RuntimeError 等标准异常——保持自己的层级干净、可控。
4. 用稳定 error_code 辅助日志/监控聚合；用结构化字段携带上下文。
"""


class MiniInferError(Exception):
    """所有 mini-infer 领域异常的基类。"""
    error_code: str = "E_INTERNAL"


class ConfigurationError(MiniInferError):
    error_code = "E_CONFIG"


class TokenizationError(MiniInferError):
    error_code = "E_TOKENIZE"


class ModelExecutionError(MiniInferError):
    error_code = "E_MODEL"


class CacheCapacityError(MiniInferError):
    error_code = "E_CACHE"

    def __init__(self, requested: int, capacity: int, *, request_id: str | None = None) -> None:
        self.requested = requested
        self.capacity = capacity
        self.request_id = request_id
        msg = f"KV cache 容量不足：请求 {requested} slot，上限 {capacity}"
        if request_id:
            msg += f"（request_id={request_id}）"
        super().__init__(msg)
```

**设计原则（讲给学员的口诀）**：
- **语义化**：名字告诉调用方「发生了哪类失败」，而不是 `MyError` / `Error1`。
- **带上下文**：把 `request_id`、容量、路径等诊断信息塞进异常，定位时不靠猜。
- **稳定错误码**：监控告警按 `error_code` 聚合，比按消息字符串可靠。
- **不要过度细分**：层级太深会变成另一种「错误码地狱」。四类足矣，需要时在消息里区分。

**`raise...from...` 保留因果链**（这是 Day 4 的硬知识点，对标 C++11 的 `std::throw_with_nested`）：

```python
# src/mini_infer/config.py（节选）
import json
from pathlib import Path

from .exceptions import ConfigurationError


def load_config(path):
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        # from exc → 异常.__cause__ 指向原始底层异常，链不断
        raise ConfigurationError(f"配置文件不存在：{path}") from exc
    except OSError as exc:
        raise ConfigurationError(f"读取配置文件失败：{path}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigurationError(f"配置文件不是合法 JSON：{path}") from exc
```

没有 `from` 时，Python 仍会把原始异常放进 `__context__`（隐式），但用 `from` 表达的「这是我主动翻译出来的」语义更精确，且 `traceback` 会打印 `The above exception was the direct cause of the following exception:`。

---

### 3.4 资源管理、RAII 思想与 `with` 上下文管理器

**资源类型对照（在 mini-infer 里全是真实场景）**：

| 资源 | 在项目的载体 | 泄漏后果 |
|------|--------------|----------|
| 文件句柄 | 词表 `vocab.txt`、配置、日志 | 句柄耗尽，OS 报错 |
| 数据库连接 | （若接外部元数据/缓存服务） | 连接池耗尽 |
| 网络连接 | 远程 tokenizer / 模型服务 adapter | 端口/连接泄漏 |
| 设备显存 | 真实 GPU 推理时的权重/activation | OOM，整进程崩 |

**RAII 思想（C++ 工程师的母语）**：Resource Acquisition Is Initialization——
资源在对象构造时获取，在析构时**确定性**释放。只要对象离开作用域，析构必跑，资源必还。

**Python 的对应物**：Python 没有可靠的析构（`__del__` 时机不确定，且循环引用时可能永不调用），所以**用上下文管理器 + `with` 语句**来复刻 RAII 的保证：进入 `with` 获取资源，离开 `with`（无论正常还是异常）一定调用 `__exit__` 释放。

```python
# src/mini_infer/engine/session.py
import logging
from typing import TYPE_CHECKING

from .exceptions import ModelExecutionError

if TYPE_CHECKING:
    from .config import ModelConfig
    from .request import GenerationResult

logger = logging.getLogger(__name__)


class ModelSession:
    """模型推理会话：持有权重/设备等重资源，用 `with` 管理生命周期。"""

    def __init__(self, config: "ModelConfig") -> None:
        self._config = config
        self._model = None
        self._owned: list[object] = []

    def __enter__(self) -> "ModelSession":
        try:
            self._model = self._load_model(self._config)   # 获取重资源
        except Exception as exc:
            # 初始化失败也要保证「已分配的部分资源」被释放（见 _release）
            self._release()
            raise ModelExecutionError("模型加载失败") from exc
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self._release()        # 无论是否异常，都释放
        return False           # 返回 falsy → 不吞异常，继续向外传播

    def _load_model(self, config):
        # 伪代码：打开文件、分配显存……把获取到的资源登记到 self._owned
        ...

    def _release(self) -> None:
        for res in reversed(self._owned):
            try:
                getattr(res, "close", lambda: None)()
            except Exception:
                logger.exception("释放资源时出错，已忽略以免掩盖原始错误")
        self._owned.clear()
        logger.info("ModelSession 资源已释放")

    def generate(self, prompt: str) -> "GenerationResult":
        if self._model is None:
            raise ModelExecutionError("会话未初始化，请使用 `with ModelSession(...) as s`")
        ...
```

```python
# 调用方（业务层）：只看到领域异常，不关心底层是文件错还是显存错
with ModelSession(config) as session:
    result = session.generate("hello")
```

**轻量写法：`contextlib.contextmanager`**（适合「一个函数就是一段资源管理」的场景，例如加载词表文件）：

```python
from contextlib import contextmanager

@contextmanager
def open_vocab(path):
    f = open(path, "r", encoding="utf-8")   # 获取
    try:
        yield f                              # 交给 with 块使用
    finally:
        f.close()                            # 释放（等价于 __exit__）

with open_vocab("vocab.txt") as f:
    ...
```

> 口诀：**RAII 在 C++ 靠析构，在 Python 靠 `with`。两者保证同一个东西——资源生命周期绑定到作用域。**

---

### 3.5 `finally` / `using` / try-with-resources 对比与选择

横向对照，给 C#/Java 都沾边的工程师一张完整心智地图：

| 机制 | 语言 | 释放保证 | 备注 |
|------|------|----------|------|
| `try/finally` | Python / 多语言 | 有（手动） | 容易漏写 `finally`，或把清理写错位置 |
| `with` 语句 | Python | 有（自动，`__exit__`） | **mini-infer 首选**；等价 RAII |
| `using` | C# | 有（`IDisposable.Dispose`） | 编译期要求实现接口，确定性 |
| `try-with-resources` | Java | 有（`AutoCloseable.close`） | 编译期约束，最「强制」 |

**选择原则（项目落地）**：
1. **Python 项目一律首选 `with`**，而不是手写 `try/finally`——可读性高、不易漏。
2. 只有当需要把「资源获取 + 释放」封装成一个可复用函数时，才用 `@contextmanager`。
3. `finally` 保留给**不适合做成上下文管理器**的清理（例如在 `__exit__` 之外还想在普通函数里兜底）。
4. 跨语言协作时：向 C#/Java 同事解释「Python 的 `with` ≈ 你们的 `using`/`try-with-resources`」即可对齐心智。

---

### 3.6 日志记录与异常信息的关联

异常负责「带走错误」，日志负责「留下痕迹」。两者在**边界**汇合：

```python
import logging
import uuid

logger = logging.getLogger(__name__)


def generate(request):
    request_id = request.id or uuid.uuid4().hex
    logger.info("推理开始", extra={"request_id": request_id})
    try:
        return _run(request)
    except MiniInferError as exc:
        # 边界记录：带上 request_id（可关联整条链路）+ exc_info（自动含 __cause__ 链）
        logger.error("推理失败", extra={"request_id": request_id}, exc_info=exc)
        raise  # 重新抛出，让上层决定如何恢复——绝不吞掉
```

**三条铁律（Day 5 日志课的前置，今天先立规矩）**：
1. **绝不 `except Exception: pass`**。静默吞异常 = 把可诊断的错误变成不可复现的玄学。至少要 `logger.exception(...)`。
2. **日志带 `request_id`**，让一次失败能在分散的日志里被串成一条线。
3. **不要往日志里写完整 prompt / token**（敏感数据）。记「prompt 长度 / token 数」即可。

```python
# ❌ 错误示范：静默吞掉，后续定位灾难
try:
    session.generate(prompt)
except Exception:
    pass

# ✅ 正确：记录并向上传播
try:
    session.generate(prompt)
except MiniInferError:
    logger.exception("generate 失败，向上抛出")
    raise
```

---

## 4. 练习设计（3 个递进，全部基于 mini-infer 真实代码场景）

> 前置假设：项目已有 `config.py`、`exceptions.py`(空壳)、`engine/request.py`、`tokenizer/` 模块。练习在其上增量构建。

### 练习 1（基础 · 22 min）：异常层级 + 配置加载错误翻译

**目标**：落地异常层级，掌握 `raise...from...`。

**任务**：
1. 在 `src/mini_infer/exceptions.py` 写入 §3.3 的 `MiniInferError` 及四个子类。
2. 在 `config.py` 实现 `load_config(path)`，按 §3.3 用 `raise...from...` 把 `FileNotFoundError` / `OSError` / `JSONDecodeError` 翻译为 `ConfigurationError`。
3. 补一个 `SamplingConfig` 的运行时校验：若 `temperature <= 0` 或 `max_tokens <= 0`，抛 `ConfigurationError`（用 LBYL，因为校验本身很轻）。

**检查点 / 预期输出**：
```python
from mini_infer.config import load_config
from mini_infer.exceptions import ConfigurationError

try:
    load_config("/no/such/file.json")
except ConfigurationError as e:
    print(type(e).__name__, "|", e.error_code)
    print("cause:", type(e.__cause__).__name__)   # 应为 FileNotFoundError
# 输出：
# ConfigurationError | E_CONFIG
# cause: FileNotFoundError
```
`e.__cause__` 非空且为底层异常类型即通过。

---

### 练习 2（进阶 · 28 min）：`ModelSession` 资源管理器 + 初始化失败清理

**目标**：用 `with` 实现 RAII 式生命周期，验证「初始化失败也释放」「异常链保留」。

**任务**：
1. 在 `engine/session.py` 实现 §3.4 的 `ModelSession`（可用一个假的「模型句柄」对象代替真实 GPU，例如一个带 `close()` 的 `FakeModelHandle`，内部计数 `opened/closes`）。
2. 故意让 `_load_model` 在某条件下抛底层异常（如 `ValueError("CUDA OOM")`），验证 `__enter__` 里 `raise ModelExecutionError(...) from exc` 且 `_release` 被调用。
3. 在 `tokenizer/adapter.py` 中：捕获第三方 tokenizer 异常并翻译为 `TokenizationError`（EAFP 风格）。

**检查点 / 预期输出**：
```python
# 用例 A：正常路径资源成对
with ModelSession(cfg) as s:
    s.generate("hi")
# 日志含 "ModelSession 资源已释放"；handle.opened == handle.closed

# 用例 B：初始化失败也释放 + 因果链
try:
    with ModelSession(broken_cfg):   # _load_model 抛 ValueError
        pass
except ModelExecutionError as e:
    print(e.__cause__.__class__.__name__)   # ValueError
    print(handle.closed)                     # True（资源已释放）
```
断言：`handle.opened == handle.closed` 且 `e.__cause__` 为实际底层异常。

---

### 练习 3（挑战 · 22 min）：异常边界统一 + 日志关联 + 业务层只依赖领域异常

**目标**：把「边界翻译 + 日志 + 业务层只认 `MiniInferError`」串成端到端。

**任务**：
1. 在 `engine/cache.py`：当请求的 cache slot 超过 `capacity` 时抛 `CacheCapacityError`（带 `requested/capacity/request_id`）。
2. 在顶层 `generate(request)` 加边界日志（§3.6）：`request_id` + `exc_info`，并 `raise` 重新抛出。
3. 写一个集成断言：模拟『配置文件缺失 + 分词器第三方异常 + cache 满』三条路径，业务调用方统一用 `except MiniInferError` 即可覆盖，且每条路径日志都带 `request_id`。

**检查点 / 预期输出**：
```python
import logging
from mini_infer.exceptions import MiniInferError, CacheCapacityError

for bad in [bad_config, bad_tokenizer, over_capacity]:
    try:
        generate(bad)
    except MiniInferError as e:
        print(type(e).__name__, getattr(e, "error_code", "?"))

# 输出（顺序可能因场景而定，但三类都应出现）：
# ConfigurationError E_CONFIG
# TokenizationError  E_TOKENIZE
# CacheCapacityError E_CACHE

# 且 pytest caplog 中每条 error 日志都含 request_id 字段，且无完整 prompt。
```
断言：所有失败都被 `MiniInferError` 捕获；`caplog` 记录中包含 `request_id`；无 `except Exception: pass`。

---

## 5. 课后测验 / 思考题

### 选择题（判断你对概念的理解）

1. 下列哪个场景**不适合**用异常？
   a) 配置文件缺失导致推理无法启动
   b) 用异常跳出正常 generation 循环
   c) KV cache 容量不足
   d) Hugging Face tokenizer 调用抛错

2. `raise ConfigurationError("bad") from exc` 中，`from exc` 的作用是？
   a) 让 `ConfigurationError` 继承 `exc` 的类型
   b) 把原始异常挂到 `__cause__`，保留因果链
   c) 抑制原始异常的栈打印
   d) 等价于 `raise ConfigurationError("bad")`

3. 关于 `try/except/else/finally`，正确的是？
   a) `else` 在 `except` 之后执行
   b) `finally` 仅在无异常时执行
   c) `else` 在 try 全程无异常时执行
   d) `finally` 中抛出的异常会覆盖原异常且不可见

4. Python 中实现 RAII 式资源管理主要靠？
   a) `__del__` 析构函数
   b) `with` 语句 + 上下文管理器
   c) 全局 atexit 注册
   d) 手动 `try/finally` 且从不遗漏

### 编码思考题

5. 写出 `contextmanager` 版 `open_vocab`，要求：文件打开失败抛 `TokenizationError` 并保留 `OSError` 因果链；正常时 `yield` 文件对象；退出时关闭。

6. 为什么 `ModelSession.__exit__` 返回 `False` 而不是 `True`？如果返回 `True` 会发生什么工程后果？（结合「静默吞异常」铁律回答）

### 思考题（开放）

7. 若 mini-infer 接入真实 GPU，模型权重显存在异常路径下未释放会怎样？用 RAII 思想设计一种「即使 `__exit__` 之前进程被 SIGKILL」也能最终回收的机制（提示：进程级/操作系统级回收）。

---

## 6. 总结与延伸阅读建议

### 今日一句话总结
**异常让错误沿边界「带上下文地」传播，上下文管理器让资源「绑定作用域地」释放；前者用 `raise...from...` 保链，后者用 `with` 保命。**

### 三条今天必须刻进肌肉记忆的规则
1. 底层异常翻译成领域异常（`MiniInferError` 家族），业务层只认领域异常。
2. 资源生命周期用 `with` 管，初始化失败也要在 `__enter__` 里释放已分配部分。
3. 绝不 `except Exception: pass`；在边界用 `logger.exception` + `request_id` 记录后重新抛出。

### 延伸阅读
- **Python 官方文档**：[Built-in Exceptions](https://docs.python.org/3/library/exceptions.html) — 异常层级与标准异常。
- **PEP 3134**：*Exception Chaining and Embedded Tracebacks* — `raise...from...` / `__cause__` / `__context__` 的权威来源。
- **`contextlib` 文档**：[contextlib — Utilities for with-statement contexts](https://docs.python.org/3/library/contextlib.html) — `@contextmanager` 与 `closing`/`suppress` 的正确用法（注意 `suppress` 也别滥用成静默吞异常）。
- **`logging` 文档**：[Logging HOWTO](https://docs.python.org/3/howto/logging.html) — `exc_info`、`LoggerAdapter` 注入 `request_id`、库代码不应配置 root logger（衔接 Day 5）。
- **《Python Cookbook》第 14 章**：异常与错误处理的高级模式（异常链、上下文管理器进阶）。
- **roadmap 衔接**：Day 5「日志与可观测性」会把今天的 `request_id` 日志升级为结构化生命周期日志；Day 6 用 `pytest.raises` + `caplog` 把这些异常/日志行为写成测试。

### 给讲师的复盘提示
- 用 C++ 错误码 → 异常的类比开场，学员接受度最高。
- 练习 2 的「假模型句柄计数 `opened/closed`」是关键可观测点，务必让学员自己 print 验证。
- 收尾时强调：今天写的异常层级和 `ModelSession`，就是 Day 25 KV cache、Day 26 scheduler 错误处理的基础——**今天的代码会一直活到 v0.1.0**。
