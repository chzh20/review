**类型修饰、链接/作用域、对象模型、内存布局、现代 C++ 初始化与引用语义**

***

# 1. `const`：核心是“只读语义 + 类型系统约束”

## 面试提炼问题

* `const` 修饰变量、指针、引用、成员函数分别什么意思？
* `const int* p`、`int* const p`、`const int* const p` 区别？
* `const` 能否参与函数重载？
* `const` 成员函数中 `this` 是什么类型？
* 函数返回值加 `const` 有没有意义？

## 标准回答

### 1）修饰变量

```cpp
const int x = 10;
// x = 20; // error
```

表示 `x` 不可被修改。

***

### 2）修饰指针

```cpp
int a = 1;
int b = 2;

const int* p1 = &a;      // 指向 const int 的指针，不能通过 p1 修改 *p1
int* const p2 = &a;      // const 指针，p2 本身不能改指向
const int* const p3 = &a;// 指针本身和指向内容都不可改

// *p1 = 3;   // error
p1 = &b;      // ok

*p2 = 3;      // ok
// p2 = &b;   // error

// *p3 = 3;   // error
// p3 = &b;   // error
```

记忆法：  
**`const` 修饰它右边的东西；如果右边没有东西，就修饰左边。**

***

### 3）修饰引用

```cpp
void print(const std::string& s) {
    // s += "x"; // error
}
```

`const T&` 常用于函数参数：

* 避免拷贝；
* 防止函数内部修改实参；
* 可绑定临时对象。

所谓“没有 const reference”，意思是：

```cpp
int x = 1;
int& const r = x; // 非法/无意义
```

引用一旦绑定就不能改引用目标，所以“引用本身 const”没有意义；但可以有：

```cpp
const int& r = x; // 指向 const int 的引用
```

***

### 4）修饰成员函数

```cpp
class A {
public:
    int get() const {
        // value = 10; // error
        return value;
    }

    void set(int v) {
        value = v;
    }

private:
    int value = 0;
};
```

`const` 成员函数承诺不修改对象的逻辑状态。

在普通成员函数中：

```cpp
A* const this;
```

在 `const` 成员函数中：

```cpp
const A* const this;
```

所以不能修改成员变量，除非成员是 `mutable`。

```cpp
class Counter {
public:
    int get() const {
        ++access_count; // ok
        return value;
    }

private:
    int value = 0;
    mutable int access_count = 0;
};
```

***

### 5）`const` 可参与函数重载

```cpp
class A {
public:
    int& get() {
        return value;
    }

    const int& get() const {
        return value;
    }

private:
    int value = 0;
};
```

普通对象调用非 `const` 版本，`const` 对象调用 `const` 版本。

***

### 6）返回值加 `const`

对于内置类型返回值，意义不大：

```cpp
const int f() {
    return 1;
}
```

因为返回的是临时值，不能修改本来也没太大意义。

但返回引用或指针时有意义：

```cpp
class A {
public:
    const std::string& name() const {
        return name_;
    }

private:
    std::string name_;
};
```

这样调用者不能通过返回值修改内部成员。

***

# 2. 宏、`inline`、`constexpr`：核心是“预处理 vs 编译期语义”

## 面试提炼问题

* `#define` 和 `const` 区别？
* 宏函数和 `inline` 函数区别？
* `inline` 一定会内联吗？
* 虚函数能不能 `inline`？
* 为什么推荐 `const/enum/inline/constexpr` 替代宏？

## 标准回答

### 1）`#define` vs `const`

```cpp
#define MAX_SIZE 100
const int MaxSize = 100;
```

区别：

* `#define` 是预处理阶段文本替换；
* `const` 是编译器处理，有类型检查；
* `#define` 无作用域概念；
* `const` 遵守作用域和类型系统；
* `#define` 可能导致难查的替换问题。

***

### 2）宏函数 vs inline 函数

```cpp
#define SQUARE(x) ((x) * (x))

inline int square(int x) {
    return x * x;
}

int a = SQUARE(1 + 2); // ok，因为加了括号
int b = square(1 + 2);
```

宏函数危险示例：

```cpp
#define BAD_SQUARE(x) x * x

int y = BAD_SQUARE(1 + 2); 
// 展开为 1 + 2 * 1 + 2，结果是 5，不是 9
```

`inline` 的优势：

* 有类型检查；
* 遵守作用域；
* 可调试性更好；
* 不会发生宏的重复求值问题。

```cpp
#define MAX(a, b) ((a) > (b) ? (a) : (b))

int i = 1;
int j = 2;
int m = MAX(i++, j++); // i 或 j 可能被多次自增，危险
```

***

### 3）`inline` 不保证一定内联

```cpp
inline int add(int a, int b) {
    return a + b;
}
```

`inline` 只是建议，最终是否内联由编译器决定。

通常不容易内联的函数：

* 递归函数；
* 过大的函数；
* 包含复杂循环/switch 的函数；
* 通过基类指针发生动态绑定的虚函数。

***

### 4）虚函数可以是 `inline` 吗？

可以声明为 `inline`，但如果发生运行期多态，通常无法内联：

```cpp
class Base {
public:
    inline virtual void f() {}
};

class Derived : public Base {
public:
    void f() override {}
};

void call(Base* p) {
    p->f(); // 运行期决定调用哪个版本，通常不能内联
}

int main() {
    Base b;
    b.f(); // 编译期已知对象类型，可能内联
}
```

***

### 5）`constexpr`

`constexpr` 表示可以在编译期求值：

```cpp
constexpr int square(int x) {
    return x * x;
}

int arr[square(3)]; // 编译期常量，数组大小为 9
```

推荐：

```cpp
constexpr int MaxSize = 100;
```

替代：

```cpp
#define MAX_SIZE 100
```

***

# 3. `static`：核心是“存储期、链接属性、类共享成员”

## 面试提炼问题

* `static` 修饰局部变量、全局变量、函数、类成员变量、类成员函数分别什么意思？
* 静态局部变量什么时候初始化？
* 静态成员函数为什么不能访问非静态成员？
* `static` 和匿名 namespace 区别？

## 标准回答

### 1）静态局部变量

```cpp
void foo() {
    static int count = 0;
    ++count;
    std::cout << count << "\n";
}

int main() {
    foo(); // 1
    foo(); // 2
    foo(); // 3
}
```

特点：

* 生命周期贯穿整个程序；
* 作用域仍然限于函数内部；
* C++11 起，函数内局部静态变量初始化是线程安全的。

***

### 2）静态全局变量 / 静态函数

```cpp
// file1.cpp
static int g_value = 10;

static void helper() {}
```

表示内部链接，只能在当前翻译单元使用，避免符号冲突。

现代 C++ 更推荐匿名命名空间：

```cpp
namespace {
    int g_value = 10;

    void helper() {}
}
```

区别：

* `static` 是 C 风格做法；
* 匿名 namespace 是 C++ 风格；
* 匿名 namespace 可用于类型、函数、变量等，更统一。

***

### 3）静态成员变量

```cpp
class A {
public:
    static int count;
};

int A::count = 0;

int main() {
    A a1, a2;
    A::count = 10;
}
```

特点：

* 所有对象共享一份；
* 不属于某个具体对象；
* 需要类外定义，C++17 后可用 `inline static`。

```cpp
class B {
public:
    inline static int count = 0; // C++17
};
```

***

### 4）静态成员函数

```cpp
class A {
public:
    static void printCount() {
        std::cout << count << "\n";
        // std::cout << value; // error
    }

private:
    static int count;
    int value = 0;
};
```

静态成员函数没有 `this` 指针，所以不能直接访问非静态成员。

***

# 4. `this` 指针：核心是“成员函数隐式参数”

## 面试提炼问题

* `this` 是什么？
* 静态成员函数有没有 `this`？
* 普通成员函数和 `const` 成员函数中 `this` 类型是什么？
* 如何用 `this` 实现链式调用？
* 自赋值为什么要判断 `this == &rhs`？

## 标准回答

`this` 是非静态成员函数的隐式参数，指向当前对象。

```cpp
class A {
public:
    void set(int value) {
        this->value = value;
    }

private:
    int value = 0;
};
```

普通成员函数中：

```cpp
A* const this;
```

`const` 成员函数中：

```cpp
const A* const this;
```

***

## 链式调用

```cpp
class Builder {
public:
    Builder& setX(int x) {
        this->x = x;
        return *this;
    }

    Builder& setY(int y) {
        this->y = y;
        return *this;
    }

private:
    int x = 0;
    int y = 0;
};

int main() {
    Builder b;
    b.setX(1).setY(2);
}
```

***

## 自赋值判断

```cpp
class String {
public:
    String& operator=(const String& rhs) {
        if (this == &rhs) {
            return *this;
        }

        delete[] data;
        data = new char[std::strlen(rhs.data) + 1];
        std::strcpy(data, rhs.data);

        return *this;
    }

private:
    char* data = nullptr;
};
```

如果不判断自赋值，有可能先释放自己的资源，再从已经释放的资源中拷贝，导致未定义行为。

***

# 5. `volatile` / `assert` / `sizeof`

## 面试提炼问题

* `volatile` 有什么作用？能否保证线程安全？
* `assert` 是函数还是宏？如何关闭？
* `sizeof` 数组和指针区别？
* 空类大小是多少？

## 标准回答

### 1）`volatile`

```cpp
volatile int flag = 0;
```

含义：告诉编译器该变量可能被编译器不可见的因素修改，禁止某些优化，每次都从内存读取。

典型场景：

* 硬件寄存器；
* 信号处理；
* 某些嵌入式场景。

但注意：

> `volatile` 不保证原子性，不保证可见性同步，不保证线程安全。

线程同步应使用：

```cpp
std::atomic<int> flag{0};
```

***

### 2）`assert`

```cpp
#include <cassert>

void f(int* p) {
    assert(p != nullptr);
}
```

`assert` 是宏，不是函数。

关闭方式：

```cpp
#define NDEBUG
#include <cassert>
```

`assert` 不适合线上错误处理，因为 Release 版本可能被关闭。

***

### 3）`sizeof`

```cpp
int arr[10];
int* p = arr;

std::cout << sizeof(arr) << "\n"; // 10 * sizeof(int)
std::cout << sizeof(p) << "\n";   // 指针大小，64 位通常是 8
```

数组作为函数参数会退化为指针：

```cpp
void f(int arr[]) {
    std::cout << sizeof(arr) << "\n"; // 指针大小
}
```

***

### 4）空类大小

```cpp
class Empty {};

int main() {
    std::cout << sizeof(Empty) << "\n"; // 通常为 1
}
```

原因：不同对象必须有不同地址。

```cpp
Empty e1, e2;
std::cout << (&e1 == &e2) << "\n"; // false
```

***

# 6. 内存对齐与位域

## 面试提炼问题

* 什么是内存对齐？
* `#pragma pack`、`alignas`、`alignof` 的区别？
* 如何计算结构体大小？
* 位域能否取地址？是否跨平台一致？

## 标准回答

### 1）内存对齐

CPU 访问对齐地址通常更高效。结构体成员会按其对齐要求放置。

```cpp
struct A {
    char c; // 1 byte
    int i;  // 4 bytes
};
```

通常：

```cpp
sizeof(A) == 8
```

内存布局大致：

```cpp
c padding padding padding i i i i
```

***

### 2）结构体大小计算

规则：

1. 每个成员放在满足自身对齐要求的位置；
2. 整个结构体大小是最大对齐值的整数倍。

```cpp
#include <iostream>

struct B {
    char c;
    double d;
    int i;
};

int main() {
    std::cout << sizeof(B) << "\n";
}
```

通常为 24。

***

### 3）`#pragma pack`

```cpp
#pragma pack(push, 1)

struct Packed {
    char c;
    int i;
};

#pragma pack(pop)
```

`pack(1)` 会减少对齐，结构体可能变成 5 字节，但访问效率可能下降，且属于编译器扩展。

***

### 4）`alignas` / `alignof`

```cpp
#include <iostream>

struct alignas(16) A {
    int x;
};

int main() {
    std::cout << alignof(A) << "\n"; // 16
    std::cout << sizeof(A) << "\n";  // 通常 16
}
```

区别：

* `#pragma pack` 通常减少对齐；
* `alignas` 要求更高对齐，是 C++ 标准特性；
* `alignof(T)` 获取类型对齐要求。

***

### 5）位域

```cpp
struct Flags {
    unsigned int read  : 1;
    unsigned int write : 1;
    unsigned int exec  : 1;
};
```

位域用于节省空间或表达硬件/协议字段。

注意：

```cpp
Flags f;
// auto p = &f.read; // error，位域不能取地址
```

位域布局与编译器、平台、字节序有关，不应依赖其跨平台二进制布局。

***

# 7. `extern` 与 `extern "C"`

## 面试提炼问题

* `extern` 是什么？
* `extern "C"` 是什么？
* 为什么 C++ 混编需要 `extern "C"`？
* 什么是 name mangling？
* 头文件中定义全局变量有什么问题？

## 标准回答

### 1）`extern`

`extern` 声明变量或函数具有外部链接。

```cpp
// a.cpp
int g_value = 10;

// b.cpp
extern int g_value;
```

`extern` 声明不是定义。

***

### 2）头文件中定义全局变量的问题

错误示例：

```cpp
// common.h
int g_value = 10;
```

如果多个 `.cpp` 包含该头文件，会导致重复定义。

正确写法：

```cpp
// common.h
extern int g_value;

// common.cpp
int g_value = 10;
```

C++17 可以：

```cpp
// common.h
inline int g_value = 10;
```

***

### 3）`extern "C"`

C++ 支持函数重载，所以会对函数名做 name mangling。

```cpp
int add(int, int);
double add(double, double);
```

编译后符号名可能不同于 `add`。

为了让 C 代码能链接 C++ 函数：

```cpp
#ifdef __cplusplus
extern "C" {
#endif

int add(int a, int b);

#ifdef __cplusplus
}
#endif
```

实现：

```cpp
extern "C" int add(int a, int b) {
    return a + b;
}
```

`extern "C"` 作用：

* 禁止 C++ 名字修饰；
* 方便 C/C++ 混编；
* 常用于动态库导出稳定 C 接口。

但它不保证 ABI 完全兼容，只是解决链接符号名问题。

***

# 8. `struct` / `class` / `union` / `enum`

## 面试提炼问题

* `struct` 和 `class` 区别？
* C 和 C++ 中 `struct` 区别？
* `union` 有哪些限制？
* `enum` 和 `enum class` 区别？

## 标准回答

### 1）`struct` vs `class`

核心区别只有默认权限不同。

```cpp
struct S {
    int x; // public
};

class C {
    int x; // private
};
```

继承默认权限也不同：

```cpp
struct Derived1 : Base {}; // 默认 public 继承
class Derived2 : Base {};  // 默认 private 继承
```

习惯上：

* `struct` 表示简单数据聚合；
* `class` 表示有封装和行为的对象。

***

### 2）C 中 `typedef struct`

C 中：

```c
typedef struct Student {
    int age;
} Student;
```

如果没有 `typedef`，使用时要写：

```c
struct Student s;
```

C++ 中：

```cpp
struct Student {
    int age;
};

Student s; // 可以直接用
```

***

### 3）`union`

```cpp
union Value {
    int i;
    double d;
};

int main() {
    Value v;
    v.i = 10;
    v.d = 3.14; // 此时 i 的值不再可靠
}
```

特点：

* 所有成员共享同一块内存；
* 同一时刻只有一个有效成员；
* 大小通常等于最大成员大小，并满足对齐。

限制：

```cpp
union U {
    int x;
    // int& ref; // error，不能有引用成员
};
```

`union` 不能有虚函数，不能作为基类，也不能继承。

***

### 4）`enum` vs `enum class`

普通 `enum`：

```cpp
enum Color {
    Red,
    Green
};

int x = Red; // 可隐式转 int
```

`enum class`：

```cpp
enum class Color {
    Red,
    Green
};

Color c = Color::Red;
// int x = c; // error
int x = static_cast<int>(c);
```

更推荐 `enum class`：

* 强作用域；
* 不污染外部命名空间；
* 不隐式转换为整数；
* 类型安全。

***

# 9. `explicit` / `friend` / `using`

## 面试提炼问题

* `explicit` 如何防止隐式转换？
* 什么是复制初始化、直接初始化？
* 友元有什么特点？
* `using 声明` 和 `using 指示` 区别？
* `using Base::Base` 有什么作用？

## 标准回答

### 1）`explicit`

```cpp
class A {
public:
    A(int x) {}
};

void f(A a) {}

int main() {
    A a1(1); // 直接初始化
    A a2 = 1; // 复制初始化，允许隐式转换
    f(1);     // 允许 int -> A
}
```

加 `explicit`：

```cpp
class B {
public:
    explicit B(int x) {}
};

void g(B b) {}

int main() {
    B b1(1);     // ok
    // B b2 = 1; // error
    // g(1);     // error
    g(B(1));     // ok
}
```

***

### 2）`explicit operator bool`

```cpp
class File {
public:
    explicit operator bool() const {
        return opened;
    }

private:
    bool opened = true;
};

int main() {
    File f;

    if (f) {
        // ok，允许上下文转换为 bool
    }

    // bool b = f; // error
    bool b = static_cast<bool>(f); // ok
}
```

***

### 3）复制初始化 vs 直接初始化

```cpp
std::string s1("hello");  // 直接初始化
std::string s2 = "hello"; // 复制初始化
```

`explicit` 构造函数禁止复制初始化中的隐式转换。

***

### 4）友元

```cpp
class A {
    friend void print(const A& a);

private:
    int x = 10;
};

void print(const A& a) {
    std::cout << a.x << "\n";
}
```

特点：

* 友元可访问私有成员；
* 破坏封装，应谨慎使用；
* 友元关系不可传递；
* 友元关系不可继承；
* 友元关系不是双向的。

***

### 5）`using 声明` vs `using 指示`

```cpp
using std::cout;      // using 声明，引入一个名字
using namespace std;  // using 指示，引入整个命名空间
```

头文件里不建议：

```cpp
using namespace std;
```

因为会污染所有包含该头文件的翻译单元。

***

### 6）继承构造函数

```cpp
class Base {
public:
    Base(int x) {}
};

class Derived : public Base {
public:
    using Base::Base;
};

int main() {
    Derived d(1); // 调用 Base(int)
}
```

***

### 7）引入基类被隐藏的重载函数

```cpp
class Base {
public:
    void f(int) {}
    void f(double) {}
};

class Derived : public Base {
public:
    using Base::f;

    void f(const char*) {}
};

int main() {
    Derived d;
    d.f(1);       // ok
    d.f(3.14);    // ok
    d.f("hello"); // ok
}
```

如果没有 `using Base::f;`，派生类的 `f(const char*)` 会隐藏基类所有同名函数。

***

# 10. 引用、右值引用、`decltype`、初始化列表

## 面试提炼问题

* 指针和引用区别？
* 左值引用、右值引用是什么？
* 移动语义解决什么问题？
* 完美转发是什么？
* 引用折叠规则？
* `T&&` 一定是右值引用吗？
* `auto` 和 `decltype` 区别？
* 初始化列表有什么作用？
* `{1,2,3}` 为什么模板有时无法推导？

## 标准回答

### 1）指针 vs 引用

| 对比点      | 指针            | 引用              |
| -------- | ------------- | --------------- |
| 是否可为空    | 可以为 `nullptr` | 通常不能为空          |
| 是否可改绑定对象 | 可以改指向         | 绑定后不可改          |
| 是否需要解引用  | 需要 `*p`       | 直接使用            |
| 是否占存储    | 通常占           | 实现上通常类似指针，但语义不同 |

示例：

```cpp
int a = 1;
int b = 2;

int* p = &a;
p = &b; // ok

int& r = a;
// r = b; // 不是重新绑定，而是把 b 的值赋给 a
```

***

### 2）左值引用

```cpp
int x = 10;
int& r = x;
```

左值引用绑定有名称、可取地址的对象。

***

### 3）右值引用

```cpp
int&& r = 10;
```

右值引用绑定临时对象，主要用于：

* 移动语义；
* 完美转发。

***

### 4）移动语义

```cpp
#include <iostream>
#include <cstring>

class Buffer {
public:
    Buffer(size_t n)
        : size(n), data(new char[n]) {}

    ~Buffer() {
        delete[] data;
    }

    Buffer(const Buffer& other)
        : size(other.size), data(new char[other.size]) {
        std::memcpy(data, other.data, size);
        std::cout << "copy\n";
    }

    Buffer(Buffer&& other) noexcept
        : size(other.size), data(other.data) {
        other.size = 0;
        other.data = nullptr;
        std::cout << "move\n";
    }

private:
    size_t size;
    char* data;
};

int main() {
    Buffer a(1024);
    Buffer b = std::move(a); // move
}
```

移动语义避免深拷贝，提高性能。

注意：

```cpp
std::move(a)
```

本身不移动，只是把 `a` 转成右值引用，真正移动发生在移动构造/移动赋值里。

***

### 5）完美转发

```cpp
#include <utility>
#include <iostream>

void foo(int& x) {
    std::cout << "lvalue\n";
}

void foo(int&& x) {
    std::cout << "rvalue\n";
}

template <typename T>
void wrapper(T&& arg) {
    foo(std::forward<T>(arg));
}

int main() {
    int x = 1;

    wrapper(x);  // lvalue
    wrapper(1);  // rvalue
}
```

完美转发保留实参的左值/右值属性。

***

### 6）引用折叠

规则：

```cpp
T&  &  -> T&
T&  && -> T&
T&& &  -> T&
T&& && -> T&&
```

只要有一个 `&`，最终就是左值引用。

***

### 7）`T&&` 一定是右值引用吗？

不一定。

```cpp
template <typename T>
void f(T&& x) {}
```

这里的 `T&&` 是转发引用，也叫万能引用。

```cpp
int a = 1;
f(a); // T 推导为 int&，T&& 折叠为 int&
f(1); // T 推导为 int，T&& 是 int&&
```

但下面不是万能引用：

```cpp
void g(int&& x) {} // 纯右值引用
```

***

### 8）`decltype`

```cpp
int x = 10;
int& r = x;

decltype(x) a = 1; // int
decltype(r) b = x; // int&
```

特殊规则：

```cpp
int x = 10;

decltype(x) a = x;   // int
decltype((x)) b = x; // int&，因为 (x) 是左值表达式
```

***

### 9）`auto` vs `decltype`

```cpp
int x = 10;
int& r = x;

auto a = r;       // int，引用被忽略
decltype(r) b = x;// int&
```

`auto` 看初始化值，通常会丢掉顶层 `const` 和引用。

```cpp
const int c = 10;

auto x1 = c;        // int
decltype(c) x2 = 1; // const int
```

***

### 10）成员初始化列表

```cpp
class A {
public:
    A(int x, int& r)
        : const_value(x), ref(r), name("Danny") {}

private:
    const int const_value;
    int& ref;
    std::string name;
};
```

必须使用初始化列表的成员：

* `const` 成员；
* 引用成员；
* 没有默认构造函数的成员对象；
* 基类构造；
* 希望避免“默认构造 + 赋值”的额外开销。

***

### 11）`std::initializer_list`

```cpp
#include <initializer_list>
#include <iostream>

class Vector {
public:
    Vector(std::initializer_list<int> list) {
        for (int x : list) {
            std::cout << x << " ";
        }
    }
};

int main() {
    Vector v{1, 2, 3};
}
```

它支持花括号初始化。

***

### 12）花括号初始化特点

```cpp
int a{1};
std::vector<int> v{1, 2, 3};
```

优点：

* 统一初始化语法；
* 防止窄化转换。

```cpp
int x{3.14}; // error，防止窄化
int y = 3.14; // ok，但丢失精度
```

***

### 13）为什么 `{1,2,3}` 在模板参数推导里可能无法推导？

```cpp
template <typename T>
void f(T x) {}

int main() {
    // f({1, 2, 3}); // error
}
```

原因：

`{1,2,3}` 本身不是一个有独立类型的表达式，模板无法从它直接推导出 `T`。

解决方式：

```cpp
#include <initializer_list>
#include <vector>

template <typename T>
void f(std::initializer_list<T> list) {}

template <typename T>
void g(T x) {}

int main() {
    f({1, 2, 3}); // ok，T = int

    g(std::vector<int>{1, 2, 3}); // ok，T = std::vector<int>
}
```

***

# 面试速记版总结

## 高频一句话答案

* `const`：表达只读语义，让编译器帮助约束修改行为。
* `static`：控制生命周期、链接属性或类级共享。
* `inline`：请求编译器内联，同时解决头文件多定义问题。
* `volatile`：禁止编译器对变量访问做过度优化，但不保证线程安全。
* `this`：非静态成员函数的隐式对象指针。
* `extern "C"`：禁止 C++ 名字修饰，方便 C/C++ 链接。
* `struct/class`：默认访问权限和默认继承权限不同。
* `union`：多个成员共享同一块内存。
* `enum class`：强类型、强作用域枚举。
* `explicit`：防止不期望的隐式类型转换。
* `friend`：允许外部函数/类访问私有成员，但会破坏封装。
* `using`：可引入名字、继承构造函数、解除基类函数隐藏。
* 右值引用：服务于移动语义和完美转发。
* `std::move`：不移动，只是转换成右值。
* `std::forward`：保留值类别，实现完美转发。
* 初始化列表：直接构造成员，避免先默认构造再赋值。

***

如果你下一步要继续，我建议我们按这个节奏做：

1. **下一部分：面向对象与对象模型**  
   包括虚函数、虚表、虚析构、构造析构、多继承、虚继承。

2. **再下一部分：内存管理与智能指针**  
   包括 `malloc/free`、`new/delete`、placement new、`shared_ptr`、`weak_ptr`、循环引用。
