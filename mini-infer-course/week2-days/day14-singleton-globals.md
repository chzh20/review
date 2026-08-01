# Day 14：Singleton、全局状态与配置管理 — 每日学习教程

> 所属项目：`mini-infer`
> 前置基础：Day 10 依赖注入、Day 12 Factory、Day 13 Adapter、Day 6 测试组织
> 学员画像：EDA 工程师，C++ 系统背景（熟悉单例、全局变量、线程安全陷阱）
> 设计依据：`roadmap.md` Day 14「理解 Singleton，而不是默认采用 Singleton」

---

## 一、学习目标（当天要掌握的核心知识点）

1. 理解 **「模块本身就是进程级单实例命名空间」**——Python 不需要手写 Singleton 也能有单实例。
2. 识别 **Singleton 的隐式依赖**：谁先 import 谁被初始化，造成隐藏的启动顺序耦合。
3. 认识 **全局可变状态如何污染测试**：执行顺序依赖、状态清理困难、并行测试风险。
4. 区分 **cache 与 singleton**：cache 有 eviction 与容量，singleton 没有，二者不可混为一谈。
5. 掌握 **lazy initialization** 与 **进程/线程安全** 边界，并能把全局单例**重构为依赖注入**。

---

## 二、时间分配（建议总时长 ≈ 2 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 目标 + 衔接 Day 13（Adapter 与 DI 是搭档，与 Singleton 是天敌） | 3 min |
| 学习内容 1 | 模块即单例；Singleton 隐式依赖 | 12 min |
| 学习内容 2 | 全局状态如何污染测试 | 12 min |
| 学习内容 3 | cache vs singleton；lazy init 与线程安全 | 12 min |
| 学习内容 4 | 重构为依赖注入（DI） | 8 min |
| 实践任务 | 造全局 `ModelRegistry` → 观察三痛点 → 重构注入式 + 决策文档 | 45 min |
| 复习与收尾 | **Week 2 综合自测** + 衔接 Week 3 | 8 min |

---

## 三、学习内容

### 3.1 模块即单例；Singleton 隐式依赖

Python 的模块在进程内只被 import 一次，模块级对象天然是「单实例」。因此**多数情况下你不需要手写 Singleton**——直接把状态放进模块级变量或模块函数即可。

手写 Singleton 反而引入隐式依赖：
```python
# ❌ 反例：全局单例，谁先 import 谁初始化
class ModelRegistry:
    _instance = None
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._models = {}   # 首次实例化就跑初始化
        return cls._instance

registry = ModelRegistry()   # 模块加载即创建；测试 A 改了它，测试 B 读到脏数据
```
`__new__` 里藏了「首次创建时的副作用」，调用方完全不知情——这是最大的隐患。

### 3.2 全局状态如何污染测试

把上面 `registry` 当全局单例后，三个痛点立刻出现（Day 6 的测试组织会因此崩溃）：
1. **执行顺序依赖**：测试 B 依赖测试 A 先跑并把某模型注册进去，打乱顺序就失败。
2. **状态清理困难**：测试结束必须记得 `registry.clear()`，忘了就泄漏到下一个测试。
3. **并行测试风险**：`pytest -n` 多进程/多线程同时改同一个全局 dict → 数据竞争、偶发失败。

这正是 Day 6 反复强调「fake 优于 mock、测试要独立」的反面教材：**全局可变状态是测试独立性的头号杀手**。

### 3.3 cache vs singleton；lazy init 与线程安全

| 维度 | cache | singleton |
|------|-------|-----------|
| 容量/淘汰 | 有容量、有 eviction | 无淘汰，常驻 |
| 语义 | 「可能miss、可能被清」 | 「永远在、唯一」 |
| 测试 | 可清空重建 | 全局唯一，难重置 |

**lazy initialization**：首次使用时才创建（如 `functools.cached_property`、模块级 `if not loaded`）。线程安全上：CPython 的 import 有 GIL 保护，但**运行期**懒加载若有竞态仍需 `threading.Lock`——不要假设「Python 单线程思维」安全。

### 3.4 重构为依赖注入

把全局单例变成「谁用谁持有」：
```python
# ✅ 重构：普通类，无全局实例
class ModelRegistry:
    def __init__(self) -> None:
        self._models: dict[str, Model] = {}
    def register(self, name, model): self._models[name] = model

# 使用方自己持有，测试时各自 new 一个干净的
registry = ModelRegistry()
engine = InferenceEngine(registry=registry, ...)   # 注入（Day 10）
```
每个测试 `new` 一个 `ModelRegistry`，互不干扰；并行安全；生命周期由持有者决定。

---

## 四、实践任务

**任务 1（基础）— 先造痛点**
- 实现全局 `ModelRegistry`（模块级 `registry = ModelRegistry()`），在 `engine` 里直接 `from .registry import registry` 使用。
- 写两个测试：A 注册模型、`test_lookup` 查找；B 不注册直接 `test_lookup` 期望为空。先顺序跑通，再 `pytest -p no:randomly` 打乱顺序，观察 B 因 A 的残留数据而失败。

**任务 2（进阶）— 观察并书面记录三痛点**
- 记录：执行顺序依赖、状态清理困难、并行风险各一例（截屏/日志）。

**任务 3（进阶）— 重构为注入式**
- 删除模块级 `registry` 单例；`ModelRegistry.__init__` 不再有全局副作用。
- 改 `InferenceEngine` 构造接收 `registry: ModelRegistry` 参数（DI，呼应 Day 10）。
- 重写测试：每个测试自行 `registry = ModelRegistry()`，断言顺序无关、可并行。

**任务 4（收口）— 决策文档**
- 写 `docs/singleton-guidelines.md`，列出「何时可用 / 何时不可用」：
```text
何时可使用：
- 不可变、无业务状态的进程级元数据
- 生命周期与进程完全一致
- 有明确 reset 机制
何时不可使用：
- request state / 可变配置 / 测试依赖 / GPU 资源生命周期
```

**检查点 / 预期输出**
```python
# 重构后，两个测试各自持有干净 registry，顺序无关
def test_a():
    reg = ModelRegistry(); reg.register("m", FakeModel())
    assert reg.lookup("m") is not None
def test_b():
    reg = ModelRegistry()               # 全新，不被 test_a 污染
    assert reg.lookup("m") is None
```
断言：重构后打乱顺序 / `pytest -n` 并行均稳定通过；`docs/singleton-guidelines.md` 存在且内容覆盖「可用/不可用」清单。

---

## 五、学习重点（难点与关键点）

- **「模块即单例」**：先想清楚——你大概率不需要手写 Singleton，模块级状态已经够用，且更透明。
- **隐式依赖最危险**：Singleton 把「初始化副作用」藏进 `__new__/import`，调用方无感。能显式注入就别隐式全局。
- **cache ≠ singleton**：这是高频误解。cache 可被清、有容量；singleton 唯一常驻。混用会导致「想清掉却清不掉」。
- **DI 是 Singleton 的解药**：Day 10 的依赖注入今天正式成为「消除全局状态」的工程手段——两者在本周形成闭环。

---

## 六、复习与巩固（含 Week 2 综合自测）

- **本周串讲**：Day 8 类型 → Day 9 协议 → Day 10 组合 → Day 11 Strategy → Day 12 Factory → Day 13 Adapter → Day 14 全局状态。主线是「**让项目可替换、可隔离、无全局耦合**」。
- **衔接第一周（综合）**：
  - Day 1 质量门禁（mypy/pytest/ruff）→ Day 8 的 `--strict` 接入。
  - Day 3 模块边界 → Day 9 Protocol / Day 13 adapter 隔离。
  - Day 4 异常层级/因果链 → Day 13 adapter 错误翻译闭环。
  - Day 5 日志 → Day 10 `MetricsSink`、Day 11 采样可观测。
  - Day 6 测试替身 → Day 9 FakeTokenizer、Day 11/12 契约测试、Day 14 全局状态反面教材。
- **Week 2 综合自测（不看资料口答 5 题）**：
  1. `Protocol` 与 `abc.ABC` 本质区别？各适合什么场景？
  2. 如何用组合重构 `GreedyHuggingFaceLoggedEngine`？关键改动是什么？
  3. 新增一个 `TopPSampler`，理想情况下要改几处代码？分别是哪几处？
  4. `HuggingFaceTokenizerAdapter` 抛出的异常，业务层该 `except` 什么类型？为什么？
  5. 全局 `ModelRegistry` 单例为什么损害测试？如何修复？
- **预告 Week 3**：下周进入 Packaging / CI / 并发 / PyTorch 最小 Transformer——本周的「可替换组件 + 严格类型 + 无全局耦合」是那些内容能顺利展开的前提，`mypy --strict` 通过是硬门槛。

---

## 七、延伸阅读

- 《Python Cookbook》相关章节：模块级单例、`__new__` 陷阱。
- 《Effective Python》：优先组合、避免隐式全局状态。
- 《Refactoring》：「Replace Global Reference with Injectable Dependency」。
- 衔接：Day 16 CI（严格类型 + 分层测试是 CI 门禁）、Day 17 并发（全局状态在并发下最致命）。
