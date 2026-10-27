# CUDA 面试 4 周冲刺教程（A100 / sm_80 版）

> 面向：有 C++ 大型系统经验、需要在一个月内通过 CUDA / AI Infra 推理引擎岗位技术面的工程师。
> 硬件基准：NVIDIA A100 (GA100, compute capability 8.0)。所有数字标注了出处，可追溯到官方文档或论文。

---

## 0. 怎么用这套教程

**不要按"章节"读，按"面试题"读。**

每个周文档的结构是固定的：

| 模块 | 作用 | 建议用法 |
|---|---|---|
| 考察点拆解 | 面试官问这题到底在筛什么 | 先读，建立"答题坐标系" |
| 概念精讲 | 只讲会被追问的深度 | 通读一遍，第二遍只看加粗结论 |
| 必背数字 | 现场能报出来的硬数字 | 每天早上过一遍，5 分钟 |
| 题库 | 问 → 30 秒答法 → 追问链 | **核心**：遮住答案自己说，说不出来再翻 |
| 代码 | 可编译运行的最小实现 | 在 A100 上跑一遍，改参数看性能变化 |
| 自测清单 | 判断是否可以进入下一周 | 全打勾才推进 |

**时间分配建议**（每天 3 小时，与你现有节奏对齐）：

- 第 1 小时：题库自测（口述，不写）
- 第 2 小时：手写代码 + 跑 NCU 看指标
- 第 3 小时：读精讲 + 整理笔记

**一条硬规则**：任何一题，如果你不能在 60 秒内用"结论 + 原因 + 一个数字"三段式说完，就等于不会。面试现场没有时间给你现场推导。

---

## 1. 四周总表

| 周 | 主题 | 面试权重 | 必须产出 |
|---|---|---|---|
| W1 | 执行模型与硬件架构 | ★★★★ | 能口算 occupancy；讲清 warp divergence 的代价 |
| W2 | 内存层级与访存优化 | ★★★★★ | 能手画访存合并/不合并的两种 pattern；能解释 Padding 为什么有效 |
| W3 | 算子手写与并行算法 | ★★★★★ | 白板写出 tiled GEMM、reduction、scan |
| W4 | 性能调优与大模型算子 | ★★★★ | 会用 NCU 定位瓶颈；讲透 FlashAttention 的 IO 视角 |

面试的真实分布（AI 芯片 / 算子 / 推理引擎岗位）大致是：手写 kernel 40%、访存优化 30%、架构概念 20%、工程与调优 10%。这决定了 W2 + W3 必须是重心。

---

## 2. 文件索引

```
cuda-interview-tutorial/
├── README.md                          ← 你在这里
├── 01-执行模型与硬件架构.md            ← W1
├── 02-内存层级与访存优化.md            ← W2（最重）
├── 03-算子手写与并行算法.md            ← W3（最重）
├── 04-性能调优与大模型算子.md          ← W4
└── code/
    ├── Makefile
    ├── common.h
    ├── 00_sanity.cu             设备信息 + 计时模板
    ├── 01_vector_add.cu         grid-stride loop
    ├── 02_matmul.cu             朴素 / tiled / tiled+padding 对照
    ├── 03_transpose.cu          合并访存 + Padding 消冲突（经典题）
    ├── 04_reduction.cu          三级优化 + warp shuffle
    ├── 05_scan.cu               Hillis-Steele vs Blelloch
    └── 06_histogram.cu          shared 私有直方图
```

编译：

```bash
cd code && make all && ./02_matmul
```

Makefile 默认 `-arch=sm_80`，如果你在别的卡上跑，改成对应的 `sm_XX`。

---

## 3. 必背数字速查（A100 / CC 8.0）

全部来自 CUDA 编程指南的 Compute Capabilities 附录 [R2] 与 Ampere 架构文档 [R4]。

### 3.1 线程与调度

| 项 | 值 |
|---|---|
| Warp 大小 | **32**（自 2007 年至今所有 NVIDIA 架构都是 32） |
| 每 Block 最大线程数 | **1024** |
| 每 SM 最大常驻 Warp | **64** |
| 每 SM 最大常驻线程 | **2048**（= 64 × 32） |
| 每 SM 最大常驻 Block | **32** |
| Grid 最大 x 维 | **2³¹−1** |
| Grid 最大 y/z 维 | **65535** |
| Block 最大 z 维 | **64** |

### 3.2 存储资源（每 SM）

| 项 | 值 |
|---|---|
| 32-bit 寄存器 | **65536（64K）** |
| 每线程最大寄存器 | **255** |
| 每 Block 最大寄存器 | **64K** |
| Shared Memory 总量 | **164 KB** |
| 每 Block 最大 Shared Memory | **163 KB**（>48KB 需动态共享内存 + opt-in） |
| Shared Memory Bank 数 | **32**，bank 宽度 **4 B**（Volta 之后固定） |
| Constant Memory | 64 KB（每 SM 常量缓存工作集 8 KB） |

### 3.3 A100 整卡

| 项 | 值 |
|---|---|
| SM 数 | **108**（满血 GA100 是 128，A100 屏蔽到 108） |
| FP32 CUDA Core | 6912（64/SM） |
| Tensor Core | 432（4/SM，第三代） |
| L2 | **40 MB** |
| HBM2 | 40 GB / 1555 GB/s（80GB 版本 2039 GB/s） |
| FP32 峰值 | 19.5 TFLOPS |
| TF32 Tensor | 156 TFLOPS |
| FP16/BF16 Tensor | 312 TFLOPS |

### 3.4 由此推出的三个"面试必答"结论

1. **机器的平衡点（machine balance）**：A100 FP32 是 19.5 TFLOPS / 1555 GB/s ≈ **12.5 FLOP/Byte**；FP16 Tensor 是 312 TFLOPS / 1555 GB/s ≈ **200 FLOP/Byte** [R7]。
   → 算术强度 < 12.5 的 FP32 kernel 一定是访存受限；GEMM 在 Tensor Core 上要跑到 200 FLOP/Byte 以上才吃满算力。这就是为什么 FlashAttention 要拼命减少 HBM 读写。
2. **occupancy 上限被寄存器卡死**：64K 寄存器 / 2048 线程 = 每线程 **32 个寄存器**才能满 occupancy。用 64 个寄存器 → occupancy 最多 50%（1024 线程）；128 个 → 25%。
3. **一个 Block 最少吃一个 SM 的 warp 槽**：block 只开 1 个线程，也占 1 个 warp 槽；开 35 个线程，占 **2 个 warp**（第二个 warp 只有 3 条 lane 有效）。

---

## 4. 引用源

编号在正文中以 `[Rn]` 引用。

| 编号 | 来源 | 说明 |
|---|---|---|
| [R1] | CUDA C++ Programming Guide — https://docs.nvidia.com/cuda/cuda-programming-guide/ | 语义与执行模型的唯一权威 |
| [R2] | CUDA C++ Programming Guide · Compute Capabilities — https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html | 上面所有硬数字的出处 |
| [R3] | CUDA C++ Best Practices Guide — https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html | 合并访存、bank conflict、共享内存分块的官方数据 |
| [R4] | NVIDIA Ampere Architecture In-Depth — https://developer.nvidia.com/blog/nvidia-ampere-architecture-in-depth/ | A100 SM 结构、CC 对比表 |
| [R5] | Nsight Compute Profiling Guide — https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html | SOL / Occupancy / Memory Workload 各 section 定义 |
| [R6] | Nsight Systems User Guide — https://docs.nvidia.com/nsight-systems/UserGuide/index.html | 时间线与 Stream 重叠分析 |
| [R7] | GPU Performance Background User's Guide — https://docs.nvidia.com/deeplearning/performance/dl-performance-gpu-background/ | 算术强度、roofline 的官方讲法 |
| [R8] | Dao et al., *FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness*, arXiv:2205.14135 | tiling + IO 复杂度分析 |
| [R9] | Dao, *FlashAttention-2*, arXiv:2307.08691 | 并行度与工作划分 |
| [R10] | Shah et al., *FlashAttention-3*, arXiv:2407.08608 | Hopper 异步 + FP8 |
| [R11] | *Dissecting the NVIDIA Volta GPU Architecture via Microbenchmarking*, arXiv:1804.06826 | 各级存储延迟的实测值 |
| [R12] | Williams, Waterman, Patterson, *Roofline*, CACM 2009, doi:10.1145/1498765.1498785 | Roofline 模型原始论文 |
| [R13] | Hwu, Kirk, El Hajj, *Programming Massively Parallel Processors*, 4th ed. | 并行规约/扫描的标准讲法 |
| [R14] | NVIDIA, *Train With Mixed Precision* — https://docs.nvidia.com/deeplearning/performance/mixed-precision-training/index.html | FP16 动态范围与 loss scaling |
| [R15] | PTX ISA — https://docs.nvidia.com/cuda/parallel-thread-execution/ | `mma.sync` / `cp.async` / `red` 指令语义 |

**关于数字可信度的说明**：`[R2]` 类硬规格是官方表格，可直接引用；存储延迟这类数字在不同架构、不同测量方法下差异很大，教程中只给"数量级"并标注来源，面试时应该说"量级"而不是报精确值——报精确值反而暴露你是背的。

---

## 5. 使用检查表

- [ ] 能在纸上画出 GPU 内存层级图并标出各级的 scope（线程/block/SM/全局）与生命周期
- [ ] 能不看文档写出 tiled GEMM 并解释 `__syncthreads()` 为什么需要两次
- [ ] 能算出 occupancy 的四个限制因素并说明哪个最常成为瓶颈
- [ ] 能解释 Bank Conflict 的成因并说出 Padding 的数学原理
- [ ] 能写出 warp shuffle reduction 并说明为什么比 shared memory 版快
- [ ] 能用 NCU 的 SOL 页面判断一个 kernel 是 compute bound 还是 memory bound
- [ ] 能讲清 FlashAttention 的 online softmax 递推，以及它省掉的到底是什么
- [ ] 有一个公开的 GitHub 仓库，里面有 6 个从零手写的 kernel 和自己的 NCU 截图

最后一条最容易被忽略，但它是面试官唯一能"验证"你的东西。
