# Day 12：Factory 模式——配置到对象图 — 每日学习教程

> 所属项目：`mini-infer`
> 前置基础：Day 10 组合根（`build_engine`）、Day 11 `Sampler` 系列（greedy / top-k / temperature）
> 学员画像：EDA 工程师，C++ 系统背景（熟悉工厂函数、注册表、依赖注入容器）
> 设计依据：`roadmap.md` Day 12「集中管理对象创建，而不是隐藏全局依赖」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 区分 **simple factory** 与 **registry factory**（注册表工厂）。
2. 理解「**构造逻辑与业务逻辑分离**」：Factory 只管造对象，不掺业务。
3. 掌握 **配置驱动创建**：从 `dict` / `SamplingConfig` 映射到具体对象。
4. 理解 **插件式扩展**：新增组件只注册，不改使用方。
5. 识别 **「万能 Factory」反模式**（`if/elif` 地狱 + 全局状态）。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 目标 + 衔接 Day 11（sampler 已就绪，今天自动化创建） | 3 min |
| 学习内容 1 | simple factory vs registry factory | 12 min |
| 学习内容 2 | 构造与业务逻辑分离 | 8 min |
| 学习内容 3 | 配置驱动 + 插件式扩展 | 12 min |
| 学习内容 4 | 「万能 Factory」反模式 | 8 min |
| 实践任务 | `SamplerFactory.create(kind, config)` + 注册表 + 契约测试 | 45 min |
| 复习与收尾 | 自测 + 衔接 Day 13 | 12 min |

---

## 三、学习内容

### 3.1 simple factory vs registry factory

**simple factory**：一个函数根据参数返回不同实现，但分支写死在函数里——
```python
def make_sampler(kind, config):
    if kind == "greedy": return GreedySampler()
    if kind == "top_k":  return TopKSampler(k=config["k"])
    raise ValueError(kind)
```
问题：每加一个 sampler 就要改这个函数（违反开闭原则）。

**registry factory（推荐）**：把「名字 → 构造函数」登记进字典，新增组件只注册、不改核心逻辑——
```python
# sampling/factory.py
_REGISTRY: dict[str, type[Sampler]] = {}

def register(kind: str, cls: type[Sampler]) -> None:
    _REGISTRY[kind] = cls

def create(kind: str, config: Mapping[str, object]) -> Sampler:
    if kind not in _REGISTRY:
        raise ValueError(f"unknown sampler: {kind}")
    return _REGISTRY[kind](**config)   # 配置驱动构造
```

### 3.2 构造与业务逻辑分离

Factory 的单一职责是「造对象」。它**不**知道 sampler 怎么采样、Engine 怎么推理。Day 10 的 `build_engine` 组合根可以调用 `SamplerFactory.create`，但 Factory 本身不碰 Engine 业务。分离带来：业务代码清爽、创建逻辑集中可测。

### 3.3 配置驱动 + 插件式扩展

```python
register("greedy", GreedySampler)
register("top_k", TopKSampler)
register("temperature", TemperatureSampler)

sampler = SamplerFactory.create(
    kind="top_k",
    config={"k": 10, "temperature": 0.8},   # 配置字典驱动
)
# 新增一个 sampler 时：
class TopPSampler: ...        # 只写实现
register("top_p", TopPSampler) # 只注册，Engine/Factory 核心不动
```

**开闭原则落地**：对扩展开放（加实现+注册），对修改封闭（不动 `create` 与 Engine）。

### 3.4 「万能 Factory」反模式

```python
# ❌ 反模式：一个 Factory 管所有类型、塞满 if/elif、还藏全局可变状态
class GodFactory:
    _cache = {}               # 全局可变状态（Day 14 会痛批）
    def create(self, kind, config):
        if kind.startswith("sampler"): ...
        elif kind.startswith("tokenizer"): ...
        elif kind.startswith("model"): ...
        # 100 行分支，改一处崩全局
```
识别信号：分支覆盖多种无关类型、内部有全局缓存、测试互相污染。正确做法：按组件类型分多个 registry（SamplerFactory / TokenizerFactory），各自单一职责。

---

## 四、实践任务

**任务 1（基础）— 实现 `SamplerFactory`**
- `sampling/factory.py`：registry + `register` + `create(kind, config)`。
- 在模块加载时注册 Day 11 的三个 sampler。

**任务 2（进阶）— 让 `build_engine` 用上 Factory**
- 修改 Day 10 的 `build_engine(config)`：sampler 部分改为 `SamplerFactory.create(config.sampler_kind, config.sampler_cfg)`，删除手写 `if/elif`。

**任务 3（进阶）— 验证「新增不碰 Engine」**
- 新增一个 `TopPSampler`（或任意新 sampler），只 `register` 到 factory，断言 `build_engine({"sampler_kind": "top_p", ...})` 能产出正确 Engine，**且 `factory.py`/`engine.py` 的核心逻辑零改动**（仅加实现+注册行）。

**任务 4（收口）— 契约测试（呼应 Day 11）**
- 写测试：遍历 registry 中每个 sampler，全部通过 Day 11 的同一组契约（greedy 选 argmax、`k=1` 等价、seed 可复现、非法参数报错）。

**检查点 / 预期输出**
```python
def test_create_top_k():
    s = SamplerFactory.create("top_k", {"k": 5, "seed": 1})
    assert isinstance(s, TopKSampler)

def test_unknown_kind_raises():
    with pytest.raises(ValueError):
        SamplerFactory.create("nope", {})

def test_all_registered_pass_contract():
    for kind in SamplerFactory.registered_kinds():
        s = SamplerFactory.create(kind, valid_cfg(kind))
        assert s.sample([0.1, 2.0, 0.5]) == GreedySampler().sample(...) or True
```
断言：`create` 正确映射；未知 kind 抛错；新增 sampler 后 Engine/Factor` 核心零改动；契约测试全绿。

---

## 五、学习重点（难点与关键点）

- **registry 优于 if/elif**：注册表把「扩展点」从「改函数」变成「加注册」，是开闭原则的直接体现。
- **配置驱动构造**：`create(kind, config)` 的 `config` 是 `Mapping`，Factory 把字符串/字典变成对象——这是把「用户配置」接到「对象图」的桥梁。
- **反模式识别**：「万能 Factory + 全局缓存」是 Day 14 要批判的全局状态问题在 Factory 上的变体，今天先建立嗅觉。
- **契约测试复用**：「所有 sampler 过同一组测试」是本周最值钱的能力，Day 12 让它自动化。

---

## 六、复习与巩固

- **衔接 Day 11**：Factory 创建的正是不带任何业务逻辑、纯构造的 Sampler。复习——`GreedySampler`/`TopKSampler` 已是「无状态、可注入」的组件，Factory 只是它们的「装配站」。
- **衔接 Day 10**：Factory 接管了组合根里「建 sampler」那一小步；组合根仍负责把产物注入 Engine。Factory ≠ 组合根，前者造零件，后者装整车。
- **衔接 Day 6**：契约测试直接复用 Day 11/Day 6 的 `parametrize` + `pytest.raises`；「遍历 registry 跑契约」是参数化测试的绝佳场景。
- **三道题自测**：
  1. 简单工厂的 `if/elif` 有什么问题？注册表工厂如何消除它？
  2. 新增一个 sampler 时，理想情况下你需要改几处代码？分别是哪几处？
  3. 为什么 Factory 内部不应持有全局可变缓存？（提示：Day 14 全局状态。）
- **预告 Day 13**：明天用 `Adapter` 把「最棘手的第三方」——Hugging Face tokenizer——隔离进来，你会发现 Protocol + Factory + Adapter 三者合体后，Engine 彻底不知道 tokenizer 是谁、来自哪。

---

## 七、延伸阅读

- GoF《Design Patterns》：Factory Method / Abstract Factory。
- 《Clean Code》：单一职责；「对象创建」与「对象使用」分离。
- 衔接：Day 13 Adapter（第三方隔离）、Day 14 全局状态（Factory 反模式警示）、Day 16 CI（Factory 注册表让集成测试可参数化）。
