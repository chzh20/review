# CRTP Demos

这些示例对应 `review/C++/05_CRTP.md` 中的主要主题：

- `01_static_polymorphism` — 最小 CRTP 模型与静态多态派发
- `02_object_layout` — EBO、无 vptr、多重继承下的指针调整
- `03_type_safety` — `friend Derived` + 私有构造 + `static_assert(is_base_of)`
- `04_mixin_and_operators` — Mixin 能力注入与运算符实现复用
- `05_intrusive_refcount` — LLVM 风格侵入式引用计数（`delete static_cast<Derived*>`）
- `06_two_phase_init` — 构造期调用派生成员的风险与工厂两阶段初始化
- `07_production_skeleton` — 生产级骨架（`static_assert` + 可选 C++20 Concepts）

## Build

```sh
cmake -S . -B build
cmake --build build
```

## Run

```sh
./build/01_static_polymorphism
./build/02_object_layout
./build/03_type_safety
./build/04_mixin_and_operators
./build/05_intrusive_refcount
./build/06_two_phase_init
./build/07_production_skeleton
```

On Windows with a multi-config generator, executables live under `build\Debug` or `build\Release`:

```bat
build\Debug\01_static_polymorphism.exe
```

## C++20 Concepts

`07_production_skeleton` uses concepts when the toolchain supports them (feature-test macro
`__cpp_concepts`). Under C++17 it falls back to `static_assert`-based checks and still compiles.
To force a C++20 build:

```sh
cmake -S . -B build20 -DCMAKE_CXX_STANDARD=20
cmake --build build20
```
