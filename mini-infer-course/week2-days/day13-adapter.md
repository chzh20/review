# Day 13：Adapter 模式——接入 Hugging Face Tokenizer — 每日学习教程

> 所属项目：`mini-infer`
> 前置基础：Day 9 `Protocol`（依赖反转）、Day 4 `raise...from...` / `TokenizationError`、Day 3 模块边界
> 学员画像：EDA 工程师，C++ 系统背景（熟悉适配器/包装器、接口转换、错误码翻译）
> 设计依据：`roadmap.md` Day 13「隔离第三方接口和版本变化」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 区分 **Adapter（适配器）** 与 **Wrapper（包装器）**：Adapter 改变接口契约以适配目标，Wrapper 通常保留接口只加行为。
2. 掌握 **第三方依赖隔离**：核心层**绝不 `import transformers`**，所有 HF 接触面关在 adapter 里。
3. 实现 **返回值标准化**：把 HF 的 `list` / `BatchEncoding` 收敛成项目自己的 `TokenSequence`。
4. 落实 **错误翻译**：第三方异常 → `TokenizationError`，且保留因果链（`raise...from...`，呼应 Day 4）。
5. 理解 **capability detection** 与 slow/fast tokenizer 差异，并用 **fake object** 完成绝大多数测试。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 目标 + 衔接 Day 9（Protocol 让「不依赖具体类」成为可能） | 3 min |
| 学习内容 1 | Adapter vs Wrapper；第三方隔离动机 | 12 min |
| 学习内容 2 | 返回值标准化 + 错误翻译（呼应 Day 4） | 15 min |
| 学习内容 3 | capability detection / slow vs fast tokenizer | 8 min |
| 学习内容 4 | 用 fake object 测试（呼应 Day 6 fake 优先） | 8 min |
| 实践任务 | `HuggingFaceTokenizerAdapter` + 错误翻译 + fake 测试 + 可选集成测试 | 45 min |
| 复习与收尾 | 自测 + 衔接 Day 14 | 9 min |

---

## 三、学习内容

### 3.1 Adapter vs Wrapper；第三方隔离

```python
# tokenizer/adapter.py
class HuggingFaceTokenizerAdapter:
    """把 Hugging Face tokenizer 的接口『翻译』成本项目需要的 Tokenizer 协议。"""
    def __init__(self, tokenizer: object) -> None:
        self._tokenizer = tokenizer   # 只在这里持有第三方对象

    def encode(self, text: str) -> TokenSequence:
        ids = self._tokenizer.encode(text)        # 第三方调用
        return [TokenId(int(i)) for i in ids]     # 标准化为本项目类型

    def decode(self, token_ids: TokenSequence) -> str:
        return self._tokenizer.decode([int(i) for i in token_ids])
```

**关键约束**：`mini_infer.tokenizer.adapter` 是**唯一**允许接触 `transformers` 的模块。核心层（`engine`、`sampling`、`protocols`）永远 `from ... import ...` 不到 `transformers`——version 升级、API 变动的爆炸半径被锁死在这一个文件里。

**Adapter ≠ Wrapper**：Wrapper 通常「外面套一层、接口不变」；Adapter 是「外面套一层、**接口变成另一个**」。这里我们要的是后者——把 HF 的 `encode` 形态收敛成 `Tokenizer(Protocol)`。

### 3.2 返回值标准化 + 错误翻译（Day 4 闭环）

```python
from mini_infer.exceptions import TokenizationError

def encode(self, text: str) -> TokenSequence:
    try:
        ids = self._tokenizer.encode(text)
    except Exception as exc:                 # 捕获第三方异常（不假定其类型）
        raise TokenizationError(f"分词失败：{text!r}") from exc   # 翻译 + 保留因果链
    return [TokenId(int(i)) for i in ids]
```

这正是 Day 4 的 `raise...from...` 与「业务层只依赖 `MiniInferError`」在第三方边界的落地。引擎捕获到的永远是 `TokenizationError`，而非 `transformers` 的内部异常类型——第三方实现细节不外泄（接口隔离的延伸）。

### 3.3 capability detection / slow vs fast tokenizer

- **slow tokenizer**（纯 Python）vs **fast tokenizer**（Rust 后端）：fast 提供字符↔token 对齐能力等额外能力。
- **capability detection**：adapter 不假设对方有某方法，用 `hasattr` / `getattr(..., None)` 探测，缺能力就降级或抛明确 `TokenizationError`。这让 adapter 对 HF 版本差异更鲁棒。

### 3.4 用 fake object 测试（不依赖真实 HF）

Day 6 的「fake 优于 mock」在这里最重要：不要在单测里真装 `transformers`（慢、有网络/版本风险）。用一个**结构化 fake** 模拟 HF 接口即可：

```python
class FakeHFTokenizer:
    def encode(self, text): return [ord(c) for c in text]   # 简化但真实可运行
    def decode(self, ids): return "".join(chr(i) for i in ids)

def test_adapter_translates_errors(monkeypatch):
    fake = FakeHFTokenizer()
    def boom(t): raise RuntimeError("HF exploded")
    monkeypatch.setattr(fake, "encode", boom)
    with pytest.raises(TokenizationError) as ei:
        HuggingFaceTokenizerAdapter(fake).encode("x")
    assert isinstance(ei.value.__cause__, RuntimeError)   # 因果链保留
```

---

## 四、实践任务

**任务 1（基础）— 实现 adapter**
- `tokenizer/adapter.py`：`HuggingFaceTokenizerAdapter`，构造接收任意对象，持有于 `self._tokenizer`；`encode/decode` 标准化为 `TokenSequence`/str。

**任务 2（进阶）— 错误翻译**
- `encode` 用 `try/except Exception` 捕获第三方异常，翻译为 `TokenizationError` 并 `raise...from...` 保留 `__cause__`（呼应 Day 4 练习 3 验收点）。

**任务 3（进阶）— 核心层零依赖验证**
- 搜索确认：`src/mini_infer` 除 `tokenizer/adapter.py` 外，无任何 `import transformers` / `from transformers`。

**任务 4（收口）— fake 测试 + 可选集成测试**
- 单测用 `FakeHFTokenizer` 验证 round-trip 与错误翻译（monkeypatch 注入炸弹函数）。
- 可选集成测试（`@pytest.mark.integration`）：真实装 `transformers` 验证一次，标记 slow。

**检查点 / 预期输出**
```python
def test_adapter_roundtrip():
    a = HuggingFaceTokenizerAdapter(FakeHFTokenizer())
    ids = a.encode("hi"); assert a.decode(ids) == "hi"

def test_adapter_error_translated():
    fake = FakeHFTokenizer()
    monkeypatch.setattr(fake, "encode", lambda t: (_ for _ in ()).throw(RuntimeError("boom")))
    with pytest.raises(TokenizationError) as ei:
        HuggingFaceTokenizerAdapter(fake).encode("x")
    assert isinstance(ei.value.__cause__, RuntimeError)
```
断言：round-trip 正确；第三方异常被翻译为 `TokenizationError` 且 `__cause__` 保留；核心层无 `transformers` 导入。

---

## 五、学习重点（难点与关键点）

- **隔离是 Adapter 的灵魂**：记住「唯一接触点」原则——所有第三方耦合集中在 adapter 一个文件。版本升级只需改这里，不波及 Engine。
- **错误翻译 = 边界纪律**：第三方异常进了 core 层就是「内部实现泄漏」。Day 4 的铁律（业务层只认 `MiniInferError`）在第三方边界最该严格执行。
- **fake 优于真装**：单测用 `FakeHFTokenizer`，又快又稳又无外部依赖；真实 HF 只在标记 `@pytest.mark.integration` 的慢测里出现。
- **Adapter 改变接口，Wrapper 保留接口**：别把两者混为一谈，今天用的是前者。

---

## 六、复习与巩固

- **衔接 Day 9**：Adapter 之所以能「不 import 具体类」就让 Engine 用上 HF tokenizer，全靠 Day 9 的 `Tokenizer(Protocol)`。复习——`HuggingFaceTokenizerAdapter` 没继承 `Tokenizer`，但结构匹配，于是可被注入 Engine。
- **衔接 Day 4**：`raise...from...` 与 `TokenizationError` 今天在第三方边界完成闭环。复习 Day 4 练习 3 的验收「业务层只依赖 `MiniInferError`」——adapter 是这条规则最关键的执行点。
- **衔接 Day 3**：adapter 模块应处于依赖图「最外圈」，不反向依赖 core。复习 Day 3「模块依赖方向单向」。
- **三道题自测**：
  1. 为什么核心层绝不能 `import transformers`？如果允许，版本升级会带来什么风险？
  2. `HuggingFaceTokenizerAdapter` 抛出的异常，业务层捕获时应写 `except TokenizationError` 还是 `except RuntimeError`？为什么？
  3. Adapter 与 Wrapper 的本质区别是什么？今天用的是哪种？
- **预告 Day 14**：明天聊「全局状态 / Singleton」——你会发现，如果 `HuggingFaceTokenizerAdapter` 被做成全局单例，今天的测试可重复性与并行能力都会崩。Adapter 与 DI 是搭档，与 Singleton 是天敌。

---

## 七、延伸阅读

- GoF《Design Patterns》：Adapter 模式（类适配器 vs 对象适配器；今天用对象适配器）。
- Hugging Face 文档：`PreTrainedTokenizerBase` 的 `encode`/`decode`/`BatchEncoding` 形态。
- 衔接：Day 14 全局状态（Singleton 为何损害 adapter 可测性）、Day 16 CI（集成测试标记 slow）。
