# DannyThreadPool 软件需求规格说明书（SRS / SPEC）

**文档编号：** DTP-SPEC-001  
**版本：** 0.1.0  
**状态：** Draft  
**目标标准：** C++20  
**项目名称：** DannyThreadPool（命名空间 `dtp`）

---

## 1. 文档目的

本文档定义 DannyThreadPool 的外部行为、功能需求、质量属性、接口契约和验收标准。本文档描述“系统必须做什么”，不规定具体实现算法；实现设计见《DannyThreadPool 软件设计说明书（SDD）》。

## 2. 产品目标

DannyThreadPool 是一个用于学习和工程实践的现代 C++20 固定大小线程池。项目参考成熟开源线程池的功能分层，但独立设计与实现。

目标：

1. 复用固定数量的工作线程，避免为每个任务重复创建线程。
2. 提供无返回值任务和基于 `std::future` 的有返回值任务。
3. 明确定义任务接受、排队、执行、异常、等待和关闭语义。
4. 支持有界队列、背压、批量任务、循环分块、优先级和监控。
5. 能够使用 ThreadSanitizer、压力测试和基准测试验证正确性与性能。
6. 保持 API 简洁、可移植、可测试，并尽量只依赖 C++ 标准库。

## 3. 非目标

0.1.x 阶段不包含：

- 分布式任务调度；
- 抢占式取消正在运行的任务；
- 协程运行时或异步 I/O Reactor；
- 完整 DAG 调度器；
- NUMA 感知和通用 Work-Stealing；
- 实时系统确定性调度保证；
- 跨进程任务执行。

## 4. 术语

- **调用线程 / Producer：** 调用线程池 API 提交任务的线程。
- **Worker：** 线程池内部用于执行任务的持久线程。
- **Task：** 可调用对象及其已绑定参数。
- **Queued：** 已接受但尚未开始执行。
- **Running：** 已被 Worker 取出并正在执行。
- **Drain：** 不再接收新任务，但执行完已接受任务。
- **Cancel pending：** 丢弃尚未开始执行的任务，不中断正在运行的任务。
- **Idle：** 队列为空且无任务正在运行。
- **Backpressure：** 队列满时限制生产者继续提交任务。

## 5. 用户角色与典型场景

### 5.1 库使用者

- 提交 CPU 密集任务；
- 并行处理数组、文件块或独立数据项；
- 获取异步返回值和异常；
- 等待一组任务或整个线程池进入空闲状态；
- 在服务退出时安全关闭线程池。

### 5.2 库维护者

- 扩展调度策略；
- 运行并发正确性测试；
- 分析吞吐、排队延迟和锁竞争；
- 保持跨 GCC、Clang、MSVC 的可移植性。

## 6. 版本路线与范围

| 里程碑 | 功能范围 |
|---|---|
| V1 | 固定 Worker、无界 FIFO 队列、`detach()`、Drain shutdown |
| V2 | `submit()`、`future`、返回值与异常传播、`wait()` |
| V3 | Move-only task、完美转发、成员函数与泛型调用 |
| V4 | 显式生命周期状态机、Drain/Cancel-pending 两种关闭模式 |
| V5 | 有界队列、阻塞/非阻塞/超时提交和背压 |
| V6 | 批量提交、循环与区间分块、多 Future 聚合 |
| V7 | 暂停/恢复、任务计数、队列清理、异常处理器 |
| V8 | 优先级队列和同优先级稳定顺序 |
| V9 | Worker 上下文、同池等待死锁检测 |
| V10 | Benchmark、性能调优和文档稳定化 |

## 7. 功能需求

需求等级：**MUST** 必须；**SHOULD** 应当；**MAY** 可选。

### FR-001 创建线程池（MUST）

- 构造函数接收 Worker 数量。
- Worker 数量为 0 时必须拒绝构造，或通过明确的默认策略转为 1；本项目选择抛出 `std::invalid_argument`。
- 默认 Worker 数量使用 `std::thread::hardware_concurrency()`，返回 0 时回退为 1。
- 构造完成后所有 Worker 可接收任务。
- 若部分 Worker 创建失败，必须停止并回收已创建 Worker，然后重新抛出异常。

### FR-002 提交 Detached 任务（MUST）

```cpp
void detach(Task task);
```

- 接受可调用、无返回值语义的任务。
- 成功返回表示任务已被线程池接受，不表示已执行完成。
- 已接受任务必须至多执行一次。
- 线程池进入停止状态后必须拒绝新任务。
- 空任务必须被拒绝。
- Detached 任务的未捕获异常不得越过 Worker 顶层导致进程终止。

### FR-003 提交有结果任务（MUST，V2）

```cpp
template <typename Function, typename... Args>
auto submit(Function&& function, Args&&... args)
    -> std::future<std::invoke_result_t<Function, Args...>>;
```

- 支持非 `void` 和 `void` 返回类型。
- 支持值参数、引用包装、成员函数和 move-only 参数。
- 任务返回值必须写入对应 Future 的共享状态。
- 任务异常必须由 `future::get()` 重新抛出。
- 提交失败时，不得返回永远无法完成的 Future。

### FR-004 Worker 调度（MUST）

- V1–V7 默认使用共享 FIFO 队列。
- 无任务时 Worker 必须阻塞，禁止持续忙等。
- Worker 必须在不持有线程池内部队列锁时执行用户任务。
- 多 Worker 环境不保证任务开始顺序或完成顺序。
- 单 Worker、FIFO 调度且无优先级时，任务开始顺序应与接受顺序一致。

### FR-005 等待空闲（MUST，V2）

```cpp
void wait();

template <typename Rep, typename Period>
bool wait_for(std::chrono::duration<Rep, Period> timeout);
```

- `wait()` 等待“队列为空且 Running 任务数为 0”。
- `wait()` 不停止线程池，返回后仍可提交任务。
- `wait_for()` 超时返回 `false`，达到空闲返回 `true`。
- 若其他生产者在等待期间持续提交，等待时间可能延长；此行为必须文档化。
- Worker 在同一线程池任务内调用池级 `wait()` 必须被禁止或检测，以避免等待自身。

### FR-006 关闭（MUST）

```cpp
enum class ShutdownMode {
    drain,
    cancel_pending
};

void shutdown(ShutdownMode mode = ShutdownMode::drain) noexcept;
```

- `drain`：拒绝新任务，执行完 Queued 和 Running 任务，再回收 Worker。
- `cancel_pending`：拒绝新任务，移除未开始任务，允许 Running 任务自然结束，再回收 Worker。
- 不允许强制终止 Running 任务。
- `shutdown()` 必须幂等。
- 析构函数必须执行 `shutdown(drain)`，除非未来配置明确指定其他析构策略。
- 同池 Worker 调用 `shutdown()` 不得尝试 join 自己；必须拒绝或采用安全的非阻塞请求停止路径。

### FR-007 有界队列与背压（MUST，V5）

提供以下策略：

- 阻塞至出现空间；
- `try_submit()` 立即失败；
- `submit_for()` 超时失败；
- 停止时唤醒所有等待提交者并返回失败。

队列容量为 0 必须被拒绝。系统必须保证队列长度不超过配置容量。

### FR-008 批量提交（SHOULD，V6）

- 支持容器或迭代器区间批量提交。
- 批量提交必须明确“全部接受”或“允许部分接受”的契约；默认选择全部接受，否则整体失败。
- 带结果批量提交返回 `MultiFuture<T>`。

### FR-009 循环和区间分块（SHOULD，V6）

```cpp
submit_loop(first, last, body, block_count);
submit_blocks(first, last, block_body, block_count);
```

- 使用半开区间 `[first, last)`。
- `first >= last` 时返回空结果，不提交任务。
- 每个索引必须恰好属于一个 Block。
- Block 大小差不得超过 1。
- 不保证 Block 执行顺序。
- 默认 Block 数采用可配置策略，不把经验公式写死为正确性要求。

### FR-010 暂停与恢复（SHOULD，V7）

- 暂停只阻止 Worker 获取新任务，不中断 Running 任务。
- 暂停期间允许或拒绝提交必须由配置决定，默认允许排队。
- `wait()` 在暂停状态下的语义必须明确；本项目定义为仍等待全局 Idle，因此若存在 Queued 任务将阻塞。另提供 `wait_running()` 等待 Running 归零。
- 关闭可覆盖暂停状态并唤醒 Worker。

### FR-011 任务监控（SHOULD，V7）

至少提供：

```cpp
std::size_t worker_count() const noexcept;
std::size_t queued_task_count() const;
std::size_t running_task_count() const;
std::size_t unfinished_task_count() const;
```

必须满足可观察不变量：

```text
unfinished = queued + running
```

返回值仅是调用时刻快照，不保证返回后仍保持不变。

### FR-012 清理排队任务（SHOULD，V7）

- `purge()` 仅移除尚未开始的任务。
- 不影响 Running 任务。
- 被移除的 Future 任务必须以可观察方式完成，例如写入自定义 `task_cancelled` 异常，不能永久 pending。

### FR-013 优先级（SHOULD，V8）

- 支持有限范围的整数优先级。
- 高优先级任务先于低优先级 Queued 任务被选择。
- 已经 Running 的低优先级任务不会被抢占。
- 同优先级任务按提交序号稳定排序。
- 必须文档化低优先级任务可能饥饿。

### FR-014 Worker 上下文（SHOULD，V9）

提供只读查询：

```cpp
std::optional<std::size_t> this_worker::index() noexcept;
ThreadPool* this_worker::pool() noexcept;
```

非线程池 Worker 调用时返回空值或空指针。不得通过无类型指针要求调用者做不安全转换。

### FR-015 初始化与清理 Hook（MAY）

- 每个 Worker 可运行一次初始化函数和一次清理函数。
- Hook 在对应 Worker 线程中运行。
- Hook 异常策略必须明确；默认捕获并报告，构造失败时安全回滚。

## 8. API 草案

```cpp
namespace dtp {

enum class ShutdownMode {
    drain,
    cancel_pending
};

struct ThreadPoolOptions {
    std::size_t worker_count;
    std::optional<std::size_t> queue_capacity;
};

class ThreadPool final {
public:
    explicit ThreadPool(ThreadPoolOptions options = {});
    ~ThreadPool();

    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;
    ThreadPool(ThreadPool&&) = delete;
    ThreadPool& operator=(ThreadPool&&) = delete;

    template <typename Function, typename... Args>
    auto submit(Function&& function, Args&&... args)
        -> std::future<std::invoke_result_t<Function, Args...>>;

    template <typename Function>
    void detach(Function&& function);

    void wait();
    void shutdown(ShutdownMode mode = ShutdownMode::drain) noexcept;

    [[nodiscard]] std::size_t worker_count() const noexcept;
    [[nodiscard]] std::size_t queued_task_count() const;
    [[nodiscard]] std::size_t running_task_count() const;
};

} // namespace dtp
```

## 9. 线程安全契约

### 9.1 可并发调用

以下函数应支持来自多个外部线程的并发调用：

- `submit()`；
- `detach()`；
- 查询函数；
- `wait()` / `wait_for()`；
- `shutdown()`，但并发关闭只允许一个调用者执行实际状态转换，其他调用者等待或快速返回。

### 9.2 禁止或受限调用

- 同池 Worker 不得执行会同步等待自身完成的操作。
- 用户不得在任务开始后销毁任务捕获的引用对象。
- 不保证用户任务自身线程安全。
- 线程池对象的生命周期必须覆盖所有对其成员函数的调用。

## 10. 异常安全

- 构造：强保证；失败后无 Worker 泄漏。
- `submit()`：提交失败时任务未被接受，且不留下不可完成 Future。
- `detach()`：队列插入失败时任务未被接受。
- Worker：任何用户异常都不能从线程入口逃逸。
- `shutdown()` 与析构：`noexcept`。
- 内部状态必须在异常后保持可销毁。

## 11. 非功能需求

### NFR-001 可移植性

- 核心实现只依赖 C++20 标准库。
- 支持 GCC、Clang、MSVC 的近期稳定版本。
- 核心 API 不依赖平台原生线程句柄。

### NFR-002 正确性

- ThreadSanitizer 测试不得报告库内部数据竞争。
- 任务不丢失、不重复执行；Cancel-pending 除外，取消必须可观察。
- 不得因虚假唤醒违反状态机。
- 所有线程必须在析构完成前回收。

### NFR-003 性能

- Worker 空闲时不得忙等。
- 用户任务在内部队列锁外执行。
- 默认路径避免不必要的全局通知。
- 性能优化不得削弱可证明的同步关系。
- 基准必须分别测量提交吞吐、端到端延迟和任务粒度拐点。

### NFR-004 可维护性

- 每个共享字段必须在代码注释或 SDD 中标明同步策略。
- 锁顺序必须集中记录。
- 公共 API 使用 Doxygen 注释。
- 并发状态转换必须有单元测试。

### NFR-005 可观测性

- 能查询 Queued、Running、Unfinished 数量。
- Debug 模式应能查询 Worker index。
- 可选统计不得显著影响默认轻量路径。

## 12. 验收标准

### AC-001 基本执行

提交 100,000 个递增任务，关闭后计数必须精确等于 100,000。

### AC-002 多生产者

至少 8 个生产线程并发提交任务，所有成功接受任务必须恰好执行一次。

### AC-003 空池关闭

无任务时构造并关闭不得挂起。

### AC-004 Drain

关闭开始前已接受的任务全部完成；关闭开始后提交被拒绝。

### AC-005 Future

返回值正确；`void` Future 可等待；任务异常由 `get()` 重新抛出。

### AC-006 等待

`wait()` 仅在线程池达到 Idle 后返回，返回后线程池仍可接受任务。

### AC-007 Cancel pending

Running 任务正常完成，Queued 任务不执行，相关 Future 不得永久 pending。

### AC-008 递归提交

任务可以向同一线程池异步提交子任务；不得因内部队列锁重入而死锁。

### AC-009 死锁检测

同池 Worker 调用池级 `wait()`/同步 shutdown 时应确定性失败，而不是永久阻塞。

### AC-010 工具验证

- Debug、Release 构建通过；
- ASan/UBSan 通过；
- TSan 通过；
- GCC、Clang、MSVC 至少各一套 CI 配置通过。

## 13. 风险与约束

- Future 嵌套等待可能导致线程池饥饿死锁。
- 无界队列可能导致内存持续增长，因此生产版本必须支持有界队列。
- 过小任务会使调度开销超过并行收益。
- `hardware_concurrency()` 是提示值，不代表适合所有工作负载。
- 引用捕获和 `this` 捕获的生命周期由调用者负责。
- 优先级不是实时调度，且不能抢占 Running 任务。

## 14. 参考资料

- BS::thread_pool: https://github.com/bshoshany/thread-pool
- C++ concurrency support library: https://en.cppreference.com/w/cpp/thread
- C++ Core Guidelines, Concurrency: https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#S-concurrency
