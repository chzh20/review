下面是 **C++ 并发** 面试提炼版，重点覆盖：

* `std::thread`
* `join / detach`
* 数据竞争
* `mutex / lock_guard / unique_lock`
* 死锁与避免
* `condition_variable`
* 生产者消费者
* `atomic`
* 内存序 memory order
* `future / promise / async`
* 线程池
* 线程安全设计
* 常见面试代码题

`huihut/interview` 的操作系统部分也总结了进程/线程区别、线程同步方式、互斥锁、读写锁、自旋锁、条件变量、信号量、屏障以及死锁产生条件等内容，这些是理解 C++ 并发的基础。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

# 1. C++ 并发总览

## 面试核心问题

1. 进程和线程有什么区别？
2. 什么是数据竞争？
3. `std::thread` 如何创建线程？
4. `join()` 和 `detach()` 有什么区别？
5. `mutex` 如何保护共享资源？
6. `lock_guard` 和 `unique_lock` 有什么区别？
7. 什么是死锁？如何避免？
8. 条件变量为什么要配合 `while` 使用？
9. 什么是虚假唤醒？
10. `atomic` 和 `mutex` 有什么区别？
11. `volatile` 能否保证线程安全？
12. `memory_order` 是什么？
13. `future / promise / async` 有什么作用？
14. 如何实现线程安全队列？
15. 如何设计线程池？

***

# 2. 进程与线程

## 2.1 面试问题

1. 进程是什么？
2. 线程是什么？
3. 进程和线程的区别？
4. 线程共享哪些资源？
5. 线程私有哪些资源？

***

## 2.2 答案

进程是资源分配的基本单位，线程是 CPU 调度的基本单位。进程之间地址空间相互隔离，而同一进程内的多个线程共享进程地址空间。`huihut/interview` 中也总结：有线程系统中，进程是资源分配的独立单位，线程是资源调度的独立单位。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

线程共享：

* 进程地址空间；
* 堆；
* 全局变量；
* 静态变量；
* 文件描述符；
* 代码段。

线程私有：

* 线程栈；
* 寄存器；
* 程序计数器。

`huihut/interview` 也提到，线程之间共享堆、地址空间、全局变量、静态变量，私有线程栈、寄存器、程序计数器。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

# 3. `std::thread`

## 3.1 面试问题

1. 如何创建线程？
2. `join()` 和 `detach()` 区别？
3. `std::thread` 析构前为什么必须 `join` 或 `detach`？
4. 如何向线程函数传参？
5. 如何传引用参数？

***

## 3.2 基本用法

```cpp
#include <iostream>
#include <thread>

void worker() {
    std::cout << "worker thread\n";
}

int main() {
    std::thread t(worker);

    t.join();

    std::cout << "main thread\n";
}
```

`std::thread` 创建后会立即启动线程。

***

## 3.3 `join()` vs `detach()`

```cpp
std::thread t(worker);

t.join();   // 主线程等待子线程结束
```

```cpp
std::thread t(worker);

t.detach(); // 子线程后台运行，和 std::thread 对象分离
```

区别：

| 对比   | `join()` | `detach()` |
| ---- | -------- | ---------- |
| 行为   | 等待线程结束   | 线程后台运行     |
| 生命周期 | 可控       | 不易控制       |
| 是否推荐 | 常用       | 谨慎使用       |
| 风险   | 阻塞当前线程   | 资源生命周期难保证  |

***

## 3.4 析构前必须 `join` 或 `detach`

错误示例：

```cpp
#include <thread>

void worker() {}

int main() {
    std::thread t(worker);

    // 没有 join / detach
} 
```

程序会调用 `std::terminate()`。

正确写法：

```cpp
int main() {
    std::thread t(worker);

    if (t.joinable()) {
        t.join();
    }
}
```

***

## 3.5 线程传参

```cpp
#include <iostream>
#include <thread>
#include <string>

void print(int x, std::string s) {
    std::cout << x << " " << s << "\n";
}

int main() {
    std::thread t(print, 10, "hello");

    t.join();
}
```

***

## 3.6 传引用参数

错误示例：

```cpp
#include <thread>
#include <iostream>

void add(int& x) {
    ++x;
}

int main() {
    int value = 0;

    // std::thread t(add, value); // error 或行为不是预期
}
```

正确写法：

```cpp
#include <thread>
#include <functional>
#include <iostream>

void add(int& x) {
    ++x;
}

int main() {
    int value = 0;

    std::thread t(add, std::ref(value));

    t.join();

    std::cout << value << "\n"; // 1
}
```

***

# 4. 数据竞争 Data Race

## 4.1 面试问题

1. 什么是数据竞争？
2. 数据竞争为什么危险？
3. 如何避免数据竞争？
4. 多线程读同一个变量是否安全？
5. 一读一写是否安全？

***

## 4.2 答案

数据竞争指多个线程并发访问同一内存位置，至少一个线程执行写操作，并且没有合适的同步机制。数据竞争会导致未定义行为。

错误示例：

```cpp
#include <iostream>
#include <thread>
#include <vector>

int counter = 0;

void increment() {
    for (int i = 0; i < 100000; ++i) {
        ++counter; // 数据竞争
    }
}

int main() {
    std::thread t1(increment);
    std::thread t2(increment);

    t1.join();
    t2.join();

    std::cout << counter << "\n";
}
```

`++counter` 不是原子操作，大致包含：

```text
1. 读取 counter
2. 加 1
3. 写回 counter
```

两个线程可能交错执行，导致结果小于预期。

***

# 5. `mutex`

## 5.1 面试问题

1. `std::mutex` 有什么作用？
2. `lock()` / `unlock()` 有什么风险？
3. 为什么推荐 RAII 锁？
4. `lock_guard` 和 `unique_lock` 区别？
5. `recursive_mutex` 有什么作用？为什么不推荐滥用？

线程同步方式包括互斥锁、读写锁、自旋锁、条件变量等，互斥锁用于以排他方式保护共享数据，防止并发修改。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 5.2 使用 `mutex` 修复数据竞争

```cpp
#include <iostream>
#include <thread>
#include <mutex>

int counter = 0;
std::mutex mtx;

void increment() {
    for (int i = 0; i < 100000; ++i) {
        mtx.lock();
        ++counter;
        mtx.unlock();
    }
}

int main() {
    std::thread t1(increment);
    std::thread t2(increment);

    t1.join();
    t2.join();

    std::cout << counter << "\n";
}
```

但这种写法有风险：如果临界区中抛异常，`unlock()` 可能不会执行。

***

## 5.3 `lock_guard`

推荐使用 RAII 锁。

```cpp
#include <iostream>
#include <thread>
#include <mutex>

int counter = 0;
std::mutex mtx;

void increment() {
    for (int i = 0; i < 100000; ++i) {
        std::lock_guard<std::mutex> lock(mtx);
        ++counter;
    }
}

int main() {
    std::thread t1(increment);
    std::thread t2(increment);

    t1.join();
    t2.join();

    std::cout << counter << "\n";
}
```

`lock_guard` 构造时加锁，析构时解锁。这是 RAII 思想；`huihut/interview` 的 Effective C++ 部分也强调以对象管理资源，资源在构造函数获得，在析构函数释放。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 5.4 `unique_lock`

`unique_lock` 比 `lock_guard` 更灵活：

* 可以延迟加锁；
* 可以手动 `lock/unlock`；
* 可以移动；
* 可以配合 `condition_variable`。

```cpp
#include <mutex>

std::mutex mtx;

void f() {
    std::unique_lock<std::mutex> lock(mtx);

    // 临界区 1

    lock.unlock();

    // 非临界区

    lock.lock();

    // 临界区 2
}
```

***

## 5.5 `lock_guard` vs `unique_lock`

| 对比      | `lock_guard` | `unique_lock` |
| ------- | ------------ | ------------- |
| 开销      | 更小           | 略大            |
| 是否可手动解锁 | 不可           | 可以            |
| 是否可延迟加锁 | 不可           | 可以            |
| 是否可移动   | 不可           | 可以            |
| 条件变量    | 不适合          | 常用            |
| 使用场景    | 简单作用域锁       | 复杂锁控制         |

***

# 6. 死锁

## 6.1 面试问题

1. 什么是死锁？
2. 死锁产生的四个必要条件？
3. 如何避免死锁？
4. 多个 mutex 加锁时如何安全？
5. `std::lock` 和 `scoped_lock` 有什么作用？

`huihut/interview` 总结死锁产生条件包括互斥、请求和保持、不剥夺、环路等待，并给出打破条件的预防思路。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 6.2 死锁示例

```cpp
#include <mutex>
#include <thread>

std::mutex m1;
std::mutex m2;

void f1() {
    std::lock_guard<std::mutex> lock1(m1);
    std::lock_guard<std::mutex> lock2(m2);
}

void f2() {
    std::lock_guard<std::mutex> lock1(m2);
    std::lock_guard<std::mutex> lock2(m1);
}

int main() {
    std::thread t1(f1);
    std::thread t2(f2);

    t1.join();
    t2.join();
}
```

可能发生：

```text
t1 持有 m1，等待 m2
t2 持有 m2，等待 m1
```

***

## 6.3 使用固定加锁顺序

```cpp
void f1() {
    std::lock_guard<std::mutex> lock1(m1);
    std::lock_guard<std::mutex> lock2(m2);
}

void f2() {
    std::lock_guard<std::mutex> lock1(m1);
    std::lock_guard<std::mutex> lock2(m2);
}
```

所有线程按照相同顺序加锁，可降低死锁风险。

***

## 6.4 使用 `std::lock`

```cpp
#include <mutex>

std::mutex m1;
std::mutex m2;

void f() {
    std::lock(m1, m2);

    std::lock_guard<std::mutex> lock1(m1, std::adopt_lock);
    std::lock_guard<std::mutex> lock2(m2, std::adopt_lock);

    // 临界区
}
```

***

## 6.5 C++17 `std::scoped_lock`

更推荐：

```cpp
#include <mutex>

std::mutex m1;
std::mutex m2;

void f() {
    std::scoped_lock lock(m1, m2);

    // 同时锁多个 mutex，避免死锁
}
```

***

# 7. 条件变量 `condition_variable`

## 7.1 面试问题

1. 条件变量解决什么问题？
2. 为什么条件变量要配合 mutex？
3. 为什么 `wait` 要放在 `while` 中？
4. 什么是虚假唤醒？
5. `notify_one` 和 `notify_all` 区别？

条件变量可以以原子的方式阻塞线程直到特定条件满足，并且通常与互斥锁一起使用。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 7.2 基本模型

条件变量用于线程间等待某个条件成立。

```text
线程 A：
1. 加锁
2. 判断条件是否满足
3. 不满足则 wait，释放锁并阻塞
4. 被唤醒后重新加锁
5. 再次判断条件
6. 条件满足后继续执行

线程 B：
1. 加锁
2. 修改条件
3. 解锁
4. notify
```

***

## 7.3 生产者消费者

```cpp
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <queue>
#include <thread>

std::queue<int> q;
std::mutex mtx;
std::condition_variable cv;
bool done = false;

void producer() {
    for (int i = 0; i < 10; ++i) {
        {
            std::lock_guard<std::mutex> lock(mtx);
            q.push(i);
        }

        cv.notify_one();
    }

    {
        std::lock_guard<std::mutex> lock(mtx);
        done = true;
    }

    cv.notify_all();
}

void consumer() {
    while (true) {
        std::unique_lock<std::mutex> lock(mtx);

        cv.wait(lock, [] {
            return !q.empty() || done;
        });

        while (!q.empty()) {
            int value = q.front();
            q.pop();

            lock.unlock();

            std::cout << "consume " << value << "\n";

            lock.lock();
        }

        if (done) {
            break;
        }
    }
}

int main() {
    std::thread p(producer);
    std::thread c(consumer);

    p.join();
    c.join();
}
```

***

## 7.4 为什么用 `while` 或谓词？

错误写法：

```cpp
cv.wait(lock);

if (!q.empty()) {
    // ...
}
```

原因：

* 可能发生虚假唤醒；
* 可能多个消费者同时被唤醒，但只有一个拿到数据；
* 条件可能在唤醒后又被其他线程改变。

推荐：

```cpp
cv.wait(lock, [] {
    return !q.empty();
});
```

等价于：

```cpp
while (q.empty()) {
    cv.wait(lock);
}
```

***

# 8. `atomic`

## 8.1 面试问题

1. 什么是原子操作？
2. `atomic` 和 `mutex` 区别？
3. `atomic<int>` 的 `++` 是否线程安全？
4. `atomic` 一定无锁吗？
5. `compare_exchange` 是什么？
6. `volatile` 能替代 `atomic` 吗？

***

## 8.2 基本用法

```cpp
#include <atomic>
#include <iostream>
#include <thread>

std::atomic<int> counter{0};

void increment() {
    for (int i = 0; i < 100000; ++i) {
        ++counter;
    }
}

int main() {
    std::thread t1(increment);
    std::thread t2(increment);

    t1.join();
    t2.join();

    std::cout << counter.load() << "\n";
}
```

`std::atomic<int>` 的自增是原子操作。

***

## 8.3 `atomic` vs `mutex`

| 对比   | `atomic`      | `mutex`  |
| ---- | ------------- | -------- |
| 粒度   | 单个变量/简单状态     | 复杂临界区    |
| 开销   | 通常较低          | 通常较高     |
| 可组合性 | 差             | 强        |
| 适合场景 | 计数器、flag、无锁结构 | 保护复杂共享数据 |
| 是否阻塞 | 通常不阻塞         | 可能阻塞     |

***

## 8.4 `atomic` 不一定无锁

```cpp
#include <atomic>
#include <iostream>

int main() {
    std::atomic<long long> x;

    std::cout << x.is_lock_free() << "\n";
}
```

某些平台上某些类型的 `atomic` 可能内部仍然用锁。

***

## 8.5 `compare_exchange`

CAS：Compare And Swap。

含义：

```text
如果当前值 == expected，则改成 desired；
否则把当前值写回 expected。
```

示例：

```cpp
#include <atomic>
#include <iostream>

int main() {
    std::atomic<int> x{10};

    int expected = 10;

    bool ok = x.compare_exchange_strong(expected, 20);

    std::cout << std::boolalpha << ok << "\n"; // true
    std::cout << x.load() << "\n";             // 20
}
```

失败情况：

```cpp
std::atomic<int> x{10};

int expected = 5;

bool ok = x.compare_exchange_strong(expected, 20);

// ok == false
// expected 被更新为 10
```

***

## 8.6 `volatile` 不能保证线程安全

```cpp
volatile int counter = 0;
```

`volatile` 只告诉编译器不要对访问做某些优化，但不保证：

* 原子性；
* 线程间同步；
* 内存可见性顺序。

多线程计数应该使用：

```cpp
std::atomic<int> counter{0};
```

或者：

```cpp
std::mutex + 普通 int
```

***

# 9. 内存序 `memory_order`

## 9.1 面试问题

1. C++ 内存序是什么？
2. `memory_order_relaxed` 是什么？
3. `memory_order_acquire/release` 是什么？
4. `memory_order_seq_cst` 是什么？
5. 面试中需要掌握到什么程度？

***

## 9.2 默认内存序

```cpp
std::atomic<int> x{0};

x.store(1);
int v = x.load();
```

默认是：

```cpp
std::memory_order_seq_cst
```

即最强顺序一致性，最容易理解，但可能成本较高。

***

## 9.3 `relaxed`

只保证原子性，不保证跨线程顺序。

```cpp
std::atomic<int> counter{0};

counter.fetch_add(1, std::memory_order_relaxed);
```

适合简单统计计数，不依赖操作顺序。

***

## 9.4 `release/acquire`

常用于发布-订阅模型。

```cpp
#include <atomic>
#include <iostream>
#include <thread>

int data = 0;
std::atomic<bool> ready{false};

void producer() {
    data = 42;
    ready.store(true, std::memory_order_release);
}

void consumer() {
    while (!ready.load(std::memory_order_acquire)) {
    }

    std::cout << data << "\n"; // 一定能看到 42
}

int main() {
    std::thread t1(producer);
    std::thread t2(consumer);

    t1.join();
    t2.join();
}
```

含义：

* release：之前的写操作不能重排到 release 之后；
* acquire：之后的读操作不能重排到 acquire 之前；
* acquire 读到 release 写入的值后，建立同步关系。

***

## 9.5 面试建议

一般 C++ 工程面试掌握到这个程度即可：

```text
1. atomic 保证原子性；
2. 默认 seq_cst 最安全；
3. relaxed 只保证原子，不保证顺序；
4. release/acquire 用于线程间发布数据；
5. 不熟悉时不要乱用弱内存序。
```

***

# 10. `future / promise / async`

## 10.1 面试问题

1. `std::future` 是什么？
2. `std::promise` 是什么？
3. `std::async` 有什么作用？
4. 如何从线程获取返回值？
5. 如何在线程间传递异常？

***

## 10.2 `std::async`

```cpp
#include <future>
#include <iostream>

int compute() {
    return 42;
}

int main() {
    std::future<int> fut = std::async(std::launch::async, compute);

    int result = fut.get();

    std::cout << result << "\n";
}
```

`future::get()` 会等待任务完成并获取结果。

***

## 10.3 `promise + future`

```cpp
#include <future>
#include <iostream>
#include <thread>

void worker(std::promise<int> p) {
    p.set_value(42);
}

int main() {
    std::promise<int> p;
    std::future<int> f = p.get_future();

    std::thread t(worker, std::move(p));

    std::cout << f.get() << "\n";

    t.join();
}
```

`promise` 用来设置结果，`future` 用来获取结果。

***

## 10.4 传递异常

```cpp
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>

void worker(std::promise<int> p) {
    try {
        throw std::runtime_error("error in worker");
    } catch (...) {
        p.set_exception(std::current_exception());
    }
}

int main() {
    std::promise<int> p;
    auto f = p.get_future();

    std::thread t(worker, std::move(p));

    try {
        std::cout << f.get() << "\n";
    } catch (const std::exception& e) {
        std::cout << e.what() << "\n";
    }

    t.join();
}
```

***

# 11. 线程安全队列

## 11.1 面试问题

1. 如何实现线程安全队列？
2. 为什么要用条件变量？
3. 如何支持阻塞式 pop？
4. 如何优雅关闭队列？

***

## 11.2 简单线程安全队列

```cpp
#include <condition_variable>
#include <mutex>
#include <optional>
#include <queue>

template <typename T>
class BlockingQueue {
public:
    void push(T value) {
        {
            std::lock_guard<std::mutex> lock(mtx_);
            q_.push(std::move(value));
        }

        cv_.notify_one();
    }

    std::optional<T> pop() {
        std::unique_lock<std::mutex> lock(mtx_);

        cv_.wait(lock, [this] {
            return closed_ || !q_.empty();
        });

        if (q_.empty()) {
            return std::nullopt;
        }

        T value = std::move(q_.front());
        q_.pop();

        return value;
    }

    void close() {
        {
            std::lock_guard<std::mutex> lock(mtx_);
            closed_ = true;
        }

        cv_.notify_all();
    }

private:
    std::queue<T> q_;
    std::mutex mtx_;
    std::condition_variable cv_;
    bool closed_ = false;
};
```

使用：

```cpp
#include <iostream>
#include <thread>

int main() {
    BlockingQueue<int> q;

    std::thread producer([&] {
        for (int i = 0; i < 5; ++i) {
            q.push(i);
        }

        q.close();
    });

    std::thread consumer([&] {
        while (auto value = q.pop()) {
            std::cout << *value << "\n";
        }
    });

    producer.join();
    consumer.join();
}
```

***

# 12. 线程池

## 12.1 面试问题

1. 为什么需要线程池？
2. 线程池基本组成是什么？
3. 任务队列如何同步？
4. 如何停止线程池？
5. 如何获取任务返回值？

***

## 12.2 为什么需要线程池？

频繁创建和销毁线程开销大。线程池通过复用固定数量工作线程，减少开销，并控制并发度。

`huihut/interview` 中也对比了多线程创建、销毁、切换速度快，内存和资源占用小，但编程和调试复杂。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 12.3 简单线程池

```cpp
#include <condition_variable>
#include <functional>
#include <future>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

class ThreadPool {
public:
    explicit ThreadPool(std::size_t n) {
        for (std::size_t i = 0; i < n; ++i) {
            workers_.emplace_back([this] {
                while (true) {
                    std::function<void()> task;

                    {
                        std::unique_lock<std::mutex> lock(mtx_);

                        cv_.wait(lock, [this] {
                            return stop_ || !tasks_.empty();
                        });

                        if (stop_ && tasks_.empty()) {
                            return;
                        }

                        task = std::move(tasks_.front());
                        tasks_.pop();
                    }

                    task();
                }
            });
        }
    }

    ~ThreadPool() {
        {
            std::lock_guard<std::mutex> lock(mtx_);
            stop_ = true;
        }

        cv_.notify_all();

        for (auto& t : workers_) {
            if (t.joinable()) {
                t.join();
            }
        }
    }

    template <typename F>
    auto submit(F&& f) -> std::future<decltype(f())> {
        using R = decltype(f());

        auto task = std::make_shared<std::packaged_task<R()>>(
            std::forward<F>(f)
        );

        std::future<R> result = task->get_future();

        {
            std::lock_guard<std::mutex> lock(mtx_);
            tasks_.emplace([task] {
                (*task)();
            });
        }

        cv_.notify_one();

        return result;
    }

private:
    std::vector<std::thread> workers_;
    std::queue<std::function<void()>> tasks_;

    std::mutex mtx_;
    std::condition_variable cv_;
    bool stop_ = false;
};
```

使用：

```cpp
#include <iostream>

int main() {
    ThreadPool pool(4);

    auto f1 = pool.submit([] {
        return 1 + 2;
    });

    auto f2 = pool.submit([] {
        return std::string("hello");
    });

    std::cout << f1.get() << "\n";
    std::cout << f2.get() << "\n";
}
```

***

# 13. 读写锁 `shared_mutex`

## 13.1 面试问题

1. 什么是读写锁？
2. 读写锁适合什么场景？
3. `shared_lock` 和 `unique_lock` 区别？
4. 读多写少如何优化？

读写锁允许多个线程同时读共享数据，但写操作互斥。`huihut/interview` 的线程同步部分也提到读写锁允许多个线程同时读共享数据，而写操作互斥。 [\[huihut/int...tion, etc.\]](https://github.com/huihut/interview#cc)

***

## 13.2 示例

```cpp
#include <iostream>
#include <shared_mutex>
#include <string>
#include <unordered_map>

class Cache {
public:
    std::string get(int key) const {
        std::shared_lock<std::shared_mutex> lock(mtx_);

        auto it = data_.find(key);
        if (it == data_.end()) {
            return {};
        }

        return it->second;
    }

    void set(int key, std::string value) {
        std::unique_lock<std::shared_mutex> lock(mtx_);

        data_[key] = std::move(value);
    }

private:
    mutable std::shared_mutex mtx_;
    std::unordered_map<int, std::string> data_;
};
```

读操作共享锁，写操作独占锁。

***

# 14. 单例与线程安全

## 14.1 面试问题

1. 局部静态变量单例是否线程安全？
2. 双重检查锁定有什么问题？
3. 如何写线程安全单例？

***

## 14.2 C++11 局部静态变量单例

```cpp
class Singleton {
public:
    static Singleton& instance() {
        static Singleton obj;
        return obj;
    }

private:
    Singleton() = default;

    Singleton(const Singleton&) = delete;
    Singleton& operator=(const Singleton&) = delete;
};
```

C++11 起，局部静态变量初始化是线程安全的。

***

## 14.3 `std::call_once`

```cpp
#include <memory>
#include <mutex>

class Singleton {
public:
    static Singleton& instance() {
        std::call_once(flag_, [] {
            instance_.reset(new Singleton);
        });

        return *instance_;
    }

private:
    Singleton() = default;

    static std::once_flag flag_;
    static std::unique_ptr<Singleton> instance_;
};

std::once_flag Singleton::flag_;
std::unique_ptr<Singleton> Singleton::instance_;
```

***

# 15. 常见并发 Bug

## 15.1 数据竞争

```cpp
int x = 0;

void f() {
    ++x; // 多线程下数据竞争
}
```

解决：

```cpp
std::atomic<int> x{0};
```

或：

```cpp
std::mutex mtx;
```

***

## 15.2 死锁

多个锁加锁顺序不一致。

解决：

* 固定加锁顺序；
* 使用 `std::scoped_lock`;
* 减少锁粒度；
* 避免持锁调用外部回调；
* 避免嵌套锁。

***

## 15.3 忘记 `join`

```cpp
std::thread t(f);
// 忘记 join/detach，析构 terminate
```

解决：

```cpp
if (t.joinable()) {
    t.join();
}
```

或 C++20：

```cpp
std::jthread t(f);
```

`std::jthread` 析构时自动 join。

***

## 15.4 条件变量丢通知

错误：

```cpp
cv.notify_one();
cv.wait(lock);
```

如果通知发生在等待之前，可能永远等不到。

正确模型：

```cpp
cv.wait(lock, [] {
    return condition;
});
```

条件变量等待的核心不是“通知”，而是“条件”。

***

## 15.5 持锁时间过长

错误倾向：

```cpp
std::lock_guard<std::mutex> lock(mtx);

// 做大量 IO、网络、复杂计算
```

改进：

```cpp
{
    std::lock_guard<std::mutex> lock(mtx);
    // 只保护共享数据
}

// 锁外做耗时操作
```

***

# 16. 面试高频代码题

## 题 1：下面代码有什么问题？

```cpp
#include <thread>

void f() {}

int main() {
    std::thread t(f);
}
```

答案：

```text
std::thread 对象析构时仍 joinable，会调用 std::terminate。
```

修复：

```cpp
int main() {
    std::thread t(f);
    t.join();
}
```

***

## 题 2：为什么结果不是 200000？

```cpp
#include <iostream>
#include <thread>

int x = 0;

void add() {
    for (int i = 0; i < 100000; ++i) {
        ++x;
    }
}

int main() {
    std::thread t1(add);
    std::thread t2(add);

    t1.join();
    t2.join();

    std::cout << x << "\n";
}
```

答案：

```text
++x 不是原子操作，多个线程同时读写 x，发生数据竞争。
```

修复 1：

```cpp
std::atomic<int> x{0};
```

修复 2：

```cpp
std::mutex mtx;
```

***

## 题 3：条件变量为什么要 while？

```cpp
std::unique_lock<std::mutex> lock(mtx);
cv.wait(lock);

if (!q.empty()) {
    // consume
}
```

问题：

```text
可能虚假唤醒；也可能多个消费者被唤醒后队列已被其他线程取空。
```

修复：

```cpp
cv.wait(lock, [] {
    return !q.empty();
});
```

***

## 题 4：下面是否线程安全？

```cpp
std::shared_ptr<int> p = std::make_shared<int>(0);

void f() {
    ++(*p);
}
```

答案：

```text
shared_ptr 的引用计数操作通常是线程安全的，但被管理对象 int 本身不是线程安全的。
```

修复：

```cpp
std::shared_ptr<std::atomic<int>> p = std::make_shared<std::atomic<int>>(0);
```

或用 mutex 保护。

***

# 17. 面试速记版

## 线程基础

* `std::thread` 创建线程后必须 `join` 或 `detach`。
* `join` 等待线程结束。
* `detach` 后线程后台运行，生命周期难控。
* C++20 `std::jthread` 析构自动 join。

***

## 锁

* `mutex` 保护共享资源。
* `lock_guard` 简单 RAII 锁。
* `unique_lock` 更灵活，可手动加解锁，可配合条件变量。
* 多锁用 `std::scoped_lock` 避免死锁。

***

## 条件变量

* 用于线程等待某个条件成立。
* 必须配合 mutex。
* 必须用 `while` 或谓词防止虚假唤醒。
* `notify_one` 唤醒一个等待线程。
* `notify_all` 唤醒所有等待线程。

***

## 原子

* `atomic` 适合简单共享变量。
* `atomic` 保证原子性，但不一定无锁。
* `volatile` 不是线程同步工具。
* 默认内存序 `seq_cst` 最安全。
* `relaxed` 只保证原子性，不保证顺序。
* `release/acquire` 用于发布-订阅同步。

***

## 并发设计原则

* 优先避免共享数据。
* 共享数据必须明确所有权和同步策略。
* 锁粒度要小，但不要过度复杂。
* 不要持锁调用未知外部代码。
* 线程退出路径要清晰。
* 用 RAII 管理锁和线程资源。
* 能用高层抽象就别手写底层同步。

***

下一块建议继续讲：

> **操作系统与网络基础：进程线程、虚拟内存、IPC、死锁、TCP/UDP、三次握手、四次挥手、epoll/select。**
