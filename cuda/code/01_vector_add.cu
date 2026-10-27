// 01_vector_add.cu —— 三种写法对比：朴素 / grid-stride / float4 向量化
// 结论预期：这是纯访存受限的 kernel，理论时间 = 3 * bytes / 带宽
#include "common.h"
#include <cmath>

__global__ void addNaive(const float* __restrict__ a, const float* __restrict__ b,
                         float* __restrict__ c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

__global__ void addGridStride(const float* __restrict__ a, const float* __restrict__ b,
                              float* __restrict__ c, int n) {
    int stride = blockDim.x * gridDim.x;
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += stride)
        c[i] = a[i] + b[i];
}

// 向量化：一次搬 16 字节。访存效率仍是 100%，但指令数降到 1/4
__global__ void addVec4(const float4* __restrict__ a, const float4* __restrict__ b,
                        float4* __restrict__ c, int n4) {
    int stride = blockDim.x * gridDim.x;
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n4; i += stride) {
        float4 x = a[i];
        float4 y = b[i];
        c[i] = make_float4(x.x + y.x, x.y + y.y, x.z + y.z, x.w + y.w);
    }
}

static void report(const char* tag, float ms, size_t bytes) {
    double gb = bytes / 1073741824.0;
    printf("%-14s : %7.3f ms   %7.1f GB/s\n", tag, ms, gb / (ms / 1000.0));
}

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : (1 << 24);   // 默认 16.7M 个 float = 64 MB
    size_t bytes = (size_t)n * sizeof(float);
    printf("n = %d  (%.1f MB per array, 3 arrays = %.1f MB total traffic)\n",
           n, bytes / 1048576.0, 3.0 * bytes / 1048576.0);

    float *ha, *hb, *hc, *da, *db, *dc;
    CUDA_CHECK(cudaMallocHost(&ha, bytes));
    CUDA_CHECK(cudaMallocHost(&hb, bytes));
    CUDA_CHECK(cudaMallocHost(&hc, bytes));
    for (int i = 0; i < n; ++i) { ha[i] = 1.0f; hb[i] = 2.0f; }
    CUDA_CHECK(cudaMalloc(&da, bytes));
    CUDA_CHECK(cudaMalloc(&db, bytes));
    CUDA_CHECK(cudaMalloc(&dc, bytes));
    CUDA_CHECK(cudaMemcpy(da, ha, bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(db, hb, bytes, cudaMemcpyHostToDevice));

    const int block = 256;
    int gridNaive = (n + block - 1) / block;
    int smCount = 0;
    cudaDeviceGetAttribute(&smCount, cudaDevAttrMultiProcessorCount, 0);
    int gridStride = smCount * 32;              // 固定为 SM 数的整数倍，避免 tail effect

    float t1 = bench([&] { addNaive<<<gridNaive, block>>>(da, db, dc, n); });
    CUDA_CHECK(cudaMemcpy(hc, dc, bytes, cudaMemcpyDeviceToHost));
    bool ok = true;
    for (int i = 0; i < n; ++i) if (hc[i] != 3.0f) { ok = false; break; }
    printf("correctness (naive) : %s\n", ok ? "PASS" : "FAIL");

    float t2 = bench([&] { addGridStride<<<gridStride, block>>>(da, db, dc, n); });
    float t3 = bench([&] { addVec4<<<gridStride, block>>>(
        reinterpret_cast<const float4*>(da),
        reinterpret_cast<const float4*>(db),
        reinterpret_cast<float4*>(dc), n / 4); });

    printf("\n--- 计时 ---\n");
    report("naive", t1, 3 * bytes);
    report("grid-stride", t2, 3 * bytes);
    report("float4", t3, 3 * bytes);

    printf("\n解读：三者都在 80%% 峰值带宽附近时，说明已经吃满 HBM —— 这类 kernel\n");
    printf("      没有任何\"计算优化\"空间，只能减少数据搬运或提高精度利用率。\n");

    cudaFree(da); cudaFree(db); cudaFree(dc);
    cudaFreeHost(ha); cudaFreeHost(hb); cudaFreeHost(hc);
    return 0;
}
