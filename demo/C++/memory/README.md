# C++ Memory Management Demos

这些示例对应 `review/C++/02_memory_managment02.md` 中的主要主题，重点演示：

- 存储与对象生命周期是两件事
- RAII 与 `std::unique_ptr` 表达独占所有权
- `std::shared_ptr`、`std::weak_ptr` 与控制块
- 对齐、手工构造、`std::pmr`
- 异常安全与所有权提交点
- 侵入式引用计数
- 引用计数线程安全不等于对象线程安全

## Build

```sh
cmake -S . -B build
cmake --build build
```

## Run

```sh
./build/01_lifetime_storage
./build/02_raii_unique_ptr
./build/03_shared_weak_ptr
./build/04_alignment_pmr
./build/05_exception_safety
./build/06_intrusive_ptr
./build/07_thread_safety
```

On Windows, executable files are usually under `build\Debug` or `build\Release` when using multi-config generators:

```bat
build\Debug\01_lifetime_storage.exe
```

## Optional Sanitizer Build

AddressSanitizer and UndefinedBehaviorSanitizer are available on supported GCC/Clang toolchains:

```sh
cmake -S . -B build-asan -DMEMORY_DEMO_ENABLE_SANITIZERS=ON
cmake --build build-asan
```
