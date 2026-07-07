下面是 **STL 容器与底层实现** 的面试提炼版，重点覆盖：

* `vector`
* `deque`
* `list / forward_list`
* `array`
* `stack / queue / priority_queue`
* `map / set / multimap / multiset`
* `unordered_map / unordered_set`
* 迭代器失效
* 红黑树
* 哈希表
* `allocator`
* 常见面试代码题

`huihut/interview` 中 STL 部分也把常见容器按底层结构、复杂度、有序性、是否允许重复进行了整理，比如 `vector` 底层是数组，`map/set` 底层是红黑树，`unordered_map/unordered_set` 底层是哈希表。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

# 1. STL 容器总览

## 面试核心问题

1. STL 容器分哪几类？
2. `vector/list/deque/map/unordered_map` 底层分别是什么？
3. 哪些容器支持随机访问？
4. 哪些容器插入删除快？
5. 哪些容器查找快？
6. 哪些容器会导致迭代器失效？
7. `map` 和 `unordered_map` 如何选择？

***

## 1.1 容器分类

STL 容器大致分为：

```text
顺序容器：
vector
deque
list
forward_list
array

关联容器：
set
multiset
map
multimap

无序关联容器：
unordered_set
unordered_multiset
unordered_map
unordered_multimap

容器适配器：
stack
queue
priority_queue
```

***

## 1.2 高频底层结构表

| 容器               | 底层结构   | 是否有序   | 查找复杂度       | 插入删除特点              |
| ---------------- | ------ | ------ | ----------- | ------------------- |
| `vector`         | 动态数组   | 按插入顺序  | 按值查找 `O(n)` | 尾插快，中间插入慢           |
| `deque`          | 分段连续数组 | 按插入顺序  | 按值查找 `O(n)` | 头尾插入快               |
| `list`           | 双向链表   | 按插入顺序  | `O(n)`      | 任意位置插删快             |
| `forward_list`   | 单向链表   | 按插入顺序  | `O(n)`      | 插删快，占用更小            |
| `map`            | 红黑树    | key 有序 | `O(log n)`  | 插删查稳定               |
| `set`            | 红黑树    | key 有序 | `O(log n)`  | key 不重复             |
| `unordered_map`  | 哈希表    | 无序     | 平均 `O(1)`   | 可能 rehash           |
| `unordered_set`  | 哈希表    | 无序     | 平均 `O(1)`   | key 不重复             |
| `priority_queue` | 堆      | 堆序     | top `O(1)`  | push/pop `O(log n)` |

***

# 2. `vector`

## 面试问题

1. `vector` 底层是什么？
2. `vector` 为什么支持随机访问？
3. `vector` 扩容机制是什么？
4. `size()` 和 `capacity()` 区别？
5. `resize()` 和 `reserve()` 区别？
6. `push_back()` 和 `emplace_back()` 区别？
7. `vector` 迭代器什么时候失效？
8. 为什么 `vector` 头部插入慢？
9. 如何释放 `vector` 多余容量？
10. `vector<bool>` 有什么特殊？

***

## 2.1 底层结构

`vector` 底层是 **连续动态数组**。

通常内部维护三个指针：

```text
begin     end       capacity_end
 |         |             |
 v         v             v
+---------+-------------+
| used    | unused      |
+---------+-------------+
```

大致类似：

```cpp
template <typename T>
class VectorLike {
private:
    T* begin_;
    T* end_;
    T* cap_;
};
```

因为内存连续，所以支持：

```cpp
v[i]
*(v.begin() + i)
```

随机访问复杂度为 `O(1)`。

***

## 2.2 `size` vs `capacity`

```cpp
#include <iostream>
#include <vector>

int main() {
    std::vector<int> v;

    std::cout << v.size() << " " << v.capacity() << "\n";

    v.reserve(10);

    std::cout << v.size() << " " << v.capacity() << "\n";

    v.push_back(1);
    v.push_back(2);

    std::cout << v.size() << " " << v.capacity() << "\n";
}
```

可能输出：

```text
0 0
0 10
2 10
```

区别：

* `size()`：当前元素个数；
* `capacity()`：当前已分配空间最多能容纳多少元素。

***

## 2.3 `reserve` vs `resize`

```cpp
std::vector<int> v;

v.reserve(10);
// 只改变 capacity，不创建元素

v.resize(10);
// 改变 size，创建 10 个元素
```

示例：

```cpp
#include <iostream>
#include <vector>

int main() {
    std::vector<int> v;

    v.reserve(5);
    std::cout << "size = " << v.size()
              << ", capacity = " << v.capacity() << "\n";

    v.resize(5);
    std::cout << "size = " << v.size()
              << ", capacity = " << v.capacity() << "\n";
}
```

输出类似：

```text
size = 0, capacity = 5
size = 5, capacity = 5
```

***

## 2.4 扩容机制

当 `size == capacity` 时，再插入元素会触发扩容：

```text
1. 分配更大的新内存
2. 将旧元素 move/copy 到新内存
3. 析构旧元素
4. 释放旧内存
5. 插入新元素
```

示例：

```cpp
#include <iostream>
#include <vector>

int main() {
    std::vector<int> v;

    for (int i = 0; i < 10; ++i) {
        v.push_back(i);
        std::cout << "size = " << v.size()
                  << ", capacity = " << v.capacity() << "\n";
    }
}
```

不同 STL 实现扩容倍率可能不同，常见是 1.5 倍或 2 倍。

***

## 2.5 迭代器失效

### 情况 1：扩容导致所有迭代器、指针、引用失效

```cpp
std::vector<int> v;
v.reserve(2);

v.push_back(1);
v.push_back(2);

auto it = v.begin();
int* p = &v[0];

v.push_back(3); // 可能扩容

// it、p 都可能失效
```

原因：底层数组可能搬到新地址。

***

### 情况 2：中间插入/删除导致部分迭代器失效

```cpp
std::vector<int> v{1, 2, 3, 4};

auto it = v.begin() + 2;

v.insert(v.begin() + 1, 100);

// 插入位置及其后的迭代器通常失效
```

***

## 2.6 `push_back` vs `emplace_back`

```cpp
#include <iostream>
#include <vector>
#include <string>

class Person {
public:
    Person(std::string name, int age)
        : name_(std::move(name)), age_(age) {
        std::cout << "ctor\n";
    }

    Person(const Person&) {
        std::cout << "copy\n";
    }

    Person(Person&&) noexcept {
        std::cout << "move\n";
    }

private:
    std::string name_;
    int age_;
};

int main() {
    std::vector<Person> v;
    v.reserve(2);

    Person p("Danny", 30);
    v.push_back(p);                    // copy
    v.emplace_back("Chen", 31);         // 原地构造
}
```

区别：

* `push_back(obj)`：把已有对象拷贝/移动进去；
* `emplace_back(args...)`：在容器内部直接构造对象。

但如果参数本身已经是对象：

```cpp
v.emplace_back(p);
```

也可能调用拷贝构造，不是永远更快。

***

## 2.7 如何释放多余容量？

```cpp
std::vector<int> v;
v.reserve(1000);
v.resize(10);

v.shrink_to_fit(); // 请求释放多余容量，不保证一定执行
```

常见强制方式：

```cpp
std::vector<int>(v).swap(v);
```

C++11 后常用：

```cpp
v.shrink_to_fit();
```

***

## 2.8 `vector<bool>`

`vector<bool>` 是特化版本，不一定按 `bool` 一个字节存储，而是按 bit 压缩。

问题：

```cpp
std::vector<bool> vb{true, false};

// auto p = &vb[0]; // 通常不行，因为 vb[0] 返回代理对象，不是真 bool&
```

面试回答：

> `vector<bool>` 为节省空间做了位压缩特化，元素访问返回代理对象，不是真正的 `bool&`，可能带来意外行为。

***

# 3. `deque`

## 面试问题

1. `deque` 底层是什么？
2. `deque` 和 `vector` 区别？
3. `deque` 为什么头尾插入都快？
4. `deque` 是否支持随机访问？
5. `deque` 迭代器为什么比 `vector` 复杂？

***

## 3.1 底层结构

`deque` 不是单块连续数组，而是 **分段连续存储**。

大致结构：

```text
map 控制中心
+----+----+----+----+
| p0 | p1 | p2 | p3 |
+----+----+----+----+
  |    |    |    |
  v    v    v    v
[buffer][buffer][buffer][buffer]
```

每个 buffer 是一段连续空间，整体逻辑上像连续数组。

***

## 3.2 特点

| 对比             | `vector` | `deque`     |
| -------------- | -------- | ----------- |
| 内存             | 单块连续     | 分段连续        |
| 随机访问           | 支持，快     | 支持，但略复杂     |
| 头部插入           | 慢，`O(n)` | 快，接近 `O(1)` |
| 尾部插入           | 快        | 快           |
| 扩容             | 整体搬迁     | 增加 buffer   |
| cache locality | 更好       | 略差          |

***

## 3.3 示例

```cpp
#include <deque>
#include <iostream>

int main() {
    std::deque<int> dq;

    dq.push_back(1);
    dq.push_front(0);
    dq.push_back(2);

    std::cout << dq[0] << " "
              << dq[1] << " "
              << dq[2] << "\n";
}
```

输出：

```text
0 1 2
```

***

## 3.4 适用场景

适合：

* 需要频繁头尾插入删除；
* 仍然需要随机访问；
* 不要求底层完全连续内存。

不适合：

* 需要传给 C API 的连续内存；
* 极端追求 cache locality。

***

# 4. `list` / `forward_list`

## 面试问题

1. `list` 底层是什么？
2. `list` 和 `vector` 区别？
3. `list` 插入删除为什么快？
4. `list` 为什么不支持随机访问？
5. `forward_list` 和 `list` 有什么区别？
6. `list` 的迭代器什么时候失效？

***

## 4.1 `list` 底层结构

`list` 是双向链表。

```text
node <-> node <-> node <-> node
```

每个节点通常包含：

```cpp
template <typename T>
struct ListNode {
    T value;
    ListNode* prev;
    ListNode* next;
};
```

***

## 4.2 插入删除

```cpp
#include <list>
#include <iostream>

int main() {
    std::list<int> lst{1, 2, 4};

    auto it = lst.begin();
    std::advance(it, 2);

    lst.insert(it, 3); // 1 2 3 4

    for (int x : lst) {
        std::cout << x << " ";
    }
}
```

在已知位置插入删除是 `O(1)`。  
但找到位置需要遍历，通常是 `O(n)`。

***

## 4.3 为什么不支持随机访问？

链表节点不是连续内存，不能通过地址偏移直接访问第 `i` 个元素。

```cpp
std::list<int> lst{1, 2, 3};

// lst[1]; // error
```

必须遍历：

```cpp
auto it = lst.begin();
std::advance(it, 1);
```

***

## 4.4 迭代器失效

`list` 插入不会导致已有迭代器失效。

```cpp
std::list<int> lst{1, 2, 3};

auto it = std::next(lst.begin());

lst.push_front(0);
lst.push_back(4);

// it 仍然有效，指向 2
```

删除某个节点，只会使指向该节点的迭代器失效：

```cpp
auto it = std::next(lst.begin());

lst.erase(it);

// it 失效，其他迭代器仍有效
```

***

## 4.5 `forward_list`

`forward_list` 是单向链表。

特点：

* 只支持向前遍历；
* 内存开销比 `list` 小；
* 没有 `size()`，某些实现/标准设计中为保持轻量；
* 插入删除需要前驱节点。

```cpp
#include <forward_list>
#include <iostream>

int main() {
    std::forward_list<int> fl{1, 2, 3};

    fl.push_front(0);

    for (int x : fl) {
        std::cout << x << " ";
    }
}
```

***

# 5. 容器适配器

## 面试问题

1. `stack` 底层默认是什么？
2. `queue` 底层默认是什么？
3. `priority_queue` 底层是什么？
4. 为什么 `priority_queue` 用堆？
5. 如何自定义大根堆/小根堆？

***

## 5.1 `stack`

`stack` 是容器适配器，默认底层通常是 `deque`。

```cpp
#include <stack>
#include <iostream>

int main() {
    std::stack<int> st;

    st.push(1);
    st.push(2);

    std::cout << st.top() << "\n"; // 2

    st.pop();
}
```

也可以指定底层容器：

```cpp
std::stack<int, std::vector<int>> st;
```

***

## 5.2 `queue`

```cpp
#include <queue>
#include <iostream>

int main() {
    std::queue<int> q;

    q.push(1);
    q.push(2);

    std::cout << q.front() << "\n"; // 1

    q.pop();
}
```

默认底层通常是 `deque`。

***

## 5.3 `priority_queue`

默认是大根堆，底层通常是 `vector + heap`。

```cpp
#include <queue>
#include <iostream>

int main() {
    std::priority_queue<int> pq;

    pq.push(3);
    pq.push(1);
    pq.push(5);

    std::cout << pq.top() << "\n"; // 5
}
```

小根堆：

```cpp
#include <queue>
#include <vector>
#include <functional>
#include <iostream>

int main() {
    std::priority_queue<
        int,
        std::vector<int>,
        std::greater<int>
    > pq;

    pq.push(3);
    pq.push(1);
    pq.push(5);

    std::cout << pq.top() << "\n"; // 1
}
```

***

# 6. `map` / `set`

## 面试问题

1. `map` 底层是什么？
2. `map` 为什么有序？
3. `map` 查找复杂度是多少？
4. `map` 和 `set` 区别？
5. `map` 和 `multimap` 区别？
6. `operator[]` 和 `find()` 区别？
7. 为什么 `map` 常用红黑树？

`huihut/interview` 中也总结：`set/multiset/map/multimap` 底层为红黑树，插入、删除、查找复杂度为 `O(log n)`。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

## 6.1 `map` 底层

`map` 通常由红黑树实现。

特点：

* key 自动有序；
* key 唯一；
* 查找、插入、删除 `O(log n)`；
* 迭代器按 key 有序遍历。

```cpp
#include <map>
#include <iostream>

int main() {
    std::map<std::string, int> age;

    age["Danny"] = 30;
    age["Alice"] = 25;
    age["Bob"] = 28;

    for (const auto& [name, value] : age) {
        std::cout << name << " " << value << "\n";
    }
}
```

输出按 key 排序：

```text
Alice 25
Bob 28
Danny 30
```

***

## 6.2 `map` vs `set`

| 容器         | 存储内容      | key 是否唯一 |
| ---------- | --------- | -------- |
| `set`      | key       | 唯一       |
| `map`      | key-value | key 唯一   |
| `multiset` | key       | 可重复      |
| `multimap` | key-value | key 可重复  |

***

## 6.3 `operator[]` vs `find`

```cpp
std::map<std::string, int> m;

m["Danny"] = 1;
```

`operator[]` 如果 key 不存在，会插入默认值。

```cpp
std::cout << m["Unknown"] << "\n";
```

这会插入：

```cpp
{"Unknown", 0}
```

如果只是查找，不想插入，应使用：

```cpp
auto it = m.find("Unknown");
if (it != m.end()) {
    std::cout << it->second << "\n";
}
```

C++20 可用：

```cpp
if (m.contains("Danny")) {
}
```

***

## 6.4 自定义 key 排序

```cpp
#include <map>
#include <iostream>

struct Desc {
    bool operator()(int a, int b) const {
        return a > b;
    }
};

int main() {
    std::map<int, std::string, Desc> m;

    m[1] = "one";
    m[3] = "three";
    m[2] = "two";

    for (const auto& [k, v] : m) {
        std::cout << k << " ";
    }
}
```

输出：

```text
3 2 1
```

***

# 7. 红黑树

## 面试问题

1. 红黑树是什么？
2. 红黑树有哪些性质？
3. 为什么红黑树近似平衡？
4. 红黑树和 AVL 树区别？
5. 为什么 `map/set` 常用红黑树？

***

## 7.1 红黑树性质

红黑树是一种近似平衡二叉搜索树，常见性质：

1. 节点是红色或黑色；
2. 根节点是黑色；
3. 叶子 NIL 节点是黑色；
4. 红色节点不能有红色孩子；
5. 从任一节点到其所有后代 NIL 节点路径上的黑色节点数相同。

***

## 7.2 为什么能保持近似平衡？

红黑树限制了最长路径不会超过最短路径的两倍。

所以查找、插入、删除都能保持 `O(log n)`。

***

## 7.3 红黑树 vs AVL 树

| 对比       | 红黑树   | AVL 树   |
| -------- | ----- | ------- |
| 平衡性      | 近似平衡  | 更严格平衡   |
| 查找       | 稍慢一点  | 更快一点    |
| 插入删除     | 旋转较少  | 旋转较多    |
| 适合场景     | 插删频繁  | 查找频繁    |
| STL 关联容器 | 常用红黑树 | 较少用 AVL |

***

## 7.4 为什么 `map/set` 用红黑树？

综合考虑：

* 查找 `O(log n)`；
* 插入删除 `O(log n)`；
* 保持有序遍历；
* 插入删除旋转次数相对 AVL 少；
* 更适合通用场景。

***

# 8. `unordered_map` / `unordered_set`

## 面试问题

1. `unordered_map` 底层是什么？
2. 哈希表如何实现？
3. 哈希冲突怎么解决？
4. `unordered_map` 查找复杂度是多少？
5. 什么是 bucket？
6. 什么是 load factor？
7. 什么是 rehash？
8. 如何自定义 hash？
9. `unordered_map` 和 `map` 如何选择？

`huihut/interview` 中也总结：`unordered_set/unordered_map` 底层是哈希表，平均插入、删除、查找复杂度为 `O(1)`，最差为 `O(n)`。 [\[CMU 15-213...P - CS自学指南\]](https://csdiy.wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%B3%BB%E7%BB%9F%E5%9F%BA%E7%A1%80/CSAPP/#_1)

***

## 8.1 哈希表底层

典型结构：

```text
bucket array
+----+----+----+----+
| 0  | 1  | 2  | 3  |
+----+----+----+----+
  |         |
 node      node -> node
```

通过：

```text
bucket_index = hash(key) % bucket_count
```

定位桶。

***

## 8.2 基本用法

```cpp
#include <unordered_map>
#include <iostream>

int main() {
    std::unordered_map<std::string, int> m;

    m["Danny"] = 30;
    m["Alice"] = 25;

    auto it = m.find("Danny");
    if (it != m.end()) {
        std::cout << it->second << "\n";
    }
}
```

***

## 8.3 哈希冲突

不同 key 可能得到相同 bucket。

常见处理方式：

1. 链地址法；
2. 开放定址法。

STL `unordered_map` 常见实现使用链地址法或类似结构。

***

## 8.4 load factor

```cpp
std::unordered_map<int, int> m;

std::cout << m.bucket_count() << "\n";
std::cout << m.load_factor() << "\n";
std::cout << m.max_load_factor() << "\n";
```

含义：

```text
load_factor = size / bucket_count
```

当负载因子过高，冲突变多，性能下降，于是触发 rehash。

***

## 8.5 rehash

```cpp
#include <unordered_map>
#include <iostream>

int main() {
    std::unordered_map<int, int> m;

    m.reserve(1000); // 提前预留，减少 rehash

    for (int i = 0; i < 1000; ++i) {
        m[i] = i;
    }
}
```

`rehash` 会重新分配 bucket，并把元素重新映射到新 bucket 中。

注意：

> rehash 会导致迭代器失效。

***

## 8.6 自定义 hash

```cpp
#include <unordered_map>
#include <iostream>

struct Point {
    int x;
    int y;

    bool operator==(const Point& other) const {
        return x == other.x && y == other.y;
    }
};

struct PointHash {
    std::size_t operator()(const Point& p) const {
        return std::hash<int>{}(p.x) ^ (std::hash<int>{}(p.y) << 1);
    }
};

int main() {
    std::unordered_map<Point, std::string, PointHash> m;

    m[{1, 2}] = "A";

    std::cout << m[{1, 2}] << "\n";
}
```

***

# 9. `map` vs `unordered_map`

## 面试高频对比

| 对比    | `map`      | `unordered_map`     |
| ----- | ---------- | ------------------- |
| 底层    | 红黑树        | 哈希表                 |
| 是否有序  | key 有序     | 无序                  |
| 查找复杂度 | `O(log n)` | 平均 `O(1)`，最坏 `O(n)` |
| 插入删除  | `O(log n)` | 平均 `O(1)`           |
| 内存    | 树节点指针开销    | bucket + 节点开销       |
| 范围查询  | 支持         | 不适合                 |
| 自定义要求 | 比较函数       | hash + equality     |
| 迭代顺序  | 稳定有序       | 不稳定、无序              |

***

## 选择建议

用 `map`：

* 需要 key 有序；
* 需要范围查询；
* 需要稳定的 `O(log n)`；
* 数据量不大，性能差异不明显；
* 需要 `lower_bound / upper_bound`。

用 `unordered_map`：

* 只需要快速查找；
* 不关心顺序；
* hash 函数质量可控；
* 平均性能优先。

***

## 示例：范围查询只能用 `map` 更自然

```cpp
#include <map>
#include <iostream>

int main() {
    std::map<int, std::string> m;

    m[10] = "a";
    m[20] = "b";
    m[30] = "c";
    m[40] = "d";

    auto begin = m.lower_bound(15);
    auto end = m.upper_bound(35);

    for (auto it = begin; it != end; ++it) {
        std::cout << it->first << " " << it->second << "\n";
    }
}
```

输出：

```text
20 b
30 c
```

***

# 10. 迭代器失效总结

## 面试问题

1. 什么是迭代器失效？
2. `vector` 什么时候迭代器失效？
3. `list` 什么时候迭代器失效？
4. `map` 什么时候迭代器失效？
5. `unordered_map` 什么时候迭代器失效？
6. 删除元素时如何安全遍历？

***

## 10.1 `vector`

| 操作    | 是否失效          |
| ----- | ------------- |
| 扩容    | 所有迭代器、引用、指针失效 |
| 未扩容尾插 | `end()` 失效    |
| 中间插入  | 插入位置及之后失效     |
| 删除元素  | 删除位置及之后失效     |

安全删除：

```cpp
std::vector<int> v{1, 2, 3, 4, 5};

for (auto it = v.begin(); it != v.end(); ) {
    if (*it % 2 == 0) {
        it = v.erase(it);
    } else {
        ++it;
    }
}
```

***

## 10.2 `list`

| 操作 | 是否失效          |
| -- | ------------- |
| 插入 | 不影响已有迭代器      |
| 删除 | 只有被删除元素的迭代器失效 |

```cpp
std::list<int> lst{1, 2, 3, 4};

for (auto it = lst.begin(); it != lst.end(); ) {
    if (*it % 2 == 0) {
        it = lst.erase(it);
    } else {
        ++it;
    }
}
```

***

## 10.3 `map/set`

| 操作 | 是否失效         |
| -- | ------------ |
| 插入 | 不影响已有迭代器     |
| 删除 | 只有被删除元素迭代器失效 |

```cpp
std::map<int, int> m{{1, 1}, {2, 2}, {3, 3}};

for (auto it = m.begin(); it != m.end(); ) {
    if (it->first % 2 == 0) {
        it = m.erase(it);
    } else {
        ++it;
    }
}
```

***

## 10.4 `unordered_map`

| 操作         | 是否失效                   |
| ---------- | ---------------------- |
| 插入不 rehash | 通常不影响已有元素引用，但迭代器规则需看操作 |
| rehash     | 所有迭代器失效                |
| 删除         | 被删除元素迭代器失效             |

安全建议：

```cpp
std::unordered_map<int, int> m;

m.reserve(1000); // 减少插入过程中的 rehash
```

***

# 11. `allocator`

## 面试问题

1. `allocator` 是什么？
2. 容器为什么需要 allocator？
3. allocator 做了哪两件事？
4. 分配内存和构造对象有什么区别？
5. `vector` 内部为什么要区分 allocate 和 construct？

***

## 11.1 核心概念

STL 容器需要做两件事：

```text
1. 分配原始内存
2. 在内存上构造对象
```

`allocator` 把这两个步骤分开。

***

## 11.2 示例

```cpp
#include <memory>
#include <iostream>
#include <string>

int main() {
    std::allocator<std::string> alloc;

    std::string* p = alloc.allocate(3); // 只分配原始内存，不构造对象

    std::allocator_traits<std::allocator<std::string>>::construct(
        alloc, p, "hello"
    );

    std::allocator_traits<std::allocator<std::string>>::construct(
        alloc, p + 1, "world"
    );

    std::cout << p[0] << " " << p[1] << "\n";

    std::allocator_traits<std::allocator<std::string>>::destroy(alloc, p);
    std::allocator_traits<std::allocator<std::string>>::destroy(alloc, p + 1);

    alloc.deallocate(p, 3);
}
```

重点：

* `allocate`：只分配内存；
* `construct`：在指定位置构造对象；
* `destroy`：析构对象；
* `deallocate`：释放内存。

***

## 11.3 `allocator` 和 placement new 的关系

本质上，构造阶段类似 placement new：

```cpp
new (p) T(args...);
```

析构阶段类似：

```cpp
p->~T();
```

***

# 12. 容器选择策略

## 面试问题

1. 频繁尾插用什么？
2. 频繁头尾插入用什么？
3. 频繁中间插删用什么？
4. 需要有序 key-value 用什么？
5. 需要最快 key 查询用什么？
6. 需要范围查询用什么？

***

## 12.1 选择建议

```text
默认优先 vector
头尾频繁插删：deque
任意位置频繁插删且已知位置：list
有序 key-value：map
有序唯一 key：set
无序快速 key-value：unordered_map
无序快速唯一 key：unordered_set
堆顶最大/最小：priority_queue
固定大小数组：array
```

***

## 12.2 实战建议

### 默认用 `vector`

因为：

* 内存连续；
* cache 友好；
* 随机访问快；
* 尾插性能好；
* STL 算法支持好。

除非明确需要其他特性，否则优先 `vector`。

***

### 不要因为“中间插删”无脑用 `list`

虽然 `list` 已知位置插删是 `O(1)`，但实际中：

* 找位置是 `O(n)`；
* 节点分散，cache 不友好；
* 每个节点额外存两个指针；
* 现代 CPU 下 `vector` 可能更快。

***

# 13. 面试高频代码题

## 题 1：`vector` 迭代器失效

```cpp
#include <vector>
#include <iostream>

int main() {
    std::vector<int> v;
    v.reserve(2);

    v.push_back(1);
    v.push_back(2);

    auto it = v.begin();

    v.push_back(3);

    std::cout << *it << "\n"; // 有什么问题？
}
```

答案：

```text
push_back(3) 可能触发扩容，it 失效，解引用是未定义行为。
```

***

## 题 2：`map operator[]`

```cpp
#include <map>
#include <iostream>

int main() {
    std::map<std::string, int> m;

    std::cout << m["Danny"] << "\n";
    std::cout << m.size() << "\n";
}
```

输出：

```text
0
1
```

原因：

```text
operator[] 在 key 不存在时会插入一个默认值。
```

***

## 题 3：`unordered_map` rehash

```cpp
#include <unordered_map>
#include <iostream>

int main() {
    std::unordered_map<int, int> m;

    m[1] = 1;
    auto it = m.begin();

    for (int i = 2; i < 10000; ++i) {
        m[i] = i;
    }

    // it 可能已经失效
}
```

原因：

```text
大量插入可能触发 rehash，rehash 会导致迭代器失效。
```

***

## 题 4：删除偶数

错误写法：

```cpp
std::vector<int> v{1, 2, 3, 4};

for (auto it = v.begin(); it != v.end(); ++it) {
    if (*it % 2 == 0) {
        v.erase(it);
    }
}
```

问题：

```text
erase 后 it 失效，for 循环继续 ++it 是未定义行为。
```

正确写法：

```cpp
for (auto it = v.begin(); it != v.end(); ) {
    if (*it % 2 == 0) {
        it = v.erase(it);
    } else {
        ++it;
    }
}
```

***

# 14. 面试速记版

## 容器底层

* `vector`：连续动态数组。
* `deque`：分段连续数组。
* `list`：双向链表。
* `forward_list`：单向链表。
* `map/set`：红黑树。
* `unordered_map/unordered_set`：哈希表。
* `priority_queue`：堆，通常基于 `vector`。

***

## 复杂度

* `vector` 随机访问 `O(1)`，尾插均摊 `O(1)`。
* `list` 已知位置插删 `O(1)`，查找 `O(n)`。
* `map` 查找/插入/删除 `O(log n)`。
* `unordered_map` 平均查找/插入/删除 `O(1)`，最坏 `O(n)`。
* `priority_queue` top `O(1)`，push/pop `O(log n)`。

***

## 迭代器失效

* `vector`：扩容全部失效，中间插删影响后续。
* `list`：插入不影响，删除只影响被删元素。
* `map/set`：插入不影响，删除只影响被删元素。
* `unordered_map`：rehash 全部迭代器失效。

***

## 选择策略

* 默认：`vector`
* 头尾操作：`deque`
* 已知位置大量插删：`list`
* 有序映射：`map`
* 快速哈希查找：`unordered_map`
* 优先级队列：`priority_queue`
* 固定大小：`array`

***

下一块建议继续讲：

> **算法与数据结构面试高频：排序、二分、链表、树、哈希、堆、DFS/BFS、动态规划基础。**
