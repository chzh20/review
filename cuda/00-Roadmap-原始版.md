# CUDA 面试 4 周冲刺 Roadmap

> 来源：对话截图逐字提取（共 4 张）。被截图边缘截断处已用 `[截图截断]` 标注。

**提问**：用一个月准备 CUDA 面试，结合全网的面试经验，帮我做一个 roadmap

**回答**：

一个月的 CUDA 面试冲刺时间非常紧凑，但只要**抓核心、重代码、攻高频**，完全可以通关。CUDA 面试的核心逻辑是：**"不仅要懂架构，更要手写过核函数（Kernel），并且知道怎么做性能调优。"**

以下是结合全网大厂（AI 芯片、大模型算子、自动驾驶等公司）高频面试经验，为你量身定制的 **4 周冲刺 Roadmap**。

---

## 📅 第一周：硬件架构与执行模型（打牢理论地基）

面试官非常喜欢从硬件底层提问，因为只有懂硬件，才能写出高性能的算子。

- **核心知识点：**
  - **GPU 硬件架构**：SM（Streaming Multiprocessor）、SP（CUDA Core）、Tensor Core 的关系；流处理器集群的内部结构。
  - **执行模型（Execution Model）**：Grid、Block、Thread 的三维映射关系；Warp（线程束）的概念；Warp Divergence（分支分化）的原因与规避方法。
  - **硬件潜伏期掩盖**：为什么要保持高的 Occupancy（占用率）？如何计算 Occupancy？

- **高频面试题：**
  - 什么是 Warp Divergence？如果在 `if-else` 中线程走不同分支会发生什么？
  - SIMD 和 SIMT 的区别是什么？
  - 如果一个 Block 设为 35 个线程，硬件实际上会怎么分配？（答：分配 2 个 Warp，共 64 个线程，多余的掩码关闭）

---

## 📅 第二周：内存架构与访存优化（面试重灾区 ⭐）

CUDA 性能瓶颈 80% 在访存。这一周是最核心、最容易被挂的部分。

- **核心知识点：**
  - **内存层级（Memory Hierarchy）**：Register、Shared Memory、Global Memory、Constant/Texture Memory 的速度与可见范围。
  - **Global Memory 访存对齐**：什么是 Coalesced Memory Access（合并访存）？AOS 与 SOA 的区别。
  - **Shared Memory 冲突**：Bank Conflict（银行冲突）的原理；如何通过 Padding（填充）来消除冲突。
  - **原子操作（Atomic Operations）**：为什么需要原子操作？它的性能开销在哪里？

- **高频面试题：**
  - 什么是 Bank Conflict？怎么解决？（以二阶矩阵转置为例说明 Padding 技巧）
  - 写一个指针相加的例子，解释什么样的访存是合并的，什么是不合并的。
  - 如何理解 `__shared__` 内存的广播（Broadcast）和多播（Multicast）机制？

---

## 📅 第三周：经典算子手写与并行算法（代码通关关键）

很多面试会直接让你在白板或 IDE 上手写 Kernel 算子。不要只看书，必须上机敲代码。

- **核心知识点与手写练习：**
  - **Vector Add / Element-wise 算子**：暖身题，理解一维/多维索引计算。
  - **Matrix Multiplication（GEMM 优化）**：
    - 朴素版矩阵乘法。
    - 使用 Shared Memory 的分块（Tiled）矩阵乘法（大厂必考！）。
  - **Reduction（并行规约）**：理解 Tree-based 规约。掌握循环展开、Warp Shuffle（线程束洗牌指令）优化。
  - **Prefix Sum (Scan) / Histogram**：了解一维前缀和与直方图的并行实现思路。

- **高频面试题：**
  - 请手写一个基于 Shared Memory 的矩阵乘法 Kernel，并计算其访存节约了多少倍。
  - 在 Reduction 优化中，为什么用 Warp Shuffle 比用 Shared Memory 更好？

---

## 📅 第四周：工程实践、性能调优与大模型算子（加分项与模拟）

最后一周提升工程视野，结合现在的 LLM（大模型）热点进行查漏补缺。

- **核心知识点：**
  - **并发与异步**：CUDA Stream（流）的概念；默认流与非默认流；如何利用 Stream 实现 计算与传输重叠（Overlap of Computation and Communication）。
  - **性能分析工具**：知道如何使用 NVIDIA Nsight Compute (NCU) 和 Nsight Systems (NSYS)。了解什么是 Compute Bound（计算受限）和 Memory Bound（带宽受限）。
  - **大模型高频**：了解 FlashAttention 的核心思想（Tiling + 减少 HBM 读写）；了解混合精度训练（FP16/BF16/FP8）与 Tensor Core 的使用。

- **高频面试题：**
  - 如何判断一个 CUDA 程序是计算密集型还是访存密集型？
  - 给你一个耗时很长的 Kernel，你用 NCU 分析时会优先看哪几个指标？（如：SOL, Memory Throughput, Occupancy）
  - 讲一讲 FlashAttention 的原理，它为什么能变快？

---

## 💡 复习搞钱小贴士（Tips）

1. **代码仓库准备**：在 GitHub 上自己建一个 `CUDA-Interview-Prep` 的仓库。把第二、第三周提到的算子（MatrixMul, Reduction 等）从零纯手写一遍，写好注释。面试官如果看你 `[截图截断]`
