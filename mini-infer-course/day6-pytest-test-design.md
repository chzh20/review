# Day 6：pytest 测试设计 — 课程方案

> 所属项目：`mini-infer`（可扩展的迷你 LLM 推理流水线框架）
> 前置基础：Day 2 对象模型（`SamplingConfig` frozen dataclass / `InferenceRequest`）、Day 3 模块边界、Day 4 异常设计（`MiniInferError` 层级 / `raise...from...`）、Day 5 日志与可观测性（`generate()` 生命周期日志 + `caplog`）
> 学员画像：EDA 工程师，C++ 系统背景（熟悉 GoogleTest / Catch2 的 TEST / SetUp / EXPECT_THROW / TEST_P）
> 设计依据：`roadmap.md` Day 6「测试行为，而不是绑定内部实现」

---

## 0. 课程概览与时间分配（总时长 ≈ 2.8 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 课程目标、与 Day 4/5 的衔接（异常/日志已成测试对象） | 5 min |
| 3.1 | 测试哲学：测行为而非实现 + Arrange–Act–Assert | 12 min |
| 3.2 | `fixture`：可复用测试上下文（类比 GoogleTest SetUp） | 18 min |
| 3.3 | 参数化测试 `parametrize`（类比 `TEST_P`） | 12 min |
| 3.4 | 测试三件套：`tmp_path` / `monkeypatch` / `pytest.raises` | 18 min |
| 3.5 | 测试分层：单元 / 集成 / 契约 + mock 的合理边界 | 10 min |
| 3.6 | 落到项目：`tests/` 目录结构与命名约定 | 8 min |
| 练习 1 | unit 层：`SamplingConfig` 参数化 + 异常链测试 | 22 min |
| 练习 2 | fixture + `tmp_path`：tokenizer 临时词表 + 日志捕获 | 28 min |
| 练习 3 | integration 层：CLI 集成测试 + 契约测试 | 22 min |
| 收尾 | 课后测验讲解 + 总结与延伸阅读 | 14 min |

> 标注「可压缩」：3.5、3.6 可合并为 12 min；练习 3 的契约测试可作进阶选做。核心不可删：**AAA、fixture、parametrize、pytest.raises、tmp_path、分层结构与命名**。

---

## 1. 课程目标

学完今天，学员应当能够：

1. **确立哲学**：区分「测行为」与「绑实现」，写出的测试在重构后依然稳定。
2. **用对 fixture**：用 `@pytest.fixture` 构建可复用、有作用域、可组合的测试上下文，替代重复的 SetUp 代码。
3. **批量覆盖**：用 `parametrize` 把「同一逻辑、多组输入」压缩成一个测试，避免复制粘贴。
4. **掌握三件套**：`tmp_path`（临时文件）、`monkeypatch`（安全替换依赖）、`pytest.raises`（异常断言，含 `__cause__` 检查）。
5. **分层与边界**：区分单元 / 集成 / 契约测试；知道 mock 该用在哪、fake 在何时更优。
6. **落地结构**：在 `mini-infer` 中按 `tests/unit` 与 `tests/integration` 组织测试，并用 marker 标记慢测试，衔接 Day 16 的 CI。

---

## 2. 知识点大纲

```text
pytest 测试设计
├── 2.1 测试哲学
│      ├── 测行为而非实现（重构稳定性）
│      └── Arrange–Act–Assert（AAA）
├── 2.2 fixture
│      ├── 定义与注入（按名传参）
│      ├── 作用域 function/module/session
│      ├── yield fixture（teardown）
│      └── 组合与 conftest.py
├── 2.3 参数化 parametrize
│      ├── 多组输入一个测试
│      └── 与 GoogleTest TEST_P 类比
├── 2.4 测试三件套
│      ├── tmp_path（临时目录，自动清理）
│      ├── monkeypatch（安全替换，自动恢复）
│      └── pytest.raises（+ excinfo / __cause__）
├── 2.5 分层与 mock 边界
│      ├── 单元 / 集成 / 契约
│      └── mock 合理边界：外部依赖才 mock，domain 用 fake
└── 2.6 项目落地
       ├── tests/unit + tests/integration
       ├── conftest.py 共享 fixture
       └── marker：@pytest.mark.integration（衔接 Day 16 CI）
```

---

## 3. 详细讲解内容

### 3.1 测试哲学：测行为而非实现 + Arrange–Act–Assert

**核心一句话**：测试锁定的是「对外可观察的行为 / 契约」，不是「内部怎么实现的」。否则每做一次无害重构，测试就成片崩——测试反而成了重构的阻力。

```python
# ❌ 绑实现：断言内部私有属性，重构改个名就红
def test_config():
    cfg = load_config("x.yaml")
    assert cfg._raw["temperature"] == 0.7     # 内部细节，脆弱

# ✅ 测行为：断言公开契约（字段值 / 异常 / 副作用）
def test_config():
    cfg = load_config("x.yaml")
    assert cfg.temperature == 0.7             # 公开 API
    assert cfg.max_tokens == 32
```

**AAA 三段式**（所有测试框架通用，GoogleTest 里你也这么写）：

| 阶段 | 职责 | 在 mini-infer 的示例 |
|------|------|----------------------|
| **Arrange** | 准备输入、状态、依赖 | 构造 `SamplingConfig`、`tmp_path` 词表 |
| **Act** | 调用被测行为 | `session.generate(prompt)` |
| **Assert** | 检查可观察结果 | 输出文本正确 / 抛 `MiniInferError` / 日志含 `request_id` |

> 口诀：**Arrange 摆场面，Act 做动作，Assert 看结果。** 三段清晰分离，测试才好读、好修。

---

### 3.2 `fixture`：可复用测试上下文（类比 GoogleTest SetUp）

**类比**：GoogleTest 的 `SetUp()` / `TearDown()` 把准备逻辑从每个 TEST 抽出来。pytest 的 `fixture` 是同一个想法的「升级版」——但更灵活：可按**名字注入**、有**作用域**、可**互相依赖组合**。

```python
import pytest
from mini_infer.config import SamplingConfig

@pytest.fixture
def sampling_config():
    # Arrange 的复用：每个用到它的测试都拿到一个干净实例
    return SamplingConfig(temperature=0.7, max_tokens=16)

def test_temperature(sampling_config):
    assert sampling_config.temperature == 0.7

def test_max_tokens(sampling_config):
    assert sampling_config.max_tokens == 16
```

**三个进阶点（新手最容易踩）**：

1. **作用域**：`@pytest.fixture(scope="function|module|session")`。`function`（默认）每个测试重建；`session` 整个测试会话只建一次（适合昂贵的模型加载）。
2. **yield 做 teardown**：`yield` 之前的代码是 setup，之后的代码是 teardown（即使测试失败也跑）。
3. **组合与 `conftest.py`**：fixture 可以依赖其他 fixture；把跨文件共享的 fixture 放进 `tests/conftest.py`，自动对所有测试可见，无需 import。

```python
@pytest.fixture
def temp_vocab(tmp_path):            # 依赖内置 fixture tmp_path
    vocab = tmp_path / "vocab.txt"
    vocab.write_text("hello\nworld\n")
    yield vocab                      # 测试用完后再往下走
    # （tmp_path 本身会被 pytest 自动清理，这里也可做额外收尾）

@pytest.fixture
def fake_tokenizer():
    return FakeTokenizer()          # 一个轻量真实现，非 mock
```

---

### 3.3 参数化测试 `parametrize`（类比 `TEST_P`）

**类比**：C++ 里你用 `TEST_P` + `INSTANTIATE_TEST_SUITE_P` 把「同一逻辑、多组数据」合成一组测试。pytest 的 `@pytest.mark.parametrize` 是同一个意图的直白写法。

```python
import pytest
from mini_infer.config import SamplingConfig
from mini_infer.exceptions import ConfigurationError

@pytest.mark.parametrize("temperature,max_tokens,should_raise", [
    (0.7, 16, False),
    (0.0, 16, True),     # temperature 必须 > 0
    (-1.0, 16, True),
    (0.7, 0, True),      # max_tokens 必须 > 0
    (0.7, -5, True),
])
def test_sampling_config_validation(temperature, max_tokens, should_raise):
    if should_raise:
        with pytest.raises(ConfigurationError):
            SamplingConfig(temperature=temperature, max_tokens=max_tokens)
    else:
        cfg = SamplingConfig(temperature=temperature, max_tokens=max_tokens)
        assert cfg.temperature == temperature
```

**收益**：5 组数据 = 1 个测试函数，pytest 会展开成 5 个独立用例，失败时能精确定位是哪一组。比复制 5 个 `test_xxx_1/2/3` 强太多，且改动校验规则只改一处。

---

### 3.4 测试三件套：`tmp_path` / `monkeypatch` / `pytest.raises`

这三件是 Day 6 实战的「工具箱」。

**① `tmp_path`（内置 fixture）**：一个 `Path` 指向本次测试专用的临时目录，**测试结束自动删除**。适合写词表、配置、缓存文件。
```python
def test_load_vocab(tmp_path):
    vocab = tmp_path / "vocab.txt"
    vocab.write_text("hello\nworld\n")
    tok = WhitespaceTokenizer.from_file(vocab)
    assert tok.encode("hello world") == [0, 1]
```

**② `monkeypatch`**：在测试期间**安全替换**属性 / 函数 / 环境变量，退出自动恢复——不会污染其他测试。
```python
def test_tokenizer_adapter_error(monkeypatch):
    # 把第三方 tokenizer 的 encode 替换成必抛异常，验证 adapter 翻译
    def boom(text):
        raise RuntimeError("HF exploded")
    monkeypatch.setattr("mini_infer.tokenizer.adapter._hf_encode", boom)
    with pytest.raises(TokenizationError):
        adapter.encode("hi")
```

**③ `pytest.raises`**：断言「此处应抛某异常」。类比 GoogleTest 的 `ASSERT_THROW` / `EXPECT_THROW`。可捕获 `excinfo` 进一步检查类型、消息、甚至 Day 4 讲的 `__cause__` 因果链。
```python
def test_config_missing_cause(tmp_path):
    missing = tmp_path / "nope.json"
    with pytest.raises(ConfigurationError) as excinfo:
        load_config(missing)
    # 验证 Day 4 的 raise...from... 因果链真的保留
    assert isinstance(excinfo.value.__cause__, FileNotFoundError)
    assert excinfo.value.error_code == "E_CONFIG"
```

---

### 3.5 测试分层：单元 / 集成 / 契约 + mock 的合理边界

```text
单元测试 (unit)        集成测试 (integration)      契约测试 (contract)
┌──────────┐          ┌──────────────────┐        ┌──────────────────┐
│ 单模块隔离 │          │ 多模块端到端       │        │ Adapter 满足协议   │
│ 快、无 I/O │          │ CLI → engine → ...│        │ 第三方边界不破约   │
└──────────┘          └──────────────────┘        └──────────────────┘
```

- **单元测试**：测单个模块，快、无真实 I/O、依赖用 fake/mock 替身。如 `test_config.py`、`test_request.py`。
- **集成测试**：多个模块串起来跑，如 `test_cli.py` 从命令行到输出。
- **契约测试**：验证「适配器满足对外协议」，例如 `HuggingFaceTokenizerAdapter` 的 `encode/decode` 语义符合 `Tokenizer` Protocol——防止第三方升级悄悄破坏接口。

**mock 的合理边界（最容易被过度使用）**：

| 该 mock 的 | 不该 mock 的 |
|------------|--------------|
| 外部/不可用依赖（HF tokenizer、GPU、网络、时间） | **被测对象本身** |
| 有副作用或慢的协作方 | 领域逻辑（用 **fake 真实现** 更优） |

> 关键取舍：**fake 优于 mock**。Day 3 的 `FakeTokenizer` 是一个「行为简单但真实」的实现，比 `Mock()` 更能抓出逻辑 bug——mock 只验证「被怎么调用」，fake 验证「算得对不对」。只在依赖不可构造（如真 GPU）时才用 mock/monkeypatch。

---

### 3.6 落到项目：`tests/` 目录结构与命名约定

直接对齐 roadmap Day 6 的目标结构：

```text
tests/
├── conftest.py              # 共享 fixture（temp_vocab / fake_tokenizer / caplog 辅助）
├── unit/
│   ├── test_config.py       # SamplingConfig 参数化 + load_config 异常链
│   ├── test_request.py      # InferenceRequest 不可变 / 不共享默认 stop
│   └── test_logging.py      # generate 生命周期日志 + 敏感数据防护
└── integration/
    └── test_cli.py          # CLI 端到端 + Adapter 契约
```

约定与技巧：
- 文件/函数命名 `test_*`；fixture 名见 `conftest.py`。
- 慢测试打 `@pytest.mark.integration`，CI 里可 `pytest -m "not integration"` 先跑快的。
- `conftest.py` 里放跨测试 fixture，pytest 自动发现，无需 import。
- 这直接衔接 **Day 16 CI**：分层 + marker 让「快速反馈」与「慢速集成」分轨跑。

---

## 4. 练习设计（3 个递进，全部基于 mini-infer 真实代码场景）

### 练习 1（基础 · 22 min）：unit 层 — `SamplingConfig` 参数化 + 异常链测试

**目标**：用 parametrize 批量覆盖配置校验；用 `pytest.raises` 验证 Day 4 的因果链。

**任务**：
1. 在 `tests/unit/test_config.py` 用 `@pytest.mark.parametrize` 测试 `SamplingConfig`：`temperature>0` 与 `max_tokens>0` 非法时抛 `ConfigurationError`，合法时字段正确。
2. 异常链测试：`load_config` 对缺失文件抛 `ConfigurationError`，且 `excinfo.value.__cause__` 为 `FileNotFoundError`、`error_code == "E_CONFIG"`（承接 Day 4）。
3. 回顾 Day 2：断言 `SamplingConfig` 是 frozen，重新赋值应抛 `FrozenInstanceError`。

**检查点 / 预期输出**：
```bash
python -m pytest tests/unit/test_config.py -v
# 输出（节选）：
# test_config.py::test_sampling_config_validation[0.7-16-False] PASSED
# test_config.py::test_sampling_config_validation[0.0-16-True]  PASSED
# test_config.py::test_sampling_config_validation[-1.0-16-True] PASSED
# test_config.py::test_load_config_missing_cause PASSED
# test_config.py::test_frozen_immutable PASSED
```
断言：parametrize 展开为 5 个用例全绿；`__cause__` 类型断言通过；frozen 赋值抛错。

---

### 练习 2（进阶 · 28 min）：fixture + `tmp_path` + 日志捕获

**目标**：用 fixture 抽离准备逻辑，验证 Day 5 的日志契约。

**任务**：
1. 在 `tests/conftest.py` 写 fixture：
   - `temp_vocab(tmp_path)`：写临时词表文件并返回 `Path`。
   - `fake_tokenizer`：返回 `FakeTokenizer`（Day 3 已实现）。
2. 在 `tests/unit/test_logging.py` 用 `caplog` 验证：
   - 正常路径包含 `start / tokenize / end` 生命周期日志，且 `request_id` 一致（承接 Day 5）。
   - 错误路径日志带 `request_id` 与 `exc_info`（异常上下文）。
   - **敏感数据防护**：完整 prompt 不出现于任何记录。
3. 用 `temp_vocab` fixture 驱动的 tokenizer 跑一次 `generate`，断言 `prompt_tokens` 字段正确。

**检查点 / 预期输出**：
```python
def test_normal_path_lifecycle(caplog, fake_tokenizer, temp_vocab):
    with caplog.at_level(logging.INFO, logger="mini_infer"):
        generate(make_request("hello"), tokenizer=fake_tokenizer)
    msgs = [r.getMessage() for r in caplog.records]
    assert any("推理开始" in m for m in msgs)
    assert any("分词完成" in m for m in msgs)
    assert any("推理结束" in m for m in msgs)
    assert all(r.request_id != "-" for r in caplog.records)

def test_no_full_prompt(caplog, fake_tokenizer):
    with caplog.at_level(logging.DEBUG, logger="mini_infer"):
        generate(make_request("这是一段敏感prompt内容"), tokenizer=fake_tokenizer)
    full = "\n".join(r.getMessage() for r in caplog.records)
    assert "这是一段敏感prompt内容" not in full
```
断言：三个 `caplog` 断言（生命周期 / 异常上下文 / 敏感防护）全绿；fixture 注入生效，无需重复构造。

---

### 练习 3（挑战 · 22 min）：integration 层 — CLI 集成 + 契约测试

**目标**：端到端验证 CLI，并用契约测试守住第三方边界。

**任务**：
1. 在 `tests/integration/test_cli.py` 写 CLI 集成测试：调用 `mini_infer --version`（断言退出码 0、版本字符串），再调用一次 `mini_infer --prompt "hello"`（断言输出非空、退出码 0）。用 `subprocess.run([sys.executable, "-m", "mini_infer.cli", ...])` 或框架的 CLI runner。
2. 契约测试：构造 `HuggingFaceTokenizerAdapter(fake_hf_tokenizer)`，断言其 `encode/decode` 满足 `Tokenizer` Protocol 的语义（round-trip 字段一致）；并用 fake 替换后验证 `InferenceEngine` **只依赖协议、不依赖具体实现**（承接 Day 3 / Day 9 的 Protocol 思想）。
3. 给集成测试打 `@pytest.mark.integration`，演示 `pytest -m "not integration"` 只跑快的、`pytest -m integration` 只跑慢的。

**检查点 / 预期输出**：
```bash
python -m pytest tests/ -v -m "not integration"   # 只跑 unit，秒级
python -m pytest tests/ -v -m integration         # 只跑 CLI/契约
# 输出：
# tests/integration/test_cli.py::test_cli_version PASSED
# tests/integration/test_cli.py::test_cli_prompt PASSED
# tests/integration/test_cli.py::test_adapter_contract PASSED
```
断言：CLI 集成测试通过（退出码/输出正确）；契约测试证明 `engine` 不依赖具体 tokenizer 实现；marker 过滤生效。

---

## 5. 课后测验 / 思考题

### 选择题（概念自检）

1. 「测行为而非实现」意味着？
   a) 断言内部私有变量以保细节
   b) 锁定对外可观察的行为 / 契约，重构内部不改测试
   c) 重构必须同步改测试
   d) mock 越多测试越稳

2. pytest `fixture` 与 GoogleTest `SetUp` 相比，最关键的增强是？
   a) 必须写在类里
   b) 可按名注入、有作用域、可组合依赖
   c) 只能用于 teardown
   d) 等价于 `main`

3. `pytest.raises` 最接近 GoogleTest 的？
   a) `ASSERT_TRUE`  b) `ASSERT_THROW` / `EXPECT_THROW`  c) `TEST_P`  d) `fixture`

4. 关于 mock 的合理边界，正确的是？
   a) 被测对象也该 mock 掉
   b) 尽量多 mock 以彻底隔离
   c) 外部/不可用依赖才 mock；领域逻辑优先用 fake 真实现
   d) 从不使用 mock

### 编码思考题

5. 用 `@pytest.mark.parametrize` 写一个测试：当 `temperature<=0` 或 `max_tokens<=0` 时，`SamplingConfig(...)` 抛 `ConfigurationError`；并用 `pytest.raises` 捕获断言。

6. 写一个 `yield` 风格的 fixture `temp_vocab(tmp_path)`：创建临时词表文件、yield 其 `Path`、结束后打印一行清理日志。说明 `yield` 前后代码分别在什么时机执行。

### 开放思考题

7. 契约测试（contract test）与单元测试的本质区别是什么？在 mini-infer 里，为什么 `HuggingFaceTokenizerAdapter` 需要契约测试，而不能简单地把它「mock 掉就算测过」？（提示：mock 只验证「被怎么调用」，契约验证「接口语义不破」。）

---

## 6. 总结与延伸阅读建议

### 今日一句话总结
**测试锁定行为而非实现：用 fixture 抽准备、parametrize 压输入、pytest.raises 验异常、tmp_path/monkeypatch 管依赖；单元/集成/契约分层，mock 只对外、fake 留给领域。**

### 三条今天必须刻进肌肉记忆的规则
1. 断言**公开契约**（字段值 / 异常 / 副作用），不要断言内部私有细节——重构时才不会「假红」。
2. `fixture` 治重复、`parametrize` 治多输入、`pytest.raises(excinfo)` 能查 `__cause__`；三者组合覆盖绝大多数场景。
3. mock 只用于外部/不可用依赖；领域逻辑用 **fake 真实现** 更可靠；慢测试打 marker，衔接 CI。

### 延伸阅读
- **pytest 官方文档**：[pytest documentation](https://docs.pytest.org/) — 尤其 fixtures、parametrize、`tmp_path`、`monkeypatch`、`pytest.raises` 各页。
- **《Unit Testing Principles, Practices, and Patterns》**（Vladimir Khorikov）：系统讲「测行为不测实现」「fake vs mock 取舍」，与今日 3.5 完全同频。
- **GoogleTest Primer**（对照阅读）：`TEST` / `SetUp` / `EXPECT_THROW` / `TEST_P` 与 pytest 概念一一映射，帮助把 C++ 测试直觉迁移过来。
- **`tests/conftest.py` 与 fixture 作用域**：深入 `scope="session"` 在「昂贵模型加载」场景的提速价值。
- **roadmap 衔接**：Day 16 CI 把 `unit / integration` 与 `-m integration` marker 接成「快速反馈 + 慢速集成」双轨；Day 7 的 code review 五维度里「testability」直接检验今天的测试质量。

### 给讲师的复盘提示
- 开场用 GoogleTest 的 `SetUp` / `TEST_P` / `EXPECT_THROW` 三处类比，学员能立刻把 pytest 概念挂到既有心智上。
- 练习 1 的「`__cause__` 类型断言」是 Day 4→Day 6 的闭环验收，务必让学员亲眼看测试失败一次（删掉 `from exc` 后再跑）再补回。
- 练习 2 的 `caplog` 三断言直接复用 Day 5 的契约，体现「Day 4 异常 + Day 5 日志 → Day 6 测试」的累积链。
- 收尾强调：今天写下的 `tests/` 结构、fake/mock 边界、marker 规范，是后续 24 天所有新增模块（cache/scheduler/model）测试的统一底座——**这套测试纪律会一直活到 v0.1.0 的 50～100 个测试**。
