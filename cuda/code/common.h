#pragma once
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

// 统一错误检查：CUDA 调用失败就直接退出，避免"结果不对但没报错"
#define CUDA_CHECK(call)                                                     \
    do {                                                                     \
        cudaError_t err_ = (call);                                           \
        if (err_ != cudaSuccess) {                                           \
            fprintf(stderr, "CUDA error: %s  at %s:%d\n",                    \
                    cudaGetErrorString(err_), __FILE__, __LINE__);           \
            std::exit(EXIT_FAILURE);                                         \
        }                                                                    \
    } while (0)

// 用 CUDA event 计时（不要用 CPU 计时器，异步执行会让它测不准）
class GpuTimer {
public:
    GpuTimer() {
        cudaEventCreate(&start_);
        cudaEventCreate(&stop_);
    }
    ~GpuTimer() {
        cudaEventDestroy(start_);
        cudaEventDestroy(stop_);
    }
    void start() { cudaEventRecord(start_); }
    void stop() {
        cudaEventRecord(stop_);
        cudaEventSynchronize(stop_);
    }
    float ms() {
        float t = 0.f;
        cudaEventElapsedTime(&t, start_, stop_);
        return t;
    }

private:
    cudaEvent_t start_, stop_;
};

// 预热：让 GPU 频率升上来，避免第一次测量的异常慢
template <typename F>
float bench(F&& launch, int warmup = 5, int iters = 20) {
    for (int i = 0; i < warmup; ++i) launch();
    CUDA_CHECK(cudaDeviceSynchronize());

    GpuTimer t;
    t.start();
    for (int i = 0; i < iters; ++i) launch();
    t.stop();
    return t.ms() / iters;
}
