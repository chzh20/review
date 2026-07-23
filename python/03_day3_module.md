# Day 3：模块、包、导入与 API 边界

> **课程定位**：面向具有 10 年以上 C++/Java 经验的高级工程师。  
> **课程主线**：不是学习 `import` 语法，而是理解 **Python 如何组装大型系统、如何产生结构性耦合，以及如何建立可演进的 API 边界**。  
> **贯穿项目**：`mini-infer`——一个逐步演进的迷你 LLM 推理框架。  
> **建议时长**：2.5～3.5 小时，其中原理 60 分钟，重构实战 90 分钟，测试与源码导航 60 分钟。

本课程延续路线图中的约束：使用 `src layout`、稳定 API 只能从 `mini_infer` 导入、内部实现不直接暴露、主动制造一次循环依赖再通过依赖反转消除，并输出模块依赖说明。 [[github.com...roadmap.md]](https://github.com/chzh20/review/blob/main/python/roadmap.md)

---

# 0. 课程核心结论

在大型 Python 工程中：

> **类决定局部代码如何组织；模块决定整个系统能否被加载、测试、替换和演进。**

C++ 工程师往往先看类层次，Java 工程师往往先看 package 和 interface；阅读 Python/LLM 框架时，更有效的顺序是：

```text
Public API
    ↓
Package initializer / lazy import
    ↓
模块依赖方向
    ↓
核心 Protocol / Config / Data Model
    ↓
Engine / Scheduler / Executor
    ↓
Model implementation
    ↓
PyTorch / CUDA / Triton
```

不要先从类继承树或 CUDA kernel 开始。

---



# 1. 学习目标

完成本课程后，学习者应能够：

## 1.1 解释为什么模块边界往往比类设计更重要

类只能控制对象内部的职责，而模块边界还决定：

- 代码何时执行；
- 哪些依赖被加载；
- 哪些名称成为公共 API；
- 哪些全局状态在进程中唯一；
- 是否发生循环依赖；
- 测试能否独立导入；
- 可选依赖是否会污染核心层；
- CLI 或服务冷启动要加载多少代码；
- API 重构是否破坏外部用户。

一个设计良好的类，如果位于错误的模块中，仍可能造成：

```text
导入重型依赖
→ 触发 GPU 检测
→ 注册插件
→ 初始化全局状态
→ 形成循环导入
→ 所有测试和工具链受影响
```



## 1.2 建立 Python 与 C++/Java 不同的模块心智模型


| 维度     | C++                    | Java                     | Python                       |
| ------ | ---------------------- | ------------------------ | ---------------------------- |
| 主要边界   | 头文件、编译单元、库             | package、module、JAR       | module、package、distribution  |
| 加载阶段   | 编译/链接                  | 编译 + class loading       | 运行时查找并执行模块                   |
| 声明与实现  | `.h/.cpp` 常分离          | 类声明与实现一体                 | 模块顶层代码即初始化代码                 |
| 重复引用   | include guard / pragma | JVM 类缓存                  | `sys.modules` 缓存             |
| 循环依赖   | include/link 问题        | 类初始化、构建依赖问题              | 部分初始化模块最常见                   |
| 可见性    | `public/private`、符号导出  | `public/package-private` | 主要依赖命名、导出和约定                 |
| API 门面 | umbrella header        | facade package/module    | `__init__.py` re-export      |
| 动态性    | 较低                     | 中等                       | 高：可修改 `sys.modules`、模块属性和导入器 |


最重要的差异是：

> C++ 的 `#include` 主要是预处理文本包含；Java 的 `import` 主要是名称解析；Python 的 `import` 是一次运行时的“查找、创建模块对象、注册、执行模块代码、绑定名称”的过程。



## 1.3 能定位大型项目中的循环依赖与 API 泄漏

能够识别以下信号：

- `ImportError: cannot import name ... from partially initialized module ...`
- 为解决导入问题不断把 import 移进函数；
- `__init__.py` re-export 了大量内部实现；
- scheduler 直接依赖具体 model；
- model 反向 import engine/request；
- tokenizer import engine config；
- core 层直接 import `transformers`、HTTP server 或 GPU backend；
- 测试通过深层路径 import 本应稳定的 API；
- import 一个数据类却触发 CUDA、网络、日志或线程初始化。



## 1.4 能阅读 PyTorch、Transformers、vLLM 的目录结构



### PyTorch：先找语言边界

```text
torch/
├── __init__.py          # Python 顶层入口与公共命名空间
├── nn/                  # 神经网络抽象
├── autograd/            # 自动微分
├── cuda/                # CUDA Python 接口
├── distributed/         # 分布式
├── _C/                  # Python 与 C++ 扩展边界
└── csrc/                # C++ / Python binding 实现
```

阅读目标不是“看完 torch”，而是判断：

1. 当前符号在哪里对外导出？
2. 真正实现位于 Python 还是 C++？
3. import 时是否注册 operator/backend？
4. `torch.xxx` 是真实子模块、re-export，还是扩展模块属性？



### Transformers：先看公共门面与 Lazy Import

Transformers 的顶层包通过导入结构、可选依赖检查和 Lazy Module，把庞大的模型集合呈现为统一公共 API，而避免在 `import transformers` 时立即加载所有模型和后端。其源码中还为静态类型检查与运行时导入维护不同路径。 [[deepwiki.com]](https://deepwiki.com/huggingface/transformers/7.1-package-structure-and-lazy-loading), [[github.com]](https://github.com/huggingface/transformers/blob/main/docs/source/en/internal/import_utils.md)

### vLLM：先看请求生命周期

当前 vLLM 的官方架构导航围绕以下层次展开：

```text
Entrypoint
→ API / LLM
→ Engine
→ Scheduler
→ Worker
→ Model Runner
→ Model
→ Attention Backend / KV Cache
```

官方架构文档也明确区分了离线 `LLM` 入口、在线 serving、engine core 和 worker/model runner 等职责。 [[docs.vllm.ai]](https://docs.vllm.ai/en/latest/design/arch_overview/)

---



# 2. 核心原理

---



## 2.1 Module 与 Package



### 原理

- **Module**：一个可由导入系统加载的命名空间对象，通常对应 `.py` 文件，也可能来自扩展模块、内置模块或动态 loader。
- **Package**：能够包含子模块的 module；普通 package 通常有 `__init__.py`。
- **Distribution package**：通过 PyPI/pip 安装的发布单元，不等同于 import package。

例如：

```text
发布名：mini-infer
导入名：mini_infer
模块：mini_infer.config
包：mini_infer.engine
```



### 示例

```python
import mini_infer.engine.scheduler

print(mini_infer)
print(mini_infer.engine)
print(mini_infer.engine.scheduler)
```

这里至少涉及三个模块对象，它们通常分别存在于：

```python
sys.modules["mini_infer"]
sys.modules["mini_infer.engine"]
sys.modules["mini_infer.engine.scheduler"]
```



### 常见坑

1. 把 distribution 名称和 import 名称视为同一个概念。
2. 以为目录结构天然就是 API 结构。
3. 让一个模块承担太多角色：
  - 领域对象；
  - 工厂；
  - 注册表；
  - I/O；
  - GPU 初始化；
  - 对外 API。
4. 用 `utils.py` 吞掉没有明确归属的代码，最终形成依赖中心。



### 工程建议

- 一个模块应有明确的**变化原因**。
- 模块名称表达领域，而不是技术动作：
  - 推荐：`request.py`、`scheduler.py`、`sampling.py`
  - 谨慎：`common.py`、`misc.py`、`helpers.py`
- 高频共享类型放在低层稳定模块：
  - `config.py`
  - `types.py`
  - `protocols.py`
  - `exceptions.py`
- 不要把“所有人都需要”误解为“放进顶层 `__init__.py`”。

---



## 2.2 绝对导入与相对导入



### 原理

绝对导入表达完整包路径：

```python
from mini_infer.config import EngineConfig
```

相对导入表达当前 package 内的结构关系：

```python
from ..config import EngineConfig
from .request import InferenceRequest
```

两者都经过 Python 导入系统；主要差异是名称如何解析，以及代码是否依赖当前 package 上下文。

### 示例

在 `mini_infer/engine/engine.py` 中：

```python
from mini_infer.config import EngineConfig
from mini_infer.protocols import Model, Tokenizer

from .request import InferenceRequest
```

一种实用策略：

- 跨子系统：绝对导入；
- 同一子包内部：允许单层相对导入；
- 不使用多层、难以阅读的 `....x`。



### 常见坑



#### 直接执行包内文件

```bash
python src/mini_infer/engine/engine.py
```

相对导入可能失败，因为该文件没有以 package module 的身份执行。

应使用：

```bash
python -m mini_infer.engine.engine
```

但更好的工程设计是：库模块通常不是可执行入口，CLI 统一放在 `cli.py` 或 `__main__.py`。

### 工程建议

- import 风格不能解决循环依赖；绝对改相对不会改变依赖方向。
- 不要通过修改 `sys.path` 修复模块设计：

```python
# 不推荐
sys.path.append("../..")
```

- 单元测试应安装项目或使用规范的 `src layout`，不要依赖当前工作目录“碰巧可导入”。

---



## 2.3 `__init__.py` 的职责



### 原理

`__init__.py` 是 Python 包（Package）的入口文件：它定义“这个目录作为一个包（Package）被导入时，应该初始化什么，并向外暴露什么”。

核心职责与常见用途

- **标识包身份**：向 Python 解释器声明当前目录是一个可导入的常规包（常规包区别于 Python 3 引入的命名空间包）。
- **统一导出接口（API 封装）**：将复杂的内部模块路径简化，通过在文件中使用相对导入（如 `from .module import func`），让外部用户可以直接通过包名调用函数，而无需关心内部的文件组织结构。
- **执行包级初始化**：用于在包加载时自动配置全局变量、初始化日志、加载配置文件或连接数据库。
- **模糊导入控制（使用** `__all__`**）**：定义 `__all__` 列表变量，显式控制当外部使用 `from package import `* 时，哪些模块或对象可以被暴露和导入

`__init__.py` 是 package 初始化模块。第一次导入 package 时，它会被执行。

合理职责：

1. 声明少量稳定公共 API；
2. 定义包版本等轻量元数据；
3. 设置 `__all__`；
4. 在确有必要时实现受控的 lazy export；
5. 描述 package 边界，而不是承载业务逻辑。



### 推荐示例

```python
# mini_infer/__init__.py

#自动执行的初始化操作
__version__ = "1.0.0"
__author__ = "Danny Chen"
# 2. 提升接口可见性，简化外部调用
from .api import InferenceEngine, InferenceRequest, SamplingConfig


## 控制模糊导入 (from my_package import * 只能拿到 InferenceEngine，InferenceRequest， SamplingConfig)

__all__ = [
    "InferenceEngine",
    "InferenceRequest",
    "SamplingConfig",
]
```



### 不推荐示例

```python
# mini_infer/__init__.py
import torch
from transformers import AutoTokenizer

initialize_cuda()
register_all_models()
configure_root_logger()
load_default_model()
```

此时：

```python
import mini_infer
```

不再是“获得 API”，而变成“启动半个推理系统”。

### 常见坑

- 把所有子模块 `import *` 到顶层；
- 为追求方便导出内部类；
- 在 `__init__.py` 创建全局 engine；
- 依赖顶层 re-export 反向导入内部模块；
- `__init__.py` 太重，导致测试收集阶段已经触发 GPU/后端代码。

核心原则是：

> **保持** `__init__.py` **简单、快速、无意外副作用。**

### 工程建议

把 `__init__.py` 当作：

> Python 版的稳定 umbrella header / Java facade package。

但要比 C++ umbrella header 更谨慎，因为它会被执行。

所以它的核心职责可以记成四点：

1. **标识普通 Python 包；**
2. **执行必要的包初始化；**
3. **组织包级命名空间；**
4. **定义清晰、稳定的公开 AP**



---



## 2.4 `__all__`



### 原理

在 Python 中，`__all__` **是一个特殊的全局变量，用于控制当外部代码执行** `from module import `***（模糊导入）时，哪些内容会被暴露和导入**。

它必须是一个由字符串组成的列表（List）或元组（Tuple），里面的每一个字符串都代表当前模块（文件）或包（目录）中的一个变量、函数、类或模块的名字。

---

`__all__` 主要定义：

```python
from module import *
```

时应导出的名称集合，同时也可作为文档工具和 API 审查的显式信号。

`__all__` **的核心职责**

- **控制暴露内容**：明确告诉 Python 解释器，只有列表里的名字才允许被 `import `* 导出。
- **隐藏内部细节**：不愿对外公开的辅助函数、临时变量或在文件顶部导入的外部第三方库，只要不在 `__all__` 中，就不会被 `import `* 导出。
- **作为代码文档**：它是项目维护者的公开接口清单（API），让别人一眼就能看出这个文件哪些功能是供外部调用的

### 示例

```python
# mini_infer/api.py
from .engine.engine import InferenceEngine
from .engine.request import InferenceRequest
from .config import SamplingConfig

__all__ = [
    "InferenceEngine",
    "InferenceRequest",
    "SamplingConfig",
]
```



### **. 重要注意事项**

- **对精确导入无效**：`__all__` 只能限制 `import `*。如果外部显式指定名称导入（如 `from math_tools import E`），依然可以成功拿到。
- **默认行为（无** `__all__` **时）**：如果一个文件没有定义 `__all__`，执行 `from module import `* 时会导入**除了以单下划线** `_` **开头的所有全局变量和函数**。



### 工程建议

真正的 API 边界由以下因素共同形成：

```text
命名约定
+ 文档
+ 顶层导出
+ 类型声明
+ 测试
+ 语义版本策略
+ 代码评审
```

---



## 2.5 Import 执行流程



### 原理

`import` 不只是“找到并运行一个 `.py` 文件”，而是依次完成：**解析名称 → 检查缓存 → 查找模块 → 创建模块对象 → 提前写入缓存 → 执行模块代码 → 建立父子关系 → 绑定名称**

Python 官方文档把导入分成两个核心阶段：

1. **查找并加载模块**
2. **把导入结果绑定到当前作用域中的名称**

这两个阶段需要区分：模块加载由导入系统负责，而名称绑定由具体的 `import` 语句负责。



概念化流程如下：

```text
import mini_infer.engine.scheduler
        │
        ▼
检查 sys.modules
        │
    已存在？ ──是──▶ 返回缓存模块
        │否
        ▼
查找 module spec / finder
        │
        ▼
loader 创建模块对象
        │
        ▼
提前放入 sys.modules
        │
        ▼
执行模块顶层代码
        │
        ├── class / def 创建对象
        ├── 执行顶层表达式
        ├── 继续 import 其他模块
        └── 修改注册表或全局状态
        ▼
执行成功：完成初始化
执行失败：传播异常并清理相关状态
        │
        ▼
在调用方命名空间绑定名称
```

关键点：

> 模块在顶层代码执行完之前就可能已经进入 `sys.modules`。

这是循环导入出现“partially initialized module”的根本背景之一。

### 示例

```python
# demo.py
print("executing demo.py")

class Service:
    pass
```

```python
import demo
import demo
```

通常只输出一次：

```text
executing demo.py
```

第二次 import 复用 `sys.modules["demo"]`。

### 常见坑

- 以为 `import` 只声明依赖、不执行代码；
- 以为模块要执行完成后才进入缓存；
- 以为第二次 import 会重新读取配置文件；
- 删除局部变量后以为模块会卸载；
- 在测试中依赖 import 顺序。



### 工程建议

调试 import 时检查：

```python
import sys

print("mini_infer" in sys.modules)
print(sys.modules.get("mini_infer"))
```

还可使用：

```bash
python -X importtime -c "import mini_infer"
```

或者：

```bash
PYTHONPROFILEIMPORTTIME=1 python -c "import mini_infer"
```

---



## 2.6 `sys.modules` 与模块缓存



### 原理

`sys.modules` **是 Python 解释器核心的全局字典，它唯一的职责就是充当模块的“最高级缓存”**。

在 Python 运行期间，所有成功加载过的模块，都会以 `{"模块名": 模块对象}` 的键值对形式永久保存在 `sys.modules` 中。

---

**为什么需要模块缓存？**

为了**绝对的性能**。  
如果没有缓存，每次你在不同文件里写 `import os`，Python 都必须去硬盘里重新寻找文件、读取代码、编译并执行。对于大型项目，这会导致严重的 IO 瓶颈和重复初始化问题。

有了 `sys.modules` 缓存后：

- **首次导入**：Python 在硬盘找到模块，执行它，然后把结果塞进 `sys.modules`。
- **二次导入**：Python 发现 `sys.modules` 里已经有这个键了，**直接从内存拿出来返回**，耗时几近于零。

---

`sys.modules` 是当前解释器进程内“完整模块名 → 模块对象”的映射。

因此，模块天然具有“进程内单实例命名空间”特征。

### 示例

```python
# registry.py
items: list[str] = []
```

```python
# a.py
import registry
registry.items.append("a")
```

```python
# b.py
import registry
registry.items.append("b")
```

`a.py` 与 `b.py` 通常访问同一个 `registry` 模块对象，以及同一个 `items` 列表。

### 常见坑

- 把模块状态当成普通局部变量；
- 利用模块单例偷偷实现 Service Locator；
- 测试间共享模块状态；
- 误以为线程、进程拥有相同缓存：
  - 同一解释器内通常共享；
  - 不同进程通常各有自己的 `sys.modules`；
- 滥用 `importlib.reload()`，忽略旧对象引用仍可能存在。



### 工程建议

允许的模块级状态：

```python
DEFAULT_TIMEOUT = 30.0
SUPPORTED_DTYPES = frozenset({"float16", "bfloat16"})
```

谨慎或禁止：

```python
current_request = None
global_engine = InferenceEngine(...)
gpu_cache = {}
```

模块缓存不是业务级 Singleton 的充分理由。

---



## 2.7 Import-time Side Effect



**"Import-time Side Effect"（导入时副作用）是指在** `import` **一个 Python 模块时，由于执行了模块顶层的某些代码，导致程序全局状态发生改变或触发了非预期的操作。**

根据之前聊到的 Import 执行流程，Python 在首次导入模块时会执行其顶层的所有代码。如果顶层代码除了定义函数和类之外，还干了别的事情，这些事情就叫做“副作用”。

---

## **1. 坏的副作用：最常见的代码“翻车”现场**

最好的代码在被 `import` 时应该保持“安静”。以下是典型的**坏副作用**示例：

```python
# config_manager.py

print("正在初始化配置...")  # 副作用 1：污染终端输出

def load_config():
    pass

# 致命副作用 2：顶层直接执行高危/耗时操作
db_connection = connect_to_production_database() 

```

**为什么说它坏？**

1. **无法做单元测试**：测试工具（如 `pytest`）仅仅是想 `import` 这个文件来测试 `load_config` 函数，结果一导包，直接去连了生产环境数据库，甚至抛出网络超时错误。
2. **不可控的性能损耗**：只要有人 `import` 这个文件，整个程序就会卡住去执行顶层的耗时操作，哪怕根本没人用那个 `db_connection`。

---

## **2. 好的副作用：有些设计必须依赖它**

并非所有的导入副作用都是坏的。在很多成熟的 Python 框架中，正是利用了“导入即执行”的特性来实现**动态注册**和**元编程**。

## **示例 A：Flask 路由注册**

当你写 Flask 或 FastAPI 时，你会通过装饰器把函数绑定到路由上：

```python
# views.py
from app import app

@app.route('/index')  # 这是一个主动引入的副作用！
def index():
    return "Hello"

```

当主程序执行 `import views` 时，这个装饰器被执行，成功把 `/index` 路由注册到了全局的 `app` 对象中。

## **示例 B：插件自动注册机制**

```python
# plugin_core.py
PLUGIN_REGISTRY = {}

def register_plugin(name):
    def decorator(cls):
        PLUGIN_REGISTRY[name] = cls
        return cls
    return decorator

```

外部插件只需要写顶层装饰器，当主程序 `import` 它们时，全局字典 `PLUGIN_REGISTRY` 就会自动被填满。

---

## **3. 如何避免和防范坏的副作用？**

为了让你的模块成为一个安全的“纯净模块”，请遵守以下原则：

- **原则 1：顶层只做声明，不做执行**  
顶层代码应当**只用来定义**函数（`def`）、类（`class`）和常量，不要在顶层调用会产生外部影响的函数。
- **原则 2：善用** `if __name__ == '__main__':`  
只有当该文件被直接作为脚本运行时，才执行测试代码或启动逻辑；当它被 `import` 时，这段代码会被完全跳过。
- **原则 3：延迟初始化（Lazy Initialization）**  
将耗时的初始化逻辑封装进函数中，或者在使用时才真正创建对象。

```python
# 优秀的、无副作用的模块写法
class Database:
    def __init__(self):
        self.conn = None
    def connect(self):
        if not self.conn:
            self.conn = do_real_connect()

# 仅在顶层创建空壳，不触发实际连接
db = Database() 

```

---

💡 导入时副作用常常是各种隐藏 Bug（尤其是测试失败、配置覆盖、循环死锁）的根源。如果你在写代码时遇到了以下情况，可以告诉我：

- 你是否正在写一个**插件系统**，需要用到这种副作用？
- 或者你的项目在**跑单元测试时，一导包就莫名其妙报错**？我可以帮你找出隐藏在顶层的副作用代码。

### 常见坑

- 注册插件和加载模型混在一起；
- 顶层读取外部配置；
- 顶层创建线程池；
- 顶层配置 root logger；
- 顶层检查所有可选后端；
- import 时打印输出；
- import 时设置随机种子。



### 工程建议

把副作用放入显式生命周期：

```python
def create_engine(config: EngineConfig) -> InferenceEngine:
    ...

def register_builtin_models(registry: ModelRegistry) -> None:
    ...

def main() -> int:
    ...
```

原则是：

> Import 负责定义能力，显式函数负责启动能力。

---



## 2.8 Circular Import

`Circular Import`**（循环导入）是指两个或多个模块之间形成了互相引用的死循环。**

简单来说，就是 A 模块在开头写了 `import B`，而 B 模块的开头也写了 `import A`。当 Python 尝试加载它们时，就会因为卡在中间而抛出 `ImportError` 或 `AttributeError`



`Circular Import`**（循环导入）是指两个或多个模块之间形成了互相引用的死循环。**

简单来说，就是 A 模块在开头写了 `import B`，而 B 模块的开头也写了 `import A`。当 Python 尝试加载它们时，就会因为卡在中间而抛出 `ImportError` 或 `AttributeError`。

结合我们之前聊到的 sys.modules 缓存机制，我们可以非常清晰地拆解这个“死结”是如何发生的。

---

## **1. 经典翻车现场：代码示例**

假设我们有两个文件，它们互相需要对方的函数：

```python
# module_a.py
from module_b import name_b  # 第一步：A 刚开头，就去导入 B

name_a = "我是模块 A"

def print_a():
    print(name_b)

```

```python
# module_b.py
from module_a import name_a  # 第三步：B 刚开头，又回头导入 A

name_b = "我是模块 B"

def print_b():
    print(name_a)

```

此时，如果你运行 `python module_a.py`，程序会直接崩溃并报错：  
`ImportError: cannot import name 'name_a' from 'module_a'`

---

## **2. 慢动作回放：为什么会报错？**

我们用 Python 解释器的视角，一步步看它当时经历了什么：

1. 运行 `module_a.py`：解释器首先在缓存中注册 A：`sys.modules['module_a'] = <半成品A对象>`。
2. 执行 A 的第一行：发现 `from module_b import ...`，于是暂停 A 的执行，转去加载 `module_b`。
3. 加载 `module_b.py`：解释器在缓存中注册 B：`sys.modules['module_b'] = <半成品B对象>`。
4. 执行 B 的第一行：发现 `from module_a import name_a`，于是暂停 B，转去查找 `module_a`。
5. **触发致命缓存**：解释器检查 `sys.modules`，发现 `'module_a'` 已经存在了（第 1 步注册的）。
6. **拿到半成品**：解释器直接把那个**还没执行完第一行、空空如也**的 `module_a` 对象返回给了 B。
7. **彻底崩溃**：B 拿到 A 的半成品后，尝试在里面寻找 `name_a`。但由于 A 的代码当时卡在第一行还没往下走，`name_a` 根本还没诞生！于是引发 `ImportError`。

---

## **3. 解决循环导入的 4 种药方**

遇到循环导入时，可以通过以下几种由浅入深的方法来重构代码：

## **药方一：局部导入（延迟导入）—— 最快但最治标**

将 `import` 语句从文件顶部移到**具体的函数内部**。这样只有在函数被调用时才会触发导入，此时两个模块都已经完成了顶层的初始化。

```python
# module_a.py
# 顶部不导包

def print_a():
    from module_b import name_b  # 挪到函数内部
    print(name_b)

```

## **药方二：导入模块本身，而非模块内的具体变量 —— 治标**

不要使用 `from module import xx`，而是直接 `import module`。  
因为直接导入模块时，只要 `sys.modules` 里有该模块的引用（哪怕是半成品）就能成功拿到句柄。只要你在真正**调用** `module.xx` 之前，那个模块完成了初始化，就不会报错。

## **药方三：切分公共模块（重构）—— 最治本 👍**

循环导入通常意味着**代码架构设计不合理**，两个模块的职责划分不清晰。

- **方法**：把 A 和 B 互相依赖的那部分公共变量或函数，剥离出来单独放到一个新文件 `common.py`（或 `utils.py`）中。让 A 和 B 都去导入 `common.py`，从而将双向依赖变成单向依赖。

## **药方四：利用类型检查保护（仅限打包/类型提示）**

如果你仅仅是为了做 Python 的 Type Hint（类型提示）而导致了循环导入，可以使用 `typing.TYPE_CHECKING`。这个变量在运行时为 `False`，在静态类型检查时为 `True`：

```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .module_b import ClassB  # 运行时不执行，类型检查时才执行

def process(obj: 'ClassB'):  # 用字符串包裹类型
    pass

```

---



## 2.9 Public API 与 Internal Module

### 原理

在软件开发和 Python 项目设计中，**Public API（公开接口）** 与 **Internal Module（内部模块）** 是用于划分**“谁能用”**和**“怎么用”**的核心概念。

简单来说：**Public API 是包的“前台门面”，供外部用户放心调用；Internal Module 是包的“后台厨房”，供开发者自己维护，随时可能被修改或替换。**

结合我们之前聊到的 `__init__.py` 的统一接口封装 和 `__all__` 的显式暴露控制，这两个概念在 Python 中有非常具体的实现方式。

---

## **1. 核心对比**


| 特性       | Public API (公开接口)                          | Internal Module (内部模块)     |
| -------- | ------------------------------------------ | -------------------------- |
| **受众目标** | 最终用户、其他调用此库的项目。                            | 库的内部开发者、维护者。               |
| **稳定性**  | **极高**。不能轻易修改，否则会破坏用户的代码（Breaking Change）。 | **极低**。维护者可以随时重构、删除或重命名。   |
| **暴露方式** | 在 `__init__.py` 中导出，或在 `__all__` 中列出。      | 通常以单下划线 `_` 开头，或者隐藏在深层目录中。 |
| **设计目的** | 易用、直观、隐藏底层复杂的业务逻辑。                         | 高效、解耦、方便代码模块化和技术更新。        |


---

## **2. Python 中的实现与契约**

Python 社区崇尚“大家都是成年人”（We are all consenting adults here）的哲学。这意味着 Python **没有**像 Java 或 C++ 那样从语言层面强制锁定 `private` 或 `protected` 的关键字。它主要依靠**命名约定**和**显式声明**来划分公开和内部。

## **契约一：下划线约定（**`_`**）**

在 Python 中，如果一个文件、函数、类或变量的名字以**单下划线** `_` **开头**，这就表明它是一个**内部实现**。

- **代码示例**：
  ```python
  # crypto_utils.py

  def encrypt_data(data):  # Public API：公开的加密函数
      key = _generate_secret_key()  # 调用内部函数
      return "encrypted_" + data

  def _generate_secret_key():  # Internal：内部辅助函数，外部请勿直接调用
      return "secret_123"

  ```
- **效果**：外部用户依然可以通过 `import _generate_secret_key` 强行调用它（Python 不会阻止），但如果未来库升级导致这个函数被删除了，后果由用户自己承担。

## **契约二：目录结构与** `__init__.py`

大型项目通常会把内部逻辑打散到许多细小的文件中，然后通过 `__init__.py` 统一打包成 Public API。

- **结构示例**：
  ```text
  my_library/
  ├── __init__.py         <-- 在这里定义 Public API
  └── _internal/          <-- 整个目录都是内部模块
      ├── parser.py
      └── validator.py

  ```
- **代码实现**：
  ```python
  # my_library/__init__.py
  # 从深层的内部模块中，只把用户需要的功能拉出来，作为 Public API
  from ._internal.parser import quick_parse as parse

  __all__ = ['parse'] 

  ```
  对于用户来说，他们只需要知道 `import my_library; my_library.parse()` 即可，根本不需要关心 `_internal/parser.py` 的存在。

---

## **3. 为什么严格划分它们至关重要？**

1. **降低认知负担**：用户只需要学习 5 个 Public API 就能满足 90% 的需求，而不需要去理解后台 50 个 Internal Module 的协作原理。
2. **版本控制（语义化版本 Semantic Versioning）**：
  - 如果你修改了 **Internal Module**，你只需要发布一个修订版本（如 `1.0.1`）。
  - 如果你修改或删除了 **Public API**（比如改了函数名或参数），你就必须发布一个大版本（如 `2.0.0`），因为这会破坏用户的既有代码。

---



# 3. mini-infer 实战



## 3.1 推荐目录结构

```text
mini-infer/
├── pyproject.toml
├── src/
│   └── mini_infer/
│       ├── __init__.py
│       ├── api.py
│       ├── config.py
│       ├── exceptions.py
│       ├── protocols.py
│       ├── types.py
│       │
│       ├── engine/
│       │   ├── __init__.py
│       │   ├── request.py
│       │   ├── result.py
│       │   └── _engine.py
│       │
│       ├── model/
│       │   ├── __init__.py
│       │   ├── base.py
│       │   └── _tiny_model.py
│       │
│       ├── tokenizer/
│       │   ├── __init__.py
│       │   ├── base.py
│       │   └── _whitespace.py
│       │
│       ├── scheduler/
│       │   ├── __init__.py
│       │   ├── base.py
│       │   └── _fifo.py
│       │
│       ├── executor/
│       │   ├── __init__.py
│       │   ├── base.py
│       │   └── _local.py
│       │
│       └── _internal/
│           ├── __init__.py
│           └── validation.py
└── tests/
    ├── unit/
    ├── integration/
    └── import_contract/
```



## 3.2 模块职责

核心约束：

```text
api → implementations
implementations → protocols/domain types
protocols/domain types ↛ implementations
```

---



## 3.3 错误实现

```python
# engine/engine.py
from mini_infer.model.model import Model
from mini_infer.scheduler.scheduler import Scheduler
from mini_infer.tokenizer.tokenizer import Tokenizer

class InferenceEngine:
    def __init__(self) -> None:
        self.model = Model()
        self.tokenizer = Tokenizer()
        self.scheduler = Scheduler(self)
```

```python
# scheduler/scheduler.py
from mini_infer.engine.engine import InferenceEngine
from mini_infer.model.model import Model

class Scheduler:
    def __init__(self, engine: InferenceEngine) -> None:
        self.engine = engine
        self.model: Model = engine.model
```

```python
# model/model.py
from mini_infer.engine.engine import InferenceEngine

class Model:
    def warm_up(self, engine: InferenceEngine) -> None:
        ...
```

### 问题分析


这里存在多个结构问题：

1. `Engine` 自己创建所有实现，无法替换。
2. Scheduler 获得整个 Engine，权限过大。
3. Model 知道 Engine，计算层反向依赖编排层。
4. 具体实现互相作为类型契约。
5. 导入图与运行时对象图纠缠。
6. 单元测试无法只加载 Scheduler。
7. 后续接入 GPU Executor 时容易形成更多反向依赖。

---



## 3.4 重构第一步：提取领域对象

```python
# engine/request.py
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class InferenceRequest:
    request_id: str
    prompt: str
    max_new_tokens: int = 32
```

```python
# engine/result.py
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class GenerationResult:
    request_id: str
    text: str
    token_ids: tuple[int, ...]
```

这些类型不依赖 engine、scheduler 或具体模型。

---



## 3.5 重构第二步：提取契约

```python
# protocols.py
from typing import Protocol, Sequence

class Tokenizer(Protocol):
    def encode(self, text: str) -> Sequence...

    def decode(self, token_ids: Sequence[int]) -> str:
        ...


class Model(Protocol):
    def forward(self, token_ids: Sequence[int]) -> Sequence...


class Executor(Protocol):
    def execute(
        self,
        model: Model,
        token_ids: Sequence[int],
    ) -> Sequence...
```

```python
# scheduler/base.py
from dataclasses import dataclass
from mini_infer.engine.request import InferenceRequest

@dataclass(frozen=True, slots=True)
class ScheduleBatch:
    requests: tuple[InferenceRequest, ...]


class Scheduler:
    def submit(self, request: InferenceRequest) -> None:
        raise NotImplementedError

    def next_batch(self) -> ScheduleBatch:
        raise NotImplementedError
```

关键改变：

- Engine 依赖接口；
- Scheduler 只依赖 Request；
- Model 不知道 Engine；
- Executor 只知道 Model Protocol；
- 依赖方向开始单向化。

---



## 3.6 重构第三步：构造注入

```python
# engine/_engine.py
from mini_infer.engine.request import InferenceRequest
from mini_infer.engine.result import GenerationResult
from mini_infer.protocols import Executor, Model, Tokenizer
from mini_infer.scheduler.base import Scheduler


class InferenceEngine:
    def __init__(
        self,
        *,
        tokenizer: Tokenizer,
        model: Model,
        scheduler: Scheduler,
        executor: Executor,
    ) -> None:
        self._tokenizer = tokenizer
        self._model = model
        self._scheduler = scheduler
        self._executor = executor

    def generate(self, request: InferenceRequest) -> GenerationResult:
        token_ids = list(self._tokenizer.encode(request.prompt))
        self._scheduler.submit(request)

        for _ in range(request.max_new_tokens):
            logits = self._executor.execute(self._model, token_ids)
            next_token = max(range(len(logits)), key=logits.__getitem__)
            token_ids.append(next_token)

        return GenerationResult(
            request_id=request.request_id,
            text=self._tokenizer.decode(token_ids),
            token_ids=tuple(token_ids),
        )
```

Engine 不再直接构造具体组件。

---



## 3.7 重构第四步：建立 Composition Root

```python
# api.py
from mini_infer.engine._engine import InferenceEngine
from mini_infer.executor._local import LocalExecutor
from mini_infer.model._tiny_model import TinyModel
from mini_infer.scheduler._fifo import FifoScheduler
from mini_infer.tokenizer._whitespace import WhitespaceTokenizer


def create_default_engine() -> InferenceEngine:
    return InferenceEngine(
        tokenizer=WhitespaceTokenizer(),
        model=TinyModel(),
        scheduler=FifoScheduler(),
        executor=LocalExecutor(),
    )
```

只有 composition root 知道全部具体实现。

这类似：

- C++ 程序中的 `main()` / factory wiring；
- Java Spring configuration；
- 依赖注入容器的手工版本。

---



## 3.8 重构第五步：建立公共 API

```python
# mini_infer/__init__.py
from .api import create_default_engine
from .config import SamplingConfig
from .engine.request import InferenceRequest
from .engine.result import GenerationResult

__all__ = [
    "GenerationResult",
    "InferenceRequest",
    "SamplingConfig",
    "create_default_engine",
]
```

用户代码：

```python
from mini_infer import InferenceRequest, create_default_engine

engine = create_default_engine()
result = engine.generate(
    InferenceRequest(
        request_id="req-001",
        prompt="hello world",
    )
)
```

用户不需要知道：

```text
_engine.py
_fifo.py
_local.py
_tiny_model.py
```

---



# 4. pytest 测试设计

测试 import 行为时，应特别注意**当前 pytest 进程中的模块缓存会污染实验**。最可靠的方法是使用临时 package，并在必要时通过 subprocess 获得全新解释器。

---



## 4.1 验证 import 缓存行为

```python
# tests/unit/test_import_cache.py
import importlib
import sys


def test_import_executes_module_only_once(tmp_path, monkeypatch):
    module_file = tmp_path / "cached_module.py"
    counter_file = tmp_path / "count.txt"

    module_file.write_text(
        "\n".join(
            [
                "from pathlib import Path",
                f"counter_file = Path({str(counter_file)!r})",
                "old = int(counter_file.read_text()) if counter_file.exists() else 0",
                "counter_file.write_text(str(old + 1))",
                "VALUE = object()",
            ]
        ),
        encoding="utf-8",
    )

    monkeypatch.syspath_prepend(str(tmp_path))
    sys.modules.pop("cached_module", None)

    first = importlib.import_module("cached_module")
    second = importlib.import_module("cached_module")

    assert first is second
    assert first.VALUE is second.VALUE
    assert counter_file.read_text(encoding="utf-8") == "1"
```

验证点：

- 同一完整模块名只执行一次；
- 两次 import 返回同一模块对象；
- 模块内部对象也来自同一命名空间。

---



## 4.2 验证模块单例特性

```python
# tests/unit/test_module_singleton.py
import importlib
import sys


def test_two_importers_share_same_module_state(tmp_path, monkeypatch):
    (tmp_path / "registry.py").write_text(
        "items = []\n",
        encoding="utf-8",
    )

    (tmp_path / "producer_a.py").write_text(
        "import registry\n"
        "registry.items.append('a')\n",
        encoding="utf-8",
    )

    (tmp_path / "producer_b.py").write_text(
        "import registry\n"
        "registry.items.append('b')\n",
        encoding="utf-8",
    )

    monkeypatch.syspath_prepend(str(tmp_path))

    for name in ("registry", "producer_a", "producer_b"):
        sys.modules.pop(name, None)

    importlib.import_module("producer_a")
    importlib.import_module("producer_b")
    registry = importlib.import_module("registry")

    assert registry.items == ["a", "b"]
```

这也是模块级可变状态会导致测试污染的直接证明。

---



## 4.3 验证循环导入问题

使用 subprocess，避免当前 pytest 进程残留部分模块。

```python
# tests/unit/test_circular_import.py
import subprocess
import sys


def test_circular_import_reports_partially_initialized_module(tmp_path):
    package = tmp_path / "cycle_demo"
    package.mkdir()

    (package / "__init__.py").write_text("", encoding="utf-8")

    (package / "a.py").write_text(
        "from .b import B\n"
        "\n"
        "class A:\n"
        "    pass\n",
        encoding="utf-8",
    )

    (package / "b.py").write_text(
        "from .a import A\n"
        "\n"
        "class B:\n"
        "    value = A\n",
        encoding="utf-8",
    )

    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import cycle_demo.a",
        ],
        cwd=tmp_path,
        text=True,
        capture_output=True,
        check=False,
    )

    assert completed.returncode != 0
    assert (
        "partially initialized module" in completed.stderr
        or "cannot import name" in completed.stderr
    )
```

---



## 4.4 验证重构后无循环依赖

```python
def test_refactored_dependency_graph_imports_successfully(tmp_path):
    package = tmp_path / "clean_demo"
    package.mkdir()

    (package / "__init__.py").write_text("", encoding="utf-8")

    (package / "protocols.py").write_text(
        "from typing import Protocol\n"
        "\n"
        "class EngineView(Protocol):\n"
        "    @property\n"
        "    def active_count(self) -> int: ...\n",
        encoding="utf-8",
    )

    (package / "scheduler.py").write_text(
        "from .protocols import EngineView\n"
        "\n"
        "class Scheduler:\n"
        "    def inspect(self, engine: EngineView) -> int:\n"
        "        return engine.active_count\n",
        encoding="utf-8",
    )

    (package / "engine.py").write_text(
        "from .scheduler import Scheduler\n"
        "\n"
        "class Engine:\n"
        "    active_count = 0\n"
        "\n"
        "    def __init__(self):\n"
        "        self.scheduler = Scheduler()\n",
        encoding="utf-8",
    )

    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "from clean_demo.engine import Engine; print(Engine().active_count)",
        ],
        cwd=tmp_path,
        text=True,
        capture_output=True,
        check=False,
    )

    assert completed.returncode == 0
    assert completed.stdout.strip() == "0"
```

---



## 4.5 验证公共 API 边界

```python
# tests/import_contract/test_public_api.py
import mini_infer


def test_expected_public_api_is_explicit():
    assert set(mini_infer.__all__) == {
        "GenerationResult",
        "InferenceRequest",
        "SamplingConfig",
        "create_default_engine",
    }


def test_every_declared_public_name_exists():
    for name in mini_infer.__all__:
        assert hasattr(mini_infer, name)


def test_internal_implementations_are_not_top_level_exports():
    assert not hasattr(mini_infer, "TinyModel")
    assert not hasattr(mini_infer, "FifoScheduler")
    assert not hasattr(mini_infer, "LocalExecutor")
```

进一步可以增加 API snapshot：

```python
def test_public_namespace_has_no_accidental_exports():
    public_names = {
        name
        for name in vars(mini_infer)
        if not name.startswith("_")
    }

    assert public_names == set(mini_infer.__all__)
```

注意：如果 package 有意暴露 `api` 等子模块，需要相应调整断言。

---



## 4.6 验证 import 无副作用

```python
# tests/import_contract/test_import_side_effects.py
import subprocess
import sys


def test_import_produces_no_stdout_or_stderr():
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import mini_infer",
        ],
        text=True,
        capture_output=True,
        check=False,
    )

    assert completed.returncode == 0
    assert completed.stdout == ""
    assert completed.stderr == ""
```

```python
def test_import_does_not_load_torch_or_transformers():
    script = """
import sys
import mini_infer

assert "torch" not in sys.modules
assert "transformers" not in sys.modules
"""

    completed = subprocess.run(
        [sys.executable, "-c", script],
        text=True,
        capture_output=True,
        check=False,
    )

    assert completed.returncode == 0, completed.stderr
```

如果顶层 API 本身依赖 Torch 类型，这个测试需要改为检查“不导入具体 CUDA/backend 子系统”。

---



## 4.7 验证启动时间预算

```python
import subprocess
import sys


def test_import_time_is_within_budget():
    script = """
import time

start = time.perf_counter()
import mini_infer
elapsed = time.perf_counter() - start

print(elapsed)
"""

    completed = subprocess.run(
        [sys.executable, "-c", script],
        text=True,
        capture_output=True,
        check=True,
    )

    elapsed = float(completed.stdout.strip())

    # 阈值应由 CI 环境基线决定，不应盲目照搬。
    assert elapsed < 0.5
```

性能测试容易受机器、文件缓存和 CI 负载影响，因此更适合：

- 记录趋势；
- 设置宽松回归阈值；
- 区分 cold process 与 warm process；
- 多次运行取中位数。

---



# 5. PyTorch、Transformers 与 vLLM 实践



## 5.1 PyTorch：Python 门面背后的多语言系统

阅读 `torch` 时应意识到：

```text
Python public namespace
→ Python wrappers
→ dispatcher / operator registration
→ C++ extension
→ backend implementation
→ CUDA / CPU kernel
```



### 架构思想

1. `torch` 是统一公共门面。
2. Python 类型与函数可能只是底层 operator 的包装。
3. `torch._C` 是重要的 Python/C++ 边界。
4. 许多内部模块以下划线标记，但技术上仍可 import。
5. 顶层导入必须协调扩展加载、类型注册和后端能力。

PyTorch 源码树同时包含 Python 包、`torch/csrc` C++ binding、ATen 及各类 backend，因此目录结构首先反映的是**语言边界与部署边界**，而不只是业务分层。 [[github.com]](https://github.com/pytorch/pytorch/blob/master/torch/csrc/lazy/tutorial.md)

### 阅读练习

对以下 API 做“符号来源追踪”：

```python
import torch
from torch import nn

print(torch.Tensor.__module__)
print(nn.Module.__module__)
print(torch.nn.functional.linear.__module__)
```

每次记录：

```text
用户入口
→ 顶层导出位置
→ Python 定义位置
→ C++/dispatcher 边界
→ 实际 backend
```

---



## 5.2 Transformers：Public Facade + Lazy Import

Transformers 面临的问题是：

- 模型架构数量庞大；
- 存在多种可选 backend；
- 用户希望使用短而稳定的导入路径；
- IDE/type checker 又必须看见真实符号；
- 不能让 `import transformers` 加载全部模型。

因此，它采用类似以下结构：

```text
transformers.__init__
    ├── 构建 import structure
    ├── 判断可选依赖
    ├── 为静态检查提供真实 imports
    └── 运行时使用 Lazy Module
```

Transformers 的导入工具包含 Lazy Module 和可选依赖检测，其顶层包承担的是“公共 API 索引”而不是模型执行。 [[github.com]](https://github.com/huggingface/transformers/blob/main/docs/source/en/internal/import_utils.md)

### 简化版 Lazy Module

```python
# mini_infer/__init__.py
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .api import InferenceEngine
else:
    def __getattr__(name: str):
        if name == "InferenceEngine":
            from .api import InferenceEngine
            return InferenceEngine
        raise AttributeError(name)
```

更完整的实现还需要考虑：

- `__dir__`；
- 缓存已解析属性；
- 线程安全；
- 静态类型；
- 文档生成；
- pickling；
- 错误信息；
- 可选依赖异常。



### 架构思想

> Lazy import 不只是性能技巧，而是在“巨大公共表面”与“最小启动成本”之间建立中间层。

但它也有成本：

- 调试路径更复杂；
- 错误从 import 时推迟到首次访问时；
- 静态和运行时 API 结构可能漂移；
- 过度 lazy 会掩盖真实循环依赖。

PEP 690 曾提出全局透明 lazy import，但最终被拒绝；标准库仍提供 `importlib.util.LazyLoader`，这说明 lazy import 应作为受控架构策略，而不是默认语义。 [[peps.python.org]](https://peps.python.org/pep-0690/)

---



## 5.3 vLLM：按运行时责任和进程边界组织

vLLM 不只是模型库，而是推理系统：


当前官方架构中，API server、engine core 与 GPU worker 可属于不同进程，并通过明确的通信边界连接；这种拆分既是模块边界，也是故障、并发和性能边界。 [[docs.vllm.ai]](https://docs.vllm.ai/en/latest/design/arch_overview/)

### vLLM 模块组织的核心思想



#### 1. Entrypoint 不等于 Engine

Entrypoint 处理：

- 用户参数；
- HTTP/OpenAI 协议；
- 输入格式；
- 生命周期。

Engine 处理：

- 请求状态；
- 调度；
- 执行协调；
- 输出推进。



#### 2. Scheduler 不应依赖具体模型类

Scheduler 应围绕：

- token budget；
- request state；
- prefill/decode 状态；
- cache capacity；
- priority/fairness。

它不应知道某个 Llama block 如何实现 attention。

#### 3. Model Runner 是重要边界

Model Runner 把调度结果转换为模型执行输入：

```text
scheduled requests
→ batch metadata
→ tensor inputs
→ model forward
→ sampled output
```



#### 4. Backend 是策略层

CUDA、ROCm、CPU、TPU 或不同 attention kernel 不应渗透到整个 engine API。

vLLM 当前项目同时包含 Python、C++/CUDA、Rust、平台后端和独立测试/benchmark 目录；阅读时必须先锁定版本或 commit，再沿入口和请求生命周期进入，而不能按文件树漫游。 [[github.com]](https://github.com/vllm-project/vllm)

---



## 5.4 如何控制启动时间

建立 import budget：

```text
import mini_infer
        不加载 torch/transformers/GPU backend

from mini_infer import SamplingConfig
        只加载轻量领域类型

create_default_engine()
        加载默认实现

create_torch_engine()
        才加载 torch

engine.start()
        才分配线程/GPU/模型资源
```

推荐策略：

1. 核心数据类不 import 重型框架。
2. 第三方依赖放在 adapter/backend。
3. `TYPE_CHECKING` 隔离纯类型依赖。
4. 工厂函数内部加载可选 backend。
5. 不在 import 时探测全部硬件。
6. import 性能纳入 CI。
7. 用 `python -X importtime` 找热点。
8. 不用 lazy import 掩盖错误分层。

---



# 6. 面试专题



## Q1：执行 `import x` 时发生了什么？



### 标准答案

1. 检查 `sys.modules` 是否已有完整模块名。
2. 若没有，导入系统通过 finder 查找 module spec。
3. loader 创建模块对象。
4. 在执行模块代码前将模块登记到 `sys.modules`。
5. 执行模块顶层代码。
6. 执行成功后返回模块对象。
7. 在当前作用域绑定名称。



### 追问点

- 为什么要提前放入 `sys.modules`？
- import 失败后缓存如何处理？
- package 的父模块何时加载？
- `from x import y` 与 `import x` 有何不同？
- 扩展模块是否也遵循同样抽象？

---



## Q2：`sys.modules` 的作用是什么？



### 标准答案

它是解释器进程内的模块注册表和缓存，保证同一完整模块名通常只初始化一次，并允许循环导入过程中找到“正在初始化”的模块对象。

### 追问点

- 多进程是否共享？
- 删除键是否等于安全卸载？
- `importlib.reload()` 是否会更新旧引用？
- 为什么模块级状态具有单例效果？

---



## Q3：`__init__.py` 的职责是什么？



### 标准答案

- 标识和初始化普通 package；
- 定义轻量元数据；
- 组织稳定公共 API；
- 可设置 `__all__`；
- 必要时协调 lazy import。

它不应承担模型加载、设备初始化或大规模业务注册。

### 追问点

- namespace package 是否需要它？
- 为什么顶层 `__init__.py` 过重会影响 CLI？
- re-export 会如何制造隐式依赖？

---



## Q4：`__all__` 有什么用？



### 标准答案

主要控制 `from module import *` 的导出集合，并作为公共 API 的显式文档和审查信号；它不提供真正的访问控制。

### 追问点

- 下划线命名与 `__all__` 的关系？
- 如何测试 `__all__` 与实际 API 一致？
- 为什么不建议业务代码使用 wildcard import？

---



## Q5：为什么会出现循环导入？



### 标准答案

两个或更多模块的顶层执行形成依赖环，其中某个模块在尚未完成初始化时，被另一个模块访问了尚未绑定的名称。

### 追问点

- 为什么有时循环 import 不报错？
- 为什么改变 import 顺序有时“能修好”？
- 为什么这种修复不可靠？
- 类型标注如何触发额外环？

---



## Q6：如何解决循环依赖？



### 标准答案

优先修改依赖图，而不是修改 import 语法：

1. 重新分配职责；
2. 提取共享领域类型；
3. 提取 Protocol/ABC；
4. 通过构造注入实现依赖反转；
5. 使用事件、回调或消息传递打破反向调用；
6. 纯类型引用可配合 `TYPE_CHECKING`；
7. 局部 import 只用于合理的延迟加载或可选依赖。



### 追问点

- `TYPE_CHECKING` 是否一定安全？
- Protocol 应放在哪里？
- composition root 为什么可以依赖所有具体实现？

---



## Q7：为什么 import-time side effect 危险？



### 标准答案

因为 import 可能发生在应用启动、pytest 收集、IDE 分析、文档生成、插件发现或 CLI 补全阶段。副作用会让简单的名称加载变成资源初始化，导致不可预测的性能、环境依赖和测试污染。

### 追问点

- 哪些 side effect 可接受？
- 注册表初始化算不算副作用？
- 如何测试 import 纯净性？
- 如何测量 import time？

---



## Q8：Lazy Import 有什么优缺点？



### 标准答案

优点：

- 降低冷启动时间；
- 避免加载未使用重型模块；
- 支持可选 backend；
- 容纳较大的公共 API。

缺点：

- 错误延迟；
- 调试复杂；
- 静态类型与运行时行为可能分离；
- 可能隐藏架构环；
- 首次属性访问产生延迟。



### 追问点

- `TYPE_CHECKING` 在 lazy API 中的作用？
- 如何保证 IDE 自动补全？
- 如何监控首次访问延迟？

---



# 7. 一页总结



## 7.1 核心知识图谱



## 7.2 Import 执行流程图


## 7.3 循环依赖图

---



## 7.4 易错点 Top 10

1. 把 Python import 当成 Java 名称声明。
2. 忘记 import 会执行顶层代码。
3. 在 `__init__.py` 加载重型依赖。
4. 认为 `__all__` 提供 private 访问控制。
5. 用函数内 import 掩盖架构循环。
6. 让 scheduler、model、engine 相互持有完整对象。
7. 公共 API 泄漏第三方类型和异常。
8. 在模块中保存请求级可变状态。
9. 依赖测试执行顺序和已有 `sys.modules` 状态。
10. 阅读 LLM 源码时从底层 kernel 或文件树漫游开始。

---



## 7.5 工程实践 Checklist



### 模块职责

- [ ] 每个模块只有明确的变化原因。
- [ ] 不存在无边界扩张的 `utils.py` / `common.py`。
- [ ] 领域数据类型位于低层稳定模块。
- [ ] Engine、Scheduler、Executor、Model 职责不同。



### 依赖方向

- [ ] 依赖图整体单向。
- [ ] 核心层不依赖 CLI、HTTP、具体 backend。
- [ ] Model 不反向依赖 Engine。
- [ ] Scheduler 不依赖具体模型实现。
- [ ] 第三方依赖被 adapter/backend 隔离。
- [ ] composition root 是具体实现的集中组装点。



### API

- [ ] 顶层 API 最小且稳定。
- [ ] `__all__` 与文档一致。
- [ ] 内部模块使用 `_` 命名或 `_internal` 分区。
- [ ] 公共 API 不泄漏第三方类型。
- [ ] 公共异常属于领域异常层次。
- [ ] API 有导入契约测试。



### Import 行为

- [ ] import 不进行网络访问。
- [ ] import 不加载模型。
- [ ] import 不初始化 GPU。
- [ ] import 不启动线程或进程。
- [ ] import 不配置 root logger。
- [ ] import 不输出 stdout/stderr。
- [ ] 重型可选依赖延迟到功能使用阶段。



### 测试与性能

- [ ] 使用 subprocess 验证冷 import。
- [ ] 测试模块缓存和共享状态。
- [ ] 有循环导入失败案例。
- [ ] 有重构后依赖图测试。
- [ ] 使用 `-X importtime` 建立基线。
- [ ] 源码阅读固定 tag 或 commit。

---



## 7.6 记忆口诀

> **先缓存，后执行；顶层代码即初始化。**  
> **包做门面，不做启动；导出是承诺，不是便利。**  
> **依赖只能向下，组装统一向上。**  
> **遇到循环先改图，不要先挪 import。**  
> **核心不识后端，模型不识引擎，调度只识状态。**  
> **PyTorch 看语言边界，Transformers 看懒加载，vLLM 看请求生命周期。**

---



# 8. 当日验收任务

完成课程后，要求学习者提交以下成果：

```text
Day 3 Deliverables
├── src/mini_infer/
│   ├── __init__.py
│   ├── api.py
│   ├── protocols.py
│   ├── config.py
│   ├── engine/
│   ├── scheduler/
│   ├── executor/
│   ├── model/
│   └── tokenizer/
├── tests/
│   ├── test_import_cache.py
│   ├── test_module_singleton.py
│   ├── test_circular_import.py
│   ├── test_public_api.py
│   └── test_import_side_effects.py
└── docs/
    └── import-boundaries.md
```



## 必须回答的验收问题

1. `import mini_infer` 到底执行了哪些模块？
2. 哪些模块进入了 `sys.modules`？
3. 为什么 Scheduler 不需要知道 Engine？
4. 为什么 Model 不应 import Engine？
5. composition root 为什么允许知道所有具体实现？
6. 顶层 API 中哪些名称是兼容性承诺？
7. `import mini_infer` 是否加载了 Torch 或 Transformers？
8. 如何证明模块状态在同一解释器中被共享？
9. 如何在全新解释器里稳定复现循环导入？
10. 如果未来增加 `CudaExecutor`，需要修改哪些模块，不应修改哪些模块？

最终验收标准不是“能写出 import”，而是：

> 给出一个陌生的 Python/LLM 仓库，能够在 30 分钟内画出它的公共 API、模块依赖方向、import-time 副作用、关键 composition root 和潜在循环依赖。

