// 00_sanity.cu —— 先摸清这台机器的硬参数，再看 occupancy 怎么算
#include "common.h"

__global__ void dummyKernel(float* p) { p[threadIdx.x] = 1.0f; }

int main() {
    int dev = 0;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, dev));

    printf("=== 设备信息 ===\n");
    printf("name                        : %s\n", prop.name);
    printf("compute capability          : %d.%d\n", prop.major, prop.minor);
    printf("SM count                    : %d\n", prop.multiProcessorCount);
    printf("global memory               : %.1f GB\n", prop.totalGlobalMem / 1073741824.0);
    printf("memory bus width            : %d bit\n", prop.memoryBusWidth);
    // 理论峰值带宽 = 位宽/8 * 等效频率 * 2(DDR) / 1e9  [GB/s]
    double bw = 2.0 * prop.memoryClockRate * (prop.memoryBusWidth / 8) / 1.0e6;
    printf("theoretical bandwidth       : %.1f GB/s\n", bw);
    printf("L2 cache size               : %.1f MB\n", prop.l2CacheSize / 1048576.0);

    printf("\n=== 每 SM 的硬上限（对比教程 README 的必背数字）===\n");
    printf("warp size                   : %d\n", prop.warpSize);
    printf("max threads per block       : %d\n", prop.maxThreadsPerBlock);
    printf("max threads per SM          : %d\n", prop.maxThreadsPerMultiProcessor);
    printf("regs per block              : %d\n", prop.regsPerBlock);
    printf("shared mem per block        : %zu B\n", prop.sharedMemPerBlock);
    printf("shared mem per SM           : %zu B\n", prop.sharedMemPerMultiprocessor);

    printf("\n=== occupancy 手算 vs API 对照 ===\n");
    // 场景：block = 256 线程，静态 shared = 8 KB，每线程 40 个寄存器
    const int blockThreads = 256;
    const size_t shmemBytes = 8 * 1024;
    const int regsPerThread = 40;

    // 手算：
    //   threads/SM : 2048 / 256 = 8
    //   warps      : 64 / 8 = 8
    //   regs       : 每 warp 40*32=1280, 每 block 8*1280=10240, 65536/10240 = 6.4 -> 6
    //   shmem      : 164KB / 8KB = 20
    //   min = 6 个 block -> 48/64 warps = 75%
    size_t sz = shmemBytes;
    int blocksPerSM = 0;
    // 注意：这里用运行时 API 问硬件，结果才是权威（手算只用于面试答题）
    CUDA_CHECK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(
        &blocksPerSM, dummyKernel, blockThreads, sz));
    printf("假设 256 线程 / 8KB shared / 40 regs：\n");
    printf("  手算 blocks/SM = min(8, 8, 32, 6, 20) = 6 -> occupancy 75%%\n");
    printf("  实际 dummyKernel 用很少寄存器，所以 API 给出 %d blocks/SM\n", blocksPerSM);
    printf("  -> 结论：手算只能给你量级，真实 occupancy 必须问 API 或看 NCU\n");

    int minGrid, blockSize;
    CUDA_CHECK(cudaOccupancyMaxPotentialBlockSize(&minGrid, &blockSize, dummyKernel, 0, 0));
    printf("  cudaOccupancyMaxPotentialBlockSize 建议 blockSize = %d\n", blockSize);

    printf("\n提示：改 blockThreads / shmemBytes / 加 __launch_bounds__ 后再跑，观察变化。\n");
    return 0;
}
