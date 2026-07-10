# Qt 并发编程：从线程亲和性到可取消任务的工程化实践

> 面向有经验的 C++/Qt 工程师。重点不是“会创建线程”，而是理解 **QObject、事件循环、线程亲和性、任务调度、生命周期与协作式取消**，并能在面试中解释背后的设计权衡。

***

## 一、Qt 并发真正难在哪里？

Qt 并发不能简单理解成“对 `std::thread` 的跨平台封装”。

Qt 同时包含两套相互协作的模型：

1. **C++ 共享内存并发模型**
   * `QMutex`
   * `QReadWriteLock`
   * `QWaitCondition`
   * 原子变量
   * `std::mutex`、`std::atomic` 等标准库设施

2. **Qt 事件驱动并发模型**
   * `QObject` 的线程亲和性
   * 每线程事件循环
   * queued signal/slot
   * `QMetaObject::invokeMethod`
   * `deleteLater`

资深工程师需要明白：

> Qt 中一个对象“属于哪个线程”，通常不是指它在哪个线程中被 `new` 出来，也不是指哪个线程正在调用它，而是指它的 **thread affinity**——事件和 queued slot 应当在哪个线程得到处理。

Qt 提供 `QThread`、`QThreadPool`、`QRunnable`、Qt Concurrent、`QFuture` 和 `QPromise` 等不同层次的并发抽象：`QThread` 适合带事件循环或需要长期存在的工作对象；线程池和 Qt Concurrent 更适合离散任务与数据并行。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads-technologies.html)

***

# 二、最关键的概念：QThread 对象不等于工作线程

这是 Qt 并发面试中最常见的问题。

```cpp
QThread thread;
thread.start();
```

这里需要区分两个实体：

* `thread`：一个 `QThread` 类型的 **QObject 管理对象**
* 操作系统工作线程：由 `QThread::start()` 创建并执行 `run()`

假设 `QThread thread` 是在 GUI 线程创建的，那么：

* `thread` 这个 QObject 默认属于 GUI 线程；
* `QThread::run()` 在新线程执行；
* `QThread` 对象自身的 queued slot，默认仍在创建它的线程执行。

Qt 文档明确指出：`QThread` 对象管理一个线程；默认 `run()` 调用 `exec()` 启动该线程的事件循环。官方也给出了把 Worker 对象通过 `moveToThread()` 移入工作线程的标准用法。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html)

因此下面这种代码往往与作者想象的不一致：

```cpp
class BadThread : public QThread
{
    Q_OBJECT

public slots:
    void process()
    {
        // 不一定在 BadThread::run() 所在线程执行。
        // queued 调用取决于 BadThread 对象自身的线程亲和性。
    }

protected:
    void run() override
    {
        // 这里才在新线程中执行。
    }
};
```

## 面试中的标准回答

**问：为什么不建议把业务 slot 直接写在 QThread 子类中？**

可以这样回答：

> 因为 `QThread` 对象本身通常属于创建它的线程，而不是 `run()` 所运行的新线程。把业务 slot 放入 `QThread` 子类容易让对象身份与执行上下文混淆。长期运行、依赖事件循环的业务更适合使用 Worker Object，并通过 `moveToThread()` 设置其线程亲和性。

但不要回答成：

> “永远不能继承 QThread。”

这是不准确的。对于以下场景，继承 `QThread` 并重写 `run()` 是合理的：

* 一次性的线性计算；
* 不需要线程事件循环；
* 需要在线程启动时建立线程局部资源；
* 需要严格控制 `run()` 的进入和退出；
* 希望资源全部位于 `run()` 栈上，并随线程结束自动销毁。

Qt 官方将两种模式都视为有效：直接使用 `QThread` 可以获得工作线程事件循环；继承并重写 `run()` 可以执行不依赖事件循环的并行代码。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads-technologies.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html)

***

# 三、线程亲和性与信号槽到底如何工作？

## 1. `Qt::AutoConnection` 不是在 `connect()` 时决定的

默认连接类型是 `Qt::AutoConnection`。

它在信号发射时，根据 **当前执行线程** 和 **接收者对象的线程亲和性** 决定调用方式：

* 同一线程：通常退化为 `DirectConnection`
* 不同线程：通常退化为 `QueuedConnection`

对于 queued connection，Qt 不会直接调用 slot，而是向接收对象所属线程的事件队列投递事件。

因此，跨线程 queued slot 生效需要两个条件：

1. 接收对象具有正确的线程亲和性；
2. 接收线程有机会处理事件队列。

Qt 的线程支持包含线程安全的事件投递方式和跨线程 signal/slot；官方示例还展示了通过 queued signal/slot 在工作线程执行任务。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html)

***

## 2. 有事件循环，不代表事件循环一定能运行

考虑下面的 Worker：

```cpp
void Worker::process()
{
    while (!finished) {
        doHeavyWork();
    }
}
```

如果 `process()` 是由 queued connection 调用的，那么它开始后会一直占住工作线程。即使该线程已经调用过 `exec()`，事件循环也无法继续处理：

* queued `stop()`；
* `QTimer::timeout`；
* `deleteLater()`；
* socket notifier；
* 其他投递事件。

这会产生经典问题：

```cpp
emit requestStop();
```

信号确实被投递到了工作线程，但 `process()` 永不返回，所以 `stop()` 永远没有机会执行。

## 工程上的三种解决方案

### 方案 A：把长任务切成小片

每次只处理有限工作，然后把控制权还给事件循环。

```cpp
class Worker final : public QObject
{
    Q_OBJECT

public slots:
    void start()
    {
        stopped_ = false;
        QMetaObject::invokeMethod(
            this, &Worker::processChunk,
            Qt::QueuedConnection);
    }

    void stop()
    {
        stopped_ = true;
    }

private slots:
    void processChunk()
    {
        if (stopped_) {
            emit finished();
            return;
        }

        constexpr int batchSize = 256;

        for (int i = 0; i < batchSize; ++i) {
            if (!processOneItem()) {
                emit finished();
                return;
            }
        }

        // 重新排队，而不是递归调用。
        QMetaObject::invokeMethod(
            this, &Worker::processChunk,
            Qt::QueuedConnection);
    }

signals:
    void finished();

private:
    bool processOneItem();
    bool stopped_ = false;
};
```

这个模式的价值在于：

* `stop()` 可以及时得到处理；
* timer 和 socket 事件不会被永久饿死；
* Worker 状态只在自己的线程访问，通常不需要 mutex；
* 每个 chunk 是一个事件，相当于构建了一个串行 mailbox。

KDAB 的开源示例展示了类似的 Active Object 思路：对象隐藏内部工作线程，通过事件投递在该线程串行处理行为，而不是让调用者直接跨线程访问内部状态。 [\[github.com\]](https://github.com/KDABLabs/kdabtv/blob/master/Multithreading-with-Qt/ActiveObject/activeObject.cpp), [\[kdab.com\]](https://www.kdab.com/multithreading-with-qt/)

### 方案 B：使用线程安全的取消标志

对于必须连续执行的 CPU 循环，可以使用：

* `std::atomic_bool`
* `QThread::requestInterruption()`
* `QPromise::isCanceled()`

```cpp
void HashThread::run()
{
    while (!isInterruptionRequested()) {
        if (!calculateNextBlock())
            break;
    }
}
```

外部调用：

```cpp
thread.requestInterruption();
thread.wait();
```

`requestInterruption()` 是协作式请求，不会强制终止线程；工作代码必须在合理的粒度主动检查。`QThread` 的公开接口提供了 `requestInterruption()` 和 `isInterruptionRequested()`。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html), [\[qthread.h...odebrowser\]](https://codebrowser.dev/qt5/qtbase/src/corelib/thread/qthread.h.html)

### 方案 C：阻塞 I/O 使用超时或可中断系统调用

如果工作线程阻塞在：

* 文件读取；
* socket；
* 条件变量；
* 第三方库调用；

仅设置原子标志并不能唤醒它。工程上还应设计：

* 有限超时；
* 关闭 socket/句柄以唤醒阻塞调用；
* `QWaitCondition::wakeAll()`；
* `std::stop_token` 与支持停止的等待；
* 底层库提供的 cancel API。

***

# 四、可上线的 Worker Object 模式

下面给出比普通教学示例更完整的生命周期管理版本。

```cpp
class FileIndexer final : public QObject
{
    Q_OBJECT

public:
    explicit FileIndexer(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

public slots:
    void start(QString root)
    {
        if (running_)
            return;

        running_ = true;
        cancelRequested_ = false;
        root_ = std::move(root);

        QMetaObject::invokeMethod(
            this, &FileIndexer::processNextBatch,
            Qt::QueuedConnection);
    }

    void cancel()
    {
        // 该 slot 在 Worker 所属线程执行，因此普通 bool 就足够。
        cancelRequested_ = true;
    }

private slots:
    void processNextBatch()
    {
        if (!running_)
            return;

        if (cancelRequested_) {
            running_ = false;
            emit canceled();
            emit finished();
            return;
        }

        constexpr int batchSize = 128;

        for (int i = 0; i < batchSize; ++i) {
            auto result = indexOneFile();

            if (!result.has_value()) {
                running_ = false;
                emit completed();
                emit finished();
                return;
            }

            emit itemIndexed(*result);
        }

        QMetaObject::invokeMethod(
            this, &FileIndexer::processNextBatch,
            Qt::QueuedConnection);
    }

signals:
    void itemIndexed(QString path);
    void completed();
    void canceled();
    void failed(QString message);
    void finished();

private:
    std::optional<QString> indexOneFile();

    QString root_;
    bool running_ = false;
    bool cancelRequested_ = false;
};
```

Controller 负责线程和 Worker 的所有权：

```cpp
class IndexController final : public QObject
{
    Q_OBJECT

public:
    explicit IndexController(QObject *parent = nullptr)
        : QObject(parent),
          thread_(new QThread(this)),
          worker_(new FileIndexer)
    {
        thread_->setObjectName(QStringLiteral("FileIndexer"));

        // 有 parent 的 QObject 不能 moveToThread，
        // 所以 worker 创建时不能以 Controller 为 parent。
        worker_->moveToThread(thread_);

        connect(thread_, &QThread::finished,
                worker_, &QObject::deleteLater);

        connect(worker_, &FileIndexer::finished,
                thread_, &QThread::quit);

        connect(worker_, &FileIndexer::itemIndexed,
                this, &IndexController::itemIndexed);

        connect(worker_, &FileIndexer::failed,
                this, &IndexController::failed);

        thread_->start();
    }

    ~IndexController() override
    {
        if (!thread_->isRunning())
            return;

        // 跨线程异步请求取消。
        QMetaObject::invokeMethod(
            worker_, &FileIndexer::cancel,
            Qt::QueuedConnection);

        thread_->quit();

        // 析构阶段必须建立明确的 join 边界。
        if (!thread_->wait(5000)) {
            qCritical() << "FileIndexer failed to stop in time";

            // 不建议 terminate()。
            // 生产系统通常选择记录故障并执行更高层恢复策略。
            thread_->wait();
        }
    }

public slots:
    void startIndexing(const QString &root)
    {
        QMetaObject::invokeMethod(
            worker_,
            [worker = worker_, root] {
                worker->start(root);
            },
            Qt::QueuedConnection);
    }

    void cancel()
    {
        QMetaObject::invokeMethod(
            worker_, &FileIndexer::cancel,
            Qt::QueuedConnection);
    }

signals:
    void itemIndexed(QString path);
    void failed(QString message);

private:
    QThread *thread_;
    FileIndexer *worker_;
};
```

## 这个设计有哪些工程价值？

### 1. Controller 管生命周期，Worker 管业务状态

线程创建、启动、停止和等待集中在一个边界内，避免线程句柄散落到业务代码中。

### 2. Worker 状态线程封闭

`running_`、`cancelRequested_`、索引迭代器等状态只在 Worker 线程访问，不需要把每个字段都做成原子变量。

### 3. 无裸跨线程调用

外部通过 signal 或 `invokeMethod()` 投递操作，不直接调用 Worker 的普通成员函数。

### 4. 明确的关闭协议

关闭不是简单调用 `quit()`：

```text
请求业务取消
    ↓
业务停止产生新工作
    ↓
线程事件循环退出
    ↓
wait/join
    ↓
销毁资源
```

Qt 官方示例同样采用：

```cpp
connect(thread, &QThread::finished,
        worker, &QObject::deleteLater);
```

并在控制器析构时调用 `quit()` 和 `wait()`，以保证线程在控制器销毁前结束。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html)

***

# 五、`deleteLater()` 为什么在线程代码中如此重要？

不能随意在 A 线程删除属于 B 线程、并且仍可能处理事件的 QObject。

```cpp
delete worker;  // 可能跨线程析构
```

风险包括：

* 对象仍有待处理事件；
* timer 或 socket notifier 尚未注销；
* queued signal 已经在路上；
* QObject 子对象可能属于另一个线程上下文。

更安全的方法是：

```cpp
connect(thread, &QThread::finished,
        worker, &QObject::deleteLater);
```

不过资深面试中还可以进一步指出一个细节：

> `deleteLater()` 不是立即删除，而是投递 `DeferredDelete` 事件。因此必须结合事件循环的退出语义和连接时机分析，不能机械地认为任何时候调用它都一定能删除对象。

最稳妥的原则是：

* 在线程仍具有可工作的事件派发机制时安排延迟删除；
* 使用 Qt 官方推荐的 `finished -> deleteLater` 模式；
* 不要让 thread 先被析构，而 Worker 仍然存活；
* 不要把仍需跨线程移动的 Worker 设置为 thread 的 child；
* shutdown 完成后不再向 Worker 投递新任务。

KDAB 的并发材料也强调：必须在销毁相应的 `QThread` 前销毁生活在该线程中的 QObject，并建议使用 `finished` 与 `deleteLater` 建立清理关系。 [\[kdab.com\]](https://www.kdab.com/documents/multithreading-with-qt.pdf)

***

# 六、什么时候用 QThread，什么时候用线程池？

## 1. 使用 Worker + QThread

适合：

* 长生命周期组件；
* 一个业务对象需要串行维护内部状态；
* 依赖 `QTimer`、`QTcpSocket` 或其他事件驱动对象；
* 需要固定线程上下文；
* 需要持续接收命令；
* 初始化昂贵资源并在线程内复用，例如数据库连接或推理上下文。

典型例子：

* 后台日志写入器；
* socket 通信代理；
* 文件监控器；
* 串行数据库访问；
* 设备通信 Session；
* GUI 后台解析服务。

## 2. 使用 `QThreadPool` / `QRunnable`

适合：

* 大量短任务；
* 任务之间基本独立；
* 无须为每个任务创建线程；
* 希望限制总体并发度；
* 无须在固定线程上保存 QObject 状态。

Qt 文档指出，频繁创建和销毁线程成本较高，`QThreadPool` 通过复用线程执行 `QRunnable`；每个应用还具有一个全局线程池。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads-technologies.html)

```cpp
class ParseTask final : public QRunnable
{
public:
    explicit ParseTask(QByteArray data)
        : data_(std::move(data))
    {
        setAutoDelete(true);
    }

    void run() override
    {
        const auto result = parse(data_);

        // 不直接更新 GUI，而是投递到 GUI 对象。
        QMetaObject::invokeMethod(
            receiver_,
            [receiver = receiver_, result] {
                if (receiver)
                    receiver->acceptResult(result);
            },
            Qt::QueuedConnection);
    }

    QPointer<ResultReceiver> receiver_;

private:
    QByteArray data_;
};
```

这里使用 `QPointer` 是为了避免任务完成前 GUI 接收者已经销毁。

## 3. 使用 Qt Concurrent

适合：

* 独立函数异步执行；
* map/filter/reduce；
* CPU 数据并行；
* 希望通过 `QFuture` 获取结果；
* 需要进度、取消或结果监控。

Qt Concurrent 提供 `run()`、map、filter、reduce 和 `QFutureWatcher` 等高级接口，避免调用者直接操作 mutex、wait condition 等低层线程原语；并行算法会根据可用处理器资源分发工作。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qtconcurrent-index.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/threads-technologies.html)

```cpp
QFuture<ImageInfo> future =
    QtConcurrent::run([path] {
        return analyzeImage(path);
    });

auto *watcher = new QFutureWatcher<ImageInfo>(this);

connect(watcher, &QFutureWatcher<ImageInfo>::finished,
        this, [watcher, this] {
            const ImageInfo result = watcher->result();
            updateUi(result);
            watcher->deleteLater();
        });

watcher->setFuture(future);
```

注意：

```cpp
future.result();  // 可能阻塞
```

不要在 GUI 线程中立即调用阻塞式 `result()` 或 `waitForFinished()`。对 GUI 程序，应优先使用：

* `QFutureWatcher`
* `QFuture::then()`
* 完成信号

***

# 七、QPromise/QFuture：构建可取消、可报告进度的异步 API

Qt 6 的 `QPromise` 是结果生产端，`QFuture` 是消费端。`QPromise` 可以报告：

* 开始和完成；
* 一个或多个结果；
* 进度；
* 异常；
* 暂停或取消状态。

Qt 官方文档说明，`QPromise` 的函数是线程安全的，并可用于向 `QFuture` 异步传送结果和进度；promise 是 move-only，以避免生产端意外复制导致状态不清。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qpromise.html)

```cpp
QFuture<FileInfo> scanFiles(QStringList paths)
{
    return QtConcurrent::run(
        [paths = std::move(paths)]
        (QPromise<FileInfo> &promise) {
            promise.setProgressRange(0, paths.size());

            for (qsizetype i = 0; i < paths.size(); ++i) {
                if (promise.isCanceled())
                    return;

                promise.suspendIfRequested();

                FileInfo info = scanOneFile(paths[i]);
                promise.addResult(std::move(info));
                promise.setProgressValue(static_cast<int>(i + 1));
            }
        });
}
```

消费端：

```cpp
auto future = scanFiles(paths);

auto *watcher = new QFutureWatcher<FileInfo>(this);

connect(watcher, &QFutureWatcher<FileInfo>::progressValueChanged,
        progressBar, &QProgressBar::setValue);

connect(watcher, &QFutureWatcher<FileInfo>::resultReadyAt,
        this, int index {
            appendResult(watcher->resultAt(index));
        });

connect(cancelButton, &QPushButton::clicked,
        watcher, &QFutureWatcher<FileInfo>::cancel);

connect(watcher, &QFutureWatcher<FileInfo>::finished,
        watcher, &QObject::deleteLater);

watcher->setFuture(future);
```

Qt Concurrent 的 promise 模式支持多结果、进度报告、挂起和按调用方要求停止；基础模式则通常只通过返回值提供单一结果。 [\[codebrowser.dev\]](https://codebrowser.dev/qt6/qtbase/src/concurrent/qtconcurrentrun.cpp.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/qtconcurrent-index.html)

## 一个必须说明的语义

```cpp
future.cancel();
```

通常不是“立即杀死线程”。

它表示：

> 消费方请求取消；任务实现必须观察取消状态并协作退出。

如果任务正在执行一个不可中断的第三方函数，那么取消只能等该函数返回后生效。

***

# 八、线程池中的两个生产级陷阱

## 1. 线程池饥饿

假设全局线程池有 8 个线程：

* 8 个长时间阻塞任务占满线程；
* 后续短任务、缩略图任务、解析任务全部排队；
* UI 表面上没有死锁，但异步结果迟迟不返回。

解决方案：

* 长时间阻塞 I/O 使用独立 `QThread`；
* CPU 短任务使用线程池；
* 为不同业务建立独立 `QThreadPool`；
* 为线程池设置合理的 `maxThreadCount()`；
* 不要在池中任务里等待同一个池中的子任务。

```cpp
class ComputeService
{
public:
    ComputeService()
    {
        pool_.setMaxThreadCount(
            std::max(1, QThread::idealThreadCount() - 1));
    }

    QThreadPool *pool()
    {
        return &pool_;
    }

private:
    QThreadPool pool_;
};
```

## 2. 嵌套等待导致逻辑死锁

```cpp
// 在线程池任务 A 中：
auto child = QtConcurrent::run(&samePool, childTask);
child.waitForFinished();
```

如果池中所有线程都在执行类似的父任务并等待子任务，而子任务只能排队等待空闲线程，就形成线程池饥饿死锁。

改进方法：

* 让父任务直接执行小型子任务；
* 使用 continuation，而不是同步等待；
* 保留线程池容量；
* 父子任务使用不同执行器；
* 将工作组织成无阻塞 DAG。

***

# 九、共享状态：优先消息传递，其次才是锁

很多 Qt 项目最大的问题不是“锁用错了”，而是“不该共享的数据被共享了”。

## 更推荐的设计

```text
GUI Thread
    |
    | queued command
    v
Worker Thread owns mutable state
    |
    | immutable result/value
    v
GUI Thread
```

基本原则：

1. 可变状态由一个线程独占；
2. 跨线程传递值、不可变对象或所有权；
3. 使用 queued signal/slot 表达命令和事件；
4. 只有数据确实必须被多个线程同步访问时才加锁。

这实际上是 Actor/Active Object 思想在 Qt 中的自然表达。

***

## 必须共享时：锁的工程规则

### 使用 RAII

```cpp
QMutexLocker locker(&mutex_);
updateState();
```

不要手工写：

```cpp
mutex_.lock();
updateState();       // 异常、return 都可能漏掉 unlock
mutex_.unlock();
```

### 不要持锁发射外部信号

危险示例：

```cpp
void Model::update()
{
    QMutexLocker locker(&mutex_);
    updateInternalData();

    emit changed();  // 可能通过 DirectConnection 重入未知代码
}
```

更安全：

```cpp
void Model::update()
{
    {
        QMutexLocker locker(&mutex_);
        updateInternalData();
    }

    emit changed();
}
```

### 不要持锁调用未知代码

“未知代码”包括：

* signal；
* callback；
* 虚函数；
* 插件接口；
* 用户提供的 lambda；
* 可能进入事件循环的 API。

### 锁保护的是不变量，不是单个变量

低水平设计：

```cpp
QMutex mutexA;
QMutex mutexB;
```

高水平设计首先说明：

```text
mutex_ 保护：
- queue_
- stopping_
- activeCount_
- 三者之间的关系
```

资深面试官更关心你能否定义 **invariant**，而不是会不会调用 `lock()`。

***

# 十、GUI 线程的边界

在典型 Qt Widgets/Qt Quick 应用中，应把 GUI 对象限制在 GUI 线程。工作线程完成计算后，通过 queued signal 或 `invokeMethod()` 把结果传回 GUI 线程，而不是直接调用控件方法。KDAB 的并发材料特别指出，非主线程不能执行 QWidget、Qt Quick 或 `QPixmap` 等 GUI 操作；工作线程中可以使用部分非 GUI 图像处理设施，但仍需检查具体类的线程安全契约。 [\[kdab.com\]](https://www.kdab.com/documents/multithreading-with-qt.pdf)

错误：

```cpp
void Worker::run()
{
    ui_->progressBar->setValue(50);  // 跨线程访问 GUI
}
```

正确：

```cpp
emit progressChanged(50);
```

GUI 线程中连接：

```cpp
connect(worker, &Worker::progressChanged,
        progressBar, &QProgressBar::setValue);
```

## 高频更新还要考虑背压

如果工作线程每秒发射几十万次进度信号，GUI 线程的事件队列可能堆积。

不要这样：

```cpp
for (int i = 0; i < 1'000'000; ++i)
    emit progressChanged(i);
```

应该：

* 只在百分比变化时报告；
* 每 50～100 ms 聚合一次；
* 使用单槽位“latest value”覆盖旧进度；
* 对生产者进行限流；
* 对日志和数据流设置有界队列。

并发系统不仅要考虑“数据竞争”，还要考虑：

* 队列是否有界；
* 消费者跟不上怎么办；
* 旧结果是否还有价值；
* 是否允许丢弃或合并；
* 关闭时如何清空或取消。

***

# 十一、`BlockingQueuedConnection`：能不用就不用

```cpp
QMetaObject::invokeMethod(
    worker,
    "queryState",
    Qt::BlockingQueuedConnection);
```

它的行为类似：

1. 向目标线程投递调用；
2. 当前线程阻塞；
3. 等目标线程执行完成。

风险非常高：

* 同线程使用可能自锁；
* GUI 等 Worker，Worker 又等待 GUI，形成环形死锁；
* 目标线程事件循环被长任务占住；
* shutdown 阶段目标线程已经退出。

更好的方式：

* 异步请求 + 回调 signal；
* `QFuture`；
* continuation；
* 状态快照；
* 明确的异步接口。

只有在以下条件全部可证明时才考虑阻塞连接：

* 调用双方一定属于不同线程；
* 目标线程事件循环确定正在运行；
* 目标函数不会反向等待调用线程；
* 存在严格、可证明的锁层级；
* 调用延迟具有明确上界。

***

# 十二、为什么不应该使用 `QThread::terminate()`？

`terminate()` 可能在线程任意指令位置强制停止执行。

如果线程当时：

* 持有 mutex；
* 正在修改容器；
* 正在写文件；
* 正在数据库事务中；
* 正在执行对象析构；
* 正在更新引用计数；

强制终止可能造成：

* 永久锁死；
* 数据结构不变量破坏；
* 文件或数据库损坏；
* 资源泄漏；
* 难以复现的后续崩溃。

正确模型是 **协作式取消**：

```text
request stop
    ↓
wake blocking operation
    ↓
worker observes request
    ↓
restore invariant / release resources
    ↓
return
    ↓
join
```

Qt 的 API 同时提供了 `requestInterruption()` 和 `terminate()`，但工程代码应把前者作为标准停止协议的一部分；Qt 并发实践资料也强调事件驱动和可控退出，而不是用强制终止替代生命周期设计。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qthread.html), [\[kdab.com\]](https://www.kdab.com/documents/multithreading-with-qt.pdf)

***

# 十三、从 Qt 源码可以看出什么？

打开 `qthread.h` 可以看到，`QThread` 继承自 `QObject`，暴露了：

* `start()`
* `quit()`
* `wait()`
* `requestInterruption()`
* `isInterruptionRequested()`
* `started()`
* `finished()`
* `run()`
* `exec()`

也可以看到 `QThread::create()` 的实现思路：对 callable 和参数进行 decay/转移捕获，再通过内部实现包装成线程执行体。这体现了一个重要设计点：

> 传给异步执行器的 callable 及参数必须有清晰的所有权和生命周期，不能随意捕获即将失效的局部引用。

 [\[qthread.h...odebrowser\]](https://codebrowser.dev/qt5/qtbase/src/corelib/thread/qthread.h.html)

危险：

```cpp
void Controller::start()
{
    QString temporary = loadPath();

    thread_ = QThread::create([&temporary] {
        process(temporary);  // temporary 可能已经析构
    });

    thread_->start();
}
```

正确：

```cpp
void Controller::start()
{
    QString path = loadPath();

    thread_ = QThread::create(
        [path = std::move(path)] {
            process(path);
        });

    connect(thread_, &QThread::finished,
            thread_, &QObject::deleteLater);

    thread_->start();
}
```

同样，`QtConcurrent::run()` 通常会在调用点复制参数，调用之后原参数的变化不会自动反映到异步任务中。 [\[codebrowser.dev\]](https://codebrowser.dev/qt6/qtbase/src/concurrent/qtconcurrentrun.cpp.html)

***

# 十四、面试高频问题与专家级回答

## 1. `QObject::moveToThread()` 移动的是什么？

移动的是 QObject 的线程亲和性，不是当前调用栈，也不是把对象内存搬到另一个地址。

其 children 会随父对象一起具有相应的线程归属约束，因此有 parent 的 Worker 通常不能直接移动到另一个线程。

***

## 2. `moveToThread()` 后，普通成员函数一定在新线程运行吗？

不一定。

```cpp
worker->ordinaryMethod();
```

普通 C++ 调用仍由当前调用线程同步执行。

只有通过 queued signal/slot、queued `invokeMethod()`、timer/event 等事件派发机制，才能把执行安排到对象所属线程。

***

## 3. queued connection 是否等于线程安全？

不等于。

它只解决了“把调用投递到接收对象线程”的问题，并没有自动解决：

* 参数指向共享可变内存；
* 对象生命周期；
* 队列无界增长；
* 任务顺序和业务一致性；
* 取消语义；
* shutdown 竞态。

***

## 4. `quit()` 会停止正在运行的 slot 吗？

不会。

`quit()` 请求线程事件循环退出。若某个 slot 正在长时间运行，它通常要先返回，事件循环才有机会完成退出。

***

## 5. `requestInterruption()` 会自动终止线程吗？

不会。

它设置中断请求状态，任务必须主动调用 `isInterruptionRequested()` 并自行退出。

***

## 6. `QMutex` 和 `std::mutex` 如何选择？

二者都可以，关键是保持一致并理解等待、超时和条件变量配套关系。

可以这样回答：

* 与 Qt API、`QWaitCondition`、Qt 容器深度结合时使用 Qt 原语；
* 纯 C++ 核心库优先标准库，降低框架耦合；
* 不要在没有明确适配策略时混用 `QMutex` 与 `std::condition_variable`；
* 性能差异应通过目标平台 benchmark 评估，而不是凭印象判断。

***

## 7. 信号槽是否有 happens-before 保证？

可以谨慎回答：

> queued connection 会把参数和调用信息投递到目标线程，并通过 Qt 内部同步机制安全地传递事件。但这不意味着业务代码中其他未同步共享状态自动获得完整的顺序保证。若接收方还读取信号参数之外的共享变量，仍必须使用锁、原子操作或所有权转移建立明确同步关系。

***

## 8. 为什么线程数量不是越多越好？

因为线程会带来：

* 上下文切换；
* 栈内存；
* cache miss；
* 锁竞争；
* 内存带宽竞争；
* 调度抖动；
* NUMA 访问成本。

CPU-bound 任务的并发度通常与可用核心数相关；I/O-bound 任务可能允许更高并发，但应结合连接数、句柄数和下游容量进行限制。

***

# 十五、生产环境检查清单

## 线程模型

* [ ] 每个 QObject 的线程亲和性是否明确？
* [ ] 是否真的需要专用线程？
* [ ] 长任务是否阻塞线程事件循环？
* [ ] GUI 操作是否严格回到 GUI 线程？
* [ ] 是否误把 `QThread` 对象当成实际执行线程？

## 生命周期

* [ ] 谁拥有 Worker？
* [ ] 谁拥有 QThread？
* [ ] shutdown 是否包含取消、唤醒、退出、等待？
* [ ] 是否可能在线程运行时销毁 QThread？
* [ ] queued callback 捕获的对象是否可能提前析构？
* [ ] 是否使用 `QPointer` 或其他寿命保护？

## 取消

* [ ] 取消是否为协作式？
* [ ] 检查取消的粒度是否足够小？
* [ ] 阻塞 I/O 能否被唤醒？
* [ ] 取消后是否仍会发布过期结果？
* [ ] 是否区分 canceled、failed 和 completed？

## 性能与背压

* [ ] 是否存在无界任务队列？
* [ ] 高频信号是否会淹没 GUI 事件队列？
* [ ] 是否把阻塞长任务放入全局线程池？
* [ ] 是否在线程池任务中同步等待同池子任务？
* [ ] 是否测量过吞吐、尾延迟和关闭耗时？

## 同步

* [ ] 锁所保护的不变量是否明确？
* [ ] 是否持锁发信号、调用 callback 或虚函数？
* [ ] 是否存在固定锁顺序？
* [ ] 能否通过线程封闭或不可变消息消除锁？
* [ ] 原子变量的内存序是否真的理解？

***

# 结语

高质量的 Qt 并发设计，通常不是线程和锁最多的设计，而是具备以下特征：

1. **线程边界清晰**：知道每个 QObject 属于哪个线程；
2. **状态尽量线程封闭**：通过消息传递而不是到处共享；
3. **任务可取消**：使用协作式停止，而不是 `terminate()`；
4. **生命周期确定**：明确 start、stop、quit、wait 和 delete 顺序；
5. **事件循环不被饿死**：长任务分片，或改成无事件循环计算线程；
6. **有背压策略**：生产者不能无限压垮消费者；
7. **选择正确抽象层次**：
   * 有状态长期服务：Worker + `QThread`
   * 短小独立任务：`QThreadPool`
   * 数据并行：Qt Concurrent
   * 结果、进度和取消：`QFuture` / `QPromise`

如果在面试中能围绕 **线程亲和性、事件循环、消息投递、协作式取消、结构化生命周期、线程池饥饿和背压** 展开，而不是只背诵 `moveToThread()` 的模板代码，基本就已经进入资深 Qt 工程师的讨论层次。
