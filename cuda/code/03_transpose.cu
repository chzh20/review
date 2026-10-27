// 03_transpose.cu —— 面试最经典的"合并访存 + bank conflict"综合题
//   naive  : 读合并、写不合并（列写）
//   shared : 读合并 + 写合并，但共享内存读出有 32-way bank conflict
//   pad    : 加一列 padding，冲突消失
// 运行：./03_transpose 4096
#include "common.h"

#define BDIM 32

__global__ void transposeNaive(const float* __restrict__ in, float* __restrict__ out, int n) {
    int x = blockIdx.x * BDIM + threadIdx.x;
    int y = blockIdx.y * BDIM + threadIdx.y;
    if (x < n && y < n) out[x * n + y] = in[y * n + x];   // 写 out[x*n+y]: warp 内步长 n，不合并
}

__global__ void transposeShared(const float* __restrict__ in, float* __restrict__ out, int n) {
    __shared__ float tile[BDIM][BDIM];                    // 读出时 32-way bank conflict
    int x = blockIdx.x * BDIM + threadIdx.x;
    int y = blockIdx.y * BDIM + threadIdx.y;
    if (x < n && y < n) tile[threadIdx.y][threadIdx.x] = in[y * n + x];
    __syncthreads();
    x = blockIdx.y * BDIM + threadIdx.x;
    y = blockIdx.x * BDIM + threadIdx.y;
    if (x < n && y < n) out[y * n + x] = tile[threadIdx.x][threadIdx.y];
}

__global__ void transposePadded(const float* __restrict__ in, float* __restrict__ out, int n) {
    __shared__ float tile[BDIM][BDIM + 1];                // ← 只改这一个数字
    int x = blockIdx.x * BDIM + threadIdx.x;
    int y = blockIdx.y * BDIM + threadIdx.y;
    if (x < n && y < n) tile[threadIdx.y][threadIdx.x] = in[y * n + x];
    __syncthreads();
    x = blockIdx.y * BDIM + threadIdx.x;
    y = blockIdx.x * BDIM + threadIdx.y;
    if (x < n && y < n) out[y * n + x] = tile[threadIdx.x][threadIdx.y];
}

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 4096;
    size_t bytes = (size_t)n * n * sizeof(float);
    printf("matrix %d x %d = %.1f MB\n", n, n, bytes / 1048576.0);

    float *din, *dout;
    CUDA_CHECK(cudaMalloc(&din, bytes));
    CUDA_CHECK(cudaMalloc(&dout, bytes));
    float* h = (float*)malloc(bytes);
    for (int i = 0; i < n * n; ++i) h[i] = (float)(i % 1000);
    CUDA_CHECK(cudaMemcpy(din, h, bytes, cudaMemcpyHostToDevice));

    dim3 block(BDIM, BDIM);
    dim3 grid((n + BDIM - 1) / BDIM, (n + BDIM - 1) / BDIM);

    // 正确性：用 CPU 结果校验 padded 版本
    CUDA_CHECK(cudaMemset(dout, 0, bytes));
    transposePadded<<<grid, block>>>(din, dout, n);
    CUDA_CHECK(cudaDeviceSynchronize());
    float* hout = (float*)malloc(bytes);
    CUDA_CHECK(cudaMemcpy(hout, dout, bytes, cudaMemcpyDeviceToHost));
    bool ok = true;
    for (int y = 0; y < n && ok; ++y)
        for (int x = 0; x < n; ++x)
            if (hout[y * n + x] != h[x * n + y]) { ok = false; break; }  // out[y][x] == in[x][y]
    printf("correctness (padded) : %s\n\n", ok ? "PASS" : "FAIL");
    free(h); free(hout);

    float t0 = bench([&] { transposeNaive<<<grid, block>>>(din, dout, n); });
    float t1 = bench([&] { transposeShared<<<grid, block>>>(din, dout, n); });
    float t2 = bench([&] { transposePadded<<<grid, block>>>(din, dout, n); });

    auto line = [&](const char* tag, float ms) {
        printf("%-14s : %8.3f ms   %7.1f GB/s\n", tag, ms, 2.0 * bytes / 1e9 / (ms / 1000.0));
    };
    printf("--- 计时（有效带宽 = 读写各一份 / 时间）---\n");
    line("naive", t0);
    line("shared", t1);
    line("shared+padded", t2);

    printf("\n解读：\n");
    printf("  naive       : 写侧 warp 步长 = n 个 float，32 个线程落在 32 条 cache line 上\n");
    printf("                -> 每次只搬 4/32 字节，带宽利用率 12.5%%\n");
    printf("  shared      : 全局读写都合并了，但 tile[tx][ty] 读出的 bank = ty %% 32\n");
    printf("                -> 32 个线程全撞一个 bank，串行 32 周期\n");
    printf("  shared+pad  : stride 变 33，(32*tx+tx+ty) %% 32 = (tx+ty) %% 32，铺满 32 个 bank\n");
    printf("\n想看冲突计数：ncu --metrics l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_ld.sum ./03_transpose %d\n", n);

    cudaFree(din); cudaFree(dout);
    return 0;
}
