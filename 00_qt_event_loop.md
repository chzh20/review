下面按 **Qt 5 / qtbase 源码**来串起来看。核心结论先说：

> Qt 的事件循环本质上是：`QCoreApplication::exec()` 创建主 `QEventLoop`，`QEventLoop::exec()` 在一个循环里反复调用当前线程的 `QAbstractEventDispatcher::processEvents()`；事件调度器再从「posted event 队列、timer、socket notifier、窗口系统/native event」等来源取事件，并最终通过 `QCoreApplication::notify()` / `QObject::event()` 分发给对象。相关核心入口都在 `qtbase/src/corelib/kernel/` 下，例如 `qcoreapplication.cpp`、`qeventloop.cpp`、`qabstracteventdispatcher.cpp`、`qeventdispatcher_unix.cpp`。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventloop.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qabstracteventdispatcher.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html)

***

## 1. 从 `main()` 的 `app.exec()` 开始

典型 Qt 程序：

```cpp
int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    MainWindow w;
    w.show();
    return app.exec();
}
```

`QApplication` 继承自 `QCoreApplication`，所以 `app.exec()` 最终进入 `QCoreApplication::exec()`；`QCoreApplication` 文档也明确它提供 non-GUI 应用的 event loop，而 GUI 的 `QApplication` / `QGuiApplication` 也是基于它扩展。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qcoreapplication.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html)

源码层面，`qcoreapplication.cpp` 引入了 `qeventloop.h`、`qabstracteventdispatcher.h`、`qcoreevent.h`，这说明 `QCoreApplication` 是事件循环、事件对象、事件调度器三者的上层协调者。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html)

`QCoreApplication::exec()` 的逻辑可以简化理解为：

```cpp
int QCoreApplication::exec()
{
    QEventLoop eventLoop;
    int returnCode = eventLoop.exec(QEventLoop::ApplicationExec);
    return returnCode;
}
```

也就是说：**主事件循环其实就是一个 `QEventLoop` 对象的`exec()`**。`QEventLoop` 文档也说明：调用 `exec()` 会进入事件循环，直到 `exit()` 被调用才返回。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventloop.cpp.html)

***

## 2. `QEventLoop::exec()`：事件循环的“while 主体”

`QEventLoop` 的职责非常明确：提供进入和退出事件循环的方法；源码文件 `qeventloop.cpp` 的注释也写到，可以创建 `QEventLoop` 并调用 `exec()` 启动本地事件循环，内部调用 `exit()` 会让 `exec()` 返回。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventloop.cpp.html), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html)

关键逻辑等价于：

```cpp
int QEventLoop::exec(ProcessEventsFlags flags)
{
    // 1. 设置 running / exit 状态
    // 2. 把当前 event loop 压入当前线程的 eventLoops 栈

    while (!d->exit.loadAcquire()) {
        processEvents(flags | WaitForMoreEvents | EventLoopExec);
    }

    // 3. 弹出 event loop
    return d->returnCode.load();
}
```

这里有几个重点：

1. `while (!exit)` 是事件循环的主体。
2. `processEvents()` 是每一轮真正处理事件的地方。
3. `WaitForMoreEvents` 表示没事件时可以阻塞等待，而不是空转 CPU。
4. `EventLoopExec` 是内部标记，表示这是由 `exec()` 驱动的一轮处理。 [\[blog.csdn.net\]](https://blog.csdn.net/u012999461/article/details/126225774), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html)

所以，Qt 的事件循环不是 `while(true)` 忙等，而是 **每轮委托给平台事件调度器；没事件时进入系统等待机制**。在 Unix 实现里，事件调度器会使用 pipe/eventfd、poll 等机制等待事件源，因此不会像普通死循环一样打满 CPU。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html), [\[zhuanlan.zhihu.com\]](https://zhuanlan.zhihu.com/p/648582959)

***

## 3. `QEventLoop::processEvents()`：转交给当前线程的 dispatcher

`QEventLoop::processEvents()` 自己并不直接处理鼠标、键盘、timer、socket 等事件，而是找到当前线程的事件调度器：

```cpp
bool QEventLoop::processEvents(ProcessEventsFlags flags)
{
    if (!d->threadData->hasEventDispatcher())
        return false;

    return d->threadData->eventDispatcher.load()->processEvents(flags);
}
```

这说明 Qt 的事件循环是 **线程相关的**：每个线程有自己的 `QThreadData`，其中保存该线程的 `QAbstractEventDispatcher`。`qeventloop.cpp` 包含 `qthread_p.h`，并在构造 `QEventLoop` 时会确保当前线程有 event dispatcher。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventloop.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt6/qtbase/src/corelib/kernel/qeventloop.cpp.html)

这也是为什么：

```cpp
QThread::run()
{
    exec();
}
```

后，子线程也可以处理 `QTimer`、queued signal/slot、`deleteLater()` 等事件；因为子线程也跑了自己的事件循环。 [\[blog.csdn.net\]](https://blog.csdn.net/u012999461/article/details/126225774), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html)

***

## 4. `QAbstractEventDispatcher`：平台无关接口

`QAbstractEventDispatcher` 是 Qt 对底层事件机制的抽象。不同平台有不同实现：

* Unix/Linux：`QEventDispatcherUNIX`
* Windows：`QEventDispatcherWin32`
* macOS/iOS：Core Foundation / Cocoa 相关 dispatcher
* 如果启用 GLib，也可能走 `QEventDispatcherGlib`

`qcoreapplication.cpp` 根据平台 include 了不同的 dispatcher 头文件，比如 Unix 下包括 `qeventdispatcher_unix_p.h`，Windows 下包括对应 Win dispatcher。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html)

抽象层的好处是：上层 `QEventLoop` 只调用：

```cpp
dispatcher->processEvents(flags);
```

至于底层是 `poll()`、`select()`、Win32 message pump、CoreFoundation run loop，Qt 都封装在具体 dispatcher 里。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qabstracteventdispatcher.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html)

***

## 5. Unix 下 `QEventDispatcherUNIX::processEvents()` 做了什么

以 `qeventdispatcher_unix.cpp` 为例，它处理的事件源大致包括：

1. **posted events**：也就是 `QCoreApplication::postEvent()` 放进队列的事件；
2. **timers**：`QTimer` / `QObject::startTimer()` 产生的定时器事件；
3. **socket notifiers**：`QSocketNotifier` 监听 fd 可读、可写、异常；
4. **thread wakeup pipe/eventfd**：跨线程投递事件后唤醒事件循环；
5. **平台/native event**：窗口系统事件最终会转换为 Qt 的 `QEvent`。`qeventdispatcher_unix.cpp` 引入了 `qsocketnotifier.h`、`qthread.h`、`qcoreapplication_p.h` 等，并实现 Unix 事件调度。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qevent.html)

简化流程可以写成：

```cpp
bool QEventDispatcherUNIX::processEvents(flags)
{
    // 1. 先发送当前线程 postEvent 队列中的事件
    QCoreApplicationPrivate::sendPostedEvents(...);

    // 2. 计算最近 timer 的超时时间

    // 3. 构造 pollfd 列表：
    //    - socket notifier fds
    //    - thread wakeup pipe/eventfd
    //    - timer 相关等待

    // 4. 调用 poll/select 等系统调用等待事件

    // 5. fd 就绪后激活 socket notifier
    // 6. timer 到期后投递/发送 timer event
}
```

重点是第 4 步：没有事件时，线程会阻塞在系统调用上，所以 Qt event loop 不会高 CPU 空转。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html), [\[zhuanlan.zhihu.com\]](https://zhuanlan.zhihu.com/p/648582959)

***

## 6. posted event：`postEvent()` 与 `sendEvent()` 的差异

Qt 事件来源分两类很重要：

### `sendEvent()`：同步立即发送

```cpp
QCoreApplication::sendEvent(receiver, event);
```

它会立即调用 receiver 的事件处理链，调用栈不返回之前事件已经处理完。Qt 文档说明事件可以由 `sendEvent()` 或 `postEvent()` 手动发送，其中这类事件不是来自底层窗口系统。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qevent.html)

### `postEvent()`：异步入队，下一轮事件循环处理

```cpp
QCoreApplication::postEvent(receiver, event);
```

它只是把事件放入当前接收对象所属线程的 `postEventList`，并唤醒该线程的 dispatcher；真正处理发生在后续 `sendPostedEvents()` 中。`QCoreApplication` 的 API 列表中包含 `postEvent()`、`sendPostedEvents()`、`removePostedEvents()` 等接口，源码也集中在 `qcoreapplication.cpp`。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html), [\[runebook.dev\]](https://runebook.dev/en/docs/qt/qcoreapplication/sendPostedEvents)

queued signal/slot 本质上也依赖类似机制：跨线程或 queued connection 会把一次调用封装成事件，投递到 receiver 所在线程，等该线程 event loop 处理。

***

## 7. 最终分发：`notify()` → `QObject::event()` → 具体 handler

事件被取出来后，最终会走到对象的事件分发链。Qt 文档描述得很清楚：Qt 主事件循环从 native event queue 获取窗口系统事件，将它们转换为 `QEvent`，然后发送给 `QObject`；对象通过 `QObject::event()` 接收事件，子类可以重写 `event()` 或具体 handler。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qevent.html), [\[typeerror.org\]](https://www.typeerror.org/docs/qt~5.15/eventsandfilters)

分发链可以简化为：

```cpp
QCoreApplication::notify(receiver, event)
    -> receiver->event(event)
        -> QWidget::event(event)
            -> mousePressEvent()
            -> keyPressEvent()
            -> paintEvent()
            -> timerEvent()
            -> ...
```

比如：

* 鼠标事件：`QMouseEvent` → `QWidget::mousePressEvent()`
* 键盘事件：`QKeyEvent` → `QWidget::keyPressEvent()`
* 定时器事件：`QTimerEvent` → `QObject::timerEvent()`
* 绘制事件：`QPaintEvent` → `QWidget::paintEvent()`

Qt 的事件系统文档也说明，当事件发生时 Qt 构造合适的 `QEvent` 子类，并通过调用目标对象的 `event()` 函数交付；`event()` 再根据具体类型调用对应的事件处理函数。 [\[typeerror.org\]](https://www.typeerror.org/docs/qt~5.15/eventsandfilters), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qevent.html)

***

## 8. `exit()` / `quit()` 如何让循环退出

`QEventLoop::exec()` 的循环条件是 `!exit`，所以退出只需要把这个标志置位并唤醒 dispatcher。`QEventLoop` 文档说明，`exit(returnCode)` 会让 `exec()` 返回传入的返回码，`quit()` 等价于 `exit(0)`。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html)

简化逻辑：

```cpp
void QEventLoop::exit(int returnCode)
{
    d->returnCode = returnCode;
    d->exit = true;
    wakeUp();
}
```

`QCoreApplication::quit()` / `exit()` 最终也是让主事件循环退出；如果当前线程阻塞在 dispatcher 的 wait 中，`wakeUp()` 会通过平台机制唤醒它。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qabstracteventdispatcher.cpp.html)

***

## 9. 嵌套事件循环：为什么 `QDialog::exec()` 可以“阻塞但不死”

Qt 允许局部事件循环，比如：

```cpp
QDialog dlg;
dlg.exec();
```

或者：

```cpp
QEventLoop loop;
connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
loop.exec();
```

这不是把线程卡死，而是在当前线程里又启动了一个 `QEventLoop`；它仍然继续调用同一个线程的 dispatcher 来分发事件。文档也说明可以随时创建 `QEventLoop` 并调用 `exec()` 启动一个本地事件循环。 [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/qeventloop.html)

但嵌套事件循环有风险：它会导致 reentrancy，也就是你以为当前函数还没返回，但期间其他事件已经被处理，可能修改状态甚至删除对象。因此 `QDialog::exec()`、手写 `QEventLoop`、频繁 `processEvents()` 都要谨慎。 [\[runebook.dev\]](https://runebook.dev/en/docs/qt/qeventloop/processEvents), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qeventloop.html)

***

## 10. 总体调用链图

```text
main()
  └─ QApplication/QCoreApplication app
      └─ app.exec()
          └─ QCoreApplication::exec()
              └─ QEventLoop eventLoop
                  └─ QEventLoop::exec()
                      └─ while (!exit)
                          └─ QEventLoop::processEvents()
                              └─ QAbstractEventDispatcher::processEvents()
                                  ├─ sendPostedEvents()
                                  │   └─ QCoreApplication::notify()
                                  │       └─ QObject::event()
                                  │           └─ xxxEvent()
                                  ├─ process timers
                                  ├─ process socket notifiers
                                  ├─ process native window events
                                  └─ wait/poll until next event
```

***

## 一句话总结

Qt 事件循环的实现可以概括为：

> `QCoreApplication::exec()` 启动主 `QEventLoop`；`QEventLoop::exec()` 通过 `while` 循环不断调用 `processEvents()`；`processEvents()` 交给当前线程的 `QAbstractEventDispatcher`；dispatcher 从 posted events、timer、socket、native window system 等事件源取事件；最后通过 `notify()` / `QObject::event()` 分发到具体对象和事件处理函数。 [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qcoreapplication.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventloop.cpp.html), [\[codebrowser.dev\]](https://codebrowser.dev/qt5/qtbase/src/corelib/kernel/qeventdispatcher_unix.cpp.html), [\[qthub.com\]](https://qthub.com/static/doc/qt5/qtcore/qevent.html)
