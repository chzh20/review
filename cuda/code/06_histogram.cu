// 06_histogram.cu —— 全局原子 vs 共享内存私有直方图
// 关键结论：全局 atomic 次数从"每元素一次"降到"每 block 每 bin 一次"
// 运行：./06_histogram 16777216
#include "common.h"
#include <cstring>
#include <vector>

#define BINS 256

// 朴素：每元素一次全局原子。数据分布集中时会极其缓慢
__global__ void histGlobal(const unsigned char* __restrict__ data, int n,
                           unsigned int* __restrict__ hist) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) atomicAdd(&hist[data[i]], 1u);
}

// shared 私有 bin：block 内竞争，最后每 block 合并一次
__global__ void histShared(const unsigned char* __restrict__ data, int n,
                           unsigned int* __restrict__ hist) {
    __shared__ unsigned int local[BINS];
    for (int i = threadIdx.x; i < BINS; i += blockDim.x) local[i] = 0;
    __syncthreads();

    int stride = blockDim.x * gridDim.x;
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += stride)
        atomicAdd(&local[data[i]], 1u);      // shared atomic：在 SM 内完成

    __syncthreads();
    for (int i = threadIdx.x; i < BINS; i += blockDim.x)
        if (local[i]) atomicAdd(&hist[i], local[i]);   // 每 block 每 bin 至多一次
}

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : (1 << 24);
    printf("n = %d  (%.1f MB)\n", n, n / 1048576.0);

    // 故意制造"数据分布集中"的场景：95%% 落在 0..7，少数落满 256
    unsigned char* hdata = (unsigned char*)malloc(n);
    for (int i = 0; i < n; ++i)
        hdata[i] = ((i & 31) == 0) ? (unsigned char)(i & 0xFF) : (unsigned char)(i & 7);

    unsigned char* ddata;
    unsigned int *h1, *h2;
    CUDA_CHECK(cudaMalloc(&ddata, n));
    CUDA_CHECK(cudaMemcpy(ddata, hdata, n, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMallocHost(&h1, BINS * sizeof(unsigned int)));
    CUDA_CHECK(cudaMallocHost(&h2, BINS * sizeof(unsigned int)));

    unsigned int *dg, *ds;
    CUDA_CHECK(cudaMalloc(&dg, BINS * sizeof(unsigned int)));
    CUDA_CHECK(cudaMalloc(&ds, BINS * sizeof(unsigned int)));

    // CPU 参考
    std::vector<unsigned int> ref(BINS, 0);
    for (int i = 0; i < n; ++i) ref[hdata[i]]++;

    const int block = 256;
    int grid = (n + block - 1) / block;
    int smCount = 0;
    cudaDeviceGetAttribute(&smCount, cudaDevAttrMultiProcessorCount, 0);
    int gridCap = smCount * 16;

    CUDA_CHECK(cudaMemset(dg, 0, BINS * sizeof(unsigned int)));
    histGlobal<<<grid, block>>>(ddata, n, dg);
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaMemcpy(h1, dg, BINS * sizeof(unsigned int), cudaMemcpyDeviceToHost));

    CUDA_CHECK(cudaMemset(ds, 0, BINS * sizeof(unsigned int)));
    histShared<<<gridCap, block>>>(ddata, n, ds);
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaMemcpy(h2, ds, BINS * sizeof(unsigned int), cudaMemcpyDeviceToHost));

    bool ok1 = true, ok2 = true;
    for (int i = 0; i < BINS; ++i) {
        if (h1[i] != ref[i]) ok1 = false;
        if (h2[i] != ref[i]) ok2 = false;
    }
    printf("correctness global : %s\n", ok1 ? "PASS" : "FAIL");
    printf("correctness shared : %s\n", ok2 ? "PASS" : "FAIL\n\n");

    float t1 = bench([&] {
        CUDA_CHECK(cudaMemsetAsync(dg, 0, BINS * sizeof(unsigned int)));
        histGlobal<<<grid, block>>>(ddata, n, dg);
    });
    float t2 = bench([&] {
        CUDA_CHECK(cudaMemsetAsync(ds, 0, BINS * sizeof(unsigned int)));
        histShared<<<gridCap, block>>>(ddata, n, ds);
    });

    printf("--- 计时 ---\n");
    printf("global atomic : %8.3f ms\n", t1);
    printf("shared bins   : %8.3f ms   (%.2fx faster)\n", t2, t1 / t2);
    printf("\n原子次数对比：\n");
    printf("  global : %d 次（每元素一次）\n", n);
    printf("  shared : 最多 %d 次（%d block x %d bins）\n", gridCap * BINS, gridCap, BINS);
    printf("  -> 降低 %.0f 倍\n", (double)n / (gridCap * BINS));

    printf("\n如果数据分布更集中（比如 99%% 是同一个值），shared atomic 也会串行，\n");
    printf("进一步优化：每 warp 一份 bin（privatization）或用 __match_any_sync 聚合。\n");

    cudaFree(ddata); cudaFree(dg); cudaFree(ds);
    cudaFreeHost(h1); cudaFreeHost(h2);
    free(hdata);
    return 0;
}
