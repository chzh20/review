# 从工程师到推理系统开发者：vLLM 源码阅读与 mini-infer 实战课程

> 设计基线：`review/python/roadmap.md`（一个月 Python 工程实践课）。
> 本课程将其扩展为一条覆盖 **Python 进阶 → PyTorch → LLM 推理原理 → C++ 性能优化 → CUDA 并行编程 → vLLM 源码 + mini-infer 集成** 的完整路径。

---

## 一、课程总览

### 1.1 课程目标

学完本课程后，你应能够：

1. 独立设计、实现、测试并发布一个工程级 Python 库。
2. 从执行模型层面理解 PyTorch：Tensor、autograd、dispatch、算子调用链。
3. 解释并实现 LLM 推理的关键机制：prefill/decode、KV cache、continuous batching、PagedAttention。
4. 用现代 C++ 编写高性能算子，并通过 pybind11 集成到 Python。
5. 编写、profile、优化 CUDA kernel（GEMM、softmax、attention）。
6. 沿真实调用链阅读 vLLM 源码，画出可验证的请求生命周期图。
7. 交付 **mini-infer**：一个含自研 C++/CUDA 算子的迷你 LLM 推理框架。

### 1.2 学员画像与前置要求

* 有 C++/Java/Python 任一语言的工程经验，会用 Git、能读英文文档。
* 了解线性代数基础（矩阵乘法、softmax）。
* 有一块可用的 NVIDIA GPU（模块五起需要；此前全部可在 CPU 完成）。

### 1.3 总体结构与时间预算

建议每天投入 1.5～2.5 小时，总周期约 **20 周（5 个月）**：

| 模块 | 主题 | 时长 | mini-infer 里程碑 |
|------|------|------|-------------------|
| M1 | Python 进阶与工程化 | 4 周 | v0.1：纯 Python 推理框架骨架 |
| M2 | PyTorch 深度学习框架 | 3 周 | v0.2：PyTorch 版 Transformer + KV cache |
| M3 | LLM 推理原理 | 3 周 | v0.3：continuous batching + block manager |
| M4 | C++ 性能优化 | 3 周 | v0.4：C++ 算子扩展（CPU 高性能路径） |
| M5 | CUDA 并行编程 | 4 周 | v0.5：自研 CUDA kernel（softmax/attention） |
| M6 | vLLM 源码精读与最终集成 | 3 周 | v1.0：完整交付 + vLLM 源码阅读报告 |

> 注意模块顺序的取舍：**先学推理原理（M3），再学 C++/CUDA（M4/M5）**。
> 理由：只有先知道"要优化什么"（attention、KV cache 访存模式），C++/CUDA 的学习才有明确靶子；这也与 roadmap 中"不要一开始钻入 CUDA"的原则一致。

### 1.4 贯穿项目：mini-infer 演进路线

```text
v0.1  纯 Python：tokenizer / engine / sampler / 测试与 CI          (M1)
v0.2  PyTorch：decoder-only Transformer / naive generation / KV cache (M2)
v0.3  推理系统：continuous batching / paged block manager           (M3)
v0.4  C++：pybind11 扩展，CPU 高性能 sampling & cache 操作           (M4)
v0.5  CUDA：自研 softmax / attention kernel，接入 PyTorch            (M5)
v1.0  集成：benchmark 对照 vLLM，交付源码阅读报告                     (M6)
```

最终工程结构（在 roadmap 版本基础上扩展）：

```text
mini-infer/
├── pyproject.toml / CMakeLists.txt
├── src/mini_infer/          # Python 主体（同 roadmap 结构）
│   ├── tokenizer/ model/ engine/ sampling/ ...
│   └── _ops/                # C++/CUDA 扩展的 Python 绑定层
├── csrc/
│   ├── cpu/                 # M4：C++ 算子
│   └── cuda/                # M5：CUDA kernel
├── tests/  benchmarks/  examples/  docs/
```

工程约束（继承 roadmap 并扩展）：

* `src` layout + `pyproject.toml`；公共 API 全部类型标注。
* 先定义行为再写测试；C++/CUDA 算子必须有 Python 参考实现作为 golden test。
* 第三方组件通过 Adapter 隔离；native 代码通过 `_ops` 层隔离。
* 每模块结束做一次正式 code review；源码阅读固定 tag/commit。

---

## 二、模块一：Python 进阶与工程化（4 周）

> 本模块直接采用 `roadmap.md` 的 Week 1～Week 2 全部内容 + Week 3 的工程部分，此处只列纲要与增补，细节以 roadmap 为准。

### 学习目标

* 建立 Python 工程心智模型：模块加载、引用语义、异常、日志、测试。
* 用类型系统（Protocol/ABC/泛型）定义模块边界。
* 在真实模块边界上应用 Strategy、Factory、Adapter，理解 composition over inheritance。
* 掌握 packaging、CI、并发模型（thread/process/asyncio、GIL）、profiling 方法。

### 核心知识点

| 主题 | 知识点 |
|------|--------|
| 工程基线 | pyproject.toml、src layout、editable install、ruff/mypy/pre-commit |
| 对象模型 | 名称绑定、可变性、浅/深拷贝、默认可变参数陷阱、dataclass |
| 模块系统 | 绝对/相对导入、`__init__.py`、循环导入、import-time side effect |
| 错误与观测 | 异常层级、`raise from`、context manager、logging、request ID |
| 类型系统 | Protocol vs ABC、TypedDict/Literal/NewType、`mypy --strict` |
| 设计模式 | Strategy（sampler）、Factory（registry）、Adapter（HF tokenizer）、Singleton 风险 |
| 并发 | GIL、asyncio、queue/backpressure/timeout/cancellation |
| 性能方法论 | perf_counter/cProfile、throughput vs latency、p50/p95/p99、benchmark 噪声 |

### 实践任务（mini-infer v0.1）

1. **Week 1**：搭建可安装的库骨架；实现 `InferenceRequest`/`SamplingConfig`；异常层级 + `ModelSession` 资源管理；结构化日志；20～30 个测试。
2. **Week 2**：`Tokenizer` Protocol + `WhitespaceTokenizer`；`GreedySampler`/`TopKSampler`（Strategy）；`SamplerFactory`（registry）；`HuggingFaceTokenizerAdapter`；重构全局 `ModelRegistry` 为依赖注入。
3. **Week 3**：完善 packaging（wheel + optional deps）；配置 CI 六步门禁；实现异步请求队列 `await engine.submit(request)`；tokenizer/scheduler benchmark 基线。
4. **Week 4**：模块总复盘 + 正式 code review（correctness/readability/testability/extensibility/observability 五维度）；补一份 ADR。

### 验收标准

* `python -m build` 产出的 wheel 可在干净环境安装并通过 smoke test。
* `mypy --strict`、ruff、全部测试通过；CI 绿。
* 不看资料能回答 roadmap Week 1/2/3 自测题（导入执行过程、ABC vs Protocol、GIL 影响等）。

---

## 三、模块二：PyTorch 深度学习框架（3 周）

> 对应 roadmap Week 3 Day 19-21 + Week 4 Day 22-25，并增补 autograd 与 dispatch 机制（为 M4/M5 写自定义算子做铺垫）。

### 学习目标

* 从执行模型角度理解 PyTorch：Tensor 内存布局、Module 调用协议、算子分发。
* 不依赖 `nn.MultiheadAttention`，手写 causal attention 并通过数值对照测试。
* 实现最小 decoder-only Transformer 与 autoregressive generation loop。
* 实现并验证 KV cache，建立 shape-first 的源码阅读习惯。

### 核心知识点

**Week 5：PyTorch 执行模型**

* Tensor：shape/dtype/device/stride、view vs copy、contiguous、broadcasting。
* `nn.Module`：parameter/buffer 注册、`__call__` vs `forward`、hook、`state_dict`。
* `train()/eval()`、`no_grad()/inference_mode()` 的语义差异。
* autograd 概览：计算图、`requires_grad`、为什么推理不需要它。
* dispatch 机制概览：Python API → C++ dispatcher → backend kernel（只建地图，不深挖）。

**Week 6：Attention 与 Transformer**

* Q/K/V 投影、`head_dim = hidden_size // num_heads`、reshape/transpose。
* scaled dot-product attention、causal mask、padding mask、softmax 数值稳定性。
* token embedding、位置信息（重点理解 RoPE 的概念，vLLM 会用到）。
* pre-norm vs post-norm、residual、FFN、LM head、logits。

**Week 7：生成与 KV cache**

* tokenizer 完整流水线：normalization → pre-tokenization → BPE → special tokens → padding/attention mask。
* prefill vs decode、last-token logits、EOS/stopping criteria、streaming。
* KV cache：为什么历史 K/V 可复用、cache shape `[layer, kv_head, seq, head_dim]`、MHA/MQA/GQA 对容量的影响。

### 实践任务（mini-infer v0.2）

1. `TinyModel` 调试练习：打印 shape、注册 hook、故意制造 dtype/device mismatch 并解释错误层次。
2. 手写 attention（roadmap Day 20 代码），测试：未来 token 权重为零、单头结果与手算一致、与 `F.scaled_dot_product_attention` 近似对照。
3. 最小 decoder-only Transformer：`[batch, seq] → [batch, seq, vocab]`，每个子模块独立单测，画一张 shape-flow 图。
4. naive generation loop，并写 `docs/naive-generation-bottlenecks.md` 识别五个低效点。
5. 为 `MiniAttention` 添加 KV cache：cache/no-cache logits 近似一致、超容量抛 `CacheCapacityError`；手算一次 cache 大小 `2 × layers × kv_heads × seq × head_dim × bytes`。
6. 增强 tokenizer（special tokens、批量 encode、padding、mask、vocab 持久化）；阅读 HF tokenizer 源码，输出 `docs/hf-tokenizer-call-chain.md`。

### 验收标准

* cache 与 no-cache 两种路径生成结果一致（贪心解码下逐 token 相同）。
* 能不看资料手写 causal attention 并解释每一步 shape 变化。
* 能解释 `Module.__call__ → forward` 之间发生了什么、hook 挂在哪里。

---

## 四、模块三：LLM 推理原理（3 周）

> 对应 roadmap Week 4 Day 26-28，扩展为独立模块，增补推理系统的性能模型与主流优化技术全景。

### 学习目标

* 建立推理系统的性能模型：为什么 decode 是 memory-bound、瓶颈如何随 batch/seq 变化。
* 实现 continuous batching scheduler 与简化版 paged block manager。
* 理解 vLLM 各优化技术要解决的问题（PagedAttention、chunked prefill、prefix caching、speculative decoding、量化）。
* 完成 vLLM 源码第一轮架构导航。

### 核心知识点

**Week 8：推理性能模型**

* roofline 模型：算术强度、compute-bound vs memory-bound。
* prefill（GEMM 密集，compute-bound）与 decode（GEMV 为主，memory-bound）的本质差异。
* KV cache 容量公式与显存预算；为什么 batch size 提升 decode 吞吐。
* throughput/latency trade-off：TTFT（首 token 延迟）与 TPOT（每 token 时间）。

**Week 9：调度与内存管理**

* 静态 batching → dynamic batching → iteration-level/continuous batching。
* admission control、token budget、fairness 与 starvation。
* 连续预分配 KV cache 的碎片问题；PagedAttention 的思想：logical block → block table → physical block。
* copy-on-write、prefix sharing、internal fragmentation。

**Week 10：推理优化技术全景（理论为主）**

* chunked prefill：为什么长 prompt 会阻塞 decode。
* prefix caching / automatic prefix caching。
* speculative decoding 的基本原理。
* 量化概览：INT8/FP8/AWQ/GPTQ 各解决什么问题（不要求实现）。
* FlashAttention 的核心思想：tiling + online softmax，避免物化 attention 矩阵（为 M5 铺垫）。

### 实践任务（mini-infer v0.3）

1. continuous batching scheduler（roadmap Day 26）：每个 decode iteration 重选 active requests；测试三个不同长度请求（2/5/8）时短请求不被长请求拖住；输出 scheduler 时间线。
2. CPU 版 `BlockManager`（roadmap Day 27）：分配/追加/释放/重用/容量不足；随机操作下的状态不变量测试（free list 与 allocated set 不相交等）。
3. 用 benchmark 验证性能模型：测量不同 batch size 下 naive loop 的 throughput/latency 曲线，对照理论解释拐点。
4. **vLLM 源码第一轮**（roadmap Day 28 顺序：示例入口 → 配置 → Engine → Scheduler → Model Runner → 模型实现 → Attention → cache manager，最后才是 kernel），输出 `docs/vllm-request-lifecycle.md`，每个箭头标注输入/输出类型、所有权、是否跨线程、是否性能关键路径。

### 验收标准

* 能推导给定模型配置下的 KV cache 显存占用，并解释 PagedAttention 解决的是哪类问题。
* 能画出 vLLM 从 request 到 output 的主调用链（不看笔记）。
* scheduler 与 block manager 通过全部不变量测试。

---

## 五、模块四：C++ 性能优化（3 周）

> 新增模块。目标不是"学完 C++"，而是掌握读懂并编写 vLLM csrc/ 级别代码所需的现代 C++ 与性能工程能力。

### 学习目标

* 掌握现代 C++（C++17/20）中与高性能代码相关的核心子集。
* 理解 CPU 性能模型：cache 层级、SIMD、分支预测、内存对齐。
* 用 pybind11 将 C++ 算子接入 Python/PyTorch，处理零拷贝与生命周期。
* 学会用 profiler 驱动优化，而不是猜测。

### 核心知识点

**Week 11：现代 C++ 核心子集**

* RAII、移动语义、`unique_ptr/shared_ptr`、`span/string_view`。
* 模板基础与常见惯用法（读 vLLM/PyTorch csrc 必需）：函数模板、模板特化、`constexpr`。
* 内存模型基础：对齐、placement new、避免不必要拷贝。
* 与 Python 的对照：值语义 vs 引用语义、所有权显式化。

**Week 12：CPU 性能工程**

* cache line、局部性（时间/空间）、false sharing。
* SIMD：编译器自动向量化、intrinsics 初步（AVX2 一个例子即可）。
* 多线程：`std::thread`、OpenMP、任务划分与负载均衡。
* 测量工具：`perf`、Instruments（macOS）、google benchmark。
* 矩阵乘法优化经典路径：naive → loop reorder → tiling → 向量化（这是 M5 CUDA GEMM 的 CPU 预演）。

**Week 13：pybind11 与 PyTorch 扩展**

* pybind11：函数/类绑定、GIL 释放、numpy buffer protocol。
* PyTorch C++ 扩展：`torch::Tensor` 的 accessor、`TORCH_LIBRARY` 注册、setup.py/CMake 构建。
* 零拷贝原则：C++ 侧只借用 tensor 内存，不管理生命周期。
* 错误处理：C++ 异常如何翻译成 Python 异常（对应 M1 的错误翻译原则）。

### 实践任务（mini-infer v0.4）

1. **CPU GEMM 优化练习**（独立小项目）：从 naive 三重循环出发，依次应用 loop reorder、blocking/tiling、OpenMP、向量化，每步用 google benchmark 记录提升，写成 `docs/cpu-gemm-optimization.md`（假设/环境/结果/未排除变量，沿用 M1 benchmark 规范）。
2. 用 pybind11 实现 `mini_infer._ops` 的 CPU 算子并替换 Python 实现：
   * `top_k_sampling`（含温度缩放）；
   * block manager 的热点路径（block 分配/查表）；
   * 每个算子配 golden test：与 Python 参考实现逐元素对照。
3. benchmark 对照：C++ 算子 vs Python 实现的加速比报告；分析哪些场景加速明显、哪些被调用开销吃掉。
4. 源码阅读练习：挑 vLLM `csrc/` 下一个简单 CPU/C++ 文件（如 cache 操作），用 M1 的"源码阅读登记表"格式做一次精读。

### 验收标准

* CPU GEMM 相对 naive 版本获得可复现的 10x+ 加速，并能解释每步优化的原理。
* `pip install -e .` 能自动构建 C++ 扩展；golden test 全部通过。
* 能读懂 vLLM csrc 中一个 C++ 源文件的所有权与调用约定。

---

## 六、模块五：CUDA 并行编程（4 周）

> 新增模块。目标：能读懂 vLLM 的 attention kernel 思路，并为 mini-infer 写出正确且经过 profile 的自研 kernel。

### 学习目标

* 掌握 CUDA 编程模型：grid/block/thread、内存层级、同步原语。
* 理解 GPU 性能优化核心手段：coalescing、shared memory、occupancy、reduction。
* 实现推理关键 kernel：softmax、GEMM（tiled）、单头 attention、简化 paged attention。
* 会用 Nsight Compute 定位 kernel 瓶颈。

### 核心知识点

**Week 14：CUDA 编程模型**

* host/device、kernel launch、grid/block/thread 索引计算。
* 内存层级：global/shared/register/constant；带宽与延迟数量级。
* warp 执行模型：SIMT、divergence、warp shuffle。
* 同步：`__syncthreads()`、stream、event；错误检查规范。

**Week 15：核心优化技术**

* memory coalescing：访存模式如何决定带宽利用率。
* shared memory tiling（GEMM 经典优化，与 M4 CPU tiling 对照）。
* reduction 与 online softmax（数值稳定 + 单遍扫描——FlashAttention 的基石）。
* occupancy、寄存器压力、bank conflict。
* Nsight Compute：定位 memory-bound vs compute-bound。

**Week 16：推理 kernel 实战**

* attention kernel 结构：每个 block 处理一个 (sequence, head)。
* decode attention 的特点：query 长度为 1，本质是带 softmax 的 GEMV。
* paged attention 的 kernel 视角：通过 block table 间接寻址读取 K/V。
* Triton 初步：用 Triton 重写一个 kernel，对比开发效率（vLLM 大量使用 Triton）。

**Week 17：集成与对照阅读**

* PyTorch custom CUDA op：stream 语义、`at::cuda::CUDAGuard`。
* 与 `F.scaled_dot_product_attention`、FlashAttention 的性能对照方法。
* 精读 vLLM paged attention kernel（v1 版本较易读）：block table 如何消费、每个 warp 的分工。

### 实践任务（mini-infer v0.5）

难度递进的 kernel 序列，每个都要求：正确性 golden test（对照 PyTorch）+ Nsight profile 记录：

1. vector add、elementwise（温度缩放）——熟悉工具链。
2. reduction（求 max/sum）→ **数值稳定的 online softmax**。
3. tiled GEMM：naive → coalesced → shared memory tiling，记录每步 TFLOPS。
4. **单头 decode attention kernel**：`q [1, d]` 对 `K/V [seq, d]`，融合 QK^T + softmax + weighted V。
5. **简化 paged attention**：K/V 存储在非连续 block 中，kernel 通过 block table 间接寻址（衔接 M3 的 BlockManager，把它从"CPU 模拟"变成真实 GPU 数据通路）。
6. 将 4/5 接入 mini-infer 的 attention 后端：`backend="naive" | "cuda"` 可切换，端到端生成结果一致。
7. 用 Triton 重写 softmax kernel，对比 CUDA C++ 版本的代码量与性能。

### 验收标准

* 所有 kernel 通过与 PyTorch 参考实现的近似对照测试（含边界：seq=1、非对齐长度）。
* tiled GEMM 相对 naive 版本有可解释的性能提升，能读懂 Nsight 关键指标。
* 能向他人讲清楚 paged attention kernel 如何通过 block table 找到物理 K/V。

---

## 七、模块六：vLLM 源码精读与最终集成（3 周）

> 对应 roadmap Week 5，扩展为三层对照精读 + mini-infer v1.0 交付。

### 学习目标

* 完成 PyTorch → Transformers → vLLM 三层对照阅读，理解同一抽象在不同层的职责。
* 深入 vLLM 的 Scheduler、KV cache manager、attention backend 实现细节。
* 交付 mini-infer v1.0，用三组实验验证正确性、调度收益与性能特征。

### 核心知识点与阅读路径

**Week 18：三层对照阅读**（roadmap Day 29 完整执行）

* 第一层 PyTorch：`Module.__call__`、SDPA API、state_dict、inference mode。
* 第二层 Transformers：选一个 decoder-only 模型，从 config → CausalLM → decoder layer → attention → cache 输入输出 → generate 入口。
* 第三层 vLLM：模型 forward → Model Runner 组 batch → Scheduler 决策 → cache manager → attention backend → sampler。
* 产出"三层对照表"（Module 执行 / Attention / Cache / Batch 四行），并做 shape 对照调试实验。

**Week 19：vLLM 深水区**（在 M3 第一轮导航 + M5 kernel 阅读的基础上）

* Scheduler 精读：waiting/running 队列、token budget 扣减、preemption（swap vs recompute）。
* KV cache manager：block 分配/释放时机、prefix caching 的 hash 机制。
* attention backend 选择逻辑：不同 backend 的适用条件。
* 每个主题用"源码阅读登记表"记录，问题必须可验证（如"decode step 的 cache metadata 在哪里产生"）。

**Week 20：最终交付**（roadmap Day 30 完整执行 + 扩展）

### 实践任务（mini-infer v1.0）

功能要求 = roadmap Day 30 清单 + 以下扩展：

* C++ CPU 算子路径与 CUDA attention 后端，可通过配置切换。
* benchmark 命令支持输出 TTFT/TPOT/throughput。

三组最终实验：

1. **正确性**：cache/no-cache、Python/C++/CUDA 三种后端输出一致。
2. **调度**：continuous batching 相对静态 batching 对短请求等待时间的改善（量化）。
3. **性能**：batch size 与序列长度扫描下的 throughput/latency 曲线；与理论 roofline 预期对照；可选与 vLLM 同模型对照并解释差距来源。

最终 code review 沿用 roadmap Day 30 的九个问题，追加：

* native 算子的错误是否正确翻译为 Python 领域异常？
* CUDA 后端失败时能否安全回退到 naive 后端？
* kernel 的正确性测试是否覆盖非对齐/极端 shape？

### 最终交付物

```text
mini-infer v1.0
├── 可安装 wheel（含 C++/CUDA 扩展的构建配置）
├── README + 架构设计文档 + shape-flow 图
├── 100+ 测试（unit/integration/golden test 分层）
├── CI pipeline（lint/type/test/build/smoke）
├── continuous batching scheduler + paged block manager
├── 三后端 attention（naive / C++ 辅助 / CUDA）
├── benchmark 报告（TTFT/TPOT/throughput 曲线 + roofline 分析）
├── CPU GEMM 与 CUDA kernel 优化记录
└── PyTorch/Transformers/vLLM 三层源码阅读报告
```

---

## 八、贯穿方法论（全课程通用）

以下方法从 M1 开始建立，每个模块强制执行：

1. **shape-first**：任何模型代码先问 shape 如何变化，状态存在哪里。
2. **从可运行入口读源码**：最小脚本 → 当前方法 → 输入输出类型 → 下一层调用；自顶向下（责任划分）与自底向上（数据计算）在 attention 会合。
3. **源码阅读登记表**：Repository/Tag/Entry point/Question/Call chain/State ownership/Shape changes/Error path/Unresolved questions——只记可验证问题。
4. **测试优先于底层实现**：example → public API → tests → interface → concrete → optimized → kernel。
5. **先测量再优化**：所有性能结论必须附假设、环境、输入、重复次数、未排除变量。
6. **golden test 原则**：每个优化实现（C++/CUDA/Triton）都必须有朴素参考实现作为对照，正确性优先于速度。

## 九、各模块自测清单

* **M1**：不看资料创建可安装项目、解释 import 过程、比较 ABC/Protocol、解释 GIL 与 async queue。
* **M2**：手写 causal attention、解释 `__call__ → forward`、推导 KV cache shape、cache/no-cache 一致性验证。
* **M3**：解释 prefill/decode 为何一个 compute-bound 一个 memory-bound、画 vLLM 请求生命周期、推导 cache 显存预算。
* **M4**：解释移动语义与 RAII、说出 CPU GEMM 每步优化的原理、写一个带 golden test 的 pybind11 算子。
* **M5**：写出正确的 online softmax kernel、解释 coalescing 与 shared memory tiling、读懂 Nsight 的 memory/compute 利用率。
* **M6/最终**：给一个不熟悉的 LLM 推理仓库，在 60～90 分钟内定位入口、public API、tokenizer 路径、forward、attention、cache 结构、scheduler，并输出可信调用链图。

## 十、刻意舍弃的内容

与 roadmap 的取舍原则一致，本课程**不覆盖**：

* 训练与分布式训练（FSDP/DeepSpeed/张量并行的训练侧）。
* Python 冷门语法（metaclass、descriptor 完整实现）。
* 完整的 C++ 语言特性（协程、模块、模板元编程深水区）。
* 手写生产级 FlashAttention（只要求理解思想 + 实现简化版）。
* 多机推理、张量并行的实现细节（阅读 vLLM 时了解概念即可）。

核心主线始终是：

```text
模块边界 → 类型契约 → 数据 shape → 状态所有权
→ 请求生命周期 → 性能模型 → 算子实现 → 源码调用链
```
