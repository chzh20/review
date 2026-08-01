# Day 9：Protocol、ABC 与抽象边界 — 每日学习教程

> 所属项目：`mini-infer`
> 前置基础：Day 3 模块边界 / `__all__` / 公共 API 最小化、Day 8 类型标注（`TokenId`/`RequestId`）
> 学员画像：EDA 工程师，C++ 系统背景（熟悉抽象基类、C++20 `concept`）
> 设计依据：`roadmap.md` Day 9「结构化子类型与名义子类型如何选择」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 区分 **`abc.ABC`（名义子类型）** 与 **`typing.Protocol`（结构化子类型 / duck typing）** 的本质差异与适用场景。
2. 理解**接口隔离原则（ISP）**：接口应小而专，而非大而全。
3. 掌握**依赖反转**：高层模块（Engine）依赖抽象接口，不依赖低层细节（具体 tokenizer）。
4. 区分测试替身：**fake（真实简化实现）vs stub vs mock**，知道「fake 优先于 mock」。
5. 在 `mini-infer` 中落地 `Tokenizer(Protocol)`，并验证 `InferenceEngine` 只依赖协议不依赖实现。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 目标 + 衔接 Day 8（类型已成，今天用接口组织） | 3 min |
| 学习内容 1 | `abc.ABC` / `@abstractmethod`（名义子类型） | 12 min |
| 学习内容 2 | `typing.Protocol`（结构化子类型 / duck typing） | 15 min |
| 学习内容 3 | ABC vs Protocol 对照 + 何时用哪个 | 10 min |
| 学习内容 4 | 接口隔离、依赖反转、测试替身 | 13 min |
| 实践任务 | `Tokenizer(Protocol)` + `WhitespaceTokenizer` + `FakeTokenizer` + Engine 只依赖协议 | 40 min |
| 复习与收尾 | 三道题自测 + 衔接 Day 10 | 7 min |

---

## 三、学习内容

### 3.1 `abc.ABC`：名义子类型（需要显式继承）

```python
from abc import ABC, abstractmethod

class BaseTokenizer(ABC):
    @abstractmethod
    def encode(self, text: str) -> "Sequence[int]": ...
    @abstractmethod
    def decode(self, token_ids: "Sequence[int]") -> str: ...

class WhitespaceTokenizer(BaseTokenizer):   # 必须显式继承，否则实例化报错
    def encode(self, text: str) -> list[int]: return [...]
    def decode(self, ids): return "..."
```

C++ 类比：`BaseTokenizer(ABC)` ≈ 抽象基类，子类**必须** `: public BaseTokenizer`。缺点：所有具体类都得改继承树，侵入性强。

### 3.2 `typing.Protocol`：结构化子类型（duck typing 的类型化）

```python
from typing import Protocol, Sequence

class Tokenizer(Protocol):          # 只是一个「形状」声明，无需继承
    def encode(self, text: str) -> Sequence[int]: ...
    def decode(self, token_ids: Sequence[int]) -> str: ...

# 下面这个类【没有继承 Tokenizer】，但只要方法签名匹配，mypy 就认为它「满足协议」
class WhitespaceTokenizer:
    def encode(self, text: str) -> list[int]: return text.split()
    def decode(self, ids: Sequence[int]) -> str: return " ".join(...)
```

**核心差异（今天最重要的认知）**：
- `ABC` 是「**我说你是**」——靠继承建立关系。
- `Protocol` 是「**你长得像就是**」——靠结构（方法签名）建立关系，即结构化子类型，等同 C++20 `concept` 的「无需继承的约束」。

### 3.3 ABC vs Protocol 对照

| 维度 | `abc.ABC` | `typing.Protocol` |
|------|-----------|-------------------|
| 建立关系的方式 | 显式继承 | 结构匹配（duck typing） |
| 对第三方类的侵入 | 必须改继承 | 零侵入（HF tokenizer 不用改） |
| 运行时 | 有 `isinstance` 检查（需 `abc`） | 仅静态检查，运行时不强制 |
| C++ 类比 | 抽象基类 | C++20 `concept` |
| 适用 | 你拥有、需统一基线的类 | 隔离第三方 / 解耦高层与实现 |

**经验法则**：**隔离第三方、解耦高层模块 → 用 `Protocol`**；需要 `isinstance` 检查或共享基类状态 → 用 `ABC`。

### 3.4 接口隔离、依赖反转、测试替身

- **接口隔离（ISP）**：`Tokenizer` 只声明 `encode/decode`，不把「训练、保存词表、对齐」塞进来。调用方依赖最小接口。
- **依赖反转（DIP）**：`InferenceEngine` 依赖 `Tokenizer`（抽象），而不是 `WhitespaceTokenizer` 或 `HuggingFaceTokenizerAdapter`（细节）。这样换 tokenizer 不动 Engine——这是 Week 2 的主线。
- **测试替身选择**（呼应 Day 6）：
  - **fake**：行为简单但真实的实现（如 `FakeTokenizer` 真的做 split/join）。能抓逻辑 bug，**优先用**。
  - **stub**：只返回预设值，不关心逻辑。
  - **mock**：验证「被怎么调用」。只在依赖不可构造（真 GPU）时才用。

---

## 四、实践任务

**任务 1（基础）— 定义 `Tokenizer(Protocol)`**
- 新建 `src/mini_infer/protocols.py`，写入：
```python
from typing import Protocol, Sequence
from .types import TokenId, TokenSequence

class Tokenizer(Protocol):
    def encode(self, text: str) -> TokenSequence: ...
    def decode(self, token_ids: TokenSequence) -> str: ...

class Sampler(Protocol):     # 预告 Day 11
    def sample(self, logits: list[float]) -> TokenId: ...
```

**任务 2（基础）— 实现两个满足协议的具体类**
- `tokenizer/whitespace.py`：`WhitespaceTokenizer`（真实按空格切分，可带简单词表）。
- `tokenizer/fake.py`：`FakeTokenizer`——`encode` 把每个字符映射为 `ord(c)`，`decode` 还原。这是 Day 6 已用的替身，今天正式定义为满足 `Tokenizer` 协议。

**任务 3（进阶）— 让 `InferenceEngine` 只依赖协议**
- 改造 `engine/engine.py`：构造函数接收 `tokenizer: Tokenizer`（协议类型），内部**不 import** 任何具体 tokenizer 类。
- 写一段 `generate` 调用，分别用 `WhitespaceTokenizer` 和 `FakeTokenizer` 注入，验证行为一致。

**检查点 / 预期输出**
```python
from mini_infer.engine import InferenceEngine
from mini_infer.tokenizer.whitespace import WhitespaceTokenizer
from mini_infer.tokenizer.fake import FakeTokenizer

eng_a = InferenceEngine(tokenizer=WhitespaceTokenizer())
eng_b = InferenceEngine(tokenizer=FakeTokenizer())   # 类型检查通过（都满足协议）
assert isinstance(eng_a.tokenizer, WhitespaceTokenizer)
assert isinstance(eng_b.tokenizer, FakeTokenizer)
```
断言（mypy + 运行）：两个 engine 均能 `generate`；`engine.py` 中**没有** `from .tokenizer.whitespace import ...` 这类具体 import（依赖反转成立）。

---

## 五、学习重点（难点与关键点）

- **Protocol 不要求继承**：这是反直觉点。学员常误以为「要实现协议就得继承它」。强调：Protocol 是编译期/静态期的形状约束，运行时不介入。
- **ABC vs Protocol 的抉择**：记住口诀——「**隔离第三方用 Protocol，需要 isinstance 用 ABC**」。Day 13 接 Hugging Face 时 Protocol 的价值会彻底显现。
- **依赖反转是本周主线**：今天第一次让 Engine「不知道」具体 tokenizer 是谁。Day 10 的 composition、Day 12 的 Factory、Day 13 的 Adapter 都是这条线的延伸。
- **fake 优先**：`FakeTokenizer` 是真实实现，不是 mock。它能验证「算得对」，mock 只能验证「被怎么调」。

---

## 六、复习与巩固

- **衔接第一周（Day 3）**：Day 3 讲「公共 API 与内部模块」「循环导入」——今天把那个抽象升级成「接口层」。复习 `protocols.py` 应放在依赖图的**最底层**（被各方依赖，不依赖任何人），避免引入新循环。
- **衔接 Day 8**：今天的 `Tokenizer(Protocol)` 签名直接用了 Day 8 的 `TokenId`/`TokenSequence`，类型已就绪。
- **三道题自测**：
  1. 不修改 `HuggingFaceTokenizer` 源码，如何让 mypy 认为它满足你的 `Tokenizer` 协议？（答：Protocol 结构化匹配，无需改它。）
  2. 什么场景必须用 `abc.ABC` 而非 `Protocol`？（答：需要运行时 `isinstance` 检查或共享基类逻辑。）
  3. `InferenceEngine` 依赖 `Tokenizer` 协议而非 `WhitespaceTokenizer` 具体类，这遵循了哪条设计原则？
- **预告 Day 10**：明天把 Engine 从「一个大类」拆成「组合多个组件」，你将看到 Protocol 如何支撑「任意组件可替换」。

---

## 七、延伸阅读

- Python 官方：`typing.Protocol` 文档；`abc` 模块文档。
- PEP 544（Protocols / 结构化子类型）。
- 《Design Patterns》（GoF）：Strategy / Dependency Inversion 原始定义。
- 衔接：Day 10 组合、Day 11 Strategy（Sampler 即 Protocol）、Day 13 Adapter（隔离第三方，Protocol 是基石）。
