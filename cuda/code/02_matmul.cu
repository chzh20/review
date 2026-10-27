// 02_matmul.cu —— 朴素 vs tiled vs tiled+padding
// 重点：tiled 把全局访存从 2N^3 降到 2N^3/TILE，理论提速 TILE 倍（带宽角度）
// 运行：./02_matmul 1024
// 分析：ncu --set full --kernel-name matmulTiled ./02_matmul 1024
#include "common.h"
#include <cmath>

#define TILE 32

__global__ void matmulNaive(const float* __restrict__ A, const float* __restrict__ B,
                            float* __restrict__ C, int N) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (row >= N || col >= N) return;

    float acc = 0.f;
    for (int k = 0; k < N; ++k)
        acc += A[row * N + k] * B[k * N + col];
    C[row * N + col] = acc;
}

// 标准 tiled：注意 As[ty][k] 是广播、Bs[k][tx] 是连续 —— 没有 bank conflict
__global__ void matmulTiled(const float* __restrict__ A, const float* __restrict__ B,
                            float* __restrict__ C, int N) {
    __shared__ float As[TILE][TILE];
    __shared__ float Bs[TILE][TILE];

    int tx = threadIdx.x, ty = threadIdx.y;
    int row = blockIdx.y * TILE + ty;
    int col = blockIdx.x * TILE + tx;

    float acc = 0.f;
    for (int t = 0; t < N / TILE; ++t) {
        As[ty][tx] = A[row * N + t * TILE + tx];
        Bs[ty][tx] = B[(t * TILE + ty) * N + col];
        __syncthreads();                        // ① 必须：等 tile 写完

        #pragma unroll
        for (int k = 0; k < TILE; ++k)
            acc += As[ty][k] * Bs[k][tx];

        __syncthreads();                        // ② 必须：等 tile 读完才能被覆盖
    }
    if (row < N && col < N) C[row * N + col] = acc;
}

// 对照组：给 shared 加 padding。预期更慢（多占 shared、破坏向量化），
// 用来证明"经典 tiled GEMM 本身没有 bank conflict"
__global__ void matmulTiledPadded(const float* __restrict__ A, const float* __restrict__ B,
                                  float* __restrict__ C, int N) {
    __shared__ float As[TILE][TILE + 1];
    __shared__ float Bs[TILE][TILE + 1];

    int tx = threadIdx.x, ty = threadIdx.y;
    int row = blockIdx.y * TILE + ty;
    int col = blockIdx.x * TILE + tx;

    float acc = 0.f;
    for (int t = 0; t < N / TILE; ++t) {
        As[ty][tx] = A[row * N + t * TILE + tx];
        Bs[ty][tx] = B[(t * TILE + ty) * N + col];
        __syncthreads();
        #pragma unroll
        for (int k = 0; k < TILE; ++k)
            acc += As[ty][k] * Bs[k][tx];
        __syncthreads();
    }
    if (row < N && col < N) C[row * N + col] = acc;
}

static float* allocInit(int N, float seed) {
    size_t bytes = (size_t)N * N * sizeof(float);
    float* d;
    CUDA_CHECK(cudaMalloc(&d, bytes));
    float* h = (float*)malloc(bytes);
    for (int i = 0; i < N * N; ++i) h[i] = seed + (i % 7) * 0.01f;
    CUDA_CHECK(cudaMemcpy(d, h, bytes, cudaMemcpyHostToDevice));
    free(h);
    return d;
}

static bool allclose(const float* x, const float* y, int N, float rel) {
    size_t bytes = (size_t)N * N * sizeof(float);
    float *hx = (float*)malloc(bytes), *hy = (float*)malloc(bytes);
    CUDA_CHECK(cudaMemcpy(hx, x, bytes, cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(hy, y, bytes, cudaMemcpyDeviceToHost));
    bool ok = true;
    for (int i = 0; i < N * N; ++i) {
        float d = fabsf(hx[i] - hy[i]);
        float m = fmaxf(1e-6f, fmaxf(fabsf(hx[i]), fabsf(hy[i])));
        if (d / m > rel) { ok = false; break; }
    }
    free(hx); free(hy);
    return ok;
}

int main(int argc, char** argv) {
    int N = (argc > 1) ? atoi(argv[1]) : 1024;
    if (N % TILE != 0) { printf("N 必须是 %d 的整数倍\n", TILE); return 1; }

    float *A = allocInit(N, 1.0f), *B = allocInit(N, 0.5f);
    size_t bytes = (size_t)N * N * sizeof(float);
    float *C0, *C1, *C2;
    CUDA_CHECK(cudaMalloc(&C0, bytes));
    CUDA_CHECK(cudaMalloc(&C1, bytes));
    CUDA_CHECK(cudaMalloc(&C2, bytes));

    dim3 block(TILE, TILE);
    dim3 grid((N + TILE - 1) / TILE, (N + TILE - 1) / TILE);

    // ---- 正确性：三个版本互相对照 ----
    matmulNaive<<<grid, block>>>(A, B, C0, N);
    matmulTiled<<<grid, block>>>(A, B, C1, N);
    matmulTiledPadded<<<grid, block>>>(A, B, C2, N);
    CUDA_CHECK(cudaDeviceSynchronize());
    printf("correctness: tiled vs naive        : %s\n", allclose(C1, C0, N, 1e-4f) ? "PASS" : "FAIL");
    printf("correctness: tiledPadded vs naive  : %s\n\n", allclose(C2, C0, N, 1e-4f) ? "PASS" : "FAIL");

    // ---- 性能 ----
    double flops = 2.0 * N * N * N;
    double globalReadsNaive = 2.0 * N * N * N;          // 每输出读 2N 次
    double globalReadsTiled = 2.0 * N * N * N / TILE;   // 节约 TILE 倍

    float t0 = bench([&] { matmulNaive<<<grid, block>>>(A, B, C0, N); });
    float t1 = bench([&] { matmulTiled<<<grid, block>>>(A, B, C1, N); });
    float t2 = bench([&] { matmulTiledPadded<<<grid, block>>>(A, B, C2, N); });

    printf("N = %d, TILE = %d, FLOPs = %.2f GFLOP\n", N, TILE, flops / 1e9);
    printf("%-16s %9s %9s %12s %12s\n", "kernel", "ms", "GFLOPS", "global read", "read time");
    const double BW = 1555e9;   // A100 40GB 峰值带宽，换卡请改
    auto line = [&](const char* n, float ms, double reads) {
        printf("%-16s %9.3f %9.1f %9.2f GB %9.2f ms\n", n, ms, flops / (ms * 1e6),
               reads * 4 / 1e9, reads * 4 / BW * 1e3);
    };
    line("naive", t0, globalReadsNaive);
    line("tiled", t1, globalReadsTiled);
    line("tiled+padded", t2, globalReadsTiled);

    printf("\n解读：\n");
    printf("  1) naive 的 global read 是 %.1f GB，光搬到就要 %.1f ms，而计算只要 %.2f ms\n",
           globalReadsNaive * 4 / 1e9, globalReadsNaive * 4 / BW * 1e3, flops / 19.5e12 * 1e3);
    printf("     -> 纯访存受限，算得再快也没用\n");
    printf("  2) tiled 把访存降了 %d 倍，实测加速比 %.2fx（理想接近 %d，受限于其他开销）\n",
           TILE, t0 / t1, TILE);
    printf("  3) tiled+padded 通常更慢：证明经典 tiled 没有 bank conflict，padding 是多余的\n");
    printf("  4) 想看瓶颈：ncu --set full --kernel-name matmulTiled ./02_matmul %d\n", N);

    cudaFree(A); cudaFree(B); cudaFree(C0); cudaFree(C1); cudaFree(C2);
    return 0;
}
