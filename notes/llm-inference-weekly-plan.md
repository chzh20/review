# mini-infer 实战课程：20 周逐日教学计划（C++ 工程师版）

> 配套文件：`llm-inference-course.md`（课程大纲）。
> 本文档把大纲展开为逐周、逐日的可执行计划。
>
> **学员画像**：有扎实 C++ 工程经验（熟悉 RAII、模板、并发），Python 能写但不熟工程化，
> 未系统接触过 PyTorch/CUDA。课程难度**偏高**：理论含论文与框架源码，实践含量化验收指标。
>
> **每日 2 小时分配模板**：
> - 30~40 min：理论精读（文档/论文/源码，带着问题读）
> - 70~85 min：编码实践（当天必须有可运行产出）
> - 5~10 min：复盘记录（调用链笔记 / shape 变化 / 未决问题，写入 `docs/`）

---

## 难度设计说明（相对通用版的调整）

| 模块 | 通用处理 | 本计划处理（偏高） |
|------|----------|--------------------|
| M1 Python | 正常节奏 | 压缩语法对照，增加 CPython 源码阅读、descriptor/asyncio 内部机制 |
| M2 PyTorch | 会用为主 | 要求读 dispatcher/autograd 源码路径，理解 `__torch_function__` 之外的分发 |
| M3 推理原理 | 概念理解 | 要求读 PagedAttention / FlashAttention 原论文，手推 roofline 数值 |
| M4 C++ | 语言教学 | **跳过语言基础**，直入性能工程：cache/SIMD/perf/ATen 源码 |
| M5 CUDA | 入门 kernel | 要求手写 online-softmax attention 并用 Nsight 做归因分析 |
| M6 vLLM | 读主调用链 | 要求精读 scheduler/cache manager 并回答可验证问题清单 |

每周设「✦ 挑战项」：不强制，但建议至少完成一半。

---

# 模块一：Python 进阶与工程化（W1–W4）

> 对应 roadmap Week 1–3。对 C++ 工程师的关键迁移点：**值语义 → 引用语义**、
> **RAII → context manager**、**编译期契约 → 静态标注 + 运行时校验**、**模板 → Protocol/泛型**。

## Week 1：工程基线、对象模型与错误处理

**学习主题**：从第一天起按工程标准写 Python；理解 CPython 的对象模型与 C++ 的本质差异。

**理论知识要点**
- pyproject.toml / src layout / editable install；package vs module vs distribution
- 名称绑定语义（对比 C++ 的值语义与引用）；`is` vs `==`；可变性；浅/深拷贝
- 异常层级、`raise from` 因果链（对比 C++ exception 的栈展开与 noexcept 边界）
- context manager 协议（`__enter__/__exit__`，对比 RAII 的确定性析构）
- logging 的 logger/handler/formatter 分层；库代码不碰 root logger

**每日安排（每天 2h）**

| 日 | 理论学习（30–40min） | 实践任务（70–85min） |
|----|----------------------|----------------------|
| 1 | PyPA Packaging Guide 核心章节 | 建 `mini-infer` 仓库：src layout + pyproject + ruff/mypy/pytest/pre-commit，`mini-infer --version` CLI 跑通 |
| 2 | Python 数据模型：对象/引用/可变性（官方 docs） | 实现 `InferenceRequest`/`SamplingConfig`/`GenerationResult`；写测试证明默认参数不共享、嵌套拷贝独立 |
| 3 | 导入系统：`sys.modules` 缓存、import 执行时机 | 拆分 config/protocols/exceptions/engine；故意制造循环导入并用依赖反转消除；写 `docs/import-boundaries.md` |
| 4 | 异常设计 + EAFP/LBYL（对比 C++ 错误码/异常之争） | 建立异常层级 `MiniInferError → ConfigurationError/TokenizationError/...`；实现 `ModelSession` context manager；测试初始化失败时资源释放 |
| 5 | logging 官方 HOWTO + 结构化日志 | 日志模块输出 request_id/tokenizer 耗时/token 数/cache 用量/总延迟；`caplog` 验证不记录完整 prompt |
| 6 | pytest：fixture/参数化/monkeypatch/tmp_path | 补齐 unit + integration 测试分层；参数化 `SamplingConfig` 边界值；CLI 集成测试 |
| 7 | 周复盘：通读本周全部代码 | 模拟 PR 评审（correctness/readability/testability/extensibility/observability），识别 ≥3 个设计问题并重构；写 ADR-001（为何 src layout） |

**预期成果**：可安装的库骨架；20–30 个测试全绿；`mypy`/ruff 通过；一份模块依赖文档。
**✦ 挑战项**：阅读 CPython `Objects/dictobject.c` 的注释段（compact dict 设计），写 300 字笔记说明与 `std::unordered_map` 的设计差异。

## Week 2：类型系统、抽象边界与设计模式

**学习主题**：把类型当契约而非注释；Protocol vs ABC（对比 C++ concepts vs 虚继承）。

**理论知识要点**
- `Sequence/Iterable/Mapping` 抽象容器；TypedDict/Literal/NewType；`Any` 的传播风险
- Protocol（结构化子类型，≈ C++20 concepts 的 duck typing）vs ABC（名义子类型，≈ 抽象基类）
- composition over inheritance（C++ 工程师熟知的教训在 Python 同样成立）
- Strategy / Factory(registry) / Adapter 的真实适用边界；Singleton 与全局状态的测试毒性

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 8 | typing 模块文档 + `mypy --strict` 语义 | 引入 `TokenId/RequestId = NewType(...)`；公共 API 清除裸 `dict` 与 `Any`；CI 加入严格类型检查 |
| 9 | Protocol vs ABC（PEP 544） | 定义 `Tokenizer` Protocol；实现 `WhitespaceTokenizer` + `FakeTokenizer`；证明 Engine 只依赖协议 |
| 10 | 组合根 / 依赖注入模式 | Engine 组合为 Tokenizer+Model+Sampler+Scheduler+MetricsSink；测试时可替换任一组件 |
| 11 | Strategy 模式与可重复性 | `GreedySampler`/`TopKSampler`/`TemperatureSampler`；测试 top_k=1 ≡ greedy、固定 seed 可复现、非法 temperature 报错 |
| 12 | Factory(registry) 与反模式 | `SamplerFactory.create(kind=..., config=...)`；新增 sampler 不改 Engine；契约测试套件对所有 sampler 生效 |
| 13 | Adapter 与第三方隔离 | `HuggingFaceTokenizerAdapter`：核心层不 import transformers；第三方异常翻译为 `TokenizationError`；fake object 覆盖多数测试 |
| 14 | 全局状态的危害（带实验） | 先写全局 `ModelRegistry` 观察测试顺序依赖，再重构为注入式；输出「何时可用 Singleton」决策文档 |

**预期成果**：`mypy --strict` 通过；可替换 tokenizer/sampler；协议边界清晰。
**✦ 挑战项**：用 `typing.Generic` 给 `Sampler` 协议加泛型参数（如 logits 容器类型），并让 mypy 严格模式下通过。

## Week 3：Packaging、并发与性能测量

**学习主题**：从源码到 wheel；理解 GIL（C++ 工程师最容易误判的地方）；先测量再优化。

**理论知识要点**
- sdist vs wheel、build backend、optional deps、entry point
- GIL 的真实语义：为什么 CPU-bound 多线程无效、C 扩展可释放 GIL（这是 M4 的关键伏笔）
- asyncio 事件循环模型（对比 C++ 的 io_uring/epoll 事件循环）；backpressure/cancellation
- profiling 方法论：CPU time vs wall time、p50/p95/p99、warm-up 与噪声控制

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 15 | Python Packaging User Guide（构建章节） | 完善 optional deps（dev/torch/transformers）；构建 wheel 并在干净 venv 安装 + smoke test |
| 16 | CI 设计：fail-fast、测试分层、矩阵 | CI 六步：lint → type → unit → integration → build → smoke install；`@pytest.mark.integration` 标记；覆盖率阈值 |
| 17 | GIL 官方文档 + David Beazley 的 GIL 经典分析 | 写 CPU-bound 对比实验：thread vs process vs 单线程，用数据说明 GIL 影响；结论写入 `docs/gil-experiment.md` |
| 18 | asyncio：coroutine/task/queue 语义 | 实现 `await engine.submit(request)`：队列、定时取 batch、timeout、backpressure、取消不泄漏 future |
| 19 | cProfile/timeit 与 benchmark 设计 | tokenizer/scheduler benchmark：单请求延迟、批量吞吐、不同 batch/长度；输出 `benchmarks/results.json` + report |
| 20 | pXX 延迟与性能回归概念 | benchmark 报告必须含假设/环境/输入/重复次数/未排除变量；为 CI 加一个性能回归告警（阈值 +20%） |
| 21 | 周复盘 | code review #2；把 asyncio 队列与 C++ 生产者-消费者队列做对照笔记 |

**预期成果**：wheel 可装、CI 绿、异步队列工作、可信 benchmark 基线。
**✦ 挑战项**：阅读 CPython `Python/ceval_gil.c`（或 3.13 的 free-threading 设计文档），写笔记：GIL 正在如何被移除，对扩展作者意味着什么。

## Week 4：Python 高阶机制 + 模块验收

**学习主题**：为读 PyTorch/vLLM 源码储备机制层知识——这两个库大量使用动态特性。

**理论知识要点**
- descriptor 协议（`__get__/__set__`）：`nn.Module.__setattr__` 拦截参数注册的基石
- `__call__` 协议与 hook 机制（PyTorch Module 调用链的入口）
- metaclass 最小必要知识（注册表模式的另一种实现；vLLM 的模型注册用过）
- monkeypatch 与动态导入在测试/插件系统中的角色

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 22 | descriptor 协议官方指南 | 手写一个简化版 `nn.Module.__setattr__`：赋值时自动注册 Parameter 到 `_parameters` dict；与 PyTorch 源码对照 |
| 23 | `__call__` 与 hook 链 | 给自己的 Engine 加 pre/post forward hook 机制（用于注入 metrics），测试 hook 顺序与异常传播 |
| 24 | metaclass 的最小可用子集 | 用 metaclass 实现 sampler 自动注册（替代 W2 手动 register）；对比两种方案的优劣写进 ADR-002 |
| 25 | 动态导入与插件发现（importlib） | 实现 `mini_infer.plugins`：entry_points 或目录扫描加载第三方 sampler |
| 26 | CPython 源码选读：`typeobject.c` 的 `type_call` | 用调用链登记表记录 `MyClass()` 从 Python 到 C 的完整路径 |
| 27 | 模块一整体复盘 | 对照 M1 自测清单逐条口头回答（录音或写要点）；补薄弱项 |
| 28 | — | **M1 验收**：全量测试 + 构建 + CI 绿；mini-infer v0.1 tag；模块 review 报告 |

**预期成果**：mini-infer v0.1；理解 PyTorch/vLLM 依赖的动态机制；CPython 阅读笔记 2 篇。
**✦ 挑战项**：用纯 Python 实现一个支持 `module.param` 属性访问 + `state_dict()` 的 150 行迷你 Module 系统。

---

# 模块二：PyTorch 深度学习框架（W5–W7）

> 对 C++ 工程师的重点：PyTorch 是一个「Python 壳 + C++ dispatcher + backend kernel」的三层系统。
> 本模块要求同时理解 Python 层行为与 C++ 层分发路径（为 M4/M5 写扩展铺路）。

## Week 5：PyTorch 执行模型与源码路径

**学习主题**：Tensor 内存模型（stride!）、Module 调用协议、dispatcher 地图。

**理论知识要点**
- Tensor：shape/dtype/device/**stride**；view vs copy；contiguous；broadcasting 规则
- parameter/buffer 注册（W4 手写机制的工业版）；`state_dict` 语义
- `no_grad` vs `inference_mode`；`train/eval` 的行为开关
- dispatcher：Python API → C++ `at::` → dispatch key（CPU/CUDA/Autograd）→ kernel
- autograd 计算图概念（推理只需理解为何关掉它）

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 29 | Tensor stride 官方文档 + einsum 博客 | stride 实验：`transpose/narrow/expand` 后打印 stride；证明 view 不拷贝；写出"哪些操作会强制拷贝"清单 |
| 30 | `nn.Module` 源码（`module.py` 的 `__call__`/`__setattr__`） | `TinyModel` 两层 MLP：forward hook 打印 shape；故意制造 dtype/device mismatch 并定位错误层次 |
| 31 | autograd 概览（官方 autograd mechanics） | 同一段 forward 分别在 grad/no_grad/inference_mode 下跑，测量内存与耗时差异 |
| 32 | dispatcher 文档（Ed Yang 的 "PyTorch Dispatcher" 演讲/博客） | 用 `torch.profiler` 抓取一次 forward 的算子调用序列，画出 dispatch 路径草图 |
| 33 | einsum 与高效张量操作 | 用 einsum 重写 TinyModel；benchmark 对比显式 matmul |
| 34 | 混合精度与 dtype 转换 | 给 TinyModel 加 fp16/bf16 路径；处理 dtype mismatch 的规范写法 |
| 35 | 周复盘 | 输出 `docs/pytorch-execution-model.md`：Tensor/Module/dispatch 三层地图 |

**预期成果**：能解释任何一次 `model(x)` 从 Python 到 C++ kernel 的完整路径；stride 操作不踩坑。
**✦ 挑战项**：读 `aten/src/ATen/native/Linear.cpp`，记录 `linear → addmm → gemm` 的分发链。

## Week 6：Attention 与最小 Transformer

**学习主题**：从公式到手写实现，全部经过数值验证——这是后面一切推理优化的锚点。

**理论知识要点**
- Q/K/V 投影、分头 reshape、scaled dot-product、causal/padding mask
- softmax 数值稳定性（max-subtraction 技巧——M5 online softmax 的前置）
- pre-norm vs post-norm、residual、FFN、LM head、tie embeddings
- RoPE 的概念与实现思路（vLLM 模型实现里直接出现）
- KV cache 的数学依据：为什么历史 K/V 与后续计算无关

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 36 | "Attention Is All You Need" §3 + annotated transformer | 手写 single-head attention；与手算 3×3 小例子逐元素对照 |
| 37 | 数值稳定 softmax 推导 | 实现 naive vs stable softmax，构造 overflow 输入证明差异 |
| 38 | 多头注意力的 reshape 路径 | multi-head 版本：测试未来 token 权重为 0、与 `F.scaled_dot_product_attention` 近似一致（atol=1e-5） |
| 39 | RoPE 论文/博客（旋转矩阵的相对位置性质） | 实现 RoPE 并验证相对位置性质：`⟨f(q,m), f(k,n)⟩` 只依赖 m−n |
| 40 | pre-norm/post-norm 对比文献 | 完整 decoder block：LN → MHA → residual → LN → FFN → residual |
| 41 | LM head 与 weight tying | 最小 decoder-only 模型：`[B,T] → [B,T,V]`，tie embeddings 开关；每个子模块独立单测 |
| 42 | 周复盘 | 画完整 shape-flow 图（embedding→blocks→norm→logits），标注每个 reshape |

**预期成果**：CPU 可跑的最小 Transformer；attention 全部数值验证通过；shape-flow 图。
**✦ 挑战项**：不用 for 循环实现 GQA（num_kv_heads < num_heads）的 reshape 路径，并测通。

## Week 7：Tokenizer、生成循环与 KV cache

**学习主题**：从 logits 到文本的完整闭环；第一次亲手制造并消除推理的低效。

**理论知识要点**
- tokenizer 流水线：normalization → pre-tokenization → BPE → special tokens → padding/mask
- prefill vs decode；last-token logits；EOS/stopping criteria；streaming
- KV cache：shape `[L, H_kv, S, D]`；MHA/MQA/GQA 容量对比；每步追加一个位置
- HF `PreTrainedTokenizerBase.__call__` 的调用链结构

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 43 | HF tokenizer 文档 + BPE 算法 | 增强 `WhitespaceTokenizer`：special tokens、批量 encode、padding、mask、vocab 持久化；Unicode/空串/未知词测试 |
| 44 | 读 HF tokenizer 源码（按 roadmap 阅读路径） | 输出 `docs/hf-tokenizer-call-chain.md`；字段语义对照测试（mini-infer vs HF） |
| 45 | 自回归生成的算法结构 | naive generation loop（每步全量重算）；接上 sampler 跑通文本生成 |
| 46 | KV cache 复用的推导（自己推一遍） | 给 `MiniAttention` 加 cache：`forward(x, kv_cache)`；测试 cache/no-cache logits 一致、长度每步 +1、超容量抛 `CacheCapacityError` |
| 47 | MHA/MQA/GQA 容量计算 | 手算并写脚本验证：给定 7B 配置，4K 上下文的 cache 显存（三种架构对比） |
| 48 | 性能对比实验设计 | benchmark：naive vs cached generation 的 token/s 曲线；写 `docs/naive-generation-bottlenecks.md` |
| 49 | — | **M2 验收**：v0.2 tag；生成结果确定性测试（greedy 逐 token 相同） |

**预期成果**：mini-infer v0.2；KV cache 正确且可量化提速；两篇源码调用链文档。
**✦ 挑战项**：给 generation 加 streaming 输出（async generator），并保持与 batch 路径共享同一套 sampler。

---

# 模块三：LLM 推理原理（W8–W10）

> 本模块偏理论 + 系统实验。目标：在碰 C++/CUDA 之前，先建立「该优化什么」的判断力。

## Week 8：推理性能模型

**学习主题**：roofline 模型 + 真实测量。推理优化的所有决策都从算术强度出发。

**理论知识要点**
- roofline：算术强度 = FLOPs / bytes；compute-bound vs memory-bound 的判定
- prefill 是 GEMM（compute-bound）、decode 近 GEMV（memory-bound）的本质
- TTFT / TPOT / throughput 的定义与测量方法
- KV cache 显存预算公式；为什么 decode 吞吐随 batch size 近线性提升

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 50 | roofline 原始论文/经典讲义 | 手推：A100/H100（或你的 GPU）上 d_model=4096 的 GEMV 算术强度，判定 bound 类型 |
| 51 | "LLM inference arithmetic" 类博客（Kipply/Finbarr 等） | 推导并脚本化：每层 decode 的 FLOPs 与访存字节数公式 |
| 52 | TTFT/TPOT 定义与产业报告 | 给 mini-infer benchmark 加 TTFT/TPOT 指标（monkeypatch 计时点） |
| 53 | batch 对算术强度的影响推导 | 实验：batch=1/2/4/8 下 TPOT 与吞吐曲线，对照理论预测解释拐点 |
| 54 | 显存预算完整模型（权重+KV+激活+碎片） | 写显存估算器：输入模型配置/序列长/batch，输出各组件占用 |
| 55 | 一周数据整理 | 所有实验数据汇成 `docs/performance-model.md`：理论预测 vs 实测偏差分析 |
| 56 | 周复盘 | 回答：为什么"加大 batch"对 decode 几乎免费、对 prefill 不是？（写下来） |

**预期成果**：能量化预测推理性能；实验数据与理论偏差 ≤ 数量级一致。
**✦ 挑战项**：推导出 continuous batching 下吞吐上界的解析式，并用实验验证趋势。

## Week 9：调度与内存管理

**学习主题**：continuous batching 与 PagedAttention——vLLM 的两大支柱，先在自己的框架里实现简化版。

**理论知识要点**
- 静态/dynamic/iteration-level batching 演进；admission control；fairness/starvation
- 连续预分配 KV cache 的内外碎片问题
- PagedAttention 论文：logical block → block table → physical block；CoW；prefix sharing
- preemption 策略：swap vs recompute 的代价模型

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 57 | Orca 论文（continuous batching 出处）核心章节 | scheduler v1：静态 batch 基线 + 时间线日志 |
| 58 | iteration-level 调度的状态机设计 | scheduler v2：每 decode iteration 重选 active set；完成的立即退出、新请求可插入 |
| 59 | admission control 与 token budget | 加约束：最大请求数/token budget/最大等待时间；写 starvation 防护测试 |
| 60 | 调度实验设计 | 三请求（长度 2/5/8）实验：证明短请求等待时间显著低于静态 batch；输出时间线图 |
| 61 | PagedAttention 论文精读（§3–4） | CPU 版 `BlockManager`：分配/追加/释放/重用；block table 可视化 |
| 62 | CoW 与 prefix sharing 机制 | 给 BlockManager 加引用计数 + CoW 语义（逻辑层即可） |
| 63 | 不变量测试设计 | 随机操作下的 property-based 测试：free∩allocated=∅、释放后全部归还等 |

**预期成果**：mini-infer v0.3 雏形；scheduler + block manager 通过全部不变量测试。
**✦ 挑战项**：实现 prefix sharing 测试场景（两个请求共享 system prompt），验证物理 block 复用。

## Week 10：优化技术全景 + vLLM 第一轮导航

**学习主题**：知道每项技术解决什么问题；建立 vLLM 请求生命周期地图（M6 深读的地基）。

**理论知识要点**
- chunked prefill：长 prompt 阻塞 decode 的原因与切片混跑
- prefix caching 的 hash 机制；speculative decoding 的接受率与加速比
- 量化全景：INT8/FP8/AWQ/GPTQ 各自的 trade-off（只要求概念）
- FlashAttention 论文核心：tiling + online softmax、不物化 attention 矩阵
- vLLM 架构：LLM/Engine/Scheduler/ModelRunner/Model/AttentionBackend/CacheEngine 分层

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 64 | FlashAttention 论文 §1–3（重点 online softmax） | 推导 online softmax 的合并公式；用 numpy 实现两遍 vs online 版本对照 |
| 65 | chunked prefill 设计文档（vLLM blog） | 给 scheduler 加"prefill 分块"开关，测量长 prompt 场景下 TPOT 变化 |
| 66 | speculative decoding 论文（Leviathan et al.） | 概念实验：用小模型当 draft，测接受率（可用随机权重模型模拟） |
| 67 | 量化综述阅读 | 写一页对比表：各量化方案的精度/显存/速度 trade-off |
| 68 | vLLM 官方架构文档 | 跑通 vLLM offline 示例；用登记表记录 `LLM.generate()` 入口链路 |
| 69 | 按 roadmap Day 28 顺序读源码 | 沿 Engine→Scheduler→ModelRunner→Model→Attention→Cache 走一遍，标注输入输出类型 |
| 70 | — | **M3 验收**：输出 `docs/vllm-request-lifecycle.md`（每个箭头含类型/所有权/线程边界/是否热路径） |

**预期成果**：mini-infer v0.3；vLLM 生命周期图；每项优化技术能一句话说清"解决什么问题"。
**✦ 挑战项**：在 vLLM 源码里找到 token budget 扣减的确切代码行并记录 commit hash。

---

# 模块四：C++ 性能优化（W11–W13）

> **跳过语言基础**。默认你已会 RAII/移动语义/模板；本模块只讲"写出快代码"和"接入 PyTorch"。

## Week 11：CPU 性能工程 I——内存与测量

**学习主题**：性能来自对硬件的理解，不是语法技巧。重建 cache 层级的直觉。

**理论知识要点**
- cache line / L1-L3 延迟数量级；时间/空间局部性；false sharing
- 分支预测与数据导向设计（data-oriented design）的基本思想
- `perf`（Linux）/ Instruments（macOS）/ google benchmark 的正确使用
- 对齐、`alignas`、预取的基本概念

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 71 | "What Every Programmer Should Know About Memory" §1–3 | 实验：行优先 vs 列优先遍历大矩阵，测 10x+ 差异并解释 |
| 72 | false sharing 文献 | 构造 false sharing 多线程计数器实验；用 padding 消除并测量 |
| 73 | google benchmark 文档 | 搭建 `mini-infer/benchmarks/cpp/`：fixture、参数扫描、防止编译器优化掉被测代码 |
| 74 | perf/Instruments 使用 | 对 W3 的 Python 热点路径对应的 C++ 版本做 profile 实操，记录火焰图 |
| 75 | 分支预测实验文献 | 实验：sorted vs unsorted 数组的条件求和（经典分支预测案例），测量差异 |
| 76 | data-oriented design 选读 | 把 BlockManager 的一个热点结构从 AoS 改 SoA，benchmark 对比 |
| 77 | 周复盘 | 输出 `docs/cpu-memory-model-notes.md`：所有实验数据 + 结论 + 未排除变量 |

**预期成果**：所有性能结论有 benchmark 数据支撑；能熟练使用至少一种 profiler。
**✦ 挑战项**：用 `perf stat` 测量 cache-misses/branch-misses，把硬件计数器数据与 wall time 关联解释。

## Week 12：CPU 性能工程 II——GEMM 优化专项

**学习主题**：以 naive → tiled → SIMD → 多线程 的 GEMM 优化路径为载体，掌握全套优化手法（M5 CUDA GEMM 的直接预演）。

**理论知识要点**
- GEMM 的算术强度分析：为什么 tiling 是核心
- loop reorder/blocking 对 cache 命中率的影响
- 编译器自动向量化的条件与阻碍；AVX2 intrinsics 最小子集
- OpenMP/`std::thread` 任务划分；线程数与 NUMA 的基本注意事项

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 78 | GEMM 优化经典教程（如 FLAME/HowToOptimizeGemm） | naive ijk 三重循环基线，记录 GFLOPS |
| 79 | loop order 与访存模式 | ikj 重排 + 内层连续访存版本，测提升并解释 |
| 80 | cache blocking/tiling 理论 | blocked GEMM（tile=32/64/128 扫描），找出最优 tile 并解释为什么 |
| 81 | 编译器向量化报告（`-Rpass`） | 调整代码让内层循环自动向量化；读编译器报告确认 |
| 82 | AVX2 intrinsics 最小子集 | 手写 8-wide FMA 内积 kernel；与自动向量化版本对比 |
| 83 | OpenMP 并行 GEMM | 多线程版本；扫描线程数曲线，解释超线性/亚线性段 |
| 84 | 对照 BLAS | 与 OpenBLAS/Accelerate 对比差距；写 `docs/cpu-gemm-optimization.md` 完整优化史 |

**预期成果**：相对 naive ≥ 10x 加速（有数据）；理解每一步为什么有效。
**✦ 挑战项**：加入 packing（数据��排成块连续布局），再测一轮提升。

## Week 13：pybind11 与 PyTorch C++ 扩展

**学习主题**：把 C++ 算子安全地接入 Python/PyTorch——这是 vLLM `csrc/` 的同款技术栈。

**理论知识要点**
- pybind11：函数/类绑定、GIL 释放（`call_guard<gil_scoped_release>`）、buffer protocol
- `torch::Tensor` 内存所有权；accessor/数据指针；`TORCH_CHECK` 错误处理
- `TORCH_LIBRARY` 算子注册与 Python 侧 `torch.ops` 调用
- CMake/setup.py 构建；editable install 下的扩展开发循环

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 85 | pybind11 官方文档（基础+GIL 章节） | 建 `csrc/cpu/`：hello 扩展跑通；绑定函数 + 异常翻译为 Python 异常 |
| 86 | buffer protocol / numpy 互操作 | 实现零拷贝的 numpy↔C++ 双向传递；验证不触发拷贝 |
| 87 | PyTorch 自定义 C++ 扩展官方教程 | `torch::Tensor` 版 `top_k_sampling`（含温度缩放）；`TORCH_CHECK` 参数校验 |
| 88 | GIL 释放的正确姿势 | 给算子加 GIL 释放；写多线程并发调用测试证明无死锁/竞态 |
| 89 | TORCH_LIBRARY 注册机制 | 把算子注册为 `torch.ops.mini_infer.*`；对比 pybind 直绑与算子注册的差异 |
| 90 | golden test 设计 | 每个 C++ 算子配 Python 参考实现的逐元素对照测试（含边界：k=1、k≥vocab、非法温度） |
| 91 | — | **M4 验收**：`pip install -e .` 自动构建扩展；C++ 算子接入 Engine 可选启用；benchmark：C++ vs Python 加速比报告 |

**预期成果**：mini-infer v0.4；`mini_infer._ops` 可用；所有算子有 golden test。
**✦ 挑战项**：读 vLLM `csrc/` 下一个简单文件（如 cache ops），用源码登记表记录其所有权与调用约定。

---

# 模块五：CUDA 并行编程（W14–W17）

> 需要 NVIDIA GPU。没有 GPU 时降级方案：W14–15 用 CPU 模拟概念 + 阅读，W16–17 暂缓。
> 本模块全部 kernel 遵循「正确性 golden test 先行，性能 profile 归因其次」。

## Week 14：CUDA 编程模型

**学习主题**：SIMT 执行模型与内存层级——与 CPU 思维的最大断裂点。

**理论知识要点**
- grid/block/thread 索引；kernel launch 配置；host/device 内存模型
- global/shared/register 的带宽与延迟数量级（对比 CPU cache 层级）
- warp 执行：SIMT、divergence 的代价、warp shuffle
- stream/event 与异步执行；统一的错误检查规范

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 92 | CUDA C++ Programming Guide §1–3 | 环境搭建 + vector add kernel；写统一的 CUDA error check 宏 |
| 93 | 索引计算与 grid-stride loop | 实现任意长度 elementwise 温度缩放 kernel；接 W13 的扩展框架，golden test 对照 PyTorch |
| 94 | 内存层级量化数据 | 实验：不同访存模式的带宽实测（stride=1/2/32），画出带宽曲线 |
| 95 | warp/divergence 机制 | 构造 divergence 实验（奇偶分支），测量性能差异 |
| 96 | shared memory 与 `__syncthreads()` | 用 shared memory 实现 block 内 reduction（求和）；处理同步与边界 |
| 97 | stream/event 异步语义 | 用 event 精确测 kernel 耗时；对比 cudaEvent vs wall clock |
| 98 | 周复盘 | 输出 `docs/cuda-mental-model.md`：与 CPU 编程模型的对照表 |

**预期成果**：工具链就绪；3 个正确的基础 kernel；带宽/分歧实验数据。
**✦ 挑战项**：实现 warp shuffle 版 reduction，与 shared memory 版对比。

## Week 15：CUDA 优化核心技术

**学习主题**：coalescing、tiling、reduction——把 W11–12 的 CPU 优化直觉迁移到 GPU。

**理论知识要点**
- memory coalescing 的判定；为什么 decode attention 天然 memory-bound
- shared memory tiling（GEMM）与 bank conflict
- online softmax 的 CUDA 实现：单 block 单遍扫描的数值稳定 softmax
- occupancy、寄存器压力；Nsight Compute 指标阅读（SM busy / memory throughput / achieved occupancy）

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 99 | coalescing 指南（Best Practices Guide） | naive GEMM → coalesced 访存改造，Nsight 对比 memory throughput |
| 100 | shared memory tiling 教程 | tiled GEMM v1（对照 W12 CPU 版思路）；测 TFLOPS 提升 |
| 101 | bank conflict 机制 | 给 tile 加 padding 消除 bank conflict，测量差异 |
| 102 | online softmax 推导（W10 的重温，这次是并行版） | CUDA online softmax kernel（block 内 warp reduce + 跨 warp 合并）；golden test 含极端值 |
| 103 | Nsight Compute 指标手册 | 对 softmax kernel 做完整 profile：判定 memory-bound 程度，记录关键指标截图/数据 |
| 104 | occupancy 计算与寄存器压力 | 用 `--ptxas-options=-v` 查看寄存器用量；实验 block size 扫描对性能的影响 |
| 105 | 周复盘 | tiled GEMM 与 cuBLAS 差距分析；优化记录文档 |

**预期成果**：tiled GEMM 显著超 naive；数值稳定 online softmax；能读懂 Nsight 关键指标。
**✦ 挑战项**：GEMM 加 double buffering（cp.async 或手动流水），再测提升。

## Week 16：推理 Kernel 实战

**学习主题**：手写 decode attention kernel——把 W6 的数学、W15 的优化、M3 的 block 概念合流。

**理论知识要点**
- decode attention 的结构：q 为 1 个 token → 带 softmax 的 GEMV
- kernel 划分策略：每个 block 负责一个 (sequence, head)；head_dim 维度的向量化加载
- KV cache 布局对访存的影响：`[H, S, D]` vs `[S, H, D]`
- PyTorch custom CUDA op 的 stream 语义与 `CUDAGuard`

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 106 | decode attention 的计算分解（自己先推） | kernel v1：单头、`q[1,D]` × `K/V[S,D]`，QK^T + online softmax + 加权 V 融合 |
| 107 | golden test 强化 | 边界全集：S=1、S 非 warp 对齐、D=64/128、极端 logits；对照 PyTorch 参考（atol 1e-4） |
| 108 | 多头并行的 block 划分 | kernel v2：grid=(batch, head)；每 block 处理一个头 |
| 109 | KV 布局实验 | 两种 cache 布局各实现一版读取，Nsight 对比 coalescing |
| 110 | PyTorch CUDA 扩展规范（stream/guard） | 把 kernel 封装为 `torch.ops.mini_infer.decode_attention`；多 stream 调用测试 |
| 111 | profile 归因 | Nsight 全指标分析：确认 memory-bound；计算实测带宽占峰值比例 |
| 112 | 性能对照 | 与 `F.scaled_dot_product_attention` 对比 decode 场景延迟；分析差距来源 |

**预期成果**：正确且有 profile 数据的 decode attention kernel；集成进扩展框架。
**✦ 挑战项**：用 float4/向量化加载优化 K/V 读取，量化提升。

## Week 17：Paged Attention + Triton + 集成

**学习主题**：实现简化版 paged attention kernel，完成 mini-infer 的 GPU 数据通路；认识 Triton。

**理论知识要点**
- paged attention 的 kernel 视角：block table 间接寻址；物理 block 内连续、块间跳跃
- vLLM paged attention v1 kernel 的结构（每 warp 的分工）
- Triton 编程模型：block-level 抽象、自动 coalescing/tiling
- 后端可切换架构：naive / cuda 的接口统一

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 113 | paged attention kernel 设计（vLLM v1 源码导读） | 设计文档：block table 如何传入、kernel 如何按表寻址 |
| 114 | 间接寻址实现 | paged attention kernel v1：K/V 存非连续物理 block，kernel 查表读取 |
| 115 | 与 BlockManager 对接 | 把 W9 的 CPU BlockManager 升级为 GPU 数据通路：分配物理 block、拷贝 K/V 写入 |
| 116 | golden test | paged kernel vs 连续 KV 参考实现逐元素对照；含 block 跨页边界场景 |
| 117 | Triton 官方教程（vector add → softmax） | Triton 版 online softmax；与 CUDA C++ 版对比代码量/性能 |
| 118 | Triton 进阶 | 可选：Triton 版 decode attention 原型 |
| 119 | 后端抽象设计 | Engine 支持 `backend="naive"\|"cuda"` 切换；端到端生成结果一致性测试 |
| 120 | — | **M5 验收**：mini-infer v0.5；全部 kernel golden test 绿；Nsight 归因报告；Triton 对比笔记 |

**预期成果**：mini-infer v0.5 含真实 GPU 推理路径；能讲清 paged attention kernel 的寻址逻辑。
**✦ 挑战项**：读 vLLM `csrc/attention/attention_kernels.cu`（固定 tag），记录每 warp 分工与 block table 消费方式。

---

# 模块六：vLLM 源码精读与最终集成（W18–W20）

## Week 18：PyTorch → Transformers → vLLM 三层对照

**学习主题**：同一抽象在三个代码库中的不同职责——此前所有模块的知识在此汇合。

**理论知识要点**
- PyTorch 层：`Module.__call__`、SDPA、state_dict、inference mode（W5 的重温，这次看代码）
- Transformers 层：config → CausalLM → decoder layer → attention → `past_key_values` → `generate`
- vLLM 层：模型 forward → ModelRunner 组 batch → Scheduler 决策 → cache manager → attention backend → sampler

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 121 | 确定三个库的固定 commit | 建对照工作区：三个 repo clone + checkout 固定 tag；写阅读计划 |
| 122 | PyTorch 路径精读 | 登记表：`__call__ → forward → SDPA` 调用链 + dispatch 路径 |
| 123 | Transformers 模型结构（上） | 选一个 decoder-only 模型：config → 顶层类 → forward 参数；记录 shape |
| 124 | Transformers 模型结构（下） | decoder layer → attention → cache 输入输出；hook 实测 shape 与 mini-infer 对照 |
| 125 | vLLM 模型实现精读 | 同一模型在 vLLM 中的 forward；与 Transformers 版的差异清单（不只是类名） |
| 126 | ModelRunner/Scheduler 接口 | 记录 batch → tensor 的组装过程；cache metadata 的产生位置 |
| 127 | 三层对照表 | 完成 Module执行/Attention/Cache/Batch 四行对照表 + shape 对照调试实验报告 |

**预期成果**：三层对照表 + 每层的源码登记记录。
**✦ 挑战项**：找出 Transformers 与 vLLM 在 KV cache 布局上的具体差异及原因。

## Week 19：vLLM 深水区

**学习主题**：scheduler、cache manager、attention backend 的实现细节——带着可验证问题读。

**理论知识要点**
- Scheduler：waiting/running 队列、token budget 扣减点、preemption（swap vs recompute）
- KV cache manager：block 分配/释放时机、prefix caching 的 hash 与命中流程
- attention backend 选择逻辑：FlashAttention/FlashInfer/xFormers 的适用条件
- 采样与输出处理：logits processor 链、detokenize 的增量式处理

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 128 | scheduler 精读准备（列问题清单） | 回答并记录：token budget 在哪扣减？decode step 为何只喂 1 个 token？ |
| 129 | preemption 机制 | 找到 swap/recompute 的决策代码；与 W9 自己的简化实现对比 |
| 130 | cache manager（上） | block 分配/释放的完整生命周期；记录所有权归属 |
| 131 | cache manager（下） | prefix caching：hash 计算位置、命中后 block 如何共享 |
| 132 | attention backend | backend 选择逻辑；block table 如何传进 kernel（衔接 W17） |
| 133 | 采样与输出路径 | logits processor 链；增量 detokenize 的实现 |
| 134 | 周复盘 | 所有登记表汇总成 `docs/vllm-deep-dive.md`；每个问题附 commit hash + 代码行号 |

**预期成果**：vLLM 深水区阅读报告；每个结论可定位到具体代码。
**✦ 挑战项**：给 vLLM 提一个文档/测试级别的 PR（或至少写出 issue 级别的分析）。

## Week 20：最终集成、验收实验与交付

**学习主题**：把 20 周成果压成一个可评审的工程交付。

**每日安排**

| 日 | 理论学习 | 实践任务 |
|----|----------|----------|
| 135 | release checklist 设计 | 全量回归：所有测试 + 构建 + CI；三后端（naive/C++/CUDA）一致性验证 |
| 136 | 实验设计方法 | **实验一·正确性**：cache/no-cache、三后端 greedy 逐 token 一致 |
| 137 | 调度收益量化 | **实验二·调度**：continuous vs 静态 batching 的短请求等待时间对比（量化图表） |
| 138 | 性能曲线扫描 | **实验三·性能**：batch × seq 扫描的 TTFT/TPOT/吞吐曲线；对照 W8 的 roofline 预测 |
| 139 | 与 vLLM 对照 | 同模型对比 vLLM 的吞吐；分析差距来源（kernel 质量/调度/量化等），写归因分析 |
| 140 | 文档收尾 | README quick start、架构图、错误模型文档、benchmark 可复现说明 |
| 141 | 最终 code review | 按 roadmap 九问 + native 扩展三问（异常翻译/后端回退/边界 shape）逐项过 |
| 142 | — | **交付**：mini-infer v1.0 tag；源码阅读报告；课程总结（哪些设计在真实 GPU 系统中会失效） |

**预期成果**：mini-infer v1.0 完整交付（见大纲第七节清单）；vLLM 源码阅读报告；三组验收实验数据。
**✦ 挑战项**：把 benchmark 框架参数化，写成 `make bench` 一键复现全部曲线。

---

## 课程完成标准（最终自测）

不看任何资料，你应能：

1. 手写 causal attention（含数值稳定 softmax）并通过数值验证。
2. 推导任意模型配置的 KV cache 显存与 decode 算术强度，判定 bound 类型。
3. 讲清 continuous batching 的状态机与 PagedAttention 的 block table 寻址。
4. 写一个带 golden test 的 pybind11/`torch.ops` C++ 算子。
5. 写一个正确的 CUDA online softmax / decode attention kernel，并用 Nsight 归因。
6. 给一个陌生 LLM 推理仓库，60–90 分钟产出可信调用链图（定位入口/API/tokenizer/forward/attention/cache/scheduler）。
7. 交付 mini-infer v1.0：100+ 测试、三后端、CI、benchmark 报告、源码阅读报告。

## 风险与调整预案

| 风险 | 预案 |
|------|------|
| 无 NVIDIA GPU | W14–15 改纯阅读 + 概念实验；W16–17 整体顺延或以 Triton-on-CPU 教程替代 |
| 某周任务量超时 | 优先砍「✦ 挑战项」；核心任务的 golden test 不可砍 |
| CUDA 调试卡壳 | 降级到更小 shape 复现；所有 kernel 问题先写 CPU 参考实现对照 |
| vLLM 版本变动 | 全程固定 commit；阅读记录必须含 commit hash |
