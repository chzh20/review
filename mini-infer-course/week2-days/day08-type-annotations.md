# Day 8：工程化类型标注 — 每日学习教程

> 所属项目：`mini-infer`（可扩展的迷你 LLM 推理流水线框架）
> 前置基础：Day 1 工程基线（`pyproject.toml` / `src` layout / 质量门禁）、Day 2 对象模型与 `dataclass`
> 学员画像：EDA 工程师，C++ 系统背景（熟悉 `using TokenId = int`、模板类型参数）
> 设计依据：`roadmap.md` Day 8「将类型作为模块间契约」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 掌握现代容器/泛型类型写法：`list[str]`、`dict[str, int]`、`T | None`（替代旧的 `Optional[T]` / `List[str]`）。
2. 理解**抽象容器** `Sequence` / `Iterable` / `Mapping` 的接口意义——面向接口而非具体类型。
3. 能用 `NewType` / `TypeAlias` / `TypedDict` / `Literal` 给领域概念起名字，让类型即文档。
4. 认识 `Any` 的**传播风险**（类型黑洞），知道何时必须排除它。
5. 分清「静态类型检查（mypy）」与「运行时校验」的**职责边界**：类型管契约，校验管非法输入。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 今日目标 + 与第一周（Day 2 dataclass）的衔接 | 3 min |
| 学习内容 1 | 现代容器类型 `list[str]` / `dict[...]` / `T \| None` | 15 min |
| 学习内容 2 | 抽象容器 `Sequence` / `Iterable` / `Mapping` | 15 min |
| 学习内容 3 | `NewType` / `TypeAlias` / `TypedDict` / `Literal` | 20 min |
| 学习内容 4 | `Any` 的传播风险 | 12 min |
| 学习内容 5 | 静态类型 vs 运行时校验的边界 | 15 min |
| 实践任务 | 引入领域类型 + 清 `Any` + 运行时校验 + `mypy --strict` | 35 min |
| 复习与收尾 | 当日回顾 + 衔接 Day 9 预告 | 5 min |

---

## 三、学习内容

### 3.1 现代容器类型

```python
# ❌ 旧写法（仍可用但风格过时）
from typing import List, Dict, Optional
def f(x: Optional[List[str]]) -> Dict[str, int]: ...

# ✅ 现代写法（Python 3.9+ 内置泛型可直接用于注解）
def f(x: list[str] | None) -> dict[str, int]: ...
```

C++ 类比：`list[str]` ≈ `std::vector<std::string>`，`dict[str,int]` ≈ `std::map<std::string,int>`；`T | None` 就是 C++17 的 `std::optional<T>`。`| None` 强制调用方处理「可能没有」的情况，等价于 `optional` 必须 `.has_value()` 检查。

### 3.2 抽象容器：面向接口而非实现

关键认知：**函数参数用 `Sequence[int]` 比 `list[int]` 更宽、更稳**——`tuple`、`list`、自定义序列都能传，且声明了「我只读，不改」。

```python
from collections.abc import Sequence, Iterable, Mapping

def encode(text: str) -> Sequence[int]: ...      # 返回只读序列
def ingest(tokens: Iterable[int]) -> None: ...     # 只迭代，不要求可下标
def get_meta(conf: Mapping[str, str]) -> str: ... # 只当映射读
```

> 口诀：**「接收用抽象（Sequence/Iterable），返回用具体（list/tuple）」**——返回具体类型给调用方更多自由，接收抽象类型则自己更宽容。

### 3.3 给领域概念起名字

这是 Day 8 最重要的一步：把「裸 `int`/`str`」升级为「有语义的领域类型」。

```python
from typing import NewType, TypeAlias, TypedDict, Literal

TokenId = NewType("TokenId", int)            # 不是别名！是「名义上不同」的类型
RequestId = NewType("RequestId", str)

# TypeAlias：给复杂类型起短名
TokenSequence: TypeAlias = "Sequence[TokenId]"

# TypedDict：结构化的配置/记录，比无约束 dict 安全
class GenerationMeta(TypedDict):
    request_id: str
    prompt_tokens: int
    decode_tokens: int

# Literal：限定枚举式的取值
StopReason = Literal["eos", "max_tokens", "cancelled"]
```

**`NewType` 的微妙之处**（易错点）：`TokenId` 运行时仍是 `int`，但 mypy 会阻止你把任意 `int` 当 `TokenId` 传。这正对标 C++ 的 `using TokenId = int` + 强类型封装——编译器帮你防止「把长度当 token id」。

### 3.4 `Any` 的传播风险

`Any` 是类型黑洞：一旦出现，mypy 对它**放弃检查**，并且会**污染**所有接触它的表达式。

```python
def load(path: str) -> Any: ...        # 返回 Any
x = load("a.json")
y = x.foo.bar.baz                       # mypy 全部放行 → 运行时才炸
```

规则：**公共 API 的返回类型绝不写 `Any`**。如果第三方库只给你 `Any`，在边界立刻用 `cast()` 或解析为具体类型。

### 3.5 静态类型 vs 运行时校验

| 维度 | 静态（mypy） | 运行时（手工 / pydantic） |
|------|--------------|---------------------------|
| 何时跑 | 开发/CI 阶段 | 程序执行到那一行时 |
| 能查 | 类型契约、拼写、`None` 遗漏 | 取值范围、文件存在、JSON 结构 |
| 不能查 | `temperature > 0` 这类**值约束** | 未经执行的代码路径 |

关键边界：`temperature: float = 0.7` 只保证「是浮点」，**不保证正数**。值的合法性必须在运行时校验（见实践任务 3，呼应 Day 4 的 `ConfigurationError`）。

---

## 四、实践任务

> 在 `src/mini_infer` 上增量修改；完成后跑 `python -m mypy --strict src` 与 `python -m pytest`。

**任务 1（基础）— 引入领域类型**
- 新建 `src/mini_infer/types.py`，定义 `TokenId = NewType("TokenId", int)`、`RequestId = NewType("RequestId", str)`、`TokenSequence: TypeAlias = "Sequence[TokenId]"`。
- 把 `tokenizer/base.py` 的 `encode` 返回类型改为 `TokenSequence`。

**任务 2（基础）— 公共 API 不出现无约束 `dict`**
- 找出现有函数里返回/接收裸 `dict` 的地方（如配置读取），改为 `Mapping[str, object]` 或具体 `TypedDict`。

**任务 3（进阶）— 清理 `Any` + 运行时校验**
- 在 `config.py` 的 `load_config` 中：把 `json.loads` 的结果**解析**为具体对象而非 `Any`；并对 `SamplingConfig` 运行校验（呼应 Day 4）：`temperature > 0`、`max_tokens > 0` 非法时抛 `ConfigurationError`。
- 用 Day 2 的 frozen `SamplingConfig` 承接：`temperature: float`、`max_tokens: int`、`stop_token_ids: tuple[int, ...]`。

**任务 4（收口）— 接入严格模式**
- 在 `pyproject.toml` 的 `[tool.mypy]` 加入 `strict = true`（或 `disallow_any_generics = true` 等近似严格配置），并跑通。

**检查点 / 预期输出**
```bash
python -m mypy --strict src
# Success: no issues found in 12 source files

python -m pytest -q
# 全绿（Day 6 已有测试不应因类型重构而红）
```
断言：`mypy --strict` 通过；`load_config` 对 `temperature<=0` 抛 `ConfigurationError`；公共 API 无裸 `dict`、无 `Any`。

---

## 五、学习重点（难点与关键点）

- **`NewType` ≠ `type alias`**：`TypeAlias` 是纯别名（可互换），`NewType` 是名义新类型（mypy 阻止混用）。这是今天最容易被忽略的区别。
- **接收抽象、返回具体**：参数用 `Sequence/Iterable/Mapping`，返回用 `list/tuple`，这条规矩决定 API 的宽容度。
- **类型不查值**：`float` 不代表「正数」。值约束必须运行时校验，且异常要翻译成 Day 4 的 `MiniInferError` 家族。
- **`Any` 是债不是糖**：每写一个 `Any`，就关掉了一块检查。优先在边界处解析掉。

---

## 六、复习与巩固

- **衔接第一周（Day 2）**：今天给 `SamplingConfig` 加类型约束，正是 Day 2「配置对象用 frozen dataclass」的自然延伸——frozen 防意外修改，类型防误用，二者互补。复习 Day 2 的 `default_factory=tuple` 为何用不可变 `tuple` 而非 `list`。
- **即时小测（自答 3 题）**：
  1. `TokenId = NewType("TokenId", int)` 后，`TokenId(5)` 与 `5` 在 mypy 眼里能互换吗？
  2. 函数接收「只读整数序列」，参数该标 `list[int]` 还是 `Sequence[int]`？为什么？
  3. `temperature: float = 0.7` 能否阻止调用方传入 `-1.0`？如果不能，谁来挡？
- **预告 Day 9**：明天用 `typing.Protocol` 把这些领域类型组织成「接口」，让 `Tokenizer` 不再依赖具体实现。

---

## 七、延伸阅读

- Python 官方：`typing` 模块文档（NewType / Protocol / TypeAlias / TypedDict / Literal）。
- PEP 484（类型提示）、PEP 613（TypeAlias）、PEP 589（TypedDict）。
- `mypy` 文档：`Strict Mode and following imports`，理解 `--strict` 打开的每一项检查。
- 衔接：Day 9 Protocol / ABC、Day 8 的 `TokenId`/`RequestId` 将直接出现在 `Tokenizer(Protocol)` 与 `Sampler(Protocol)` 签名中。
