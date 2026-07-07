# Qt QObject / Meta-Object / Signal-Slot 机制源码笔记

> 主题：结合 Qt5 源码理解 `QObject`、`Q_OBJECT`、`moc`、signal/slot、parent-child 内存管理、`deleteLater()` 与跨线程对象销毁。
>
> 主要源码参考：
>
> - `qtbase/src/corelib/kernel/qobject.cpp`
> - `qtbase/src/corelib/kernel/qobject.h`
> - `qtbase/src/corelib/kernel/qobject_p.h`
> - `qtbase/src/corelib/kernel/qmetaobject.cpp`
> - Qt Meta-Object System / moc / signal-slot 文档

---

## 目录

- [1. Qt 的 signal/slot 机制](#1-qt-的-signalslot-机制)
- [2. QObject 在 Qt 中解决了什么问题](#2-qobject-在-qt-中解决了什么问题)
- [3. Q_OBJECT 宏有什么作用](#3-q_object-宏有什么作用)
- [4. Qt 为什么需要 moc](#4-qt-为什么需要-moc)
- [5. signal/slot 为什么依赖元对象系统](#5-signalslot-为什么依赖元对象系统)
- [6. qobject_cast 与 dynamic_cast 的区别](#6-qobject_cast-与-dynamic_cast-的区别)
- [7. QObject parent-child 内存管理机制](#7-qobject-parent-child-内存管理机制)
- [8. QObject 析构注释解释](#8-qobject-析构注释解释)
- [9. 如何安全使用 deleteLater](#9-如何安全使用-deletelater)
- [10. 跨线程删除 QObject 示例](#10-跨线程删除-qobject-示例)
- [11. 常见实践规则总结](#11-常见实践规则总结)

---

# 1. Qt 的 signal/slot 机制

## 1.1 signal/slot 的本质

Qt 的 signal/slot 不是 C++ 原生语法，而是基于：

```text
QObject + Q_OBJECT + moc + QMetaObject + QObjectPrivate::Connection
```

共同实现的一套运行时对象通信机制。

用户代码中常见写法：

```cpp
class Sender : public QObject
{
    Q_OBJECT

signals:
    void valueChanged(int value);
};

class Receiver : public QObject
{
    Q_OBJECT

public slots:
    void onValueChanged(int value);
};
```

连接：

```cpp
QObject::connect(sender, &Sender::valueChanged,
                 receiver, &Receiver::onValueChanged);
```

触发：

```cpp
emit sender->valueChanged(10);
```

从 C++ 层面看，`emit` 通常只是一个空宏，用来增强语义可读性。真正起作用的是 moc 为 signal 生成的函数体。

---

## 1.2 moc 生成的 signal 函数

假设有：

```cpp
signals:
    void valueChanged(int value);
```

moc 生成的 signal 函数概念上类似：

```cpp
void Sender::valueChanged(int value)
{
    void *args[] = {
        nullptr,
        &value
    };

    QMetaObject::activate(this, &staticMetaObject, signal_index, args);
}
```

所以：

```cpp
emit valueChanged(10);
```

大致等价于：

```cpp
valueChanged(10);
```

然后进入 moc 生成的函数体，再进入：

```cpp
QMetaObject::activate(...);
```

---

## 1.3 connect() 做了什么

`QObject::connect()` 的核心工作是建立连接关系。

它会记录：

```text
sender
signal index
receiver
slot / method index
connection type
argument types
receiver thread data
```

可以简化理解为：

```cpp
sender->connections[signalIndex].append({
    receiver,
    methodIndex,
    connectionType,
    argumentTypes
});
```

在 Qt5 `qobject.cpp` 中，连接对象会被加入 sender 对应 signal 的 connection list，同时也会挂到 receiver 的 senders list 中，这样析构时可以双向清理。

---

## 1.4 emit 后的调用链

完整流程：

```text
用户代码 emit
    ↓
moc 生成的 signal 函数
    ↓
QMetaObject::activate(sender, signalIndex, argv)
    ↓
QObjectPrivate::doActivate(...)
    ↓
遍历 sender 对应该 signal 的 connection list
    ↓
根据 connection type 决定：
    - DirectConnection：立即调用 slot
    - QueuedConnection：投递 QMetaCallEvent
    - BlockingQueuedConnection：投递事件并等待
```

---

## 1.5 DirectConnection

DirectConnection 是同步调用：

```cpp
connect(sender, &Sender::valueChanged,
        receiver, &Receiver::onValueChanged,
        Qt::DirectConnection);
```

特点：

```text
signal 发出时立即调用 slot
slot 执行完后 emit 后面的代码才继续执行
slot 运行在 emit 所在线程
跨线程 DirectConnection 需要非常小心线程安全
```

调用链类似：

```text
Sender::valueChanged()
    -> QMetaObject::activate()
        -> Receiver::onValueChanged()
```

---

## 1.6 QueuedConnection

QueuedConnection 是异步事件投递：

```cpp
connect(worker, &Worker::progressChanged,
        window, &MainWindow::onProgressChanged,
        Qt::QueuedConnection);
```

流程：

```text
sender 所在线程：
    emit signal
        ↓
    QMetaObject::activate()
        ↓
    创建 QMetaCallEvent
        ↓
    QCoreApplication::postEvent(receiver, event)

receiver 所在线程：
    event loop 处理 QMetaCallEvent
        ↓
    调用 slot
```

QueuedConnection 的关键是：

> slot 会在 receiver 所属线程的 event loop 中执行。

这也是 Qt 中跨线程通信常用 signal/slot 的原因。

---

## 1.7 AutoConnection

默认连接类型是：

```cpp
Qt::AutoConnection
```

它在 signal 发出时判断：

```cpp
if (senderThread == receiverThread)
    use DirectConnection;
else
    use QueuedConnection;
```

注意：判断的是 signal 发出时的线程上下文和 receiver 的 thread affinity，不是单纯 connect 发生在哪个线程。

---

## 1.8 QueuedConnection 参数传递

QueuedConnection 需要把参数从 signal 发出线程传到 receiver 线程。

因为 signal 参数通常位于当前栈帧：

```cpp
emit progressChanged(50);
```

如果不拷贝，signal 返回后参数地址就失效。因此 Qt 需要：

```text
1. 获取参数类型
2. 通过 QMetaType 创建参数拷贝
3. 把参数放入 QMetaCallEvent
4. 投递到 receiver 线程
5. slot 执行后析构参数
```

这也是为什么 queued connection 传自定义类型时通常要注册：

```cpp
qRegisterMetaType<MyType>("MyType");
```

否则可能出现：

```text
QObject::connect: Cannot queue arguments of type 'MyType'
Make sure 'MyType' is registered using qRegisterMetaType().
```

---

# 2. QObject 在 Qt 中解决了什么问题

`QObject` 是 Qt Object Model 的核心基类。它让普通 C++ 对象具备 Qt 框架需要的运行时能力。

一句话：

> `QObject` 给 C++ 对象增加了身份、元信息、通信、生命周期、事件、线程归属和动态属性能力。

---

## 2.1 对象通信：signal/slot

`QObject` 提供：

```cpp
connect(sender, signal, receiver, slot);
disconnect(...);
blockSignals(true);
```

解决对象之间解耦通信问题。

特点：

```text
sender 不需要知道 receiver
一个 signal 可连接多个 slot
一个 slot 可接收多个 signal
对象销毁时连接自动断开
支持跨线程 queued connection
```

---

## 2.2 运行时元信息

通过 `metaObject()` 可以获取：

```text
class name
super class
signals
slots
properties
enums
class info
```

例如：

```cpp
qDebug() << obj->metaObject()->className();
```

这些信息支撑：

```text
qobject_cast
inherits
property / setProperty
invokeMethod
connectSlotsByName
QML / Designer
```

---

## 2.3 parent-child 生命周期管理

```cpp
QObject *parent = new QObject;
QObject *child = new QObject(parent);

delete parent;  // child 自动删除
```

parent-child 机制解决 GUI/对象树中大量对象的自动释放问题。

---

## 2.4 事件系统

`QObject` 提供事件入口：

```cpp
virtual bool event(QEvent *event);
virtual bool eventFilter(QObject *watched, QEvent *event);
virtual void timerEvent(QTimerEvent *event);
virtual void childEvent(QChildEvent *event);
virtual void customEvent(QEvent *event);
```

支撑：

```text
鼠标键盘事件
timer event
child event
custom event
DeferredDelete event
MetaCall event
事件过滤器
```

---

## 2.5 thread affinity

每个 QObject 都有线程归属：

```cpp
obj->thread();
obj->moveToThread(thread);
```

规则：

```text
queued signal/post event 会在对象所属线程执行
parent 和 child 必须在同一线程
有 parent 的对象不能 moveToThread
moveToThread 会连同 children 一起移动
```

---

## 2.6 动态属性系统

```cpp
obj->setProperty("name", "Danny");
QVariant v = obj->property("name");
```

支持：

```text
Q_PROPERTY
动态属性
Qt Designer
QML binding
样式系统
```

---

## 2.7 禁止拷贝

`QObject` 不能拷贝：

```text
QObject 有 parent-child 关系
有 signal/slot 连接
有 thread affinity
有 pending events
有 objectName / property / timer
```

如果允许拷贝，语义会混乱。因此 QObject 是 identity object，不是 value object。

---

# 3. Q_OBJECT 宏有什么作用

`Q_OBJECT` 的核心作用是：

> 告诉 moc 为这个 QObject 子类生成元对象代码，使它接入 Qt Meta-Object System。

---

## 3.1 它让类拥有自己的 QMetaObject

```cpp
class MyObject : public QObject
{
    Q_OBJECT
};
```

moc 会生成该类的：

```text
staticMetaObject
metaObject()
qt_metacast()
qt_metacall()
qt_static_metacall()
字符串表
方法表
属性表
signal 函数体
```

---

## 3.2 它使自定义 signal/slot 可用

没有 `Q_OBJECT`：

```cpp
class MyObject : public QObject
{
signals:
    void changed();
};
```

通常是错误的，因为 moc 不会为 `changed()` 生成元对象数据和 signal 激活代码。

---

## 3.3 它支持 Q_PROPERTY

```cpp
class Person : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)

signals:
    void nameChanged();
};
```

`Q_PROPERTY` 信息会进入 meta-object，之后可以：

```cpp
obj->property("name");
obj->setProperty("name", "Danny");
```

---

## 3.4 它支持 qobject_cast

```cpp
QObject *obj = new MyObject;
MyObject *p = qobject_cast<MyObject *>(obj);
```

目标类型通常需要 `Q_OBJECT`，否则结果不可靠。

---

## 3.5 常见链接错误

如果加了 `Q_OBJECT`，但 moc 生成文件没有参与编译链接，常见错误：

```text
undefined reference to vtable for MyObject
```

原因是 `Q_OBJECT` 声明了元对象相关函数，但实现由 moc 生成。

CMake 中通常需要：

```cmake
set(CMAKE_AUTOMOC ON)
```

---

# 4. Qt 为什么需要 moc

Qt 需要 moc 的根本原因是：

> 标准 C++ 缺少 Qt 所需的完整运行时反射和对象元信息能力。

---

## 4.1 C++ 不认识 Qt 扩展

C++ 编译器不原生理解：

```cpp
signals:
slots:
Q_OBJECT
Q_PROPERTY
Q_INVOKABLE
```

moc 负责扫描这些 Qt 扩展，生成普通 C++ 代码。

---

## 4.2 moc 生成 runtime metadata

moc 生成的数据包括：

```text
类名
父类
signal 列表
slot 列表
method 参数类型
property 列表
enum 列表
class info
```

这些数据用于：

```text
signal/slot
qobject_cast
property system
invokeMethod
QML
Designer
```

---

## 4.3 moc 生成 signal 函数体

用户只声明 signal：

```cpp
signals:
    void finished(int code);
```

不实现它。实现由 moc 生成，概念上类似：

```cpp
void Worker::finished(int code)
{
    void *args[] = { nullptr, &code };
    QMetaObject::activate(this, &staticMetaObject, signal_index, args);
}
```

---

## 4.4 为什么模板不能完全替代 moc

Qt5 新 connect 语法确实利用了模板做编译期检查：

```cpp
connect(sender, &Sender::finished,
        receiver, &Receiver::onFinished);
```

但模板不能提供完整运行时反射，例如：

```text
按字符串查找属性
按字符串调用方法
QML 绑定
Designer 属性编辑
connectSlotsByName
跨动态库 qobject_cast
动态属性系统
```

因此 moc 仍然必要。

---

# 5. signal/slot 为什么依赖元对象系统

核心原因：

> Qt 的 signal/slot 不是简单函数指针回调，而是运行时可查询、可动态连接、可跨线程投递、可自动清理的对象通信系统。

---

## 5.1 connect 阶段需要查找 signal/slot

旧语法：

```cpp
connect(sender, SIGNAL(valueChanged(int)),
        receiver, SLOT(updateValue(int)));
```

Qt 需要在运行时判断：

```text
sender 是否有 valueChanged(int)
receiver 是否有 updateValue(int)
参数是否兼容
```

这些信息来自 `QMetaObject`。

---

## 5.2 emit 阶段需要 signal index

signal 发出后会进入：

```cpp
QMetaObject::activate(sender, signalIndex, argv);
```

`signalIndex` 来自元对象系统。Qt 通过该 index 找到对应 connection list。

---

## 5.3 queued connection 需要参数类型信息

跨线程时，Qt 必须拷贝参数到事件中。

需要知道：

```text
参数个数
参数类型
如何构造
如何析构
```

这些依赖 `QMetaObject` 和 `QMetaType`。

---

## 5.4 析构自动断开连接需要连接元数据

QObject 析构时会清理：

```text
以自己为 sender 的连接
以自己为 receiver 的连接
```

这要求 Qt 内部保存 sender、receiver、signal index、method index 等连接元数据。

---

# 6. qobject_cast 与 dynamic_cast 的区别

一句话：

> `dynamic_cast` 依赖 C++ RTTI；`qobject_cast` 依赖 Qt Meta-Object System。

---

## 6.1 dynamic_cast

```cpp
Base *base = new Derived;
Derived *d = dynamic_cast<Derived *>(base);
```

要求：

```text
Base 是多态类
编译器开启 RTTI
适用于普通 C++ 类
```

---

## 6.2 qobject_cast

```cpp
QObject *obj = new QPushButton;
QPushButton *button = qobject_cast<QPushButton *>(obj);
```

要求：

```text
对象继承 QObject
目标类型通常有 Q_OBJECT
不依赖 C++ RTTI
可跨动态库边界工作
```

---

## 6.3 对比

| 项目 | dynamic_cast | qobject_cast |
|---|---|---|
| 依赖机制 | C++ RTTI | Qt Meta-Object System |
| 是否需要 QObject | 否 | 是 |
| 是否需要 Q_OBJECT | 否 | 目标类型通常需要 |
| RTTI 关闭后 | 不可用 | 仍可用 |
| 适用场景 | 普通 C++ 多态类 | QObject 派生类 |
| 失败行为 | 指针返回 nullptr | 指针返回 nullptr |

---

# 7. QObject parent-child 内存管理机制

## 7.1 核心思想

```cpp
QObject *parent = new QObject;
QObject *child = new QObject(parent);

delete parent;  // child 自动删除
```

QObject parent-child 是树形 ownership：

```text
一个 child 同时最多有一个 parent
parent 析构时 delete children
child 析构时从 parent children list 中移除
```

---

## 7.2 内部数据结构

每个 QObject 内部保存：

```cpp
QObject *parent;
QObjectList children;
```

概念上：

```text
child->d_ptr->parent = parent
parent->d_ptr->children.append(child)
```

---

## 7.3 构造时设置 parent

```cpp
QObject::QObject(QObject *parent)
```

内部会：

```text
初始化 QObjectPrivate
设置 threadData
检查 parent 是否同线程
调用 setParent(parent)
```

parent 和 child 必须在同一线程，否则不能建立 parent-child 关系。

---

## 7.4 setParent() 流程

```cpp
child->setParent(parent);
```

核心流程：

```text
1. 如果已有旧 parent，从旧 parent->children 移除
2. 发送 ChildRemoved 事件
3. 设置 parent = newParent
4. 检查线程是否一致
5. 加入 newParent->children
6. 发送 ChildAdded 事件
```

伪代码：

```cpp
void QObjectPrivate::setParent_helper(QObject *newParent)
{
    if (newParent == parent)
        return;

    if (parent) {
        parent->children.removeOne(q);
        sendChildRemovedEvent();
    }

    parent = newParent;

    if (parent) {
        if (threadData != parent->threadData) {
            parent = nullptr;
            return;
        }

        parent->children.append(q);
        sendChildAddedEvent();
    }
}
```

---

## 7.5 parent 析构时删除 children

`QObject::~QObject()` 中有核心逻辑：

```cpp
if (!d->children.isEmpty())
    d->deleteChildren();
```

`deleteChildren()` 大致如下：

```cpp
void QObjectPrivate::deleteChildren()
{
    isDeletingChildren = true;

    for (int i = 0; i < children.count(); ++i) {
        currentChildBeingDeleted = children.at(i);
        children[i] = nullptr;
        delete currentChildBeingDeleted;
    }

    children.clear();
    currentChildBeingDeleted = nullptr;
    isDeletingChildren = false;
}
```

为什么不能简单 `qDeleteAll(children)`？

因为 child 析构过程中可能删除 sibling，或者修改 parent 的 children list，Qt 需要处理重入和递归删除。

---

## 7.6 child 单独析构时从 parent 摘除

```cpp
QObject *parent = new QObject;
QObject *child = new QObject(parent);

delete child;
delete parent;  // 不会 double delete child
```

因为 child 析构时会：

```cpp
if (d->parent)
    d->setParent_helper(nullptr);
```

从 parent 的 children list 中移除自己。

---

## 7.7 栈对象设置 parent 的坑

危险代码：

```cpp
QObject child;
QObject parent;

child.setParent(&parent);
```

析构顺序：

```text
parent 先析构
    -> delete child
child 后析构
    -> 栈对象再次析构
```

结果：未定义行为，常见 crash。

安全情况：

```cpp
QObject parent;
QObject child(&parent);
```

这里 child 后构造、先析构，会先从 parent 中摘除。

---

## 7.8 不要和 shared_ptr ownership 混用

危险：

```cpp
QObject *parent = new QObject;
std::shared_ptr<QObject> child(new QObject(parent));
```

问题：

```text
parent 会 delete child
shared_ptr 也会 delete child
```

可能 double delete。

---

# 8. QObject 析构注释解释

源码注释核心内容：

```cpp
/*!
    Destroys the object, deleting all its child objects.
    All signals to and from the object are automatically disconnected, and
    any pending posted events for the object are removed from the event
    queue. However, it is often safer to use deleteLater() rather than
    deleting a QObject subclass directly.
    ...
*/
```

逐句解释如下。

---

## 8.1 Destroys the object, deleting all its child objects

销毁当前 QObject 时，会删除所有 children。

```cpp
QObject *parent = new QObject;
QObject *child = new QObject(parent);

delete parent;  // child 自动删除
```

---

## 8.2 All signals to and from the object are automatically disconnected

当前对象相关的所有 signal/slot 连接都会断开。

包括：

```text
对象作为 sender 的连接
对象作为 receiver 的连接
```

因此 receiver 删除后，sender 再 emit 也不会调用悬空 slot。

---

## 8.3 pending posted events are removed

如果事件队列中还有发给该对象的事件，析构时会移除。

例如：

```cpp
QCoreApplication::postEvent(obj, new QEvent(QEvent::User));
delete obj;
```

Qt 会尝试移除该对象对应的 pending events，避免事件投递到已销毁对象。

---

## 8.4 safer to use deleteLater()

很多情况下，直接 `delete` 不如 `deleteLater()` 安全。

危险：

```cpp
void MyObject::slot()
{
    delete this;
}
```

更安全：

```cpp
void MyObject::slot()
{
    deleteLater();
}
```

因为当前对象可能还在 signal/slot 或 event handler 调用栈中。

---

## 8.5 child objects on stack or global will crash

如果 child 是栈对象或全局对象，但被 parent 管理，parent 析构时会尝试 `delete child`，这很危险。

危险：

```cpp
QObject child;
QObject parent;
child.setParent(&parent);
```

---

## 8.6 不建议外部长期保存 child 裸指针

如果 parent 删除 child，外部裸指针会悬空。

推荐：

```cpp
QPointer<QObject> ptr = child;
```

或者监听：

```cpp
connect(child, &QObject::destroyed, [] {
    qDebug() << "child destroyed";
});
```

---

## 8.7 跨线程不要直接 delete

如果 QObject 属于另一个线程，不能在当前线程直接 delete。

应使用：

```cpp
obj->deleteLater();
```

让对象所属线程的 event loop 删除它。

---

# 9. 如何安全使用 deleteLater

## 9.1 deleteLater 的本质

`deleteLater()` 本质是投递 deferred delete event：

```cpp
void QObject::deleteLater()
{
    QCoreApplication::postEvent(this, new QDeferredDeleteEvent());
}
```

它不是立即删除，而是等 event loop 回到合适时机再删除。

---

## 9.2 适合使用 deleteLater 的场景

```text
1. 在 slot 中删除自己
2. 在 event handler 中删除自己
3. 跨线程删除 QObject
4. 对象可能还有 pending events
5. queued signal 可能尚未处理
```

示例：

```cpp
connect(worker, &Worker::finished,
        worker, &QObject::deleteLater);
```

---

## 9.3 调用后不要继续使用对象

不推荐：

```cpp
obj->deleteLater();
obj->doSomething();  // 不推荐
```

推荐：

```cpp
obj->deleteLater();
obj = nullptr;
```

或者：

```cpp
QPointer<QObject> ptr = obj;
obj->deleteLater();

if (ptr) {
    // 对象尚未真正析构
}
```

---

## 9.4 前提：对象所属线程应有 event loop

`deleteLater()` 依赖事件循环。

如果对象所在线程没有 event loop，或者 main event loop 已经停止，对象可能不会按预期删除。

---

## 9.5 不要对栈对象调用 deleteLater

错误：

```cpp
void foo()
{
    QObject obj;
    obj.deleteLater();  // 错误
}
```

`deleteLater()` 最终会 delete 对象，因此只适用于 heap object。

正确：

```cpp
QObject *obj = new QObject;
obj->deleteLater();
```

---

## 9.6 不要混用 parent ownership 和智能指针默认 deleter

危险：

```cpp
std::shared_ptr<QObject> obj(new QObject(parent));
obj->deleteLater();
```

原因：

```text
parent 可能删除它
deleteLater 可能删除它
shared_ptr 也可能删除它
```

ownership 混乱。

---

# 10. 跨线程删除 QObject 示例

## 10.1 推荐 worker-thread 模式

```cpp
class Worker : public QObject
{
    Q_OBJECT

public slots:
    void doWork()
    {
        qDebug() << "Worker running in thread:" << QThread::currentThread();

        // 模拟工作完成
        emit finished();
    }

signals:
    void finished();
};
```

使用：

```cpp
QThread *thread = new QThread;
Worker *worker = new Worker;

// worker 不能有 parent，否则 moveToThread 会失败
worker->moveToThread(thread);

QObject::connect(thread, &QThread::started,
                 worker, &Worker::doWork);

QObject::connect(worker, &Worker::finished,
                 thread, &QThread::quit);

QObject::connect(worker, &Worker::finished,
                 worker, &QObject::deleteLater);

QObject::connect(thread, &QThread::finished,
                 thread, &QObject::deleteLater);

thread->start();
```

---

## 10.2 为什么安全

流程：

```text
thread started
    ↓
worker::doWork 在子线程执行
    ↓
worker emit finished
    ↓
thread quit
    ↓
worker deleteLater
    ↓
worker 所属线程 event loop 处理 DeferredDelete
    ↓
worker 在正确线程析构
    ↓
thread finished
    ↓
thread deleteLater
```

---

## 10.3 错误示例

```cpp
QThread *thread = new QThread;
Worker *worker = new Worker;

worker->moveToThread(thread);
thread->start();

// 假设这里在主线程
delete worker;  // 错误：worker 属于子线程
```

风险：

```text
worker 所属线程可能还有 pending events
queued signal 可能还没处理
timer 可能注册在子线程 event dispatcher
直接析构破坏 QObject thread affinity
```

---

## 10.4 如果从任意线程请求删除

可以使用：

```cpp
worker->deleteLater();
```

或者显式 queued invocation：

```cpp
QMetaObject::invokeMethod(worker, "deleteLater", Qt::QueuedConnection);
```

但要保证 worker 所属线程 event loop 仍然存在。

---

# 11. 常见实践规则总结

## 11.1 signal/slot

```text
1. 新代码优先使用 Qt5 函数指针 connect 语法
2. 跨线程默认使用 AutoConnection 即可
3. 不要强行跨线程 DirectConnection，除非明确线程安全
4. queued connection 传自定义类型时注册 qRegisterMetaType
5. 重复 connect 会导致 slot 被调用多次，可用 Qt::UniqueConnection
```

---

## 11.2 Q_OBJECT / moc

```text
1. QObject 子类如果有 signal/slot/property/invokable，必须加 Q_OBJECT
2. CMake 项目开启 AUTOMOC
3. undefined reference to vtable 通常和 moc 未生成/未链接有关
4. qobject_cast 的目标类型通常需要 Q_OBJECT
```

---

## 11.3 QObject parent-child

```text
1. heap child 可以交给 parent 管理
2. parent 析构自动删除所有 children
3. child 析构自动从 parent 移除
4. 不要把栈对象随意 setParent
5. 不要和 shared_ptr 默认 deleter 混用
6. parent-child 必须在同一线程
```

---

## 11.4 deleteLater

```text
1. 跨线程删除 QObject，用 deleteLater
2. slot/event handler 中删除自己，用 deleteLater
3. 调用 deleteLater 后不要继续使用对象
4. 对象必须是 heap object
5. 对象所属线程应有 event loop
6. 外部保存指针建议用 QPointer
```

---

# 附：核心源码关注点

```text
qobject.h
    QObjectData::parent
    QObjectData::children
    QObject::parent()
    QObject::children()

qobject_p.h
    QObjectPrivate
    QObjectPrivate::setParent_helper
    QObjectPrivate::deleteChildren

qobject.cpp
    QObject::QObject(QObject *parent)
    QObject::~QObject()
    QObject::setParent(QObject *parent)
    QObject::deleteLater()
    QObject::event(QEvent *)
    QObject::connect / disconnect
    QMetaObject::activate
    queued_activate
    QMetaCallEvent
```

---

# 总结

Qt 的 QObject 体系可以看成 C++ 之上的一套对象运行时：

```text
QObject 提供对象身份、事件、线程归属、生命周期和连接管理
Q_OBJECT 让类接入元对象系统
moc 生成元对象代码和 signal 函数体
QMetaObject 提供运行时方法/属性/类型信息
signal/slot 基于连接表和元对象系统实现解耦通信
parent-child 提供树形 ownership
deleteLater 提供事件驱动的安全延迟销毁
```

最终，Qt 用这套机制把普通 C++ 对象扩展成适合 GUI、事件循环、跨线程通信和动态 UI 系统的框架级对象模型。



下面是一段适合**面试 3 分钟内口述**的文稿，内容比 2 分钟版更完整，覆盖 `QObject / Q_OBJECT / moc / 元对象系统 / connect / emit / Direct / Queued / parent-child / deleteLater` 等重点。

***

## 面试 3 分钟回答稿：Qt signal/slot 机制

Qt 的 signal/slot 机制，本质上是 Qt 基于 `QObject`、`Q_OBJECT`、moc 和元对象系统实现的一套**对象间解耦通信机制**，它不是简单的 C++ callback。

首先，Qt 中的 `signals`、`slots`、`emit` 并不是 C++ 原生关键字，而是 Qt 定义的宏。真正让 signal/slot 工作的是 `Q_OBJECT` 宏和 moc。一个类如果继承自 `QObject`，并且声明了 signal、slot、`Q_PROPERTY` 或需要使用元对象能力，就需要加 `Q_OBJECT`。moc 会扫描这个类，生成对应的元对象代码，比如 `staticMetaObject`、`qt_metacall()`、`qt_static_metacall()`，以及 signal 函数体。

比如我们声明一个信号：

```cpp
signals:
    void valueChanged(int value);
```

这个函数我们并没有自己实现，它的函数体是 moc 生成的。生成后的逻辑大致是：把参数放进一个 `void* argv[]` 数组，然后调用：

```cpp
QMetaObject::activate(this, &staticMetaObject, signal_index, argv);
```

所以 `emit valueChanged(10)` 本质上就是调用这个 moc 生成的普通成员函数，然后进入 `QMetaObject::activate()`。

`connect()` 的作用是建立连接关系。Qt 内部会记录 sender、signal index、receiver、slot method index、连接类型、参数类型、receiver 所在线程等信息，并保存到 `QObjectPrivate` 的连接表中。等 signal 发出时，`QMetaObject::activate()` 会根据 signal index 找到所有连接到这个 signal 的 slot，然后按连接顺序依次触发。

连接类型是 signal/slot 机制里很重要的一点。默认是 `Qt::AutoConnection`。如果 sender 和 receiver 在同一个线程，通常会退化成 `DirectConnection`，也就是 signal 发出时立即调用 slot，slot 运行在 emit 所在线程，属于同步调用。如果 sender 和 receiver 在不同线程，通常会变成 `QueuedConnection`。这时 Qt 不会立即调用 slot，而是把这次调用封装成一个 `QMetaCallEvent`，通过 `QCoreApplication::postEvent()` 投递到 receiver 所属线程的事件队列里，等 receiver 所在线程的 event loop 处理时再调用 slot。所以跨线程 signal/slot 的本质是事件投递。

QueuedConnection 依赖元对象系统非常明显。因为跨线程调用时，signal 发出后当前栈帧很快就结束了，参数地址不能直接保存，所以 Qt 必须知道参数类型，然后通过 `QMetaType` 拷贝参数到事件对象中。因此如果 queued connection 传递自定义类型，通常需要 `qRegisterMetaType<MyType>()`，否则 Qt 可能不知道如何拷贝和析构这个参数。

Qt5 以后的新 connect 语法：

```cpp
connect(sender, &Sender::valueChanged,
        receiver, &Receiver::onValueChanged);
```

相比旧的 `SIGNAL()`、`SLOT()` 字符串语法，优点是可以做编译期类型检查，避免函数名写错或参数不匹配。但即使用新语法，signal 的触发、连接表管理、queued connection、跨线程事件投递，仍然依赖 QObject 和元对象系统。

另外，signal/slot 和 QObject 生命周期管理也结合得很紧。`QObject` 析构时，会自动断开所有与它相关的连接，包括它作为 sender 发出的连接，以及它作为 receiver 接收的连接，所以可以避免 slot 指向已经销毁的对象。同时 QObject 还有 parent-child 内存管理机制，parent 析构时会自动 delete 所有 children，child 析构时也会从 parent 的 children list 中移除。

跨线程删除 QObject 时要特别小心，不能在错误线程直接 `delete`。因为 QObject 有 thread affinity，pending event、queued signal、timer 都和对象所属线程有关。更安全的方式是调用 `deleteLater()`，它会投递一个 deferred delete event，让对象所属线程的 event loop 在安全时机删除对象。典型 worker 线程写法是：worker 完成后发出 `finished()`，连接到 `worker->deleteLater()`，同时连接到 `thread->quit()`，最后 `thread->finished()` 再连接到 `thread->deleteLater()`。

所以总结来说，Qt 的 signal/slot 不是普通 callback，而是一套基于元对象系统的运行时通信机制。它支持对象解耦、一对多连接、运行时查找、参数类型管理、跨线程事件投递、自动断连和 QObject 生命周期管理，这也是 Qt 在 GUI 和多线程场景下非常常用 signal/slot 的原因。

***

## 如果最后要补一句总结

可以用这句收尾：

> 简单说，`emit` 只是入口，真正的核心是 moc 生成的 signal 函数调用 `QMetaObject::activate()`，再通过 QObject 内部连接表找到 slot；同线程直接调用，跨线程投递事件，生命周期由 QObject 的自动断连、parent-child 和 `deleteLater()` 机制保证。

