# Qt QObject Thread Affinity（线程亲和性）源码笔记

> 主题：结合 Qt5 源码理解 `QObject` 的线程亲和性、`moveToThread()` 规则、Parent/Child 限制、GUI 线程约束，以及跨线程信号槽与事件分发。
>
> 主要源码参考：
>
> - `qtbase/src/corelib/kernel/qobject.cpp`
> - `qtbase/src/corelib/kernel/qobject_p.h`
> - `qtbase/src/corelib/kernel/qcoreapplication.cpp`
> - [Qt 5 源码浏览（codebrowser.dev）](https://codebrowser.dev/qt5/)

---

## 目录

- [1. Thread Affinity 是什么](#1-thread-affinity-是什么)
- [2. moveToThread() 与 Parent/Child 限制](#2-movetothread-与-parentchild-限制)
- [3. QWidget 为什么不能 moveToThread](#3-qwidget-为什么不能-movetothread)
- [4. 推荐的多线程架构](#4-推荐的多线程架构)
- [5. 源码深入：QThreadData 与底层拦截](#5-源码深入qthreaddata-与底层拦截)
- [6. 规则速查表](#6-规则速查表)

---

# 1. Thread Affinity 是什么

**Thread Affinity（线程亲和性）** 指每个 `QObject` 实例都绑定并生活在某一个特定线程中，可通过 `QObject::thread()` 获取。

## 1.1 默认归属

默认情况下，`QObject` 属于**创建它时所在的那个线程**。

## 1.2 核心作用

Thread Affinity 决定了两件关键事情：

1. **事件处理**：该对象接收到的所有事件（如 `QTimer` 定时器事件、网络数据到达事件）都由其亲和线程的事件循环（Event Loop）负责分发和处理。
2. **信号槽执行**：当使用 `Qt::AutoConnection`（默认连接方式）时，如果信号发送者与接收者的 Thread Affinity 不同，Qt 会自动采用 `Qt::QueuedConnection`，槽函数一定在接收者对象所属的线程中执行。

---

# 2. moveToThread() 与 Parent/Child 限制

利用 `QObject::moveToThread()` 可以手动改变对象的线程亲和性，但 Qt 对 Parent/Child（父子对象）有严格限制。

## 2.1 限制一：有 parent 的对象不能 moveToThread()

如果一个 `QObject` 已经设置了 parent，直接对其调用 `moveToThread()` 会失败：

```text
QObject::moveToThread: Cannot move objects with a parent
```

**正确做法**：先调用 `setParent(nullptr)` 剥离父子关系，再调用 `moveToThread()`。

## 2.2 限制二：子对象必须与父对象在同一线程

Qt 强制要求一个对象树（Parent-Child 树）中的所有 `QObject` 必须拥有**完全相同**的 Thread Affinity。

- **自动随动**：对一个没有 parent 但有子对象的 `QObject` 调用 `moveToThread()` 时，该对象会连同所有子对象（及其后代）一起移动到目标线程。
- **禁止跨线程设 parent**：若尝试将属于 A 线程的 `QObject` 的 parent 设置为属于 B 线程的 `QObject`，Qt 会在运行时阻止并报错：

```text
QObject::setParent: Cannot set parent, new parent is in a different thread
```

## 2.3 限制三：不能在非对象所属线程中创建子对象

若 parent 对象已被移动到子线程，不能在主线程中通过 `new QObject(parent)` 为它创建子对象。这违反了「子对象必须在其 parent 关联的线程内创建」的 Qt 底层安全机制。

## 2.4 限制四：moveToThread 只能在对象当前线程调用

`moveToThread()` 必须由对象**当前所在线程**发起。若在别的线程调用，Qt 会打印警告并直接返回（源码见第 5.2 节）。

---

# 3. QWidget 为什么不能 moveToThread

`QWidget`（以及所有 GUI 控件）不能使用 `moveToThread`，根本原因是：**操作系统和 Qt 架构都限制了 GUI 操作必须在主线程（GUI 线程）中执行**。

## 3.1 操作系统底层的窗口管理限制

无论是 Windows (Win32)、macOS (Cocoa) 还是 Linux (X11/Wayland)，绝大多数操作系统的底层图形子系统都采用单线程 GUI 架构：

- 窗口句柄、消息循环、鼠标键盘事件分发，都绑定在进程启动的第一个线程（主线程）。
- 在子线程中操作窗口（哪怕只是修改尺寸或重绘），可能导致底层 API 崩溃或未定义行为。

## 3.2 Qt 源码层面的强制拦截

在 Qt 源码中，`QWidget` 拦截了与线程亲和性相关的逻辑：

- **主动报错**：强行对 `QWidget` 调用 `moveToThread()` 时，控制台会打印：

```text
QWidget::moveToThread: Widgets cannot be moved to a new thread
```

- **断言拦截**：`QWidget` 的构建和事件处理代码会校验当前线程是否为主线程；检测到非主线程操作时会触发 `Q_ASSERT` 断言失败。

## 3.3 图形渲染与重绘的冲突

`QWidget` 的核心职责是渲染（Painting）：

- Qt 的界面重绘由全局制图引擎 / 渲染管道统一调度。
- 界面刷新时，主线程事件循环触发 `QPaintEvent`；若 `QWidget` 生活在子线程，子线程的重绘请求会与主线程的图形上下文产生死锁或内存冲突。

---

# 4. 推荐的多线程架构

若有耗时任务（大文件下载、图像处理、AI 推理等），**不要移动 UI 控件**，应采用以下经典架构：

| 角色 | 做法 |
|---|---|
| **Worker（后台逻辑）** | 继承 `QObject`，将 Worker `moveToThread()` 到子线程 |
| **Widget（UI）** | 留在主线程负责展示 |
| **数据通信** | 通过 Signals & Slots 跨线程通信；`Qt::AutoConnection` 会自动使用 `QueuedConnection` |

---

# 5. 源码深入：QThreadData 与底层拦截

结合 [Qt 5 官方源码（qtbase/src/corelib/kernel/）](https://codebrowser.dev/qt5/)，`QObject` 的 Thread Affinity 通过数据结构和硬性检查在源码层面保证多线程架构稳定。

## 5.1 Thread Affinity 的底层本质：QThreadData

`QObject` 并不是直接绑定 `QThread*`，而是存储 `QThreadData*`：

```cpp
// 摘自 qtbase/src/corelib/kernel/qobject_p.h
class Q_CORE_EXPORT QObjectPrivate : public QObjectData
{
public:
    // ...
    QThreadData *threadData; // 核心：指向线程数据块的指针
};
```

**为什么这么设计？** 当 `QObject` 被创建时，当前线程可能还没有对应的 `QThread` 对象（例如主线程刚启动时，或原生 `std::thread`）。`QThreadData` 是针对特定线程的底层事件循环、事件队列的数据集合，才是线程亲和性的「生命基石」。

`QObject::thread()` 的底层实现：

```cpp
// 摘自 qtbase/src/corelib/kernel/qobject.cpp
QThread *QObject::thread() const
{
    return d_func()->threadData->thread.loadAcquire();
}
```

## 5.2 moveToThread() 的源码级硬性限制

`qobject.cpp` 中 `QObject::moveToThread(QThread *targetThread)` 的核心逻辑：

```cpp
void QObject::moveToThread(QThread *targetThread)
{
    Q_D(QObject);
    // 限制 1：如果已经是该线程，直接返回
    if (d->threadData.loadRelaxed()->thread.loadAcquire() == targetThread)
        return;

    // 限制 2：有 parent 的对象不能移动
    if (d->parent != nullptr) {
        qWarning("QObject::moveToThread: Cannot move objects with a parent");
        return;
    }

    // 限制 3：只能在对象当前线程调用 moveToThread
    if (d->threadData.loadRelaxed()->thread.loadAcquire() != QThread::currentThread()) {
        qWarning("QObject::moveToThread: Current thread (%p) is not the object's thread (%p).",
                 QThread::currentThread(), d->threadData.loadRelaxed()->thread.loadAcquire());
        return;
    }

    // ... 后续开始递归移动子对象 ...
}
```

### 5.2.1 子对象如何「打包一起移动」

`moveToThread` 内部调用私有辅助函数 `d->setThreadData_r(currentData, targetData)`，`_r` 代表 Recursive（递归）：

```cpp
void QObjectPrivate::setThreadData_r(QThreadData *currentData, QThreadData *targetData)
{
    // 1. 修改当前对象的 threadData
    threadData = targetData;

    // 2. 递归遍历所有子对象，强制同步它们的 threadData
    for (int i = 0; i < children.size(); ++i) {
        QObject *child = children.at(i);
        child->d_func()->setThreadData_r(currentData, targetData);
    }
}
```

**源码结论**：Qt 通过树状递归，确保「父子对象必须在同一个线程」。

## 5.3 跨线程修改父子关系的底层拦截

`QObject::setParent()` 在跨线程时会比对两者的 `threadData`：

```cpp
void QObject::setParent(QObject *parent)
{
    Q_D(QObject);
    if (parent == d->parent)
        return;

    if (parent) {
        // 核心防御线：比对两者的线程数据块是否一致
        if (d->threadData != parent->d_func()->threadData) {
            qWarning("QObject::setParent: Cannot set parent, new parent is in a different thread");
            return; // 拦截，不执行挂载
        }
        // ...
    }
    // ...
}
```

若 `d->threadData != parent->d_func()->threadData`，挂载逻辑直接被 `return` 截断。

## 5.4 事件分发阶段的线程安全校验

当别的线程通过 `QCoreApplication::postEvent` 投递事件时，Qt 在 `notifyInternal2` 阶段进行校验：

```cpp
// 摘自 qtbase/src/corelib/kernel/qcoreapplication.cpp
if (receiver->d_func()->threadData->thread.loadAcquire() != currentThread) {
    qWarning("Cannot send events to objects owned by a different thread. "
             "Current thread %p. Receiver '%s' was created in thread %p",
             currentThread, receiver->objectName().toLocal8Bit().data(),
             receiver->d_func()->threadData->thread.loadAcquire());
    return false;
}
```

**源码结论**：事件循环分发事件时，若当前线程与 `receiver->threadData` 不一致，Qt 会丢弃该事件并报警。这也解释了为什么 Thread Affinity 决定了哪个线程的事件循环来处理该对象的事件。

---

# 6. 规则速查表

| 维度 | 规则与限制 |
|---|---|
| 默认归属 | `QObject` 属于创建它时所在的线程 |
| 移前检查 | 调用 `moveToThread()` 的对象其 `parent` 必须为 `nullptr` |
| 调用线程 | `moveToThread()` 必须在对象当前所在线程发起 |
| 树状跟随 | 移动一个无 parent 的父节点，其所有子节点会一起移动到目标线程 |
| 同生共死 | 整个父子对象树上的所有节点，在任何时候都必须处于同一个线程 |
| GUI 例外 | `QWidget` 及其子类不能 `moveToThread()`，必须留在主线程 |
| 跨线程通信 | 使用信号槽（`Qt::AutoConnection` → `QueuedConnection`），不要直接跨线程操作对象 |

---

## 延伸阅读

- 跨线程信号槽底层如何通过 `QMetaCallEvent` 将参数打包并投递到目标线程事件队列（见 `01_Qt_QObject_SignalSlot.md`）
- 跨线程安全销毁对象：`deleteLater()` 机制（见 `01_Qt_QObject_SignalSlot.md` 第 9、10 节）

## 参考资料

- [qobject.cpp（codebrowser.dev）](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qobject.cpp.html)
- [qcoreapplication.cpp（codebrowser.dev）](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html)
- [Threads and QObjects（Qt 官方文档）](https://doc.qt.io/qt-6/threads-qobject.html)
- [QObject（PySide6 文档）](https://doc.qt.io/qtforpython-6/PySide6/QtCore/QObject.html)
