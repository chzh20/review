# 第二周教学计划：类型系统、抽象接口与设计模式

> 所属课程：`mini-infer` 一个月 Python 工程实践课程（Day 8–14）
> 学员画像：EDA 领域工程师，C++ 系统背景，可用 A100 算力
> 教学主线：用类型定义边界，用组合替代脆弱继承，把 Strategy / Factory / Adapter 落到真实模块边界
> 配套文档：`roadmap.md`（Week 2）、`llm-career-course-design.md`（W2 = 类型与设计模式）

---

## 一、课程主题与目标

### 1.1 本周核心主题

**「从『给每行补类型』升级到『用类型与接口定义模块边界』。」**

第一周解��了「项目能跑、能测、有日志」；第二周解决「项目能演化」——
让 `mini-infer` 在不破坏已有行为的前提下，支持可替换的 tokenizer / sampler / model，
并把第三方依赖（Hugging Face）关进 Adapter 的笼子里。

本周不是讲「Python 设计模式大全」，而是围绕一个真实工程问题展开：

> 当推理引擎要同时支持内置 tokenizer、HF tokenizer、greedy/top-k/temperature 采样时，
> 怎么组织代码才不会变成 `GreedyHuggingFaceLoggedEngine` 这种继承怪兽？

### 1.2 学员完成本周后应掌握的知识点

| 维度 | 具体知识�� |
|------|-----------|
| 类型作为契约 | `NewType` / `TypeAlias` / `TypedDict` / `Literal`；抽象容器 `Sequence/Iterable/Mapping`；`Any` 的传播风险；静态类型 vs 运行时校验 |
| 抽象边界 | `abc.ABC` vs `typing.Protocol`；结构化子类型 vs 名义子类型；接口隔离；依赖反转；测试替身（fake / stub） |
| 组合优于继承 | is-a / has-a；继承膨胀；mixin 边界；委托；依赖注入；组合根（composition root） |
| 三大模式落地 | Strategy（采样）、Factory（对象图）、Adapter（第三方隔离） |
| 反模式识别 | Singleton 的隐式依赖、全局状态导致的测试污染、cache 与 singleton 的区别、lazy init 与线程安全 |

### 1.3 学员完成本周后应掌握的技能（可验收）

1. 能用 `Protocol` / `ABC` 定义一组稳定接口，并让业务层只依赖接口不依赖实现。
2. 能把一个继承层级重构为「组合 + 构造注入」的形式，且任意组件可被测试替身替换。
3. 能实现可替换的 `Sampler`（greedy / top-k / temperature），并通过契约测试。
4. 能写 `Factory`，使新增一个组件时**不修改** `Engine`，只扩展实现与注册。
5. 能写 `Adapter` 把 Hugging Face tokenizer 隔离在核心层之外，并把第三方异常翻译为领域异常。
6. 能指出 Singleton / 全局状态为什么损害可测试性，并在需要时改用注入式。

> 对应 `roadmap.md` 的 **Week 2 自测标准**：不看资料能否——
> 比较 ABC 与 Protocol；用 composition 重构继承层级；实现可替换 sampler；
> 隔离第三方 tokenizer；解释 Singleton 为什么损害测试。

---

## 二、教学内容大纲（按逻辑顺序）

> 难度与依赖严格递进：先会「标类型」→ 再会「定接口」→ 再会「换实现」→ 最后识别「什么时候别用」。

### Day 8：工程化类型标注
- 现代容器类型：`list[str]`、`dict[str, int]`、`T | None`
- 抽象容器：`Sequence` / `Iterable` / `Mapping`（面向接口而非具体类型）
- 给领域起名字：`TypeAlias`、`TypedDict`、`Literal`、`NewType`（`TokenId`、`RequestId`）
- `Any` 的传播风险（类型黑洞）
- 静态类型（mypy）与运行时校验（pydantic / 手工）的边界与配合
- **实战**：为 `mini-infer` 引入领域类型；公共 API 不出现无约束 `dict`；清理 `Any`；配置输入运行时校验；`mypy --strict` 加入 CI

### Day 9：Protocol、ABC 与抽象边界
- `abc.ABC` / `@abstractmethod`（名义子类型）
- `typing.Protocol`（结构化子类型 / duck typing）
- 接口隔离原则（ISP）
- 依赖反转（高层不依赖低层细节）
- 测试替身：fake / stub / mock 的职责边界
- **实战**：定义 `Tokenizer(Protocol)`；实现 `WhitespaceTokenizer` 与 `FakeTokenizer`；验证 `InferenceEngine` 只依赖协议不依赖实现

### Day 10：Composition 优先于继承
- is-a 与 has-a 的语义差别
- 继承层级膨胀的典型征兆（`GreedyHuggingFaceLoggedEngine(BaseEngine)`）
- mixin 的适用边界
- 委托（delegation）与依赖注入（DI）
- 组合根（composition root）：对象图在一个地方组装
- **实战**：把 `InferenceEngine` 组合为 `Tokenizer + Model + Sampler + Scheduler + MetricsSink`；禁止继承扩展；构造注入；测试时替换任意组件

### Day 11：Strategy 模式——采样算法
- Strategy 接口设计（行为参数化）
- 无状态策略 vs 有状态策略
- 随机数种子与可重复性
- 数值边界条件（`temperature` 非法、`top_k <= 0`）
- **实战**：实现 `GreedySampler`、`TopKSampler`（可选 `TemperatureSampler`）；`Sampler(Protocol)`；测试 greedy 永远选最大 logit、`top_k=1` 等价于 greedy、固定种子可重复、非法 temperature 明确报错

### Day 12：Factory 模式——配置到对象图
- simple factory vs registry factory
- 构造逻辑与业务逻辑分离
- 配置驱动创建（从 `dict` / `SamplingConfig` 到对象）
- 插件式扩展（注册表）
- 反模式：「万能 Factory」把所有创建塞进一个 `if/elif` 地狱
- **实战**：`SamplerFactory.create(kind="top_k", config={...})`；新增 sampler **不修改** `Engine`；为所有 sampler 写同一组契约测试

### Day 13：Adapter 模式——接入 Hugging Face Tokenizer
- Adapter 与 wrapper 的差异（是否改变接口契约）
- 第三方依赖隔离（核心层不 `import transformers`）
- 返回值标准化（HF 的 `list` / `BatchEncoding` → 项目自己的 `Sequence[int]`）
- 错误翻译（第三方异常 → `TokenizationError`，呼应 Day 4 的 `raise...from...`）
- capability detection / slow vs fast tokenizer
- **实战**：`HuggingFaceTokenizerAdapter`；用 fake object 完成绝大多数测试；可选集成测试验证真实 tokenizer

### Day 14：Singleton、全局状态与配置管理
- 模块本身即可作为进程级单实例命名空间
- Singleton 的隐式依赖（谁先 import 谁被初始化）
- 全局可变状态导致测试互相污染、执行顺序敏感、并行风险
- cache 与 singleton 的区别（cache 有 eviction，singleton 没有）
- lazy initialization 与进程/线程安全
- **实战**：先实现全局 `ModelRegistry` 观察三大痛点 → 重构为 `InferenceEngine(registry=...)` 注入式；产出「何时用 / 何时不用」决策文档

---

## 三、教学活动安排（每日时间分配）

> 基准：每天 **约 2 小时**（与 roadmap 的 1.5–2.5h 一致）。
> 三段式：概念（30–35min）→ 编码（70–80min）→ 测试/复盘（15–25min）。
> 形式符号：📖 讲授　💡 讨论　🔧 实践　✅ 验收

| 天 | 主题 | 时间轴（约 120min） | 活动分配 |
|----|------|--------------------|----------|
| **Day 8** | 工程化类型标注 | 0–30 📖 现代类型语法 + `NewType` 动机（类比 C++ 强类型 `using TokenId = int`）<br>30–105 🔧 给 `mini-infer` 公共 API 标类型、清理 `Any`、写运行时校验<br>105–120 ✅ `mypy --strict` 通过、提交一个类型 PR | 📖 25%　💡 5%　🔧 65%　✅ 5% |
| **Day 9** | Protocol / ABC | 0–35 📖 ABC vs Protocol（类比 C++ abstract class vs C++20 concept）<br>35–50 💡 讨论：何时名义、何时结构化<br>50–110 🔧 写 `Tokenizer(Protocol)` + `WhitespaceTokenizer` + `FakeTokenizer`<br>110–120 ✅ 用 `FakeTokenizer` 跑通 `InferenceEngine` | 📖 30%　💡 12%　🔧 50%　✅ 8% |
| **Day 10** | 组合优于继承 | 0–30 📖 继承膨胀征兆 + DI / 组合根（C++ 工程师天然熟悉）<br>30–45 💡 现场重构演示：把 `GreedyHuggingFaceLoggedEngine` 拆开<br>45–110 🔧 改造 `InferenceEngine` 为组合结构，构造注入<br>110–120 ✅ 替换任意组件跑测试 | 📖 25%　💡 12%　🔧 55%　✅ 8% |
| **Day 11** | Strategy 采样 | 0–30 📖 Strategy 接口 + 可重复性与种子<br>30–45 💡 讨论 greedy/top-k/temperature 的数值边界<br>45–105 🔧 实现 `GreedySampler`/`TopKSampler`+ 契约测试<br>105–120 ✅ 断言 `top_k=1 == greedy`、非法温度报错 | 📖 25%　💡 12%　🔧 50%　✅ 13% |
| **Day 12** | Factory | 0–30 📖 simple vs registry factory + 反模式<br>30–40 💡 讨论「新增组件不碰 Engine」如何落地<br>40–105 🔧 `SamplerFactory.create` + 注册表 + 契约测试<br>105–120 ✅ 加一个 sampler 验证 Engine 零改动 | 📖 25%　💡 8%　🔧 55%　✅ 12% |
| **Day 13** | Adapter | 0–35 📖 Adapter vs wrapper + 错误翻译（呼应 Day 4）<br>35–50 💡 讨论核心层为何不能 `import transformers`<br>50–110 🔧 `HuggingFaceTokenizerAdapter` + fake 测试 + 可选集成测试<br>110–120 ✅ 第三方异常被翻译为 `TokenizationError` | 📖 30%　💡 12%　🔧 50%　✅ 8% |
| **Day 14** | Singleton 与全局状态 | 0–30 📖 模块即单例 + Singleton 三大痛点<br>30–50 💡 讨论：cache ≠ singleton，线程安全边界<br>50–110 🔧 先造全局 `ModelRegistry` 复现痛点 → 重构为注入式<br>110–120 ✅ 写「何时用/不用」决策文档 | 📖 25%　💡 15%　🔧 50%　✅ 10% |

**每周固定动作（来自课程工程约束）**
- 本周至少一次 code review（建议 Day 14 收尾时做 Week 1+2 联合 review）。
- 源码阅读固定到具体 tag / commit，避免路径随版本漂移。

---

## 四、作业与评估

### 4.1 本周作业（每日收尾 + 周末综合）

| 类型 | 任务 | 要求 |
|------|------|------|
| 每日练习 | Day 8–14 的实战练习全部落地为 `mini-infer` 代码 | 进入 `src/mini_infer`，带类型标注与测试 |
| 周中作业（Day 10 后） | 把 Day 2 的 `SamplingConfig` 用 `Protocol`/`NewType` 重新约束 | 公共 API 不出现无约束 `dict` |
| 周末大作业 | 为 `Engine` 配置一份「组件可替换」证明：用 `FakeTokenizer` + `GreedySampler` 跑通一次 `generate()`，再换成 `HuggingFaceTokenizerAdapter` + `TopKSampler` 跑通 | 同一份 `Engine` 代码，**不修改**即可换实现 |
| 文档作业 | Day 14 产出 `docs/singleton-guidelines.md`（何时用/不用）+ `docs/import-boundaries.md` 更新 | 决策有依据，非口号 |

### 4.2 评估方式（过程 + 结果）

**A. 过程性评估（每日打卡）**
- 每日 `pytest` + `mypy --strict` + `ruff` 全绿才算当天完成（呼应 Week 1 已搭好的质量门禁）。
- 每节练习的「✅ 验收」环节即当日最小达标线。

**B. 结果性评估（Week 2 输出成果，对标 roadmap）**

学员应达到：

- [ ] 能用 `Protocol` / `ABC` 定义稳定接口
- [ ] 能解释并演示「何时用 composition」
- [ ] 能将 Strategy / Factory / Adapter 应用于真实模块边界
- [ ] 能识别 Singleton / 全局状态的测试风险
- [ ] `mini-infer` 已支持**可替换 tokenizer 和 sampler**
- [ ] 类型检查**严格模式通过**

**C. 自测题（不看资料，对标 Week 2 自测标准）**

1. 口述：ABC 与 Protocol 的本质区别？各自适合什么场景？
2. 现场重构：把一段三层继承的 `Engine` 改成组合注入（白板/代码均可）。
3. 编码：新增一个 `TopPSampler`，要求**不修改** `Engine` 与 `Factory` 的已有逻辑。
4. 诊断：给一段因全局 `ModelRegistry` 导致测试顺序敏感的代码，指出问题并给出注入式修复。
5. 解释：为什么 cache 不是 singleton？

---

## 五、先修知识衔接（与第一周的连贯性）

本周不是另起炉灶，而是把第一周已经埋下的地基正式「封顶」：

| 第一周已建（Day） | 第二周如何承接 |
|------------------|----------------|
| **Day 1** `src` layout、`pyproject.toml`、可编辑安装 | Day 8 的 `mypy --strict` 作为质量门禁之一直接接入 Day 1 的 CI 骨架 |
| **Day 2** `dataclass` 不可变配置（`SamplingConfig`） | Day 8 `NewType` / `TypedDict` 给数据类加领域语义；Day 11 的 `Sampler` 直接消费 `SamplingConfig` |
| **Day 3** 模块边界、`__all__`、循环导入消除、公共 API 最小化 | Day 9 `Protocol` / 接口隔离是 Day 3「公共 API 与内部模块」的抽象层升级；Day 13 Adapter 是依赖反转的落地 |
| **Day 4** `MiniInferError` 异常层级、`raise...from...`、资源管理器 | Day 13 的「第三方异常 → `TokenizationError`」正是 Day 4 异常翻译与 `raise...from...` 的直接应用；Day 10 的组合对象图包含 Day 4 的 `ModelSession` 资源管理 |
| **Day 5** `request_id` 生命周期日志、敏感数据防护 | Day 10 的 `MetricsSink`、Day 11 的采样器可通过 Day 5 的结构化日志记录耗时与决策，形成可观测链路 |
| **Day 6** `pytest` fixture / 参数化 / `pytest.raises` / 契约测试 / fake 优于 mock | Day 9 的 `FakeTokenizer`、Day 11 的可重复性测试、Day 12 的契约测试，全部复用 Day 6 的测试替身与断言技巧；Day 14 的「全局状态污染测试」正是 Day 6 测试组织知识的反向印证 |

**一句话主线**：第一周让项目「能跑、能测、能报错、能记录」；第二周让项目「能换、能扩、能隔离、能长期演化」。
异常层级（W1-D4）、日志（W1-D5）、测试（W1-D6）是本周所有练习的「验收探针」——
学员写的每个新组件，都要能被第一周搭好的异常/日志/测试三件套所覆盖。

---

## 六、教学提示（给讲师）

- **C++ 类比锚点**：`Protocol` ≈ C++20 `concept`（结构化子类型，无需继承）；`ABC` ≈ 抽象基类；依赖注入、组合根对 C++ 系统工程师是母语级概念，可少讲多练。
- **反模式优先**：Day 10 先让学员亲手写一个 `GreedyHuggingFaceLoggedEngine`，再拆——痛苦感能强化「组合优于继承」的记���。
- **契约测试贯穿**：Day 11/12 的「所有 sampler 过同一组测试」是本周最值钱的能力，提前预告它会在 Week 3 的 CI 双轨（快速/慢速）里被复用。
- **不要过度 mock**：呼应 Day 6 的「fake 优于 mock」，Adapter 测试用 fake object 而非 mock 第三方，既快又稳。
- **承上启下**：Week 3 的 Packaging / CI / 并发 / Transformer 最小实现，都依赖本周的「可替换组件 + 严格类型」——本周末 `mypy --strict` 通过是硬门槛，否则 Week 3 会反复被类型问题绊住。

---

## 附：第二周 → 成果物清单（可直接核对）

```text
mini-infer/
├── src/mini_infer/
│   ├── protocols.py          # Day 9: Tokenizer(Protocol) 等稳定接口
│   ├── types.py              # Day 8: TokenId / RequestId (NewType) 等
│   ├── sampling/
│   │   ├── base.py           # Day 11: Sampler(Protocol)
│   │   ├── greedy.py         # Day 11
│   │   ├── top_k.py          # Day 11
│   │   └── factory.py        # Day 12: SamplerFactory
│   ├── tokenizer/
│   │   ├── base.py           # Day 9: 协议实现
│   │   ├── whitespace.py     # Day 9: WhitespaceTokenizer
│   │   ├── fake.py           # Day 9/13: FakeTokenizer
│   │   └── adapter.py        # Day 13: HuggingFaceTokenizerAdapter
│   └── engine/engine.py      # Day 10: 组合式 InferenceEngine
├── docs/
│   ├── singleton-guidelines.md   # Day 14
│   └── import-boundaries.md      # Day 3 更新 + Day 9/13
└── tests/  (unit/integration 复用 Day 6 结构，新增 sampler/tokenizer/engine 测试)
```
