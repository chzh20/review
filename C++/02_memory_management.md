下面是 **C++ 内存管理与智能指针** 的面试提炼版，重点覆盖：

- `malloc/free`
- `new/delete`
- `new[]/delete[]`
- placement new
- RAII
- `unique_ptr`
- `shared_ptr`
- `weak_ptr`
- 循环引用
- 对象生命周期
- 常见内存错误

这些内容也是 `huihut/interview` C/C++ 部分的高频主题，包括 `malloc/calloc/realloc/alloca`、`new/delete`、placement new、`delete this`、智能指针、`shared_ptr`、`unique_ptr`、`weak_ptr` 等。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

# 1. C/C++ 内存区域

## 面试问题

1. C++ 程序运行时有哪些主要内存区域？
2. 栈和堆有什么区别？
3. 全局变量、静态变量、字符串常量分别放在哪里？
4. 野指针、悬空指针、内存泄漏分别是什么？

---

## 1.1 程序常见内存布局

一个 C/C++ 程序运行时常见区域：

```text
高地址
+------------------+
| 栈 stack          | 局部变量、函数参数、返回地址
+------------------+
| 堆 heap           | malloc/new 动态分配
+------------------+
| BSS 段            | 未初始化的全局变量、静态变量
+------------------+
| data 段           | 已初始化的全局变量、静态变量
+------------------+
| rodata 段         | 字符串常量、只读常量
+------------------+
| text 段           | 程序机器指令
+------------------+
低地址
```

仓库链接装载库部分也整理了栈、堆、可执行文件映像、保留区，以及 `.text`、`.data`、`.bss`、`.rodata` 等目标文件段。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

## 1.2 示例

```cpp
#include <iostream>

int g_init = 10;        // data 段
int g_uninit;           // bss 段
static int s_init = 20; // data 段

int main() {
    int local = 1;              // 栈
    static int s_local = 2;     // data 段
    int* p = new int(3);        // p 在栈，*p 在堆
    const char* str = "hello";  // 字符串常量在 rodata 段

    std::cout << &g_init << '\n';
    std::cout << &g_uninit << '\n';
    std::cout << &s_init << '\n';
    std::cout << &local << '\n';
    std::cout << &s_local << '\n';
    std::cout << p << '\n';
    std::cout << static_cast<const void*>(str) << '\n';

    delete p;
}
```

---

# 2. `malloc/free`

## 面试问题

1. `malloc` 做什么？
2. `free` 做什么？
3. `malloc` 和 `calloc` 区别？
4. `realloc` 有什么风险？
5. `malloc(0)` 会怎样？
6. `free(nullptr)` 合法吗？
7. `malloc/free` 会调用构造和析构函数吗？

---

## 2.1 `malloc/free` 基本用法

```cpp
#include <cstdlib>
#include <cstring>
#include <iostream>

int main() {
    int* p = static_cast<int*>(std::malloc(sizeof(int)));

    if (!p) {
        return 1;
    }

    *p = 42;
    std::cout << *p << '\n';

    std::free(p);
    p = nullptr;
}
```

`malloc` 只负责分配一块原始内存，不会调用构造函数。  
`free` 只负责释放内存，不会调用析构函数。

---

## 2.2 `malloc` vs `calloc`

```cpp
#include <cstdlib>
#include <iostream>

int main() {
    int* a = static_cast<int*>(std::malloc(5 * sizeof(int)));
    int* b = static_cast<int*>(std::calloc(5, sizeof(int)));

    // a 中内容未初始化，值不确定
    // b 中内容被初始化为 0

    std::free(a);
    std::free(b);
}
```

区别：


| 函数                       | 含义                |
| ------------------------ | ----------------- |
| `malloc(size)`           | 分配 size 字节，内容未初始化 |
| `calloc(n, size)`        | 分配 n size 字节，并清零  |
| `realloc(ptr, new_size)` | 调整已有内存大小，可能搬迁     |


---

## 2.3 `realloc` 风险

错误写法：

```cpp
int* p = static_cast<int*>(std::malloc(10 * sizeof(int)));

p = static_cast<int*>(std::realloc(p, 20 * sizeof(int)));
// 如果 realloc 失败，返回 nullptr，原来的 p 就丢了，造成内存泄漏
```

安全写法：

```cpp
int* p = static_cast<int*>(std::malloc(10 * sizeof(int)));

int* new_p = static_cast<int*>(std::realloc(p, 20 * sizeof(int)));
if (new_p) {
    p = new_p;
} else {
    // p 仍然有效
    std::free(p);
}
```

---

## 2.4 `malloc(0)`

```cpp
void* p = std::malloc(0);
```

标准允许它返回：

- `nullptr`
- 或者一个不能解引用但可以传给 `free` 的非空指针

所以不要依赖 `malloc(0)` 的具体行为。

---

## 2.5 `free(nullptr)` 合法

```cpp
int* p = nullptr;
std::free(p); // ok
```

和 `delete nullptr` 一样，都是安全的。

---

# 3. `new/delete`

## 面试问题

1. `new` 做了哪几件事？
2. `delete` 做了哪几件事？
3. `new/delete` 和 `malloc/free` 有什么区别？
4. `new` 失败会怎样？
5. `delete nullptr` 合法吗？
6. 为什么 `new[]` 必须配 `delete[]`？

仓库中也总结：`new/new[]` 先分配内存再调用构造函数，`delete/delete[]` 先调用析构函数再释放空间。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

## 3.1 `new/delete` 基本过程

```cpp
#include <iostream>

class A {
public:
    A() {
        std::cout << "A ctor\n";
    }

    ~A() {
        std::cout << "A dtor\n";
    }
};

int main() {
    A* p = new A;  // 1. 分配内存 2. 调用构造函数

    delete p;     // 1. 调用析构函数 2. 释放内存
}
```

输出：

```text
A ctor
A dtor
```

---

## 3.2 `new/delete` vs `malloc/free`


| 对比点  | `malloc/free` | `new/delete`              |
| ---- | ------------- | ------------------------- |
| 语言   | C 函数          | C++ 运算符                   |
| 类型   | 返回 `void*`    | 返回具体类型指针                  |
| 内存大小 | 手动传字节数        | 自动计算                      |
| 构造函数 | 不调用           | 调用                        |
| 析构函数 | 不调用           | 调用                        |
| 失败行为 | 返回 `nullptr`  | 默认抛 `std::bad_alloc`      |
| 重载   | 不能按类重载        | 可重载 `operator new/delete` |


---

## 3.3 `new` 失败

默认情况下：

```cpp
int* p = new int[1000000000000];
```

如果分配失败，会抛出：

```cpp
std::bad_alloc
```

可以使用 `nothrow`：

```cpp
#include <new>

int* p = new (std::nothrow) int[1000000000000];

if (!p) {
    // 分配失败
}
```

---

# 4. `new[]` / `delete[]`

## 面试问题

1. 为什么 `new[]` 要配 `delete[]`？
2. `delete` 和 `delete[]` 混用有什么问题？
3. 数组对象析构时如何知道调用几次析构？

---

## 4.1 正确用法

```cpp
#include <iostream>

class A {
public:
    A() {
        std::cout << "ctor\n";
    }

    ~A() {
        std::cout << "dtor\n";
    }
};

int main() {
    A* arr = new A[3];

    delete[] arr;
}
```

输出：

```text
ctor
ctor
ctor
dtor
dtor
dtor
```

---

## 4.2 错误用法

```cpp
A* arr = new A[3];

delete arr; // 错误，应使用 delete[]
```

这属于未定义行为。

原因：

- `new[]` 分配的是数组对象；
- 运行时通常需要记录数组元素个数；
- `delete[]` 才会逐个调用析构函数；
- `delete` 只按单个对象处理。

---

# 5. placement new

## 面试问题

1. placement new 是什么？
2. placement new 会分配内存吗？
3. placement new 创建的对象如何销毁？
4. placement new 适合哪些场景？
5. placement new 和普通 new 有什么区别？

---

## 5.1 基本概念

placement new 是在一块已经分配好的内存上构造对象。

```cpp
#include <iostream>
#include <new>

class A {
public:
    A(int x) : x_(x) {
        std::cout << "A ctor\n";
    }

    ~A() {
        std::cout << "A dtor\n";
    }

private:
    int x_;
};

int main() {
    alignas(A) char buffer[sizeof(A)];

    A* p = new (buffer) A(42); // 在 buffer 上构造 A，不分配内存

    p->~A(); // 手动调用析构函数
}
```

---

## 5.2 placement new 特点

- 不分配内存；
- 只调用构造函数；
- 对象销毁时需要手动调用析构函数；
- 原始内存是否释放，由用户自己负责。

常见场景：

- 内存池；
- 对象池；
- 自定义 allocator；
- 高性能场景避免频繁堆分配；
- 在共享内存/固定 buffer 上构造对象。

---

# 6. RAII

## 面试问题

1. 什么是 RAII？
2. RAII 解决什么问题？
3. RAII 和异常安全有什么关系？
4. 常见 RAII 类有哪些？
5. 如何自己写一个 RAII 类？

---

## 6.1 RAII 核心思想

RAII：Resource Acquisition Is Initialization。

核心思想：

> 资源在对象构造时获取，在对象析构时释放。

这样可以确保即使发生异常，栈展开时析构函数也会自动释放资源。

---

## 6.2 不使用 RAII 的问题

```cpp
#include <stdexcept>

void f() {
    int* p = new int(10);

    throw std::runtime_error("error");

    delete p; // 永远执行不到，内存泄漏
}
```

---

## 6.3 使用 RAII

```cpp
#include <memory>
#include <stdexcept>

void f() {
    std::unique_ptr<int> p = std::make_unique<int>(10);

    throw std::runtime_error("error");

    // 不需要手动 delete
}
```

发生异常时，`unique_ptr` 析构，自动释放内存。

---

## 6.4 自定义 RAII 类

```cpp
#include <iostream>

class File {
public:
    explicit File(const char* path) {
        fp_ = std::fopen(path, "w");
        if (!fp_) {
            throw std::runtime_error("open failed");
        }
    }

    ~File() {
        if (fp_) {
            std::fclose(fp_);
        }
    }

    File(const File&) = delete;
    File& operator=(const File&) = delete;

private:
    std::FILE* fp_ = nullptr;
};
```

关键点：

- 构造函数获取资源；
- 析构函数释放资源；
- 禁止拷贝，避免重复释放；
- 必要时支持移动。

---

# 7. 三五零法则

## 面试问题

1. Rule of Three 是什么？
2. Rule of Five 是什么？
3. Rule of Zero 是什么？
4. 为什么有析构函数时通常要考虑拷贝构造和赋值？
5. 什么时候应该禁用拷贝？

---

## 7.1 Rule of Three

如果类自己管理资源，并定义了以下任意一个：

- 析构函数；
- 拷贝构造函数；
- 拷贝赋值运算符；

通常需要同时考虑另外两个。

```cpp
class Buffer {
public:
    explicit Buffer(size_t n)
        : size_(n), data_(new char[n]) {}

    ~Buffer() {
        delete[] data_;
    }

    Buffer(const Buffer& other)
        : size_(other.size_), data_(new char[other.size_]) {
        std::copy(other.data_, other.data_ + size_, data_);
    }

    Buffer& operator=(const Buffer& other) {
        if (this == &other) {
            return *this;
        }

        char* new_data = new char[other.size_];
        std::copy(other.data_, other.data_ + other.size_, new_data);

        delete[] data_;

        data_ = new_data;
        size_ = other.size_;

        return *this;
    }

private:
    size_t size_;
    char* data_;
};
```

---

## 7.2 Rule of Five

C++11 后还要考虑：

- 移动构造函数；
- 移动赋值运算符。

```cpp
class Buffer {
public:
    explicit Buffer(size_t n)
        : size_(n), data_(new char[n]) {}

    ~Buffer() {
        delete[] data_;
    }

    Buffer(const Buffer& other)
        : size_(other.size_), data_(new char[other.size_]) {
        std::copy(other.data_, other.data_ + size_, data_);
    }

    Buffer& operator=(const Buffer& other) {
        if (this == &other) return *this;

        Buffer temp(other);
        swap(temp);
        return *this;
    }

    Buffer(Buffer&& other) noexcept
        : size_(other.size_), data_(other.data_) {
        other.size_ = 0;
        other.data_ = nullptr;
    }

    Buffer& operator=(Buffer&& other) noexcept {
        if (this == &other) return *this;

        delete[] data_;

        size_ = other.size_;
        data_ = other.data_;

        other.size_ = 0;
        other.data_ = nullptr;

        return *this;
    }

    void swap(Buffer& other) noexcept {
        std::swap(size_, other.size_);
        std::swap(data_, other.data_);
    }

private:
    size_t size_;
    char* data_;
};
```

---

## 7.3 Rule of Zero

最推荐：

> 不自己管理裸资源，交给标准库类型管理。

```cpp
#include <vector>

class Buffer {
public:
    explicit Buffer(size_t n)
        : data_(n) {}

private:
    std::vector<char> data_;
};
```

这样不需要手写析构、拷贝、移动，交给编译器和标准库。

---

# 8. `unique_ptr`

## 面试问题

1. `unique_ptr` 有什么特点？
2. `unique_ptr` 能否拷贝？
3. `unique_ptr` 如何转移所有权？
4. `make_unique` 有什么好处？
5. `unique_ptr` 如何管理数组？
6. `unique_ptr` 支持自定义删除器吗？

---

## 8.1 基本特点

`unique_ptr` 表示独占所有权。

```cpp
#include <memory>
#include <iostream>

int main() {
    std::unique_ptr<int> p = std::make_unique<int>(42);

    std::cout << *p << '\n';
}
```

离开作用域时自动释放。

---

## 8.2 不能拷贝，只能移动

```cpp
std::unique_ptr<int> p1 = std::make_unique<int>(1);

// std::unique_ptr<int> p2 = p1; // error

std::unique_ptr<int> p2 = std::move(p1); // ok

if (!p1) {
    std::cout << "p1 is empty\n";
}
```

---

## 8.3 函数返回 `unique_ptr`

```cpp
#include <memory>

std::unique_ptr<int> create() {
    return std::make_unique<int>(42);
}

int main() {
    auto p = create();
}
```

这是表达资源所有权转移的好方式。

---

## 8.4 管理数组

```cpp
std::unique_ptr<int[]> arr = std::make_unique<int[]>(10);

arr[0] = 1;
```

---

## 8.5 自定义删除器

```cpp
#include <cstdio>
#include <memory>

int main() {
    auto deleter = std::FILE* fp {
        if (fp) {
            std::fclose(fp);
        }
    };

    std::unique_ptr<std::FILE, decltype(deleter)> fp(
        std::fopen("test.txt", "w"),
        deleter
    );
}
```

---

# 9. `shared_ptr`

## 面试问题

1. `shared_ptr` 的引用计数是什么？
2. `shared_ptr` 如何判断何时释放对象？
3. `shared_ptr` 的控制块里有什么？
4. `make_shared` 和 `shared_ptr<T>(new T)` 有什么区别？
5. `shared_ptr` 是否线程安全？
6. 为什么不要用同一个裸指针构造多个 `shared_ptr`？
7. `shared_ptr` 循环引用是什么？

仓库中总结：`shared_ptr` 实现共享所有权，多个智能指针指向同一对象，对象会在最后一个 reference 被销毁时释放。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

## 9.1 基本用法

```cpp
#include <memory>
#include <iostream>

class A {
public:
    A() {
        std::cout << "A ctor\n";
    }

    ~A() {
        std::cout << "A dtor\n";
    }
};

int main() {
    std::shared_ptr<A> p1 = std::make_shared<A>();

    {
        std::shared_ptr<A> p2 = p1;
        std::cout << p1.use_count() << '\n'; // 2
    }

    std::cout << p1.use_count() << '\n'; // 1
}
```

离开 `main` 时，最后一个 `shared_ptr` 析构，对象释放。

---

## 9.2 控制块

`shared_ptr` 通常包含：

```text
shared_ptr 本体:
+----------------+
| 对象指针        |
| 控制块指针      |
+----------------+

控制块:
+----------------+
| 强引用计数      |
| 弱引用计数      |
| 删除器          |
| allocator 信息  |
+----------------+
```

---

## 9.3 `make_shared` vs `shared_ptr<T>(new T)`

推荐：

```cpp
auto p = std::make_shared<A>();
```

不推荐：

```cpp
std::shared_ptr<A> p(new A);
```

`make_shared` 优点：

1. 一次内存分配，对象和控制块通常一起分配；
2. 异常安全更好；
3. 性能更好，cache locality 更好。

但也有注意点：

- 如果对象很大，并且还有 `weak_ptr` 存活，对象内存可能要等控制块一起释放；
- 需要自定义删除器时，不能直接用 `make_shared` 指定删除器。

---

## 9.4 错误：同一个裸指针构造多个 `shared_ptr`

```cpp
A* raw = new A;

std::shared_ptr<A> p1(raw);
std::shared_ptr<A> p2(raw); // 严重错误
```

这会产生两个独立控制块，最终重复 delete，未定义行为。

正确做法：

```cpp
auto p1 = std::make_shared<A>();
auto p2 = p1;
```

---

## 9.5 `shared_ptr` 线程安全问题

要分清两层：

### 1）引用计数控制块通常是线程安全的

不同线程拷贝、销毁不同 `shared_ptr` 对象，引用计数更新是安全的。

```cpp
std::shared_ptr<int> p = std::make_shared<int>(1);

// 多线程中拷贝 p 的副本，引用计数自身通常安全
```

### 2）被管理对象本身不是自动线程安全

```cpp
auto p = std::make_shared<int>(0);

// 多线程同时 ++(*p) 不是线程安全
```

需要加锁或使用原子类型。

---

# 10. `weak_ptr`

## 面试问题

1. `weak_ptr` 是什么？
2. `weak_ptr` 是否增加强引用计数？
3. `weak_ptr` 如何访问对象？
4. `weak_ptr` 如何解决循环引用？
5. `expired()` 和 `lock()` 有什么区别？

仓库中总结：`weak_ptr` 共享但不拥有对象，可用于打破 `shared_ptr` 循环引用。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

## 10.1 基本用法

```cpp
#include <memory>
#include <iostream>

int main() {
    std::weak_ptr<int> wp;

    {
        auto sp = std::make_shared<int>(42);
        wp = sp;

        std::cout << sp.use_count() << '\n'; // 1

        if (auto locked = wp.lock()) {
            std::cout << *locked << '\n';
        }
    }

    if (wp.expired()) {
        std::cout << "object destroyed\n";
    }
}
```

`weak_ptr` 不增加强引用计数，不拥有对象。

访问对象前需要：

```cpp
auto sp = wp.lock();
```

如果对象已释放，`lock()` 返回空 `shared_ptr`。

---

# 11. 循环引用

## 面试问题

1. 什么是 `shared_ptr` 循环引用？
2. 为什么循环引用会导致内存泄漏？
3. 如何用 `weak_ptr` 解决？
4. 父子关系中谁用 `shared_ptr`，谁用 `weak_ptr`？

---

## 11.1 错误示例：循环引用

```cpp
#include <iostream>
#include <memory>

class B;

class A {
public:
    std::shared_ptr<B> b;

    ~A() {
        std::cout << "~A\n";
    }
};

class B {
public:
    std::shared_ptr<A> a;

    ~B() {
        std::cout << "~B\n";
    }
};

int main() {
    auto pa = std::make_shared<A>();
    auto pb = std::make_shared<B>();

    pa->b = pb;
    pb->a = pa;
}
```

程序结束时不会输出：

```text
~A
~B
```

原因：

```text
pa 外部引用释放后：
A 仍被 B::a 持有
B 仍被 A::b 持有

二者引用计数都不为 0
```

---

## 11.2 正确示例：用 `weak_ptr` 打破环

```cpp
#include <iostream>
#include <memory>

class B;

class A {
public:
    std::shared_ptr<B> b;

    ~A() {
        std::cout << "~A\n";
    }
};

class B {
public:
    std::weak_ptr<A> a;

    ~B() {
        std::cout << "~B\n";
    }
};

int main() {
    auto pa = std::make_shared<A>();
    auto pb = std::make_shared<B>();

    pa->b = pb;
    pb->a = pa;
}
```

输出：

```text
~A
~B
```

经验规则：

- 拥有关系用 `shared_ptr` 或 `unique_ptr`；
- 非拥有观察关系用 `weak_ptr` 或裸指针/引用；
- 父拥有子，子观察父：父到子用 `shared_ptr/unique_ptr`，子到父用 `weak_ptr`。

---

# 12. `enable_shared_from_this`

## 面试问题

1. 为什么不能直接用 `this` 构造 `shared_ptr`？
2. `enable_shared_from_this` 解决什么问题？
3. `shared_from_this()` 使用前提是什么？

---

## 12.1 错误示例

```cpp
#include <memory>

class A {
public:
    std::shared_ptr<A> getPtr() {
        return std::shared_ptr<A>(this); // 错误
    }
};

int main() {
    auto p1 = std::make_shared<A>();
    auto p2 = p1->getPtr(); // 两个控制块，最终 double delete
}
```

---

## 12.2 正确做法

```cpp
#include <memory>
#include <iostream>

class A : public std::enable_shared_from_this<A> {
public:
    std::shared_ptr<A> getPtr() {
        return shared_from_this();
    }

    ~A() {
        std::cout << "~A\n";
    }
};

int main() {
    auto p1 = std::make_shared<A>();
    auto p2 = p1->getPtr();

    std::cout << p1.use_count() << '\n'; // 2
}
```

注意：

```cpp
A a;
// a.getPtr(); // 错误，对象必须已由 shared_ptr 管理
```

`shared_from_this()` 的前提：

> 当前对象已经被某个 `shared_ptr` 正确管理。

---

# 13. `delete this`

## 面试问题

1. `delete this` 合法吗？
2. 使用 `delete this` 需要满足哪些条件？
3. `delete this` 后还能访问成员吗？
4. Qt/回调/异步场景中为什么要小心对象自删除？

仓库中也列出了 `delete this` 合法但需要确保对象由 `new` 创建，且之后不能再访问该对象等条件。 [[CMU 15-213...P - CS自学指南]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

---

## 13.1 示例

```cpp
class SelfDelete {
public:
    void destroy() {
        delete this;
    }

private:
    ~SelfDelete() = default;
};

int main() {
    SelfDelete* p = new SelfDelete;
    p->destroy();

    // p->destroy(); // 错误，p 已悬空
}
```

---

## 13.2 必须满足

`delete this` 只有在以下条件满足时才安全：

1. 对象确实由 `new` 创建；
2. 不是栈对象；
3. 不是全局对象；
4. 不是数组 `new[]` 创建；
5. 不是 placement new 创建；
6. `delete this` 后不再访问任何成员；
7. 外部也不再访问该对象。

---

# 14. 常见内存错误

## 面试问题

1. 什么是内存泄漏？
2. 什么是野指针？
3. 什么是悬空指针？
4. 什么是重复释放？
5. 什么是越界访问？
6. 如何排查内存问题？

---

## 14.1 内存泄漏

```cpp
void leak() {
    int* p = new int(10);
    // 忘记 delete
}
```

解决：

```cpp
void noLeak() {
    auto p = std::make_unique<int>(10);
}
```

---

## 14.2 悬空指针

```cpp
int* p = new int(10);
delete p;

*p = 20; // 错误，use-after-free
```

改进：

```cpp
delete p;
p = nullptr;
```

但更推荐：

```cpp
auto p = std::make_unique<int>(10);
```

---

## 14.3 重复释放

```cpp
int* p = new int(10);

delete p;
delete p; // 错误，double free
```

智能指针可以避免大部分这类问题。

---

## 14.4 越界访问

```cpp
int* arr = new int[3];

arr[3] = 10; // 越界，未定义行为

delete[] arr;
```

推荐：

```cpp
std::vector<int> arr(3);
arr.at(3) = 10; // 抛异常，便于发现错误
```

---

# 15. 面试高频对比总结

## 15.1 `unique_ptr` vs `shared_ptr` vs `weak_ptr`


| 智能指针         | 所有权 | 是否可拷贝    | 典型场景        |
| ------------ | --- | -------- | ----------- |
| `unique_ptr` | 独占  | 不可拷贝，可移动 | 明确单一所有者     |
| `shared_ptr` | 共享  | 可拷贝      | 多方共享生命周期    |
| `weak_ptr`   | 不拥有 | 可拷贝      | 观察对象，打破循环引用 |


---

## 15.2 什么时候用哪个？

优先级建议：

```text
默认优先 unique_ptr
确实需要共享生命周期时 shared_ptr
需要观察 shared_ptr 管理的对象但不拥有时 weak_ptr
非拥有且生命周期明确时，可以用裸指针/引用
```

---

## 15.3 不要滥用 `shared_ptr`

错误倾向：

```cpp
std::shared_ptr<T> everywhere;
```

问题：

- 所有权不清晰；
- 更容易产生循环引用；
- 引用计数有开销；
- 生命周期变得不可控；
- 难以判断对象何时释放。

更好的设计：

```cpp
class Owner {
private:
    std::unique_ptr<Resource> resource_;
};
```

---

# 16. 面试代码题

## 题 1：输出什么？

```cpp
#include <iostream>
#include <memory>

class A {
public:
    A() {
        std::cout << "ctor\n";
    }

    ~A() {
        std::cout << "dtor\n";
    }
};

int main() {
    std::shared_ptr<A> p1;

    {
        auto p2 = std::make_shared<A>();
        p1 = p2;
        std::cout << p2.use_count() << '\n';
    }

    std::cout << p1.use_count() << '\n';
}
```

答案：

```text
ctor
2
1
dtor
```

---

## 题 2：哪里有问题？

```cpp
int* p = new int[10];

delete p;
```

问题：

```cpp
new[] 必须配 delete[]
```

正确：

```cpp
delete[] p;
```

---

## 题 3：哪里有问题？

```cpp
class A {};

A* raw = new A;
std::shared_ptr<A> p1(raw);
std::shared_ptr<A> p2(raw);
```

问题：

```text
p1 和 p2 有两个独立控制块，会 double delete
```

正确：

```cpp
auto p1 = std::make_shared<A>();
auto p2 = p1;
```

---

## 题 4：循环引用如何修？

错误：

```cpp
class Node {
public:
    std::shared_ptr<Node> next;
    std::shared_ptr<Node> prev;
};
```

如果两个节点互指，会循环引用。

修正：

```cpp
class Node {
public:
    std::shared_ptr<Node> next;
    std::weak_ptr<Node> prev;
};
```

---

# 17. 面试速记版

## 内存管理

- `malloc/free` 是 C 函数，只分配/释放原始内存，不调用构造析构。
- `new/delete` 是 C++ 运算符，分配内存并构造对象，析构对象并释放内存。
- `new[]` 必须配 `delete[]`。
- `placement new` 不分配内存，只在指定地址构造对象。
- `delete nullptr` 和 `free(nullptr)` 都安全。
- 内存泄漏、重复释放、越界访问、use-after-free 都是未定义行为风险。

---

## RAII

- 资源生命周期绑定对象生命周期。
- 构造获取资源，析构释放资源。
- 异常安全的核心手段。
- 标准库中 `string`、`vector`、`unique_ptr`、`shared_ptr`、`lock_guard` 都是 RAII 思想。

---

## 智能指针

- `unique_ptr`：独占所有权，默认首选。
- `shared_ptr`：共享所有权，最后一个引用释放资源。
- `weak_ptr`：弱引用，不拥有对象，用于观察和打破循环引用。
- `make_unique` / `make_shared` 优先于裸 `new`。
- 不要用同一个裸指针构造多个 `shared_ptr`。
- `shared_ptr` 的引用计数安全不代表对象访问线程安全。

---

如果继续下一块，我建议讲：

> **STL 容器与底层实现：vector/list/deque/map/unorderedmap、迭代器失效、红黑树、哈希表、allocator。**

