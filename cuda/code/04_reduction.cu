// 04_reduction.cu —— 三级优化：交错寻址 -> 连续寻址 -> warp shuffle
// 运行：./04_reduction 16777216
#include "common.h"
#include <cmath>
#include <vector>

// V0：交错寻址（tid % (2*stride) == 0），有 warp divergence
__global__ void reduceV0(const float* __restrict__ in, float* __restrict__ out, int n) {
    extern __shared__ float s[];
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + tid;
    s[tid] = (i < n) ? in[i] : 0.f;
    __syncthreads();
    for (int stride = 1; stride < blockDim.x; stride *= 2) {
        if (tid % (2 * stride) == 0) s[tid] += s[tid + stride];
        __syncthreads();
    }
    if (tid == 0) out[blockIdx.x] = s[0];
}

// V1：连续寻址（tid < stride），活跃线程永远是低位连续，warp 被完整使用
__global__ void reduceV1(const float* __restrict__ in, float* __restrict__ out, int n) {
    extern __shared__ float s[];
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + tid;
    s[tid] = (i < n) ? in[i] : 0.f;
    __syncthreads();
    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (tid < stride) s[tid] += s[tid + stride];
        __syncthreads();
    }
    if (tid == 0) out[blockIdx.x] = s[0];
}

__inline__ __device__ float warpReduceSum(float v) {
    #pragma unroll
    for (int offset = 16; offset > 0; offset >>= 1)
        v += __shfl_down_sync(0xffffffffu, v, offset);
    return v;
}

// V2：grid-stride 累加 + warp shuffle 两级归约 + 每 block 一次 atomic
__global__ void reduceShuffle(const float* __restrict__ in, float* __restrict__ out, int n) {
    float sum = 0.f;
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x)
        sum += in[i];

    sum = warpReduceSum(sum);
    __shared__ float s[32];
    int lane = threadIdx.x & 31;
    int wid  = threadIdx.x >> 5;
    if (lane == 0) s[wid] = sum;
    __syncthreads();

    int nwarps = blockDim.x >> 5;
    sum = (threadIdx.x < nwarps) ? s[threadIdx.x] : 0.f;
    if (wid == 0) sum = warpReduceSum(sum);
    if (threadIdx.x == 0) atomicAdd(out, sum);
}

// 把每 block 的结果再求和（V0/V1 需要，为了和 V2 公平比较总时间）
// 部分和只有几千个，单线程循环即可，避免为了"并行"写出难理解的代码
__global__ void reducePartials(const float* __restrict__ partials, float* __restrict__ out, int m) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    float sum = 0.f;
    for (int i = 0; i < m; ++i) sum += partials[i];
    *out += sum;
}

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : (1 << 24);
    size_t bytes = (size_t)n * sizeof(float);
    printf("n = %d  (%.1f MB)\n", n, bytes / 1048576.0);

    float* din;
    CUDA_CHECK(cudaMalloc(&din, bytes));
    {
        std::vector<float> h(n);
        for (int i = 0; i < n; ++i) h[i] = 1.0f + (i % 5) * 0.001f;
        CUDA_CHECK(cudaMemcpy(din, h.data(), bytes, cudaMemcpyHostToDevice));
    }

    const int block = 256;
    int grid = (n + block - 1) / block;
    float* dpartial;
    CUDA_CHECK(cudaMalloc(&dpartial, (size_t)grid * sizeof(float)));
    float* dout;
    CUDA_CHECK(cudaMalloc(&dout, sizeof(float)));

    auto fetch = [&]() {
        float v; CUDA_CHECK(cudaMemcpy(&v, dout, sizeof(float), cudaMemcpyDeviceToHost)); return v;
    };

    // 参考值（CPU double 累加）
    double ref = 0.0;
    for (int i = 0; i < n; ++i) ref += 1.0 + (i % 5) * 0.001;

    size_t shmem = block * sizeof(float);

    CUDA_CHECK(cudaMemset(dout, 0, sizeof(float)));
    reduceV0<<<grid, block, shmem>>>(din, dpartial, n);
    reducePartials<<<1, 256>>>(dpartial, dout, grid);
    CUDA_CHECK(cudaDeviceSynchronize());
    printf("V0 result = %.3f  (ref %.3f, rel err %.2e)\n", fetch(), ref, fabs(fetch() - ref) / ref);

    CUDA_CHECK(cudaMemset(dout, 0, sizeof(float)));
    reduceV1<<<grid, block, shmem>>>(din, dpartial, n);
    reducePartials<<<1, 256>>>(dpartial, dout, grid);
    CUDA_CHECK(cudaDeviceSynchronize());
    printf("V1 result = %.3f  (rel err %.2e)\n", fetch(), fabs(fetch() - ref) / ref);

    CUDA_CHECK(cudaMemset(dout, 0, sizeof(float)));
    reduceShuffle<<<grid, block>>>(din, dout, n);
    CUDA_CHECK(cudaDeviceSynchronize());
    printf("V2 result = %.3f  (rel err %.2e)\n\n", fetch(), fabs(fetch() - ref) / ref);

    float t0 = bench([&] {
        reduceV0<<<grid, block, shmem>>>(din, dpartial, n);
        reducePartials<<<1, 256>>>(dpartial, dout, grid);
    });
    float t1 = bench([&] {
        reduceV1<<<grid, block, shmem>>>(din, dpartial, n);
        reducePartials<<<1, 256>>>(dpartial, dout, grid);
    });
    float t2 = bench([&] { reduceShuffle<<<grid, block>>>(din, dout, n); });

    printf("--- 计时（含必要的第二阶段）---\n");
    printf("%-18s : %8.3f ms   %7.1f GB/s\n", "V0 交错+syncthreads", t0, bytes / 1e9 / (t0 / 1000.0));
    printf("%-18s : %8.3f ms   %7.1f GB/s\n", "V1 连续+syncthreads", t1, bytes / 1e9 / (t1 / 1000.0));
    printf("%-18s : %8.3f ms   %7.1f GB/s\n", "V2 shuffle+atomic", t2, bytes / 1e9 / (t2 / 1000.0));

    printf("\n解读：\n");
    printf("  V0 慢在 tid%%(2*stride)==0 造成 warp 内大片 lane 空转；\n");
    printf("  V1 把活跃线程变成低位连续，warp 被完整使用，通常快 2 倍以上；\n");
    printf("  V2 再省掉最后 5 轮 syncthreads 和 shared 往返，接近纯带宽上限（a100 约 1555 GB/s）。\n");
    printf("  注意：浮点加法不满足结合律，三种顺序结果会有 1e-6 级差异，属正常。\n");

    cudaFree(din); cudaFree(dpartial); cudaFree(dout);
    return 0;
}
