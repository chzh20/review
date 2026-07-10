# Qt QThread 源码笔记

> 主题：结合 Qt5 源码理解 `QThread` 的线程管理模型、worker-object 模式、并发方案选型，以及 `start()` / `run()` / `exec()` 启动退出流程。
>
> 主要源码参考：
>
> - `qtbase/src/corelib/thread/qthread.h`
> - `qtbase/src/corelib/thread/qthread.cpp`
> - `qtbase/src/corelib/thread/qthread_p.h`
> - `qtbase/src/corelib/thread/qthread_unix.cpp`
> - `qtbase/src/corelib/thread/qthreadpool.cpp`
> - `qtbase/src/concurrent/`
> - [Qt 5 源码浏览（codebrowser.dev）](https://codebrowser.dev/qt5/)

---

## 目录

- [1. Qt 并发总体模型](#1-qt-并发总体模型)
- [2. QThread 的本质](#2-qthread-的本质)
- [3. 并发方案选型](#3-并发方案选型)
- [4. 线程安全 vs reentrant](#4-线程安全-vs-reentrant)
- [5. worker-object 标准写法](#5-worker-object-标准写法)
- [6. 常见错误与最佳实践](#6-常见错误与最佳实践)
- [7. 源码深入：QThreadData 与类结构](#7-源码深入qthreaddata-与类结构)
- [8. 源码深入：start → run → exec 启动流程](#8-源码深入start--run--exec-启动流程)
- [9. 源码深入：quit / exit / wait 与生命周期信号](#9-源码深入quit--exit--wait-与生命周期信号)
- [10. moveToThread 与 QThread 的关系](#10-movetothread-与-qthread-的关系)
- [11. 何时继承 QThread](#11-何时继承-qthread)
- [12. 源码学习路线](#12-源码学习路线)
- [13. 规则速查表](#13-规则速查表)

---

# 1. Qt 并发总体模型

Qt 的并发不是简单地「开线程跑函数」，而是围绕以下核心概念组织：

| 层次 | 核心概念 | 说明 |
|---|---|---|
| 线程管理 | `QThread` | 管理一个底层 OS 线程；默认 `run()` 会启动该线程的 Qt event loop（`exec()`） |
| 对象归属 | Thread Affinity | 每个 `QObject` 属于某个线程，事件和 queued signal 投递到其所属线程的 event loop（详见 `02_thread_affinity.md`） |
| 跨线程通信 | Signal/Slot、invokeMethod、postEvent | 推荐用 `Qt::QueuedConnection`，不要直接跨线程调用对象方法 |
| 任务并行 | `QThreadPool` / `QtConcurrent` | 短任务、批量任务用线程池或高层并行 API |
| 同步原语 | `QMutex`、`QReadWriteLock`、`QSemaphore`、`QWaitCondition`、`QAtomic*` | 共享数据时的线程同步 |

---

# 2. QThread 的本质

## 2.1 核心结论

> **`QThread` 是一个 QObject 风格的「线程控制对象」，它管理一个底层线程，但 `QThread` 对象本身通常仍然生活在创建它的线程中，不会自动搬到新线程里。**

```cpp
QThread* t = new QThread;   // 假设在主线程创建
t->start();                 // 创建/启动底层新线程
```

- `t` 这个 **QObject 对象** 的 thread affinity 仍然是主线程
- `t->run()` 是在新建的 OS 线程里执行
- `QThread` 子类的普通成员函数/槽函数，不代表它们自动运行在新线程
- 只有 `run()` 里的代码，或 `moveToThread` 后 worker 对象的 queued slot，才会在新线程执行

## 2.2 面试级一句话

> `QThread` 不是「生活在新线程中的业务对象」，它是「管理一个新线程的 QObject 控制器」；业务逻辑应放到 `moveToThread` 后的 worker 对象里，或者放到重写的 `run()` 中。

## 2.3 与 Thread Affinity 的关系

`QObject` 的 thread affinity、`moveToThread()` 限制、parent/child 规则、GUI 线程约束等，详见 [`02_thread_affinity.md`](02_thread_affinity.md)。本节只列与 `QThread` 使用最相关的几条：

1. **child 必须和 parent 在同一线程创建** — 不要把 `QThread* this` 当作在新线程中创建对象的 parent
2. **有 parent 的 QObject 不能独立 moveToThread**
3. **event-driven 对象（`QTimer`、`QTcpSocket`、`QNetworkAccessManager` 等）必须在自己的线程里创建和使用**
4. **跨线程删除用 `deleteLater()`**，不要直接 `delete`

---

# 3. 并发方案选型

## 3.1 选择原则

| 方案 | 适合场景 | 不适合场景 | 关键词 |
|---|---|---|---|
| `QThread + worker QObject` | 长生命周期任务；需要 signal/slot、`QTimer`、socket、event loop | 大量很短的一次性任务 | controllable event loop |
| subclass `QThread` | 非 QObject 任务；清楚 `run()` 生命周期；不需要 worker slots | 把业务 slots 写在 QThread 子类里期待自动跑到新线程 | lower-level |
| `QThreadPool + QRunnable` | 大量短任务；无事件循环需求；复用线程降低创建销毁成本 | 需要长期 QObject、timer/socket event loop | task queue |
| `QtConcurrent` | map/filter/reduce、简单后台函数、少写线程同步代码 | 复杂生命周期控制、复杂取消/暂停、需要 QObject event loop | high-level parallelism |
| `std::thread` | 纯 C++ 库层；完全不依赖 Qt event loop | 需要 Qt queued signal、QObject affinity、QTimer/socket | standard C++ |

## 3.2 实战建议

- **GUI 不要阻塞主线程**：耗时计算、IO、网络等待放到后台；UI 更新只能回到 main GUI thread
- **需要 `QTimer` / `QTcpSocket` / `QNetworkAccessManager` 的 worker**：优先 `QThread + worker-object`，在 worker 的 slot 中创建这些对象
- **CPU 批处理**：优先 `QtConcurrent::map/filter/reduce` 或 `QThreadPool`
- **高频小任务**：优先 `QThreadPool`，因为线程创建销毁代价高
- **纯 C++ 模块**：可用 `std::thread` / `std::jthread` / `std::async`，但一旦接入 QObject，就要遵守 thread affinity 和 event loop 规则

---

# 4. 线程安全 vs reentrant

## 4.1 定义

- **thread-safe**：多个线程可以同时调用同一对象/共享数据上的函数，因为内部或外部对共享数据访问做了序列化
- **reentrant**：多个线程可以同时调用，但前提是每个线程操作的是**自己的实例/自己的数据**；同一实例被多个线程同时访问通常仍不安全
- **关系**：thread-safe 一定 reentrant，但 reentrant 不一定 thread-safe

## 4.2 典型 thread-safe 类/函数

- `QMutex`、`QRecursiveMutex`、`QMutexLocker`
- `QReadWriteLock`、`QReadLocker`、`QWriteLocker`
- `QSemaphore`、`QWaitCondition`
- `QAtomicInteger`、`QAtomicPointer`
- `QObject::connect` / `disconnect`、`deleteLater` 等（现代 Qt 文档标注为 thread-safe 的函数）

## 4.3 典型 reentrant 类

- `QObject` 本身是 reentrant
- `QTimer`、`QTcpSocket`、`QUdpSocket`、`QProcess` 等
- Qt 容器（`QList`、`QMap`、`QHash`、`QSet` 等）：只读方式被多线程访问时是 thread-safe，但不同线程同时修改同一实例不安全

## 4.4 明确不能跨线程用的类

- `QWidget` 及其所有子类只能在 GUI/main thread 使用
- 绝大多数 GUI 类都不能在 worker thread 直接创建/操作

---

# 5. worker-object 标准写法

这是 Qt 并发最重要的模板。官方 QThread 文档给出的模式：创建 `Worker : QObject`，`moveToThread(&workerThread)`，连接 `QThread::finished` 到 `worker->deleteLater()`，跨线程用 signal 调 worker slot，析构时 `quit()` + `wait()`。

## 5.1 Worker 类

```cpp
// worker.h
#pragma once

#include <QObject>
#include <QThread>
#include <QDebug>

class Worker : public QObject
{
    Q_OBJECT

public:
    explicit Worker(QObject* parent = nullptr)
        : QObject(parent)
    {}

public slots:
    void doWork(QString input)
    {
        // 通过 QueuedConnection 调用时，运行在 worker 所属线程
        qDebug() << "Worker thread:" << QThread::currentThread();

        QString result;
        // ... 耗时任务，不要直接操作 UI ...

        emit resultReady(result);
        emit finished();
    }

signals:
    void resultReady(QString result);
    void finished();
};
```

## 5.2 Controller 类

```cpp
// controller.h / controller.cpp
#include <QObject>
#include <QThread>
#include "worker.h"

class Controller : public QObject
{
    Q_OBJECT

public:
    explicit Controller(QObject* parent = nullptr)
        : QObject(parent)
    {
        worker = new Worker;              // 不要设置 parent
        worker->moveToThread(&thread);

        connect(&thread, &QThread::finished,
                worker, &QObject::deleteLater);

        connect(this, &Controller::startWork,
                worker, &Worker::doWork,
                Qt::QueuedConnection);

        connect(worker, &Worker::resultReady,
                this, &Controller::handleResult,
                Qt::QueuedConnection);

        connect(worker, &Worker::finished,
                &thread, &QThread::quit);

        connect(&thread, &QThread::finished,
                this, &Controller::threadFinished);

        thread.start();
    }

    ~Controller() override
    {
        thread.quit();
        thread.wait();
    }

signals:
    void startWork(QString input);

private slots:
    void handleResult(QString result)
    {
        // 回到 Controller 所属线程，通常是主线程
    }

    void threadFinished()
    {
        // 可选：线程结束后的清理
    }

private:
    QThread thread;
    Worker* worker = nullptr;
};
```

## 5.3 为什么这个模板正确

- `Worker` 无 parent，因此可以 `moveToThread()`
- worker 的 slot 通过 queued connection 执行在 worker 所属线程
- worker 不直接操作 UI，而是发 signal 把结果传回主线程
- `thread.finished → worker.deleteLater` 确保 worker 在合适时机销毁
- 析构中 `quit()` + `wait()`，避免 `QThread: Destroyed while thread is still running`

## 5.4 官方推荐连接模式

```cpp
QThread *thread = new QThread;
Worker *worker = new Worker;

worker->moveToThread(thread);

connect(thread, &QThread::started, worker, &Worker::doWork);
connect(worker, &Worker::finished, thread, &QThread::quit);
connect(worker, &Worker::finished, worker, &QObject::deleteLater);
connect(thread, &QThread::finished, thread, &QObject::deleteLater);

thread->start();
```

---

# 6. 常见错误与最佳实践

## 6.1 把耗时业务写进 QThread 子类的 slot

```cpp
class MyThread : public QThread
{
    Q_OBJECT
public slots:
    void doWork(); // 很多人以为这个会自动跑在新线程，通常不是
};
```

`QThread` 对象本身通常仍属于创建它的线程；`start()` 不会让 QThread 子类的普通 slots 自动跑到新线程。

## 6.2 在构造函数里创建 socket/timer，然后 moveToThread

如果 worker 在主线程构造时就创建了 `QTimer` / `QTcpSocket` / `QNetworkAccessManager`，这些 child 也在主线程；之后 move worker 或在其他线程使用它们，容易遇到 parent/thread 不一致。

**更稳的写法**：在 worker 的 `init()` slot 中创建这些对象：

```cpp
class NetworkWorker : public QObject
{
    Q_OBJECT

public slots:
    void init()
    {
        // 此时 init() 已在 worker thread 中执行
        manager = new QNetworkAccessManager(this);
    }

    void request()
    {
        // 在 manager 所属线程使用
    }

private:
    QNetworkAccessManager* manager = nullptr;
};
```

```cpp
connect(&thread, &QThread::started, worker, &NetworkWorker::init);
```

## 6.3 跨线程直接调用 QObject 方法

应通过 signal/slot 或 `QMetaObject::invokeMethod`：

```cpp
QMetaObject::invokeMethod(worker, "doWork",
                          Qt::QueuedConnection,
                          Q_ARG(QString, "input"));
```

## 6.4 worker 直接更新 UI

UI 只能在主线程操作，worker 应发 signal，把结果交给主线程 slot 更新界面。

---

# 7. 源码深入：QThreadData 与类结构

## 7.1 QThread 公开 API

```cpp
// 摘自 qtbase/src/corelib/thread/qthread.h
class Q_CORE_EXPORT QThread : public QObject
{
    Q_OBJECT

public:
    static Qt::HANDLE currentThreadId() noexcept;
    static QThread *currentThread();
    static int idealThreadCount() noexcept;

    explicit QThread(QObject *parent = nullptr);
    ~QThread();

public Q_SLOTS:
    void start(Priority = InheritPriority);
    void terminate();
    void quit();

Q_SIGNALS:
    void started(QPrivateSignal);
    void finished(QPrivateSignal);

protected:
    virtual void run();
    int exec();
};
```

`QThread` 继承自 `QObject`，是一个管理底层线程生命周期的控制器：

```text
QThread 对象本身：QObject，通常活在创建它的线程中
QThread 管理的线程：底层 OS thread，由 start() 创建
run()：真正运行在新线程里的入口函数
exec()：在新线程里启动事件循环
```

## 7.2 QThreadData：per-thread 状态

`QThread` 公开 API 很薄，内部状态在 `QThreadPrivate` / `QThreadData` 中维护：

```cpp
class QThreadData {
    QAtomicInt ref;
    int loopLevel;
    int scopeLevel;
    QAbstractEventDispatcher *eventDispatcher;
    bool quitNow;
    bool canWait;
    bool isAdopted;
    bool requiresCoreApplication;
    // 还有 posted events、TLS、当前 QThread 指针等
};
```

Qt 的线程模型不是单纯封装 `pthread_t` / `HANDLE`，而是把 **线程、事件循环、事件派发器、posted events、QObject affinity** 绑定在一起管理。`qthread_p.h` 中的 `QPostEvent`（含 `receiver`、`event`、`priority`）说明跨线程事件投递最终落到每个线程自己的 posted event 队列。

---

# 8. 源码深入：start → run → exec 启动流程

## 8.1 整体流程

```text
用户调用 thread.start()
    ↓
QThreadPrivate 检查状态、设置 priority、stack size 等
    ↓
平台层创建底层线程（pthread_create / Windows thread）
    ↓
新线程入口函数被调用
    ↓
设置当前线程的 QThreadData
    ↓
发出 started()
    ↓
调用 QThread::run()
    ↓
默认 run() 调用 exec()
    ↓
事件循环运行
    ↓
quit()/exit() 让事件循环结束
    ↓
run() 返回
    ↓
发出 finished()
    ↓
线程清理
```

`start()` **不是直接执行你的任务**，它只是创建底层线程；真正运行在新线程的是 `run()`。

## 8.2 默认 run() 为什么调用 exec()

`QThread` 默认不是为了「一次性跑个函数就结束」，而是给该线程提供一个 **event loop**，让它能处理：

- queued signal/slot
- `QTimer`
- socket notifier
- `deleteLater()`
- posted event
- 其他依赖事件循环的 Qt 机制

默认 `QThread::run()` 大致等价于：

```cpp
void QThread::run()
{
    exec();
}
```

因此 `thread.start()` 后，新线程进入自己的事件循环，等待投递给该线程中 QObject 的事件和 queued slot。这正是 worker-object 模式的基础：把 `QObject` worker `moveToThread()` 到该线程，再通过 signal/slot 触发 worker 的槽函数。

## 8.3 QThread 对象本身不在新线程

```cpp
QThread *thread = new QThread(this);
thread->start();
```

`thread` 这个 `QObject` 是在当前线程创建的，thread affinity 属于当前线程。`start()` 创建新 OS 线程，但不会把 `thread` 这个 QObject 自身搬过去。

```cpp
class MyThread : public QThread
{
    Q_OBJECT

public slots:
    void doWork();   // 这个 slot 不一定在新线程执行

protected:
    void run() override;
};
```

- `run()` 在新线程执行
- `doWork()` 作为 `MyThread` 这个 QObject 的 slot，queued 调用时取决于 `MyThread` 对象本身的 thread affinity，通常仍是创建它的旧线程

> `QThread::run()` 在新线程；`QThread` 对象本身通常还在旧线程。

---

# 9. 源码深入：quit / exit / wait 与生命周期信号

## 9.1 exec / quit / exit

```cpp
void exit(int retcode = 0);
void quit();
protected:
    int exec();
```

- `exec()`：事件循环入口
- `exit(retcode)`：请求事件循环带返回码退出
- `quit()`：通常等价于 `exit(0)`

典型用法：

```cpp
thread.start();  // 新线程进入 run()，默认 run() 进入 exec()

// later
thread.quit();   // 通知 event loop 退出
thread.wait();   // 等待底层线程真正结束
```

析构时必须 `quit()` + `wait()`，否则可能出现 `QThread: Destroyed while thread is still running`。

## 9.2 started / finished 信号

```cpp
Q_SIGNALS:
    void started(QPrivateSignal);
    void finished(QPrivateSignal);
```

常见连接：

```cpp
connect(&thread, &QThread::started, worker, &Worker::init);
connect(&thread, &QThread::finished, worker, &QObject::deleteLater);
```

`deleteLater()` 通过事件机制延迟删除 QObject，更适合 Qt 的线程和事件循环模型。

---

# 10. moveToThread 与 QThread 的关系

`QThread` 负责提供线程和事件循环，`QObject::moveToThread()` 负责改变 QObject 的 thread affinity。两者分工：

```text
QThread：负责线程生命周期
Worker：负责业务逻辑
Signal/Slot：负责跨线程通信
```

当 `worker` 被 move 到 `thread` 后，投递给 `worker` 的 queued slot 会在 `thread` 的事件循环中执行。这也是 worker-object 模式比继承 `QThread` 更适合大多数业务场景的原因。

`moveToThread()` 的底层限制和源码拦截逻辑，详见 [`02_thread_affinity.md`](02_thread_affinity.md) 第 5 节。

---

# 11. 何时继承 QThread

继承 `QThread` 不是绝对错误，但要明确你是在改写线程入口 `run()`：

```cpp
class MyThread : public QThread
{
protected:
    void run() override
    {
        // 这里运行在新线程
        doHeavyWork();

        // 如果需要事件循环，显式调用 exec()
        // exec();
    }
};
```

**适合继承 `QThread` 的场景**：

- 一次性计算、不需要 QObject
- 不需要 timer/socket
- 不需要 queued slot
- 不调用 `exec()`，该线程中没有事件循环

**应优先用 worker-object 的场景**：

- `QTimer`、`QTcpSocket`、`QUdpSocket`、`QNetworkAccessManager`
- queued signal/slot
- `deleteLater()`
- long-running service object

---

# 12. 源码学习路线

建议按以下顺序阅读 Qt5 源码（[codebrowser.dev/qt5](https://codebrowser.dev/qt5/)）：

| 顺序 | 文件 | 关注点 |
|---|---|---|
| 1 | `qtbase/src/corelib/thread/qthread.h/.cpp` | `start()`、`run()`、`exec()`、`quit()`、`wait()`、`QThreadData` |
| 2 | `qtbase/src/corelib/kernel/qobject.h/.cpp` | `moveToThread()`、`thread()`、`connect()`、queued connection 投递逻辑 |
| 3 | `qtbase/src/corelib/kernel/qcoreapplication.cpp` | `postEvent()`、事件队列、deferred delete、queued slot、timer/socket 回调 |
| 4 | `qtbase/src/corelib/thread/qthreadpool.cpp`、`qrunnable.h` | 线程池如何复用线程、调度 `QRunnable::run()` |
| 5 | `qtbase/src/concurrent/` | `QtConcurrent::run/map/filter/reduce`、返回 `QFuture`、结合线程池调度 |

---

# 13. 规则速查表

| 维度 | 规则 |
|---|---|
| QThread 定位 | 线程控制器，不是 worker 本身 |
| 业务逻辑 | 用 QObject worker + `moveToThread()` |
| QThread 对象归属 | 通常仍在创建它的线程，不在新线程 |
| 新线程入口 | `run()` 在新线程执行；默认 `run()` 调用 `exec()` |
| 跨线程通信 | Signal/Slot（`Qt::QueuedConnection`）或 `QMetaObject::invokeMethod` |
| event-driven 对象 | 在所属线程创建和使用（`QTimer`、socket、network 等） |
| GUI | 只能主线程操作 |
| 短任务 | `QThreadPool` / `QtConcurrent` |
| 长生命周期 + event loop | `QThread + worker-object` |
| reentrant vs thread-safe | reentrant ≠ thread-safe；同一实例跨线程共享必须加锁或只读 |
| 退出线程 | `quit()` + `wait()` |
| 销毁对象 | `deleteLater()`，不要跨线程直接 `delete` |

---

## 延伸阅读

- Thread Affinity 与 `moveToThread()` 底层机制：[`02_thread_affinity.md`](02_thread_affinity.md)
- 信号槽与 `deleteLater()` 跨线程销毁：[`01_Qt_QObject_SignalSlot.md`](01_Qt_QObject_SignalSlot.md)
- 事件循环基础：[`00_qt_event_loop.md`](00_qt_event_loop.md)

## 参考资料

- [qthread.h（codebrowser.dev）](https://codebrowser.dev/qt5/qtbase/src/corelib/thread/qthread.h.html)
- [qthread.cpp（codebrowser.dev）](https://codebrowser.dev/qt5/qtbase/src/corelib/thread/qthread.cpp.html)
- [qthread_unix.cpp（codebrowser.dev）](https://codebrowser.dev/qt5/qtbase/src/corelib/thread/qthread_unix.cpp.html)
- [QThread（Qt 官方文档）](https://doc.qt.io/qt-6/qthread.html)
- [Threads and QObjects（Qt 官方文档）](https://doc.qt.io/qt-6/threads-qobject.html)
- [Thread Support in Qt（Qt 官方文档）](https://doc.qt.io/qt-6/threads.html)
