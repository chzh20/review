# Day 11：Strategy 模式——采样算法 — 每日学习教程

> 所属项目：`mini-infer`
> 前置基础：Day 9 `Protocol`、Day 10 组合注入、Day 8 `TokenId`/`NewType`、Day 6 `parametrize`/`pytest.raises`
> 学员画像：EDA 工程师，C++ 系统背景（熟悉策略模式、函数指针、`std::mt19937` 种子）
> 设计依据：`roadmap.md` Day 11「将变化行为从 Engine 中剥离」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 理解 **Strategy 模式**：把「会变化的行为」（采样算法）抽象成一个可替换的接口，而非硬编码在 Engine 里。
2. 区分 **无状态策略** 与 **有状态策略**：采样器通常无状态，更易测试。
3. 掌握 **随机数种子与可重复性**：固定种子 → 结果可复现 → 测试可信。
4. 识别 **数值边界条件**：非法 `temperature`、`top_k <= 0` 必须明确报错。
5. 在 `mini-infer` 中实现 `GreedySampler` / `TopKSampler`（可选 `TemperatureSampler`），并全部接入 Day 10 的组合结构。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 目标 + 衔接 Day 10（Sampler 是第一个即插即用组件） | 3 min |
| 学习内容 1 | Strategy 接口设计（行为参数化） | 12 min |
| 学习内容 2 | 无状态 vs 有状态策略 | 8 min |
| 学习内容 3 | 随机数种子与可重复性 | 12 min |
| 学习内容 4 | 数值边界条件 | 8 min |
| 实践任务 | 实现 Greedy/TopK/Temperature + 契约测试 | 45 min |
| 复习与收尾 | 自测 + 衔接 Day 12 | 12 min |

---

## 三、学习内容

### 3.1 Strategy 接口设计

把「从 logits 选下一个 token」这个变化点抽成协议（Day 9 已预告）：

```python
# sampling/base.py
from typing import Protocol
from mini_infer.types import TokenId

class Sampler(Protocol):
    def sample(self, logits: list[float]) -> TokenId: ...
```

引擎只依赖协议，不在 `generate` 里写 `if strategy == "greedy"`：

```python
# engine 内部
next_id = self._sampler.sample(logits[:, -1])
```

**价值**：新增一种采样策略，只需加一个实现，**不改 Engine**（对比 Day 10 的继承爆炸）。这正是 Strategy 模式解决的核心问题。

### 3.2 无状态 vs 有状态策略

- **无状态**（推荐）：`sample(logits)` 只看输入，不含内部可变状态。同样的输入永远给同样的输出（给定随机源）。最易测试、最易并发。
- **有状态**（谨慎）：若采样器内部维护历史（如某些 penalty 策略），必须在构造时注入随机源并文档化状态语义。

采样器属于前者——无状态，种子只影响「随机性来源」，不影响「是否可复现」。

### 3.3 随机数种子与可重复性

```python
import random

class GreedySampler:
    def sample(self, logits: list[float]) -> TokenId:
        # 贪心：永远选最大 logit，不依赖随机 → 天然可重复
        return TokenId(int(max(range(len(logits)), key=lambda i: logits[i])))

class TopKSampler:
    def __init__(self, k: int, *, seed: int | None = None) -> None:
        if k <= 0:
            raise ValueError("top_k must be positive")
        self._k = k
        self._rng = random.Random(seed)   # 固定 seed → 可重复
    def sample(self, logits):
        topk = sorted(range(len(logits)), key=lambda i: logits[i], reverse=True)[:self._k]
        return TokenId(self._rng.choice(topk))
```

**可重复性测试**：同一个 `seed`，两次 `sample` 结果一致；不同 `seed` 可能不同。这把概率行为变成确定性测试对象。

### 3.4 数值边界条件

| 输入 | 期望行为 |
|------|----------|
| `temperature <= 0` | 抛 `ValueError`（或 Day 4 的 `ConfigurationError`，取决于落点） |
| `top_k <= 0` | 抛 `ValueError` |
| `top_k == 1` | 等价于 greedy（确定性） |
| 空 `logits` | 抛明确错误，不 IndexError 静默炸 |

边界条件要在构造函数或 `sample` 入口用 LBYL 提前校验（呼应 Day 4 轻量校验用 `if`）。

---

## 四、实践任务

**任务 1（基础）— 实现 `GreedySampler`**
- `sampling/greedy.py`：永远选 argmax；单测断言「对任意 logits，返回最大值的下标」。

**任务 2（基础）— 实现 `TopKSampler`**
- `sampling/top_k.py`：取 top-k 后随机选；`k<=0` 抛错；`k==1` 退化为贪心（确定性）。

**任务 3（进阶，可选）— `TemperatureSampler`**
- `sampling/temperature.py`：`softmax(logits / temperature)` 后按概率采样；`temperature<=0` 抛错。

**任务 4（进阶）— 契约测试（呼应 Day 10 组合 + Day 6）**
- 用 `@pytest.mark.parametrize` 覆盖：
  - greedy 永远选最大 logit；
  - `top_k=1` 与 greedy 输出一致（确定性）；
  - 固定 `seed` 时 `TopKSampler` 两次结果相同；
  - `temperature<=0` / `top_k<=0` 抛 `ValueError`。
- 把 `Sampler` 注入 `InferenceEngine`（Day 10），验证 `generate` 用不同采样器产出不同结果但接口一致。

**检查点 / 预期输出**
```python
def test_greedy_picks_argmax():
    s = GreedySampler()
    assert s.sample([1.0, 3.0, 0.5]) == TokenId(1)

def test_topk1_equals_greedy():
    g = GreedySampler()
    t = TopKSampler(k=1, seed=0)
    logits = [0.1, 2.0, 0.5]
    assert t.sample(logits) == g.sample(logits)

def test_topk_seed_reproducible():
    a = TopKSampler(k=3, seed=42); b = TopKSampler(k=3, seed=42)
    assert a.sample([1,2,3,4]) == b.sample([1,2,3,4])

def test_invalid_temperature():
    with pytest.raises(ValueError):
        TemperatureSampler(temperature=0.0)
```
断言：4 组测试全绿；`Sampler` 经 Day 10 组合注入 Engine 后 `generate` 行为正确。

---

## 五、学习重点（难点与关键点）

- **Strategy = 把 `if/elif` 变成对象**：当 Engine 里出现「根据策略名分支」时，就是该用 Strategy 的信号。今天把它落到 `Sampler(Protocol)`。
- **无状态优先**：采样器无状态 → 测试无需重置、并发无需加锁。若未来策略有状态，必须在构造时显式注入随机源。
- **可重复性 = 可信测试**：概率代码不「固定种子」就无法写断言。今天建立 `seed` 约定，Day 18 benchmark 还会用到。
- **边界要早抛**：`temperature<=0` 等用 LBYL 在入口拦截，抛清晰异常（可翻译为 Day 4 的 `ConfigurationError`）。

---

## 六、复习与巩固

- **衔接 Day 10**：今天实现的 `Sampler` 系列，正是 Day 10 组合结构里第一个「即插即用」的组件。复习——Engine 依赖 `Sampler` 协议而非具体类，所以加 `TemperatureSampler` 不改 Engine。
- **衔接 Day 6**：测试用 `@pytest.mark.parametrize` + `pytest.raises` 直接复用 Day 6 工具箱；契约测试「所有 sampler 过同一组测试」是本周核心能力。
- **衔接 Day 8**：`TokenId = NewType(...)` 今天第一次作为返回值类型出现，类型即文档，防止把「下标」当「token id」混用。
- **三道题自测**：
  1. 若 Engine 里写 `if sampler == "topk": ... else: ...`，违反了哪条原则？如何用 Strategy 消除？
  2. 为什么采样器最好是「无状态」的？有状态会带来什么测试难题？
  3. 如何为一句「随机采样」写确定性测试？
- **预告 Day 12**：明天用 `Factory` 把「字符串 `kind` + 配置 dict」自动变成 `Sampler` 对象，`build_engine` 的组合根将因此不再手写 `if/elif`。

---

## 七、延伸阅读

- GoF《Design Patterns》：Strategy 模式原始定义。
- Python `random` 模块：`random.Random(seed)` 的确定性语义。
- 衔接：Day 12 Factory（对象创建自动化）、Day 11 的契约测试会升级为「Factory 注册表」的验证。
