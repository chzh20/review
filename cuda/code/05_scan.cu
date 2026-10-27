// 05_scan.cu —— 三阶段前缀和（块内 Hillis-Steele + 块间扫描 + 加偏移）
// 这就是"CUB 简化版"的思路：scan -> scan block sums -> add offsets
// 运行：./05_scan
#include "common.h"
#include <cmath>
#include <vector>

// 阶段 1：每 block 内部做 inclusive scan（Hillis-Steele）
// 注意循环里必须"先读后写"两次同步，否则原地更新会踩掉别人还没读的值
__global__ void scanBlocks(float* __restrict__ out, float* __restrict__ blockSums,
                           const float* __restrict__ in, int n) {
    extern __shared__ float s[];
    int tid = threadIdx.x;
    int gid = blockIdx.x * blockDim.x + tid;

    s[tid] = (gid < n) ? in[gid] : 0.f;
    __syncthreads();

    for (int off = 1; off < blockDim.x; off <<= 1) {
        float v = (tid >= off) ? s[tid - off] : 0.f;   // 先读
        __syncthreads();
        s[tid] += v;                                    // 后写
        __syncthreads();
    }

    if (gid < n) out[gid] = s[tid];
    if (tid == blockDim.x - 1) blockSums[blockIdx.x] = s[tid];   // 本块总和
}

// 阶段 2：对 blockSums 做单块 inclusive scan（要求 block 数 <= 1024）
__global__ void scanBlockSums(float* __restrict__ blockSums, int nb) {
    extern __shared__ float s2[];
    int tid = threadIdx.x;
    s2[tid] = (tid < nb) ? blockSums[tid] : 0.f;
    __syncthreads();
    for (int off = 1; off < blockDim.x; off <<= 1) {
        float v = (tid >= off) ? s2[tid - off] : 0.f;
        __syncthreads();
        s2[tid] += v;
        __syncthreads();
    }
    if (tid < nb) blockSums[tid] = s2[tid];
}

// 阶段 3：把前一块的累计和加回去
__global__ void addOffsets(float* __restrict__ out, const float* __restrict__ blockSums, int n) {
    int gid = blockIdx.x * blockDim.x + threadIdx.x;
    if (blockIdx.x > 0 && gid < n) out[gid] += blockSums[blockIdx.x - 1];
}

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : (1 << 20);
    const int block = 1024;
    int nb = (n + block - 1) / block;
    if (nb > 1024) { printf("本示例要求 block 数 <= 1024，请减小 n\n"); return 1; }

    size_t bytes = (size_t)n * sizeof(float);
    printf("n = %d, block = %d, blocks = %d\n", n, block, nb);

    std::vector<float> h(n);
    for (int i = 0; i < n; ++i) h[i] = 1.0f;
    float* din;
    CUDA_CHECK(cudaMalloc(&din, bytes));
    CUDA_CHECK(cudaMemcpy(din, h.data(), bytes, cudaMemcpyHostToDevice));
    float *dout, *dsums;
    CUDA_CHECK(cudaMalloc(&dout, bytes));
    CUDA_CHECK(cudaMalloc(&dsums, (size_t)nb * sizeof(float)));

    auto run = [&] {
        scanBlocks<<<nb, block, block * sizeof(float)>>>(dout, dsums, din, n);
        scanBlockSums<<<1, block, block * sizeof(float)>>>(dsums, nb);
        addOffsets<<<nb, block>>>(dout, dsums, n);
    };

    run();
    CUDA_CHECK(cudaDeviceSynchronize());

    std::vector<float> hout(n);
    CUDA_CHECK(cudaMemcpy(hout.data(), dout, bytes, cudaMemcpyDeviceToHost));
    bool ok = true;
    for (int i = 0; i < n; ++i) {
        float expect = (float)(i + 1);            // 全 1 输入的 inclusive scan = 1,2,3,...
        if (fabsf(hout[i] - expect) > 1e-3f) { ok = false; printf("mismatch at %d: %f vs %f\n", i, hout[i], expect); break; }
    }
    printf("correctness : %s\n", ok ? "PASS" : "FAIL");
    printf("first 8     : ");
    for (int i = 0; i < 8; ++i) printf("%.0f ", hout[i]);
    printf("... last = %.0f\n", hout[n - 1]);

    float ms = bench(run);
    printf("\ninclusive scan (%d elements) : %.3f ms  (%.1f GB/s, 读写各一份)\n",
           n, ms, 2.0 * bytes / 1e9 / (ms / 1000.0));

    printf("\n要点回顾：\n");
    printf("  1) 循环里两次 __syncthreads()：先读进寄存器、再写回，顺序不能反；\n");
    printf("  2) 三阶段结构：块内 scan -> 块和 scan -> 加前块偏移；\n");
    printf("  3) Hillis-Steele 是 O(n log n) work，Blelloch 是 O(n) work，\n");
    printf("     GPU 上块内用 HS 更简单，跨块用 work-efficient 方案更省总带宽。\n");

    cudaFree(din); cudaFree(dout); cudaFree(dsums);
    return 0;
}
