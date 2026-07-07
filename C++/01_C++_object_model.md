下面是 **C++ 面向对象与对象模型** 的面试提炼版，重点覆盖：**虚函数、虚表、虚析构、构造析构、多继承、虚继承**。这些内容也是 `huihut/interview` C/C++ 面向对象部分的高频主题：封装、继承、多态、虚函数、虚析构函数、纯虚函数、虚函数表、虚继承、抽象类等。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

# 1. 面向对象三大特性

## 面试问题

1. 面向对象三大特性是什么？
2. 什么是封装、继承、多态？
3. C++ 的多态有哪些类型？

## 答案

C++ 面向对象三大特性：

1. **封装**
   * 把数据和操作数据的方法封装在类中；
   * 对外暴露稳定接口；
   * 隐藏内部实现细节。

2. **继承**
   * 派生类复用基类的属性和行为；
   * 表达 `is-a` 关系。

3. **多态**
   * 同一接口在不同对象上表现出不同行为；
   * 分为编译期多态和运行期多态。

C++ 多态主要有：

| 类型    | 实现方式          | 绑定时间 |
| ----- | ------------- | ---- |
| 函数重载  | 同名函数不同参数      | 编译期  |
| 运算符重载 | `operator+` 等 | 编译期  |
| 模板    | 函数模板、类模板      | 编译期  |
| 虚函数   | `virtual`     | 运行期  |

***

## 示例

```cpp
#include <iostream>

class Shape {
public:
    virtual double area() const = 0;

    virtual ~Shape() = default;
};

class Circle : public Shape {
public:
    explicit Circle(double r) : r_(r) {}

    double area() const override {
        return 3.14159 * r_ * r_;
    }

private:
    double r_;
};

class Rectangle : public Shape {
public:
    Rectangle(double w, double h) : w_(w), h_(h) {}

    double area() const override {
        return w_ * h_;
    }

private:
    double w_;
    double h_;
};

void printArea(const Shape& s) {
    std::cout << s.area() << '\n';
}

int main() {
    Circle c(2.0);
    Rectangle r(3.0, 4.0);

    printArea(c); // 调 Circle::area
    printArea(r); // 调 Rectangle::area
}
```

这里 `printArea` 通过基类引用调用虚函数，实际执行哪个函数由运行期对象类型决定。

***

# 2. 虚函数

## 面试问题

1. 什么是虚函数？
2. 虚函数如何实现运行期多态？
3. 普通函数、静态函数、构造函数能否是虚函数？
4. 虚函数和纯虚函数有什么区别？
5. `override` 和 `final` 有什么作用？

***

## 2.1 什么是虚函数？

用 `virtual` 修饰的成员函数叫虚函数。

```cpp
class Base {
public:
    virtual void foo() {
        std::cout << "Base::foo\n";
    }
};
```

虚函数的核心作用是：

> 通过基类指针或引用调用成员函数时，根据对象的真实类型决定调用哪个函数。

***

## 2.2 虚函数实现动态绑定

```cpp
#include <iostream>

class Base {
public:
    virtual void foo() {
        std::cout << "Base::foo\n";
    }
};

class Derived : public Base {
public:
    void foo() override {
        std::cout << "Derived::foo\n";
    }
};

int main() {
    Derived d;

    Base* p = &d;
    Base& r = d;

    p->foo(); // Derived::foo
    r.foo(); // Derived::foo

    Base b = d;
    b.foo(); // Base::foo，对象切片
}
```

重点：

* 通过 **基类指针/引用** 调用虚函数，才有运行期多态；
* 如果发生对象切片，只剩基类部分，多态消失。

***

## 2.3 哪些函数不能是虚函数？

### 普通非成员函数不能是虚函数

```cpp
// virtual void f(); // error
```

虚函数机制依赖对象和 `this` 指针，普通函数不属于对象。

***

### 静态成员函数不能是虚函数

```cpp
class A {
public:
    // virtual static void f(); // error
};
```

原因：

* 静态成员函数没有 `this` 指针；
* 虚函数调用依赖对象中的虚表指针；
* 静态函数不属于具体对象。

***

### 构造函数不能是虚函数

```cpp
class A {
public:
    // virtual A(); // error
};
```

原因：

* 构造对象时，对象还没有完全形成；
* 虚表指针需要在构造过程中建立；
* 调用构造函数本身之前无法通过虚表分派。

***

### 析构函数可以且经常应该是虚函数

尤其是多态基类。

```cpp
class Base {
public:
    virtual ~Base() = default;
};
```

***

## 2.4 虚函数和纯虚函数

### 虚函数

```cpp
class Base {
public:
    virtual void foo() {
        std::cout << "Base::foo\n";
    }
};
```

派生类可以重写，也可以不重写。

***

### 纯虚函数

```cpp
class Base {
public:
    virtual void foo() = 0;
};
```

含有纯虚函数的类是抽象类，不能直接实例化。

```cpp
class Derived : public Base {
public:
    void foo() override {
        std::cout << "Derived::foo\n";
    }
};
```

***

## 2.5 纯虚函数可以有函数体吗？

可以。

```cpp
#include <iostream>

class Base {
public:
    virtual void foo() = 0;
};

void Base::foo() {
    std::cout << "Base::foo body\n";
}

class Derived : public Base {
public:
    void foo() override {
        Base::foo();
        std::cout << "Derived::foo\n";
    }
};

int main() {
    Derived d;
    d.foo();
}
```

纯虚函数有函数体时，仍然要求派生类实现它，否则派生类仍是抽象类。

***

## 2.6 `override` 和 `final`

### `override`

显式告诉编译器：这个函数必须重写基类虚函数。

```cpp
class Base {
public:
    virtual void foo(int) {}
};

class Derived : public Base {
public:
    void foo(int) override {}
};
```

如果写错签名，编译器会报错：

```cpp
class Derived2 : public Base {
public:
    // void foo(double) override {} // error，不是真正 override
};
```

***

### `final`

禁止派生类继续重写。

```cpp
class Base {
public:
    virtual void foo() final {}
};

class Derived : public Base {
public:
    // void foo() override {} // error
};
```

也可以禁止类被继承：

```cpp
class FinalClass final {};
```

***

# 3. 虚表与虚指针

## 面试问题

1. 什么是虚函数表？
2. 什么是虚函数指针？
3. 虚表在哪里？虚指针在哪里？
4. 一个类多个对象是否共享虚表？
5. 虚函数调用大概发生了什么？
6. 虚函数会增加对象大小吗？

***

## 3.1 基本概念

通常实现中：

* **虚函数表 vtable**
  * 保存虚函数地址的表；
  * 每个多态类通常有一张或多张虚表。

* **虚函数指针 vptr**
  * 对象内部隐藏的指针；
  * 指向该对象所属动态类型的虚表。

`huihut/interview` 也总结到：含有虚函数的类对象中通常有虚函数指针，虚函数表用于存放虚函数地址，派生类重写虚函数时会覆盖虚表中的对应函数地址。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

## 3.2 示例

```cpp
#include <iostream>

class Base {
public:
    virtual void f1() {
        std::cout << "Base::f1\n";
    }

    virtual void f2() {
        std::cout << "Base::f2\n";
    }

    int x = 1;
};

class Derived : public Base {
public:
    void f1() override {
        std::cout << "Derived::f1\n";
    }

    int y = 2;
};

int main() {
    Base b;
    Derived d;

    Base* p = &d;
    p->f1(); // Derived::f1
    p->f2(); // Base::f2

    std::cout << sizeof(Base) << '\n';
    std::cout << sizeof(Derived) << '\n';
}
```

大致虚表结构：

```text
Base vtable:
+----------------+
| &Base::f1      |
| &Base::f2      |
+----------------+

Derived vtable:
+----------------+
| &Derived::f1   |
| &Base::f2      |
+----------------+
```

对象大致布局：

```text
Base object:
+-------+
| vptr  |
+-------+
| x     |
+-------+

Derived object:
+-------+
| vptr  |
+-------+
| x     |
+-------+
| y     |
+-------+
```

注意：这是常见实现模型，不是 C++ 标准强制规定的具体布局。

***

## 3.3 虚函数调用过程

表达式：

```cpp
p->f1();
```

大致等价于：

```text
1. 通过 p 找到对象
2. 通过对象中的 vptr 找到 vtable
3. 从 vtable 找到 f1 对应槽位
4. 调用该函数指针
```

***

## 3.4 虚函数的开销

主要开销：

1. 对象中多一个 `vptr`；
2. 调用虚函数时多一次间接寻址；
3. 编译器较难内联；
4. 可能影响 cache 和优化。

但实际工程中，虚函数开销通常不是瓶颈，除非在极高频路径中。

***

# 4. 虚析构函数

## 面试问题

1. 为什么多态基类析构函数要声明为 `virtual`？
2. 如果基类析构函数不是虚函数会发生什么？
3. 哪些类需要虚析构函数？
4. 纯虚析构函数是否需要定义？

***

## 4.1 为什么需要虚析构？

看错误示例：

```cpp
#include <iostream>

class Base {
public:
    ~Base() {
        std::cout << "~Base\n";
    }
};

class Derived : public Base {
public:
    ~Derived() {
        std::cout << "~Derived\n";
    }
};

int main() {
    Base* p = new Derived;
    delete p; // 未定义行为，通常只调用 ~Base
}
```

可能输出：

```text
~Base
```

`Derived` 的析构没有执行，派生类资源可能泄漏。

***

## 4.2 正确做法

```cpp
#include <iostream>

class Base {
public:
    virtual ~Base() {
        std::cout << "~Base\n";
    }
};

class Derived : public Base {
public:
    ~Derived() override {
        std::cout << "~Derived\n";
    }
};

int main() {
    Base* p = new Derived;
    delete p;
}
```

输出：

```text
~Derived
~Base
```

析构顺序：

```text
先派生类析构，再基类析构
```

***

## 4.3 什么时候需要虚析构？

如果一个类满足下面条件，通常应有虚析构函数：

1. 作为基类使用；
2. 有虚函数；
3. 可能通过基类指针删除派生类对象。

```cpp
class Interface {
public:
    virtual void run() = 0;
    virtual ~Interface() = default;
};
```

***

## 4.4 纯虚析构函数

纯虚析构函数也必须有定义。

```cpp
class Base {
public:
    virtual ~Base() = 0;
};

Base::~Base() {}
```

原因：

派生类析构完成后，仍然要调用基类析构函数。

***

# 5. 构造与析构

## 面试问题

1. 构造顺序是什么？
2. 析构顺序是什么？
3. 构造函数和析构函数中调用虚函数会发生什么？
4. 成员初始化顺序由什么决定？
5. 拷贝构造和赋值运算符区别？
6. 析构函数为什么不应该抛异常？

***

## 5.1 构造顺序

```cpp
#include <iostream>

class Base {
public:
    Base() {
        std::cout << "Base ctor\n";
    }

    ~Base() {
        std::cout << "Base dtor\n";
    }
};

class Member {
public:
    Member() {
        std::cout << "Member ctor\n";
    }

    ~Member() {
        std::cout << "Member dtor\n";
    }
};

class Derived : public Base {
public:
    Derived() {
        std::cout << "Derived ctor\n";
    }

    ~Derived() {
        std::cout << "Derived dtor\n";
    }

private:
    Member m_;
};

int main() {
    Derived d;
}
```

输出：

```text
Base ctor
Member ctor
Derived ctor
Derived dtor
Member dtor
Base dtor
```

构造顺序：

```text
基类 -> 成员对象 -> 派生类自身
```

析构顺序相反：

```text
派生类自身 -> 成员对象 -> 基类
```

***

## 5.2 成员初始化顺序

成员初始化顺序由 **成员声明顺序** 决定，不由初始化列表顺序决定。

```cpp
#include <iostream>

class A {
public:
    A() : y_(1), x_(y_) {}

    void print() {
        std::cout << "x = " << x_ << ", y = " << y_ << '\n';
    }

private:
    int x_;
    int y_;
};
```

虽然初始化列表写的是 `y_` 在前，但实际先初始化 `x_`，因为 `x_` 先声明。

更安全写法：

```cpp
class B {
public:
    B() : y_(1), x_(1) {}

private:
    int y_;
    int x_;
};
```

或者按声明顺序写初始化列表。

***

## 5.3 构造/析构中调用虚函数

```cpp
#include <iostream>

class Base {
public:
    Base() {
        foo();
    }

    virtual ~Base() {
        foo();
    }

    virtual void foo() {
        std::cout << "Base::foo\n";
    }
};

class Derived : public Base {
public:
    void foo() override {
        std::cout << "Derived::foo\n";
    }
};

int main() {
    Derived d;
}
```

输出通常是：

```text
Base::foo
Base::foo
```

原因：

* 基类构造期间，派生类部分尚未构造完成；
* 基类析构期间，派生类部分已经析构；
* 所以构造/析构中的虚函数不会动态分派到派生类版本。

面试答案：

> 不要在构造函数和析构函数中依赖虚函数多态。

***

## 5.4 拷贝构造 vs 拷贝赋值

```cpp
class A {
public:
    A() = default;

    A(const A& other) {
        std::cout << "copy ctor\n";
    }

    A& operator=(const A& other) {
        std::cout << "copy assignment\n";
        return *this;
    }
};

int main() {
    A a;
    A b = a; // copy ctor

    A c;
    c = a;   // copy assignment
}
```

区别：

* 拷贝构造：用已有对象创建新对象；
* 拷贝赋值：两个对象都已存在，把右边内容赋给左边。

***

## 5.5 析构函数不要抛异常

```cpp
class A {
public:
    ~A() noexcept {
        // 不应抛异常
    }
};
```

原因：

* 如果栈展开过程中析构函数再抛异常，程序可能调用 `std::terminate`；
* 析构函数应吞掉异常、记录日志，或提供单独 `close()` 函数让用户显式处理错误。

***

# 6. 多继承

## 面试问题

1. 多继承下对象布局是什么样？
2. 多继承可能有什么问题？
3. 什么是二义性？
4. 多继承下虚函数表可能有几张？
5. 为什么要谨慎使用多继承？

***

## 6.1 简单多继承

```cpp
#include <iostream>

class A {
public:
    int a = 1;
};

class B {
public:
    int b = 2;
};

class C : public A, public B {
public:
    int c = 3;
};

int main() {
    C obj;

    A* pa = &obj;
    B* pb = &obj;

    std::cout << &obj << '\n';
    std::cout << pa << '\n';
    std::cout << pb << '\n';
}
```

`pa` 和 `pb` 的地址可能不同。

大致布局：

```text
C object:
+-------------+
| A subobject |
+-------------+
| B subobject |
+-------------+
| C members   |
+-------------+
```

***

## 6.2 多继承二义性

```cpp
class A {
public:
    void foo() {}
};

class B {
public:
    void foo() {}
};

class C : public A, public B {};

int main() {
    C c;
    // c.foo(); // error，二义性

    c.A::foo(); // ok
    c.B::foo(); // ok
}
```

***

## 6.3 多继承下虚函数

```cpp
#include <iostream>

class A {
public:
    virtual void fa() {
        std::cout << "A::fa\n";
    }

    virtual ~A() = default;
};

class B {
public:
    virtual void fb() {
        std::cout << "B::fb\n";
    }

    virtual ~B() = default;
};

class C : public A, public B {
public:
    void fa() override {
        std::cout << "C::fa\n";
    }

    void fb() override {
        std::cout << "C::fb\n";
    }
};
```

多继承下，一个对象中可能有多个基类子对象，也可能有多个 `vptr`。

大致布局：

```text
C object:
+----------------+
| A::vptr        |
| A part         |
+----------------+
| B::vptr        |
| B part         |
+----------------+
| C members      |
+----------------+
```

***

## 6.4 多继承的合理使用

多继承不是绝对不能用，常见合理场景：

```cpp
class Runnable {
public:
    virtual void run() = 0;
    virtual ~Runnable() = default;
};

class NonCopyable {
protected:
    NonCopyable() = default;
    ~NonCopyable() = default;

    NonCopyable(const NonCopyable&) = delete;
    NonCopyable& operator=(const NonCopyable&) = delete;
};

class Task : public Runnable, private NonCopyable {
public:
    void run() override {}
};
```

一种常见建议：

> public 继承接口类，private 继承实现辅助类。

***

# 7. 虚继承

## 面试问题

1. 什么是菱形继承？
2. 菱形继承有什么问题？
3. 虚继承解决什么问题？
4. 虚继承对象布局有什么额外成本？
5. 虚基类由谁构造？

***

## 7.1 菱形继承问题

```cpp
#include <iostream>

class A {
public:
    int value = 1;
};

class B : public A {};
class C : public A {};

class D : public B, public C {};

int main() {
    D d;

    // d.value = 10; // error，二义性

    d.B::value = 10;
    d.C::value = 20;

    std::cout << d.B::value << '\n'; // 10
    std::cout << d.C::value << '\n'; // 20
}
```

问题：

```text
D 中有两份 A 子对象：
D
├── B
│   └── A
└── C
    └── A
```

导致：

* 数据冗余；
* 访问二义性。

***

## 7.2 使用虚继承解决

```cpp
#include <iostream>

class A {
public:
    int value = 1;
};

class B : virtual public A {};
class C : virtual public A {};

class D : public B, public C {};

int main() {
    D d;

    d.value = 100; // ok，只有一份 A

    std::cout << d.B::value << '\n';
    std::cout << d.C::value << '\n';
    std::cout << d.value << '\n';
}
```

虚继承后：

```text
D
├── B
├── C
└── shared A
```

`D` 中只有一份共享的 `A` 子对象。

`huihut/interview` 中也提到，虚继承用于解决多继承下菱形继承导致的存储浪费和二义性问题。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

## 7.3 虚继承的构造顺序

```cpp
#include <iostream>

class A {
public:
    A(int x) {
        std::cout << "A: " << x << '\n';
    }
};

class B : virtual public A {
public:
    B() : A(1) {
        std::cout << "B\n";
    }
};

class C : virtual public A {
public:
    C() : A(2) {
        std::cout << "C\n";
    }
};

class D : public B, public C {
public:
    D() : A(3), B(), C() {
        std::cout << "D\n";
    }
};

int main() {
    D d;
}
```

输出：

```text
A: 3
B
C
D
```

重点：

> 虚基类由最派生类负责构造。

这里 `D` 是最派生类，所以由 `D()` 中的 `A(3)` 构造虚基类 `A`。

如果创建的是 `B` 对象，则由 `B` 构造 `A`。

***

## 7.4 虚继承的成本

虚继承通常会引入额外开销：

* 对象中可能额外保存虚基类表指针；
* 访问虚基类成员可能需要通过偏移表间接访问；
* 对象布局更复杂；
* 构造、赋值、类型转换更复杂。

`huihut/interview` 中也总结到，虚继承通常通过虚基类指针和虚基类表实现，虚基类表记录虚基类相对本类的偏移，用于找到共享虚基类成员。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

# 8. 虚函数 vs 虚继承

这是面试常考对比。

| 对比点      | 虚函数           | 虚继承                    |
| -------- | ------------- | ---------------------- |
| 解决问题     | 运行期多态         | 菱形继承中基类重复              |
| 关键机制     | vptr + vtable | vbptr + vbtable，具体实现相关 |
| 表中存什么    | 虚函数地址         | 虚基类偏移                  |
| 是否影响对象大小 | 通常增加 vptr     | 通常增加额外指针/偏移信息          |
| 典型使用     | 接口、多态         | 多继承共享公共基类              |

***

# 9. 对象切片

## 面试问题

1. 什么是对象切片？
2. 为什么对象切片会导致多态失效？
3. 如何避免？

***

## 示例

```cpp
#include <iostream>

class Base {
public:
    virtual void foo() const {
        std::cout << "Base\n";
    }

    virtual ~Base() = default;
};

class Derived : public Base {
public:
    void foo() const override {
        std::cout << "Derived\n";
    }

private:
    int extra = 100;
};

void callByValue(Base b) {
    b.foo();
}

void callByRef(const Base& b) {
    b.foo();
}

int main() {
    Derived d;

    callByValue(d); // Base，对象切片
    callByRef(d);   // Derived
}
```

结论：

> 多态对象应该通过指针或引用传递，不要按值传递基类对象。

***

# 10. 面试高频代码题：判断输出

## 题 1：构造析构顺序

```cpp
#include <iostream>

class A {
public:
    A() { std::cout << "A ctor\n"; }
    virtual ~A() { std::cout << "A dtor\n"; }
};

class B : public A {
public:
    B() { std::cout << "B ctor\n"; }
    ~B() override { std::cout << "B dtor\n"; }
};

int main() {
    A* p = new B;
    delete p;
}
```

输出：

```text
A ctor
B ctor
B dtor
A dtor
```

***

## 题 2：构造函数中调用虚函数

```cpp
#include <iostream>

class A {
public:
    A() {
        foo();
    }

    virtual void foo() {
        std::cout << "A::foo\n";
    }

    virtual ~A() = default;
};

class B : public A {
public:
    B() = default;

    void foo() override {
        std::cout << "B::foo\n";
    }
};

int main() {
    B b;
}
```

输出：

```text
A::foo
```

原因：构造 `A` 部分时，`B` 部分尚未构造完成。

***

## 题 3：默认参数和虚函数

```cpp
#include <iostream>

class Base {
public:
    virtual void foo(int x = 1) {
        std::cout << "Base x = " << x << '\n';
    }

    virtual ~Base() = default;
};

class Derived : public Base {
public:
    void foo(int x = 2) override {
        std::cout << "Derived x = " << x << '\n';
    }
};

int main() {
    Derived d;
    Base* p = &d;

    p->foo();
}
```

输出：

```text
Derived x = 1
```

原因：

* 虚函数调用是动态绑定；
* 默认参数是静态绑定，取决于指针静态类型 `Base*`。

***

# 11. 面试速记总结

## 虚函数

* 用于运行期多态；
* 通过基类指针/引用调用才体现；
* 底层通常依赖 `vptr + vtable`；
* 构造函数不能是虚函数；
* 静态函数不能是虚函数；
* 析构函数可以且常应该是虚函数。

***

## 虚表

* 虚表存虚函数地址；
* 对象中通常有虚指针；
* 多个对象共享类的虚表；
* 派生类重写虚函数会替换虚表对应槽位；
* 多继承下可能有多个虚指针。

***

## 虚析构

* 多态基类必须重点考虑虚析构；
* 通过基类指针删除派生类对象时，只有虚析构才能正确析构完整对象；
* 析构顺序：派生类 -> 成员 -> 基类。

***

## 构造析构

* 构造顺序：虚基类 -> 直接基类 -> 成员 -> 自身；
* 析构顺序相反；
* 成员初始化顺序由声明顺序决定；
* 构造/析构中不要依赖虚函数多态；
* 析构函数不应抛异常。

***

## 多继承

* 会形成多个基类子对象；
* 可能导致名称二义性；
* 多态多继承下可能有多个 `vptr`；
* 应谨慎使用，常见合理用法是“接口多继承”。

***

## 虚继承

* 解决菱形继承中公共基类重复问题；
* 虚基类只有一份；
* 虚基类由最派生类构造；
* 代价是对象布局和访问更复杂。

***

如果你继续准备下一块，我建议顺序是：

> **内存管理与智能指针：`malloc/free`、`new/delete`、placement new、RAII、`unique_ptr/shared_ptr/weak_ptr`、循环引用、对象生命周期。**
