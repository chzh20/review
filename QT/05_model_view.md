# Qt Model/View 架构技术文章提纲

## 文章定位

* **目标读者**：具备基本 C++ 和 Qt Widgets 开发经验的工程师
* **技术范围**：以 Qt 6 Widgets 的 Model/View 框架为主，兼顾 Qt 5 常见项目
* **学习目标**：
  * 理解 Qt Model/View 的设计思想
  * 掌握 Model、View、Delegate、Selection Model 和 Proxy Model 的职责
  * 能够实现可靠的自定义列表、表格和树模型
  * 理解模型更新、索引生命周期及性能优化
  * 能够排查工程中常见的 Model/View Bug

Qt 的 Model/View 并不完全等同于经典 MVC：View 与 Controller 的职责在视图组件中有所结合，同时通过 Delegate 负责数据项的绘制和编辑。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/model-view-programming.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/zh/model-view-programming.html)

***

## 一、为什么需要 Model/View

### 1.1 从一个真实问题开始

通过一个“文件列表”或“测试结果列表”的案例，引出传统写法的问题：

* 业务数据保存一份
* `QTableWidgetItem` 中又保存一份
* 数据修改后需要手工同步 UI
* 排序、过滤后，界面行号不再等于业务对象下标
* 大数据量下创建大量 Item，内存和刷新成本较高
* UI 与业务数据高度耦合，难以测试和复用

### 1.2 Item-Based 与 Model/View-Based 控件

对比以下两类控件：

* `QListWidget` 与 `QListView`
* `QTableWidget` 与 `QTableView`
* `QTreeWidget` 与 `QTreeView`

重点说明：

> Widget 类自己拥有数据项；View 类通过统一接口访问外部 Model。

Qt 官方文档也指出，在非简单应用中，传统 Item-Based 控件容易产生两份数据之间的同步问题，而 Model/View 通过标准化接口访问外部数据，可以减少数据复制和耦合。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/modelview.html)

### 1.3 什么时候应该使用 Model/View

* 数据来自业务对象、文件、数据库或后台服务
* 同一份数据需要在多个视图中显示
* 需要排序、过滤、分组或树形展示
* 数据量较大
* UI 需要频繁增量更新
* 需要自定义显示与编辑行为
* 需要长期维护和自动化测试

***

## 二、Qt Model/View 的总体架构

### 2.1 五个核心角色

1. **Model**
   * 描述数据结构
   * 提供数据访问接口
   * 通知外界数据变化

2. **View**
   * 展示 Model 中的数据
   * 处理滚动、展开、鼠标和键盘交互

3. **Delegate**
   * 绘制单元格
   * 创建编辑器
   * 在编辑器与 Model 之间传递数据

4. **Selection Model**
   * 管理当前项和选择区域
   * 将“选择状态”与具体 View 解耦

5. **Proxy Model**
   * 在源 Model 和 View 之间进行排序、过滤和数据转换

### 2.2 组件协作关系

```text
             用户操作
                │
                ▼
┌────────┐   QModelIndex   ┌──────────┐
│  View  │ ◄─────────────► │  Model   │
└────┬───┘                 └────┬─────┘
     │                           │
     │ 绘制与编辑                │ 业务数据
     ▼                           ▼
┌──────────┐              ┌──────────────┐
│ Delegate │              │ Data Source  │
└──────────┘              └──────────────┘

     View ───── QItemSelectionModel
       │
       └──── Proxy Model ──── Source Model
```

### 2.3 信号与槽在架构中的作用

* Model 发出信号，通知 View 数据发生变化
* View 发出信号，描述用户交互
* Delegate 发出信号，通知提交或关闭编辑器
* Selection Model 发出信号，通知当前项和选择变化

***

## 三、理解 `QModelIndex`：Model/View 的关键抽象

### 3.1 `QModelIndex` 是什么

需要重点澄清：

* 它不是数据对象
* 它不是业务数据的所有者
* 它是 Model 中某个数据项的临时定位句柄
* 主要包含：
  * `row`
  * `column`
  * `parent`
  * 所属 Model
  * 内部标识

### 3.2 表格模型与树模型中的索引

表格模型：

```text
index(row, column)
```

树模型：

```text
index(row, column, parent)
```

重点解释：

> 树节点的 row 必须在其 parent 的局部范围内理解，而不是全局行号。

### 3.3 `QModelIndex` 与 `QPersistentModelIndex`

讨论：

* 普通 `QModelIndex` 的生命周期
* 模型结构改变后，缓存索引为什么危险
* 哪些场景需要 `QPersistentModelIndex`
* Persistent Index 也不是业务对象 ID 的替代品
* 长期保存时应优先保存稳定的业务标识

### 3.4 `internalPointer()` 与 `internalId()`

* 树模型如何将索引关联到内部节点
* 指针所有权不属于 `QModelIndex`
* 节点删除后的悬空指针风险
* 使用稳定 ID 和使用裸指针的取舍

***

## 四、Model 接口体系与职责边界

### 4.1 Model 类层次

```text
QAbstractItemModel
├── QAbstractListModel
├── QAbstractTableModel
├── QStringListModel
├── QStandardItemModel
├── QFileSystemModel
└── SQL Models
```

Qt 的所有 Item Model 都基于 `QAbstractItemModel`；对于列表和表格数据，通常应该优先继承 `QAbstractListModel` 或 `QAbstractTableModel`，因为它们提供了更合适的默认实现。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/model-view-programming.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/zh/model-view-programming.html)

### 4.2 最重要的虚函数

基础只读模型：

```cpp
int rowCount(const QModelIndex& parent) const override;
int columnCount(const QModelIndex& parent) const override;
QVariant data(const QModelIndex& index, int role) const override;
```

可编辑模型：

```cpp
bool setData(
    const QModelIndex& index,
    const QVariant& value,
    int role) override;

Qt::ItemFlags flags(const QModelIndex& index) const override;
```

树模型：

```cpp
QModelIndex index(
    int row,
    int column,
    const QModelIndex& parent) const override;

QModelIndex parent(const QModelIndex& index) const override;
```

动态结构：

```cpp
bool insertRows(
    int row,
    int count,
    const QModelIndex& parent) override;

bool removeRows(
    int row,
    int count,
    const QModelIndex& parent) override;
```

### 4.3 Model 不应该承担哪些职责

* 不直接操作 View
* 不依赖某个具体页面
* 不保存单元格 Widget
* 不把选中状态混入业务数据
* 不在 `data()` 中执行高成本 I/O
* 不通过行号长期标识业务对象

***

## 五、Role：同一数据项的多维表达

### 5.1 常用标准 Role

* `Qt::DisplayRole`
* `Qt::EditRole`
* `Qt::DecorationRole`
* `Qt::ToolTipRole`
* `Qt::StatusTipRole`
* `Qt::CheckStateRole`
* `Qt::ForegroundRole`
* `Qt::BackgroundRole`
* `Qt::FontRole`
* `Qt::TextAlignmentRole`
* `Qt::UserRole`

### 5.2 为什么需要 Role

一个单元格并不只有“显示文本”，它还可能包含：

* 业务 ID
* 原始数值
* 显示字符串
* 状态图标
* Tooltip
* 编辑值
* 排序键
* 颜色和字体

### 5.3 自定义 Role 的设计

```cpp
enum CustomRole {
    ObjectIdRole = Qt::UserRole + 1,
    RawValueRole,
    StatusRole,
    SortKeyRole
};
```

讨论以下工程原则：

* Role 命名要表达语义
* 显示值和排序值应适当分离
* 不要让 Proxy Model 解析格式化后的字符串
* `QVariant` 中复杂对象的类型注册问题

### 5.4 `roleNames()` 与 QML

作为扩展章节说明：

* Qt Widgets 中 Role 主要通过整数访问
* QML Delegate 常通过 Role 名称访问数据
* C++ Model 暴露给 QML 时需要考虑 `roleNames()`

Qt Quick 同样采用 Model、View、Delegate 的分工：Model 保存数据及结构，View 负责数据容器，Delegate 决定每个数据项如何显示和交互。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/qtquick-modelviewsdata-modelview.html)

***

## 六、View：数据是如何被展示出来的

### 6.1 标准 View

* `QListView`
* `QTableView`
* `QTreeView`
* 基类 `QAbstractItemView`

### 6.2 View 的重要配置

* 选择模式
* 选择行为
* 编辑触发方式
* 排序开关
* 行列隐藏
* Header 配置
* Tree 的展开与折叠
* Drag & Drop
* 滚动模式
* Uniform Row Height

### 6.3 View 与 Model 的连接

```cpp
view->setModel(model);
view->setSelectionModel(selectionModel);
view->setItemDelegate(delegate);
```

### 6.4 不要将 View 的 row 当成业务 ID

重点分析排序和过滤后的映射问题：

```text
View Index
    │
    ▼
Proxy Index
    │ mapToSource()
    ▼
Source Index
    │
    ▼
Business Object ID
```

***

## 七、Delegate：绘制与编辑的完整链路

### 7.1 Delegate 的核心职责

* 根据 Model 数据绘制单元格
* 为可编辑项创建编辑器
* 将 Model 数据写入编辑器
* 将编辑结果提交回 Model
* 控制编辑器的位置和大小

### 7.2 为什么优先继承 `QStyledItemDelegate`

标准 View 默认使用 Delegate 绘制数据项。Qt 官方建议自定义 Delegate 时通常以 `QStyledItemDelegate` 为基础，因为它会结合当前 Style 进行绘制。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/model-view-programming.html), [\[doc.qt.io\]](https://doc.qt.io/qt-6/zh/model-view-programming.html)

### 7.3 五个关键函数

```cpp
void paint(...) const override;
QSize sizeHint(...) const override;
QWidget* createEditor(...) const override;
void setEditorData(...) const override;
void setModelData(...) const override;
void updateEditorGeometry(...) const override;
```

### 7.4 编辑生命周期

```text
用户触发编辑
    │
    ▼
createEditor()
    │
    ▼
setEditorData()
    │
    ▼
用户修改内容
    │
    ▼
setModelData()
    │
    ▼
Model::setData()
    │
    ▼
dataChanged()
    │
    ▼
View 重新绘制
```

### 7.5 常见 Delegate 陷阱

* 在 `paint()` 中创建 Widget
* 忘记保存 Painter 状态
* 不使用 `QStyleOptionViewItem`
* `DisplayRole` 与 `EditRole` 混淆
* Editor 生命周期管理错误
* Tooltip 内容被缓存或更新不及时
* 每个单元格调用 `setIndexWidget()` 导致性能问题

***

## 八、Selection Model：当前项不等于选中项

### 8.1 两个容易混淆的概念

* **Current Index**：键盘操作和编辑焦点所在项
* **Selected Indexes**：当前选择集合

### 8.2 常用接口与信号

* `currentIndex()`
* `selectedIndexes()`
* `selectedRows()`
* `setCurrentIndex()`
* `select()`
* `currentChanged`
* `selectionChanged`

### 8.3 多 View 共享 Selection Model

案例：

* 左侧树和右侧表共享选择上下文
* 主视图和详情视图同步当前对象
* 共享 Model，但选择状态独立或共享

***

## 九、Model 数据更新协议：最容易写错的部分

### 9.1 数据内容变更

```cpp
emit dataChanged(topLeft, bottomRight, roles);
```

说明：

* 何时只更新一个单元格
* 何时更新连续区域
* `roles` 参数对刷新效率的影响

### 9.2 插入行

```cpp
beginInsertRows(parent, first, last);
// 修改底层数据
endInsertRows();
```

### 9.3 删除行

```cpp
beginRemoveRows(parent, first, last);
// 修改底层数据
endRemoveRows();
```

### 9.4 移动与布局变化

区分：

* `beginMoveRows()/endMoveRows()`
* `layoutAboutToBeChanged()/layoutChanged()`
* `beginResetModel()/endResetModel()`

### 9.5 为什么不能随便 Reset Model

Model Reset 通常会导致：

* View 丢失选择状态
* 展开状态被重置
* Persistent Index 失效
* 整体重新布局和绘制
* 用户上下文中断

因此，能通过 `dataChanged`、插入、删除或移动表达的更新，不应一律使用 Reset。

### 9.6 更新信号顺序错误的后果

* View 读取越界
* Selection 指向错误对象
* Proxy 映射失效
* 展开状态错乱
* 偶现崩溃
* Debug 和 Release 表现不一致

***

## 十、从零实现一个自定义 `QAbstractTableModel`

### 10.1 案例设计

实现一个“测试结果模型”，字段包括：

* 用例名称
* 所属组件
* 执行状态
* 执行时间
* 失败信息
* 稳定业务 ID

### 10.2 第一阶段：只读模型

依次实现：

* `rowCount()`
* `columnCount()`
* `data()`
* `headerData()`

### 10.3 第二阶段：支持编辑

增加：

* `flags()`
* `setData()`
* `Qt::EditRole`
* 数据校验
* `dataChanged()`

### 10.4 第三阶段：支持动态更新

增加：

* 追加测试结果
* 删除记录
* 批量更新状态
* 单元格增量刷新
* 根据业务 ID 查找数据

### 10.5 第四阶段：连接业务数据

讨论两种设计：

1. Model 自己拥有数据
2. Model 只适配外部 Repository

并比较：

* 生命周期
* 所有权
* 线程边界
* 数据一致性
* 可测试性

***

## 十一、自定义树模型

### 11.1 树模型的难点

* 每个节点都有自己的 children
* `row` 是相对于 parent 的局部位置
* 必须正确实现 `index()` 和 `parent()`
* 根节点通常不直接显示
* 节点指针必须保持稳定

### 11.2 推荐节点结构

```cpp
class TreeNode {
public:
    TreeNode* parent = nullptr;
    std::vector<std::unique_ptr<TreeNode>> children;
};
```

### 11.3 树模型五个核心函数

* `index()`
* `parent()`
* `rowCount()`
* `columnCount()`
* `data()`

### 11.4 `parent()` 的完整推导过程

重点讲解：

1. 从当前 Index 找到节点
2. 找到该节点的父节点
3. 找到父节点在祖父节点 children 中的位置
4. 创建父节点对应的 Index

### 11.5 树模型常见错误

* parent 的 row 计算错误
* 顶层节点 parent 返回了有效 Index
* 子节点地址因容器扩容而变化
* 删除节点后仍保留旧 Index
* 根节点和不可见 Root 概念混淆
* `rowCount()` 对非零列仍返回子节点数

***

## 十二、Proxy Model：排序、过滤与数据转换

### 12.1 `QSortFilterProxyModel`

主要功能：

* 排序
* 文本过滤
* 自定义行过滤
* 自定义比较逻辑
* 数据映射

### 12.2 Source Index 与 Proxy Index

```cpp
QModelIndex sourceIndex =
    proxyModel->mapToSource(proxyIndex);

QModelIndex proxyIndex =
    proxyModel->mapFromSource(sourceIndex);
```

### 12.3 自定义过滤

实现思路：

```cpp
bool filterAcceptsRow(
    int sourceRow,
    const QModelIndex& sourceParent) const override;
```

案例：

* 按状态过滤
* 多字段联合过滤
* 树节点递归过滤
* 父节点因子节点命中而保留

### 12.4 自定义排序

讨论：

* 文本排序
* 数字排序
* 日期时间排序
* 自然排序
* 空值排序
* 使用专用 `SortKeyRole`

### 12.5 多层 Proxy Model

```text
Source Model
    │
    ▼
Domain Filter Proxy
    │
    ▼
Sort Proxy
    │
    ▼
Presentation Proxy
    │
    ▼
View
```

重点说明：

* 每一层职责单一
* 多层 `mapToSource()` 的复杂性
* 业务层不应依赖最外层 Proxy Index

***

## 十三、大数据量与性能优化

### 13.1 `data()` 是高频函数

避免在 `data()` 中：

* 访问数据库
* 读取文件
* 执行复杂正则
* 创建大对象
* 重复格式化相同内容
* 输出大量日志

### 13.2 增量加载

介绍：

```cpp
bool canFetchMore(const QModelIndex& parent) const override;
void fetchMore(const QModelIndex& parent) override;
```

### 13.3 View 侧优化

* `QTreeView::setUniformRowHeights(true)`
* 控制一次更新的范围
* 避免频繁 `resizeColumnsToContents()`
* 避免大量 Persistent Editor
* 谨慎使用 `setIndexWidget()`
* 对批量数据进行合并通知

### 13.4 缓存策略

* 缓存昂贵的显示值
* 通过数据版本使缓存失效
* 区分业务数据缓存和 UI 格式缓存
* 不缓存容易失效的裸 `QModelIndex`

### 13.5 数据规模下的模型选择

* 小型静态数据：`QStandardItemModel`
* 业务对象列表：自定义 `QAbstractListModel`
* 固定列业务表：自定义 `QAbstractTableModel`
* 大型层次数据：自定义 `QAbstractItemModel`
* 数据库表：Qt SQL Model 或专用业务 Model

***

## 十四、多线程与异步更新

### 14.1 基本原则

* View 和 Model 通常在 GUI 线程中使用
* Worker 线程负责计算和 I/O
* Worker 不直接调用 View
* Worker 不直接修改正在被 View 访问的 Model 容器

### 14.2 推荐更新路径

```text
Worker Thread
    │
    │ queued signal
    ▼
GUI Thread Slot
    │
    ▼
beginInsertRows()
修改 Model 数据
endInsertRows()
```

### 14.3 高频数据更新

讨论：

* 合并刷新
* 定时批量提交
* 数据快照
* 双缓冲
* 限制 UI 刷新频率
* 保证业务对象 ID 稳定

***

## 十五、模型测试与调试方法

### 15.1 使用 `QAbstractItemModelTester`

可检查：

* Index 合法性
* Parent/Child 一致性
* 行列数量稳定性
* 插入删除协议
* 常见模型不变量

Qt 官方 Model/View Tutorial 将 Model Test 作为调试自定义模型的重要内容。 [\[doc.qt.io\]](https://doc.qt.io/qt-6/modelview.html)

### 15.2 手工检查清单

* 无效 parent 下的 `rowCount()` 是否正确
* 非零列是否错误地拥有子节点
* `parent(index)` 是否能正确反推
* `index()` 是否越界
* 更新前后行数是否符合通知参数
* `dataChanged()` 范围是否有效
* 排序过滤后是否正确进行 Index 映射

### 15.3 常见故障现象与根因

* **数据显示错行**：把 View row 当成业务对象下标
* **删除后崩溃**：旧 Index 或内部指针失效
* **编辑后不刷新**：缺少 `dataChanged`
* **排序结果异常**：按格式化字符串排序
* **树节点错乱**：`parent()` 返回错误
* **选择跳动**：过度使用 Model Reset
* **Tooltip 显示旧内容**：数据更新、事件处理或 Delegate 状态管理不正确

***

## 十六、工程设计原则与最佳实践

### 16.1 保持职责清晰

```text
Business Entity
      │
      ▼
Repository / Service
      │
      ▼
Model Adapter
      │
      ▼
Proxy Model
      │
      ▼
View + Delegate
```

### 16.2 推荐原则

1. Model 是“数据接口”，不是页面控制器
2. 使用稳定业务 ID 标识对象
3. 显示、编辑和排序数据使用不同 Role
4. 精确发送更新信号
5. 尽量避免 Reset Model
6. 自定义绘制优先使用 Delegate
7. 排序过滤优先使用 Proxy Model
8. 业务代码不保存 View Index
9. 自定义 Model 必须配套测试
10. 大数据量设计要考虑懒加载和刷新合并

### 16.3 反模式总结

* 所有内容都塞入 `QStandardItemModel`
* Model 中保存 `QWidget*`
* Delegate 直接修改业务容器
* View 点击事件中通过 row 修改原始数组
* 每次数据变化都 `beginResetModel()`
* 跨线程直接插入模型数据
* 长期保存普通 `QModelIndex`
* 用显示字符串承担排序与业务计算

***

## 十七、完整实战项目

建议全文使用一个逐步演进的案例：

### 项目：测试结果分析器

功能包括：

1. `QAbstractTableModel` 显示测试结果
2. 自定义 Role 提供业务 ID、状态和原始耗时
3. `QStyledItemDelegate` 绘制状态
4. 自定义 Editor 修改归属组件
5. `QSortFilterProxyModel` 实现状态过滤
6. 支持增量追加后台测试结果
7. 使用 Selection Model 展示详情
8. 切换到树模型按组件分组
9. 使用 `QAbstractItemModelTester` 验证模型
10. 对十万级记录进行性能分析

这个案例能够把 Model、View、Delegate、Selection、Proxy 和异步更新串成一条完整主线。

***

## 十八、结语：真正掌握 Model/View 的判断标准

学完后，应当能够准确回答：

* `QModelIndex` 到底是什么？
* 为什么排序后不能再直接使用 View 的 row？
* `dataChanged()` 与 Model Reset 有什么差别？
* Delegate 如何把编辑结果写回 Model？
* `parent()` 为什么是树模型中最容易写错的函数？
* Proxy Index 如何映射回 Source Index？
* 什么情况下使用 `QPersistentModelIndex`？
* 如何让后台线程安全地更新界面数据？
* `QStandardItemModel` 和自定义 Model 应该如何选择？
* 如何验证一个自定义 Model 的实现是正确的？

***

我建议把这篇文章定名为：

> **《深入 Qt Model/View：从 QModelIndex 到自定义树模型的完整实践》**

整体写作顺序采用：

> **设计动机 → 架构角色 → Index 与 Role → 自定义 Model → Delegate → Proxy → 动态更新 → 树模型 → 性能与调试**

这样既适合系统学习，也能覆盖实际 Qt/C++ 工程中最容易出现问题的部分。
