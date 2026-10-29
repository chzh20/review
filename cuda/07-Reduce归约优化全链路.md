# CUDA Reduce 优化全链路（面试准备版）

> 目标：能从头推演 8 个版本，每一步都说清「为什么慢 / 改什么 / 收益从哪来」，并能接住追问。
> 说明：文中带宽/耗时数字为**量级参考**（源自 NVIDIA 经典讲义 GT200 数据 + 现代 GPU 经验），不同硬件绝对值不同，但相对关系和瓶颈归属是一致的。
> 定位：`03-算子手写与并行算法.md` §5 给的是「四版本精简版」；本文是同一条链路的**完整八版本深挖**，配合 `code/04_reduction.cu` 可直接跑出对照数据。

---

## 0. 先建立心智模型（比背代码重要）

### 0.1 Reduce 天生是访存受限（memory bound）

```
算术强度 = 1 次加法 / 4 字节读 = 0.25 FLOP/Byte
```

现代 GPU 的 roofline 拐点在 10 FLOP/Byte 量级，0.25 远在左侧 → **性能上限完全由 DRAM 带宽决定**：

```
t_min = N × sizeof(T) / BW_peak
```

| 规模 | 数据量 | A100 (1.55 TB/s) 下限 | H100 (3.35 TB/s) 下限 |
|---|---|---|---|
| 1e8 float | 400 MB | 0.26 ms | 0.12 ms |
| 1e9 float | 4 GB | 2.6 ms | 1.2 ms |

**面试第一句就该说**：这不是算力题，是搬运题。所有优化只做两件事：

1. **让访存单元持续满负荷**：合并访存（coalescing）+ 足够的并发访存请求（MLP/TLP/ILP）；
2. **把非访存开销压到可忽略**：bank conflict、warp 发散、`__syncthreads`、多余指令。

### 0.2 Reduce 的三层结构

```
N 个元素
  ├─ L1  thread-local 累加   ：每线程读多个元素，寄存器内先加（无同步、无冲突）
  ├─ L2  block 内归约        ：tree / warp shuffle，把 BLOCK 个值变成 1 个
  └─ L3  grid 级归约         ：把 gridDim 个 partial 变成最终 1 个
```

**所有版本的区别，只是这三层用什么机制实现、每层做多少次同步。**

### 0.3 测试配置（下文统一假设）

- 类型 `int`（避免浮点结合律干扰结论；浮点差异单独讨论）
- `BLOCK = 256`（8 个 warp），`n` 为 2 的幂（非 2 的幂在第 12 节讨论）
- 基线取最终版 V7 = 1.00x

---

## 1. V0：全局内存归约（朴素基线）

### 1.1 两个朴素写法

```cuda
// V0-a：单线程串行（最朴素，但面试写出来就是送分）
__global__ void reduce_serial(const int* a, int* out, size_t n) {
    int sum = 0;
    for (size_t i = 0; i < n; ++i) sum += a[i];
    *out = sum;
}
```

```cuda
// V0-b：直接在 global memory 上做树形归约
__global__ void reduce_gmem_tree(int* a, size_t n) {
    for (size_t s = 1; s < n; s *= 2) {
        size_t i = (blockIdx.x * blockDim.x + threadIdx.x) * 2 * s;
        if (i + s < n) a[i] += a[i + s];      // 读 2 写 1，全在显存
        __gpu_sync();                          // 需要“整个 grid”的同步
    }
}
```

### 1.2 问题

| 写法 | 致命问题 |
|---|---|
| V0-a | 1 个线程 → 无并发，1 次 load 只用 4/32 字节扇区（1/8 效率） |
| V0-b | **没有 grid 级同步原语**，只能启动 log2(n) 个 kernel（16M 元素 = 24 次 launch，每次 ~5 µs，光 launch 就 120 µs，而 DRAM 下限只有 ~0.02 ms）；高 stride 时完全不合并 |

### 1.3 结论

朴素全局版本的真正瓶颈不是带宽，而是**"无法在设备端做全局同步"**。
→ 所以要**先把问题收缩到 block 内**：block 内可以用 `__syncthreads()` 做便宜的同步，用 shared memory 做片上树形归约。这就是 V1 的全部动机。

**收益**：0（基线）。

---

## 2. V1：共享内存归约（交错寻址 + 分支发散）

### 2.1 关键代码

```cuda
// 每个 block 处理 BLOCK 个元素，输出 1 个 partial 到 g_odata[blockIdx.x]
__global__ void reduce_v1(const int* g_idata, int* g_odata) {
    extern __shared__ int sdata[];
    unsigned int tid = threadIdx.x;
    unsigned int i   = blockIdx.x * blockDim.x + threadIdx.x;

    sdata[tid] = g_idata[i];          // 全局→共享，合并访存（好）
    __syncthreads();

    for (unsigned int s = 1; s < blockDim.x; s *= 2) {
        if (tid % (2 * s) == 0)        // ← 罪魁祸首
            sdata[tid] += sdata[tid + s];
        __syncthreads();
    }
    if (tid == 0) g_odata[blockIdx.x] = sdata[0];
}
```

### 2.2 结构说明

- **交错寻址（interleaved addressing）**：第 k 轮让 `tid % (2s) == 0` 的线程干活，活跃元素在数组里是**稀疏交错**分布的。
- 树高 = `log2(BLOCK) = 8` 层 → 8 次 `__syncthreads()`。
- 每层活跃线程数减半，总工作量 O(BLOCK)，正确但**效率极差**。

### 2.3 瓶颈：warp divergence（线程发散）

`s = 1` 时只有 16/32 个 lane 活跃；`s = 32` 时，整个 block 只有 1 个线程（`tid==0`）干活，但 **8 个 warp 全部要被调度去执行这条指令**——用 8 个 warp 的发射带宽去做 1 次加法。

另外 `%` 和 `/` 是整数除法，编译成多次乘加/移位，8 层循环里被反复执行。

**收益**：相对 V0 约 2x，但带宽只吃到 ~20%（DRAM 大部分时间在等）。

---

## 3. V2：消除 warp divergence（改为连续活跃）

### 3.1 关键改动

把「谁干活」的条件从**取模（稀疏）**改成**下标比较（连续）**：

```cuda
for (unsigned int s = 1; s < blockDim.x; s *= 2) {
    int index = 2 * s * tid;              // 交错寻址保留
    if (index < blockDim.x)               // ← 条件连续：前 blockDim/(2s) 个线程
        sdata[index] += sdata[index + s];
    __syncthreads();
}
```

### 3.2 收益

- 活跃线程 = `tid < blockDim/(2s)`，是**连续的低编号线程** → 只占满前面若干个 warp，后面的 warp 整个不活跃（不发射指令），不再有半个 warp 空转。
- 去掉了整数取模。

**收益**：带宽从 ~20% 提到 ~32%（约 1.4x）。

### 3.3 新问题：**bank conflict**

`index = 2*s*tid` 意味着 warp 内相邻 lane 访问的共享内存地址间隔 `2s` 个 word：

| s | 步长（word） | 冲突度 |
|---|---|---|
| 1 | 2 | 2-way |
| 2 | 4 | 4-way |
| 4 | 8 | 8-way |
| 8 | 16 | 16-way |
| ≥16 | 32 | **32-way（全 warp 打同一个 bank）** |

共享内存 32 个 bank，地址 `a` 落在 `bank = a % 32`。步长 32 → 所有 lane 落到**同一个 bank** → 硬件串行化 32 次。8 层里后 5 层都是最坏情况。

**这就是"解决了发散，却引入了冲突"——面试里最容易被追问的一个转折点。**

---

## 4. V3：顺序寻址，彻底消除 bank conflict

### 4.1 关键改动：翻转树的生长方向

不要再「第 k 轮合并间隔 2s 的元素」，改成「**后面的元素加到前面的元素上**」：

```cuda
__global__ void reduce_v3(const int* g_idata, int* g_odata) {
    extern __shared__ int sdata[];
    unsigned int tid = threadIdx.x;
    unsigned int i   = blockIdx.x * blockDim.x + threadIdx.x;

    sdata[tid] = g_idata[i];
    __syncthreads();

    for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) sdata[tid] += sdata[tid + s];   // ← 步长为 1 的连续访问
        __syncthreads();
    }
    if (tid == 0) g_odata[blockIdx.x] = sdata[0];
}
```

### 4.2 为什么它同时解决两个问题

- **冲突**：warp 内 32 个 lane 访问 `sdata[tid]` 和 `sdata[tid+s]`，各自都是**连续地址** → 落在 32 个不同 bank → **零冲突**。
- **发散**：`tid < s` 依然是连续条件，活跃的是低位 warp，整 warp 全活跃。
- 顺带：`s` 从 `BLOCK/2` 开始递减，最后一层只剩 1 个线程，但层数不变（还是 8 次同步）。

**收益**：~1.6x，带宽 ~50%。这是**第一个"正确的形状"**，后面所有优化都在这个骨架上做减法。

### 4.3 剩余瓶颈

1. 8 次 `__syncthreads()`，其中后 5 次只有 1 个 warp 干活、7 个 warp 空等屏障；
2. 每层都要「读 smem → 加 → 写 smem」，一半的指令是纯开销；
3. 每线程只搬 1 个元素 → 每个 block 只有 256 个 in-flight load，**MLP 不足**，访存延迟暴露。

---

## 5. V4：Unrolling（展开循环，两个方向）

### 5.1 方向一：加载时先加（减少 block 数 + 首次合并进寄存器）

```cuda
unsigned int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;
sdata[tid] = g_idata[i] + g_idata[i + blockDim.x];   // 一次搬 2 个元素，寄存器内先加
__syncthreads();
```
两个 load 互相独立 → **ILP 翻倍**，延迟被两个请求重叠掩盖；block 数减半 → partial 数、总屏障次数、block 调度开销全部减半。

### 5.2 方向二：最后一个 warp 不需要同步（去掉最后 5 次 `__syncthreads`）

```cuda
for (unsigned int s = blockDim.x / 2; s > 32; s >>= 1) {   // 只在 >32 时同步
    if (tid < s) sdata[tid] += sdata[tid + s];
    __syncthreads();
}
if (tid < 32) {                       // 只剩 1 个 warp：warp 内天然同步
    volatile int* smem = sdata;        // ← 必须 volatile，见下
    smem[tid] += smem[tid + 32];
    smem[tid] += smem[tid + 16];
    smem[tid] += smem[tid + 8];
    smem[tid] += smem[tid + 4];
    smem[tid] += smem[tid + 2];
    smem[tid] += smem[tid + 1];
}
```

**为什么能去同步**：warp 内 32 个 lane 在同一个指令流上锁步执行（Volta 之前是硬保证；Volta 之后需要 `__syncwarp()` 显式收敛，见第 12 节）。

**为什么必须 `volatile`**：编译器会把 `sdata[tid]` 提升到寄存器，跨语句复用旧值——因为它"看不到"其他 lane 写过这块内存。`volatile` 强制每次重新从 smem 读。这是本题**最高频的追问点**。

**收益**：带宽 ~58-62%，约 1.15x。注意收益**远小于**"去掉 5/8 的同步"的直觉预期——因为 occupancy 足够时，屏障停顿会被其他 block 的访存掩盖。

---

## 6. V5：模板 + 完全展开（编译期确定 block 尺寸）

### 6.1 思路

把 `blockDim.x` 变成模板参数，让 nvcc 在编译期把每个 `if (BLOCK >= 256)` 分支裁掉、把循环完全展开成一串无分支的加法：

```cuda
template <int BLOCK>
__global__ void reduce_v5(const int* __restrict__ g_idata, int* __restrict__ g_odata, unsigned n) {
    __shared__ int sdata[BLOCK];
    unsigned tid = threadIdx.x;

    // 网格跨步 + 线程内累加：MLP 拉满
    int mySum = 0;
    unsigned gridSize = BLOCK * gridDim.x;
    for (unsigned i = blockIdx.x * BLOCK + tid; i < n; i += gridSize)
        mySum += g_idata[i];
    sdata[tid] = mySum;
    __syncthreads();

    if (BLOCK >= 512) { if (tid < 256) sdata[tid] += sdata[tid + 256]; __syncthreads(); }
    if (BLOCK >= 256) { if (tid < 128) sdata[tid] += sdata[tid + 128]; __syncthreads(); }
    if (BLOCK >= 128) { if (tid <  64) sdata[tid] += sdata[tid +  64]; __syncthreads(); }
    if (BLOCK >=  64) { if (tid <  32) sdata[tid] += sdata[tid +  32]; __syncthreads(); }
    if (tid < 32) {
        volatile int* smem = sdata;
        if (BLOCK >= 32) smem[tid] += smem[tid + 16];
        if (BLOCK >= 16) smem[tid] += smem[tid +  8];
        if (BLOCK >=  8) smem[tid] += smem[tid +  4];
        if (BLOCK >=  4) smem[tid] += smem[tid +  2];
        if (BLOCK >=  2) smem[tid] += smem[tid +  1];
    }
    if (tid == 0) g_odata[blockIdx.x] = sdata[0];
}
```

### 6.2 三个收益

1. **指令数下降**：循环控制、边界判断、地址计算全部常量折叠；
2. **同步次数**从 8 降到 4（BLOCK=256 时），后 5 层无屏障；
3. **grid-stride 循环**：每线程处理 `n / gridSize` 个元素，把 L1 层（thread-local）做厚，MLP 与 ILP 同时提升；同时天然支持任意 `n`（尾块由 `i < n` 处理）。

**收益**：带宽 ~72-85%。

---

## 7. V6：Warp Shuffle —— 干掉共享内存（现代标准写法）

### 7.1 核心思想

warp 内 32 个 lane 交换值，走的是**寄存器 + `SHFL` 指令**，不经过共享内存：

```cuda
__device__ __forceinline__ int warpReduceSum(int v) {
    #pragma unroll
    for (int off = 16; off > 0; off >>= 1)
        v += __shfl_down_sync(0xffffffffu, v, off);
    return v;
}
```

`__shfl_down_sync(mask, v, off)`：lane `i` 取 lane `i+off` 的值。经过 16,8,4,2,1 五次，lane 0 拿到整个 warp 的和（蝶形/log 步）。

### 7.2 完整实现（可直接作为面试终版）

```cuda
template <int BLOCK>
__global__ void __launch_bounds__(BLOCK)
reduce_final(const int* __restrict__ in, int* __restrict__ out, size_t n) {
    // L1: 线程内累加（网格跨步，合并访存）
    int sum = 0;
    size_t stride = (size_t)gridDim.x * BLOCK;
    for (size_t i = (size_t)blockIdx.x * BLOCK + threadIdx.x; i < n; i += stride)
        sum += in[i];

    // L2a: warp 内归约（无 smem、无 barrier）
    sum = warpReduceSum(sum);

    // L2b: 每 warp 出 1 个值 → smem → 第一个 warp 再做一次 warp 归约
    __shared__ int warpSums[BLOCK / 32];
    const int lane = threadIdx.x & 31, wid = threadIdx.x >> 5;
    if (lane == 0) warpSums[wid] = sum;
    __syncthreads();                                  // ← 全 block 仅此一次同步

    if (wid == 0) {
        sum = (lane < BLOCK / 32) ? warpSums[lane] : 0;
        sum = warpReduceSum(sum);
        if (lane == 0) out[blockIdx.x] = sum;         // L3: 交给第二阶段
    }
}
```

### 7.3 收益与代价对比

| 维度 | smem tree（V5） | warp shuffle（V6） |
|---|---|---|
| 同步 | 4 次 `__syncthreads` | **1 次** |
| 共享内存流量 | O(BLOCK) 次读写 | **8 次写 + 8 次读** |
| bank conflict | 已消除但仍占 LSU 端口 | 不经过 LSU |
| 指令 | 每层 3 条（ld/add/st） | 每层 1 条 SHFL + 1 add |
| 数据通路 | smem（~30 cycle 延迟） | 寄存器直连（更低延迟） |

**收益**：带宽 ~90%，相对 V5 约 1.1-1.2x。在现代 GPU（A100/H100）上这一版通常就到 **85-95% peak**，剩下的差异主要是启动开销和尾部效应。

**注意**：`__shfl_down_sync` 的 mask 必须包含所有参与 lane，且调用时 warp 必须收敛（否则 UB）。

---

## 8. V7：多元素 + 网格级归约（L3 怎么做）

### 8.1 先把 L1 做厚：向量化 + 每线程多元素

```cuda
const float4* in4 = reinterpret_cast<const float4*>(in);
size_t n4 = n / 4;
float4 acc = {0,0,0,0};
for (size_t i = blockIdx.x * BLOCK + threadIdx.x; i < n4; i += gridDim.x * BLOCK) {
    float4 v = in4[i];                     // 16B/线程 → 一个 warp 一次搬 512B
    acc.x += v.x; acc.y += v.y; acc.z += v.z; acc.w += v.w;
}
float sum = (acc.x + acc.y) + (acc.z + acc.w);
```
- 指令数降到 1/4 → 从「LSU 发射受限」变成「纯 DRAM 受限」；
- 每线程 in-flight 字节数 ×4 → MLP 更足，可以在**较低 occupancy**下打满带宽（这是"ILP 换 TLP"的经典论据）；
- 剩下不足 4 的尾巴用标量循环处理。

### 8.2 L3 四种方案

**方案 A：两阶段（默认推荐，工程首选）**

```cuda
int block = 256;
int grid  = std::min<int>((n + block - 1) / block, maxBlocksPerGrid);  // 通常 2~4 × SM 数
reduce_final<256><<<grid, block, 0, stream>>>(d_in, d_partial, n);
reduce_final<256><<<1,    block, 0, stream>>>(d_partial, d_out, grid);
```
代价：一次额外 launch（3-10 µs）+ partial 数组往返（grid 个 int，~16 KB，带宽占比 < 0.01%）。换来：**确定性、grid 可任意配置、代码简单**。

**方案 B：`atomicAdd`（单 kernel）**

```cuda
if (threadIdx.x == 0) atomicAdd(out, blockSum);
// 需要事先 cudaMemsetAsync(out, 0, sizeof(int)/sizeof(float))
```
- 每个 block 只 1 次原子操作 → 竞争可接受（grid ≤ 几千）；
- **致命缺点**：浮点加法非结合，atomic 顺序不定 → **每次运行结果可能不同**（调试/回归测试的噩梦）；int 版无此问题。

**方案 C：`__threadfence` + 最后一个 block（单 kernel，且确定）**

```cuda
__device__ unsigned int g_retire = 0;

if (threadIdx.x == 0) {
    out[blockIdx.x] = blockSum;
    __threadfence();                                  // 保证 partial 对其他 block 可见
    unsigned int v = atomicInc(&g_retire, gridDim.x);  // 计数并回绕
    isLast = (v == gridDim.x - 1);
}
__syncthreads();
if (isLast) {
    // 这个 block 负责把 out[0..gridDim) 再归约一次，写回 out[0]
    // 并把 g_retire 清零，方便下次调用
}
```
省掉一次 launch 和 partial 的第二次全局读，但要小心 `__threadfence` 语义与计数复位。

**方案 D：Cooperative Groups `grid.sync()`**

```cuda
namespace cg = cooperative_groups;
auto g = cg::this_grid();
/* ... 第一阶段 ... */
g.sync();                    // 真正的设备级屏障
/* ... 第二阶段，读 partial 并归约 ... */
```
必须用 `cudaLaunchCooperativeKernel` 启动，且 **grid 不得超过「可同时驻留的 block 总数」**（否则 `grid.sync()` 死锁）——用 occupancy API 算 `blocksPerSM * numSM`。语义最干净，但要额外校验。

**工程现实**：直接 `cub::DeviceReduce::Sum` / `thrust::reduce`，其内部就是「多 tile + 每线程累加 + warp shuffle + 一次性 block 归约 + 单 pass 尾块处理」，并且在 H100 上用 TMA/异步拷贝做批量搬运。

---

## 9. 横向对比总表

| 版本 | 关键手段 | 解决的问题 | 剩余/新瓶颈 | 带宽占峰值 | 相对耗时 |
|---|---|---|---|---|---|
| V0 | 全局内存树 / 单线程 | —（基线） | 无 grid 同步 / 无并行 | ~11% | 8.7x |
| V1 | smem + 交错寻址 | block 内可同步、片上树 | **warp 发散** | ~22% | 4.3x |
| V2 | 连续活跃条件 | 消除发散 | **bank conflict（32-way）** | ~32% | 3.1x |
| V3 | 顺序寻址 | 冲突 & 发散双解 | 8 次屏障、每线程 1 元素 | ~50% | 2.0x |
| V4 | 加载即加 + 展开最后 warp | 减半 block/屏障、ILP↑ | 剩 4 次屏障、指令仍多 | ~60% | 1.7x |
| V5 | 模板完全展开 + grid-stride | 指令数↓、MLP↑、支持任意 n | 仍走 smem | ~80% | 1.25x |
| V6 | warp shuffle | smem 流量、屏障→1 次 | 只剩 DRAM | ~90% | 1.10x |
| V7 | float4 + 多元素 + 网格级 | 指令/LSU 端口、L3 合并 | **DRAM 墙 + launch 开销** | ~93-95% | 1.00x |

**读表要点**：收益最大的两跳是「V1→V3（解决发散+冲突）」和「V5→V6（去 smem + 去屏障）」；而"去掉 5/8 的同步"这种看起来很爽的改动其实只有 15%——**这就是为什么要 profile 而不是拍脑袋**。

---

## 10. 现代 GPU 上还能做什么（加分项）

| 手段 | 作用 | 备注 |
|---|---|---|
| `float4` / `int4` 向量化 | 减少指令、提高每线程 in-flight 字节 | 要求 16B 对齐；`n % 4` 需处理 |
| `__ldg` / `__restrict__ const` | 走只读数据通路（LDG），减少 L1 压力 | 现代架构已基本自动 |
| `__reduce_add_sync`（sm_80+） | 硬件 warp 归约，1 条指令替代 5 次 SHFL | **仅整数/无符号**，浮点不支持 |
| `cp.async` / TMA（Hopper） | 异步批量搬运，绕过寄存器 | 适合超大 tile、与计算重叠 |
| Thread Block Cluster（sm_90） | cluster 内 distributed shared memory 做跨 block 归约 | 减少一次全局往返 |
| `__launch_bounds__` | 限制寄存器，保 occupancy | 与 grid 配置联动 |
| CUB `DeviceReduce` | 工业级实现，直接对标 | 面试可说"手写到大体接近 CUB" |

---

## 11. 如何验证优化有效（面试问"你怎么知道快在哪"）

```bash
ncu --set full --kernel-name reduce_final ./a.out
```

关注这几个指标：

| 指标 | 含义 | 期望 |
|---|---|---|
| `dram__throughput.avg.pct_of_peak_sustained_elapsed` | DRAM 带宽利用率 | > 85% |
| `l1tex__data_bank_conflicts_pipe_lsu_mem_shared` | smem bank 冲突 | 接近 0 |
| `smsp__thread_inst_executed_per_inst_executed` | 平均每指令活跃线程数（发散程度） | 接近 32 |
| `smsp__warp_issue_stalled_barrier_per_warp_active` | 屏障停顿占比 | 逐版本下降 |
| `smsp__warp_issue_stalled_long_scoreboard_*` | 等全局访存 | 高说明 MLP 不足 |

判据：**如果 DRAM 利用率已经 >90%，任何"再优化指令"的尝试都不会有效**——瓶颈已经搬到带宽墙上了。

---

## 12. 面试高频追问 + 答题要点

### Q1 为什么 reduce 的优化目标不是"减少计算"？
算术强度 0.25 FLOP/B，远低于 roofline 拐点，纯访存受限。先算 `t_min = bytes/BW`，所有优化都在逼近它。**先给公式再讲版本**，这是区分"背过"和"懂了"的分水岭。

### Q2 为什么要把数据先搬到 shared memory，而不是直接在 global 上做树？
block 内需要 `log2(BLOCK)` 层归约，每层都要同步。global 没有 block 级低延迟 + 便宜同步的组合；且 global 树每层都要走 DRAM/L2，延迟由 500+ cycle 主导。smem 是 ~30 cycle 且带宽远高于 DRAM，天然适合做"片上临时区"。

### Q3 为什么 block 设 256，不是 1024 或 64？
多因素折中：
- **warp 数**：256 = 8 个 warp，warp shuffle 后正好 8 个值进 smem、1 个 warp 收尾，尾段短；
- **屏障代价**：同步开销随 warp 数增长，1024 线程（32 warp）时 barrier 和尾部空等更贵；
- **占用率/寄存器**：256 线程 + 适量寄存器能塞多个 block/SM，用 TLP 掩盖延迟；
- **树的层数** `log2(BLOCK)`，256 是 8 层，已足够摊薄；
- 工程上应 **autotune**（128/256/512 各跑一遍），面试可答"我实测 256 最优，理由是 X"。

### Q4 规模不是 2 的幂怎么办？
三层各自处理：
1. **grid 配置**：`grid = ceil_div(n, BLOCK*ELEMS_PER_THREAD)`；
2. **尾块越界**：`int v = (i < n) ? in[i] : 0;` 用**单位元**填充（加法 0、乘法 1、min `INT_MAX`、max `INT_MIN`）；
3. **block 内树**：`BLOCK` 始终取 2 的幂（256），所以 `s = BLOCK/2; s >>= 1` 的树永远是合法的；只有数据边界需要保护。
4. 若必须用非 2 的幂的 BLOCK：改成 `for (s = BLOCK/2; s > 0; s = (s+1)/2)`，并保证 `tid + s < BLOCK` 检查。

### Q5 怎么去掉最后一次 `__syncthreads`？
- **前提**：剩余活跃线程恰好 1 个 warp；
- **机制**：warp 内 lane 锁步（Volta 前硬保证；Volta 起需 `__syncwarp()` / `__shfl_*_sync` 显式收敛）；
- **必须 `volatile`**：否则编译器把 smem 值缓存进寄存器，跨语句读到旧值 → 结果错；
- **更彻底**：直接 warp shuffle，从根上不碰 smem，同步次数 8 → 1。
- **禁忌**：不能靠"把 `__syncthreads()` 写进 `if (tid < 32)`"来省——`__syncthreads` 必须是块内全体到达的屏障，条件分支内（非均一条件）是 UB/死锁。所以标准写法是把循环条件改成 `s > 32`，让屏障天然只发生在"还没进最后一段"的阶段。

### Q6 `volatile` 到底防什么？
防编译器把 `sdata[tid]` 提升为寄存器变量并跨迭代复用。没有它，nvcc 看到"这段代码里没人写 sdata[tid]"，就会只读一次。这是 CUDA 内存模型里"编译器不知道其他 lane 会写同一块 smem"的经典陷阱。现代写法：`__syncwarp()` + 非 volatile（编译器对 `__syncwarp` 有内存屏障语义）。

### Q7 `atomicAdd` 方案为什么不推荐？
- **非确定性**：浮点加法不满足结合律，atomic 到达顺序随机 → 每次结果 bit 级不同，回归测试/复现极难；
- **序列化**：所有 block 打同一地址，grid 大时有排队；
- **需要清零**：多一次 memset（可用 `cudaMemsetAsync` 融进 stream）。
  适用场景：block 数可控（几千以内）、对确定性无要求、想省一次 launch。

### Q8 两阶段 vs 单阶段（threadfence / cooperative）怎么选？
| | 两阶段 | threadfence last-block | cooperative grid.sync |
|---|---|---|---|
| launch | 2 次（+3~10 µs） | 1 次 | 1 次 |
| 确定性 | 是 | 是 | 是（若规约序固定） |
| 约束 | 无 | 需计数复位 | grid ≤ 可驻留 block 数 |
| 复杂度 | 低 | 中 | 中（需 occupancy 计算） |
  默认两阶段；延迟敏感的库（如 CUB 的单 pass 变体）用 threadfence 或 cooperative。

### Q9 浮点归约的精度与确定性？
- 树形/蝶形归约的误差是 `O(log n)` 量级，**优于串行的 `O(n)`**（长链累加误差累积更大）；
- 但**顺序一改，结果就变**——所以要 bitwise 复现必须固定规约树 + 禁用 atomic；
- 精度不足时：`double` 累加、Kahan 补偿求和、或按 block 分块后 pairwise 合并；
- int 归约无此问题（但要注意溢出，必要时用 `long long`）。

### Q10 为什么 grid 不直接开 `n/BLOCK` 个 block？
- block 数远超可驻留数时，调度/启动开销与尾波（tail effect）明显；
- partial 数组变成 O(n/BLOCK)，第二阶段读它也要花带宽（虽然占比小）；
- 标准做法：`grid = min(ceil_div(n, BLOCK), waves * SMs * blocksPerSM)`，配 grid-stride 循环。**正确性不依赖 grid 大小**，这是 grid-stride 的核心好处。

### Q11 为什么 V6 之后收益就很小了？还能怎么压？
因为已经贴上 DRAM 墙（>90% peak）。剩下的是：
- kernel launch / 两阶段往返（3-10 µs，小规模时占比高）；
- 尾波与 load imbalance；
- 如果数据在 L2 里（小 n），瓶颈变成 L2 带宽 → 此时减少指令和 smem 流量才有意义。
**答这题要体现"先判断瓶颈在哪一层"**（DRAM / L2 / LSU / 屏障），而不是继续堆技巧。

### Q12 这段代码里 `__restrict__` 和 `const` 有什么用？
让编译器确定指针不别名、输入不被写 → 允许用 LDG（只读缓存通路）、允许把 load 提前/合并、允许更激进的向量化。没有它，编译器必须假设 `out` 可能覆盖 `in`，从而插入额外的顺序约束。

### Q13 warp shuffle 版本有什么坑？
- mask 必须覆盖所有参与 lane（`0xffffffff` 要求 32 lane 全活跃）；
- Volta 后必须用 `_sync` 变体，且在**收敛**状态下调用；
- `__shfl_down_sync` 在 `lane+off >= 32` 时返回自身值，不影响 lane 0 的结果，但要理解这一点；
- `BLOCK/32` 必须 ≤ 32（即 BLOCK ≤ 1024），否则最后一步一个 warp 收不完。

### Q14 如果 n 很小（比如 1024），这套优化还成立吗？
不成立，要换策略：单 block + shuffle 就够，两阶段反而被 launch 开销主导（2 次 launch ~10 µs，而计算只要 1 µs）。**规模决定架构**——这是很好的加分回答。

---

## 13. 白板速记（30 秒口述版）

> Reduce 是访存受限（0.25 FLOP/B），目标是逼近 `N*4/BW`。
> 做法分三层：线程内累加 → block 内归约 → grid 级合并。
> 演进主线：全局内存做不了同步 → 搬进 shared memory（但交错寻址导致 warp 发散）→ 改连续条件去发散（但步长 2s 导致 32-way bank conflict）→ 改顺序寻址去冲突 → unroll 把最后 5 次同步和一半 block 砍掉 → 模板展开 + grid-stride 拉满 MLP → warp shuffle 把 smem 和屏障一起干掉（同步 8→1，带宽 ~90%）→ float4 + 两阶段/threadfence 收尾。
> 每一步的判据都来自 profile：DRAM 利用率、bank conflict 计数、活跃线程/指令、barrier stall。

---

*文档生成时间：2026-10-28 · 配套代码可直接用 `nvcc -O3 -arch=sm_80` 编译验证*
