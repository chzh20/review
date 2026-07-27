# 异常设计与资源管理：构建可诊断、可恢复的错误模型

> 一门以「可诊断性（Diagnosability）」与「可恢复性（Recoverability）」为两条主线的 Python 工程化课程。
> 学完应能：为真实业务设计分层异常体系、在再抛出时保留完整因果链、用上下文管理器杜绝资源泄漏、并识别/重构静默吞异常的四大反模式。

---

## 0. 课程定位与目标

### 0.1 为什么需要专门讲"错误模型"

很多工程师把异常处理当成"加个 try 包一下别让程序崩"，这是最危险的认知。在真实生产系统里：

- **可诊断性差** → 线上报错只有 `Exception`，没有根因、没有上下文，排查花 3 小时。
- **可恢复性差** → 异常路径下连接没关、事务没回滚、锁没释放，系统进入不一致状态，雪崩。

本课程不教"怎么捕获异常"，而是教**如何设计一套让错误自己说话、让系统自我修复的错误模型**。

### 0.2 两条贯穿主线

| 主线 | 含义 | 设计问题 |
|------|------|----------|
| **可诊断性** | 异常信息足够定位根因 | "看到这个异常，能不能 5 分钟内知道哪里错了、为什么错？" |
| **可恢复性** | 异常后系统回到一致状态 | "异常发生后，资源释放了吗？状态回滚了吗？还能继续服务吗？" |

每个知识点都标注它主要服务哪条主线（D=诊断 / R=恢复 / D+R）。

### 0.3 学习目标

1. 能设计**语义清晰、粒度合理**的自定义异常层级，并按粒度精准捕获。
2. 掌握 `raise ... from ...`，在多层调用中**保留完整因果链**，杜绝原始上下文丢失。
3. 能在这 `try/except/else/finally` 四种子句中写出**语义正确**的控制流。
4. 理解 EAFP 与 LBYL 的**权衡与适用边界**，不在并发场景误用 LBYL。
5. 熟练用 `__enter__/__exit__` 与 `@contextmanager` 实现**异常安全的资源管理**。
6. 识别并重构"静默吞异常"等反模式，**永不无声吞没错误**。

### 0.4 前置与适合人群

- 已掌握 Python 基础语法（函数、类、装饰器、生成器）。
- 有至少一门静态语言（C++/Java）经验者尤佳——你已有"异常是控制流"的直觉，本课程帮你在 Python 里用对。
- 可作为「大模型职业课程」M1 Python 进阶的工程化深潜模块。

### 0.5 贯穿案例（Capstone）

全课程围绕一个**配置驱动的数据流水线**子系统 `datapipe` 展开：
从配置文件读取 → 打开数据源 → 解析记录 → 写入目标。每模块都为它补一块错误/资源管理能力，最终集成为「可诊断、可恢复」的完整组件。

---

## 1. 模块总览

| 模块 | 主题 | 主线 | 课时 |
|------|------|------|------|
| M0 | 导论：错误模型的代价 | D+R | 1h |
| M1 | 异常层级设计 | D+R | 2h |
| M2 | `try/except/else/finally` 完整结构 | D+R | 2h |
| M3 | `raise ... from ...` 保留因果链 | D | 2.5h |
| M4 | EAFP vs LBYL | D+R | 2h |
| M5 | Context Manager 协议 | R | 2.5h |
| M6 | `contextlib.contextmanager` | R | 2h |
| M7 | 禁止静默吞异常（反模式） | D+R | 1.5h |
| M8 | 综合实战：可诊断可恢复的 `datapipe` | D+R | 3h |
| — | 评估与自查清单 | — | 1h |

**总课时约 19.5h**，建议 2 周（每天约 1.5h）或 1 周集中。

---

## 2. M0 导论：错误模型的代价（1h）

### 2.1 两个真实事故（课堂讨论）

- **事故 A（可诊断性缺失）**：某服务捕获 `Exception` 后只 `print(e)`，日志里只剩 `KeyError: 'x'`，没人知道是哪个请求、哪份配置、哪个字段。事后复盘 3 小时。
- **事故 B（可恢复性缺失）**：文件解析抛异常，但 `open()` 的文件句柄在异常路径下没关，长时间运行后 fd 耗尽，整服务不可用。

### 2.2 本课的核心信条

> 异常不是"让程序不崩"的工具，而是**系统向维护者发送的诊断报文**，以及**系统自我修复的回滚入口**。

### 2.3 自查题（课后）

列出你最近写过的 3 段 `try/except`，分别判定：诊断信息够吗？异常路径下资源释放了吗？

---

## 3. M1 异常层级设计（2h）

**主线：D（语义利于定位）+ R（粒度利于恢复）**

### 3.1 学习目标

- 设计以单一基类为根的异常层级。
- 让异常**反映业务语义**（读配置失败 ≠ 解析数据失败），而非统一抛 `Exception`。
- 支持"粗粒度兜底 + 细粒度特判"的捕获。

### 3.2 核心知识点

#### 3.2.1 不要直接继承 `Exception` 裸抛

裸抛 `Exception` 或 `RuntimeError` 会让调用方无法区分"配置错了"还是"网络错了"，只能 `except Exception` 一刀切——这正是可诊断性与可恢复性的共同敌人。

#### 3.2.2 层级设计三原则

1. **单一根**：全应用一个 `AppError(Exception)`，便于"兜底捕获但记录"。
2. **语义分层**：领域错误 → 子类型（配置/数据/网络…）→ 更细（校验/解析…）。
3. **携带结构化信息**：错误码 + 上下文字段，而非只靠字符串。

### 3.3 理论+代码：为 `datapipe` 设计异常树

```python
class DataPipeError(Exception):
    """所有 datapipe 错误的根。携带 code 便于结构化处理与日志。"""
    code = "DATAPIPE_ERROR"

# —— 一级：按领域分支 ——
class ConfigError(DataPipeError):
    code = "CONFIG_ERROR"

class SourceError(DataPipeError):
    code = "SOURCE_ERROR"

class SinkError(DataPipeError):
    code = "SINK_ERROR"

# —— 二级：更细粒度，便于差异化恢复 ——
class ConfigMissingError(ConfigError):
    code = "CONFIG_MISSING"

class ConfigParseError(ConfigError):
    code = "CONFIG_PARSE"

class RecordParseError(SourceError):
    code = "RECORD_PARSE"

class ConnectionError(SourceError):
    code = "SOURCE_CONNECTION"
```

**为什么这样分？**
- `except DataPipeError` → 统一兜底、统一日志、统一返回 5xx。
- `except ConfigMissingError` → 可恢复：用默认值或提示用户补配置。
- `except RecordParseError` → 可恢复：跳过坏记录、继续后续（详见 M8 死信队列）。

### 3.4 实践任务

1. **任务 A**：为 `datapipe` 增加 `SinkError` 的二级子类（写入失败/磁盘满/权限不足），并各带 `code`。
2. **任务 B**：写一段调用代码，演示"细粒度特判坏记录 + 粗粒度兜底其他"，打印不同日志级别。

### 3.5 验收标准

- [ ] 所有自定义异常继承自单一根 `DataPipeError`。
- [ ] 任意一处错误都能通过 `e.code` 被程序化区分。
- [ ] 调用方能"粗兜底 + 细特判"精确捕获。

---

## 4. M2 `try/except/else/finally` 完整结构（2h）

**主线：D（else 让正常路径清晰）+ R（finally 保证清理）**

### 4.1 学习目标

- 说清 `else` 与 `try` 块内代码的区别。
- 说清 `finally` 在"正常、异常、return、再抛出"四种情形下的执行行为。
- 避免把资源清理错误放进 `except` 或 `try` 导致的泄漏/冗余。

### 4.2 核心知识点

#### 4.2.1 四个子句的语义

| 子句 | 执行条件 | 典型用途 |
|------|----------|----------|
| `try` | 总是先执行 | 放"可能出错"的核心操作 |
| `except` | `try` 抛匹配异常时 | 诊断/恢复/转换异常 |
| `else` | `try` **无异常**时 | 放"依赖 try 成功才该做"的逻辑 |
| `finally` | **无论是否异常**都执行 | 释放资源、解锁、收尾 |

#### 4.2.2 关键区别：`else` vs 把代码放进 `try`

```python
# 反例：把"依赖成功"的逻辑放进 try，会扩大捕获范围
try:
    f = open(path)
    data = f.read()        # 这里出错会被当成"读取失败"，语义错乱
    process(data)          # process 的异常也被吞进同一 except
except OSError as e:
    ...

# 正例：else 隔离"成功后才做"的逻辑
try:
    f = open(path)
    data = f.read()
except OSError as e:
    log.error("read failed", exc_info=e)
    raise
else:
    process(data)          # 这里出错不会被 OSError 分支捕获，异常类型准确
finally:
    f.close()              # 无论成功失败都关
```

**可诊断性收益**：`else` 让 `__exit__`/异常类型精确对应真实失败点，不会"读文件失败"却其实是 `process` 出错。

#### 4.2.3 `finally` 的陷阱：return 与异常

```python
def demo():
    try:
        return "try"
    finally:
        return "finally"   # finally 的 return 会覆盖 try 的 return！
```
> 规则：`finally` 中的 `return`/`break`/`continue` 会**压制** `try` 的返回值与未捕获异常。生产代码**禁止**在 `finally` 里 return。

### 4.3 实践任务

为 `datapipe` 的 `load_config` 函数补全结构：读文件失败→记日志并转换（M3 再接因果链）；读成功后解析（放 `else`）；无论成败关文件（`finally`）。

### 4.4 验收标准

- [ ] 能口述四个子句执行顺序与四种组合场景。
- [ ] 代码中"成功才执行"的逻辑在 `else`，不在 `try`。
- [ ] `finally` 中无 `return`/`break`。

---

## 5. M3 `raise ... from ...` 保留因果链（2.5h）

**主线：D（保留完整追溯）**

### 5.1 学习目标

- 区分**隐式链**（`__context__`）与**显式链**（`__cause__`）。
- 掌握再抛出时用 `raise NewError(...) from e` 保留根因。
- 掌握 `raise ... from None` 主动切断噪声链。

### 5.2 核心知识点

#### 5.2.1 问题：裸再抛出会丢失根因

```python
def load_config(path):
    try:
        with open(path) as f:
            return yaml.safe_load(f)
    except OSError as e:
        raise ConfigError("cannot load config")   # 原始 OSError 上下文变成 __context__，
                                                  # 但语义上它是"原因"而非"上下文"
```

但更糟的是下面这种——完全吞掉根因：

```python
except OSError:
    raise ConfigError("cannot load config")   # 没有 from：根因只剩 __context__，
                                              # 且若中间有其他逻辑极易被掩盖
```

#### 5.2.2 正解：显式因果链

```python
def load_config(path):
    try:
        with open(path) as f:
            return yaml.safe_load(f)
    except OSError as e:
        raise ConfigError(f"cannot load config from {path}") from e
```

异常打印将呈现：

```
ConfigError: cannot load config from ./app.yaml
The above exception was the direct cause of the following exception:
...
  File "...", in load_config
OSError: [Errno 2] No such file or directory: './app.yaml'
```

**可诊断性收益**：维护者一眼看到"配置加载失败"是**由**"文件不存在"引起的，根因链路完整。

#### 5.2.3 `__context__` vs `__cause__`

| 机制 | 触发 | 属性 | 打印文案 |
|------|------|------|----------|
| 隐式上下文 | except 块内又抛异常（无 from） | `__context__` | "During handling of the above..." |
| 显式原因 | `raise ... from e` | `__cause__` | "The above exception was the direct cause..." |
| 切断 | `raise ... from None` | `__cause__=None` | 不打印上层 |

> 经验法则：当你**故意转换**异常（OSError→ConfigError），用 `from e` 声明因果；当你只是**顺带**抛了个新错，隐式 `__context__` 也够。

#### 5.2.4 何时用 `from None`

当底层异常是**实现细节、且会误导排查**时：

```python
try:
    value = int(user_input)
except ValueError as e:
    raise InvalidInput("must be an integer") from None  # 不暴露内部解析细节
```

### 5.3 实践任务

1. **任务 A**：在 `datapipe` 的 `parse_record` 中，将 `json.JSONDecodeError` 转换为 `RecordParseError`，用 `from e` 保留原始行号。
2. **任务 B**：写测试，断言 `exc.__cause__` 是原始异常类型，且 traceback 含两层。
3. **任务 C**：判断哪类错误适合 `from None`，给出 1 例并说明理由。

### 5.4 验收标准

- [ ] 再抛出自定义异常时**一律**保留根因（from e 或显式说明为何 from None）。
- [ ] 能在 traceback 中识别出 `__cause__` 与 `__context__` 差异。
- [ ] 提供"切断噪声链"的合理场景。

---

## 6. M4 EAFP vs LBYL（2h）

**主线：D（错误位置明确）+ R（原子性回滚）**

### 6.1 学习目标

- 说清两种范式语义与性能特征。
- 识别 LBYL 的**竞态（TOCTOU）**陷阱。
- 在合适场景选对范式。

### 6.2 核心知识点

#### 6.2.1 定义

- **EAFP**（Easier to Ask for Forgiveness than Permission）：先执行，错了再处理。
  ```python
  try:
      value = cache[key]
  except KeyError:
      value = compute(key)
  ```
- **LBYL**（Look Before You Leap）：先检查，再执行。
  ```python
  if key in cache:
      value = cache[key]
  else:
      value = compute(key)
  ```

#### 6.2.2 权衡表

| 维度 | EAFP | LBYL |
|------|------|------|
| 代码可读性 | 主路径清晰，错误处理分离 | 条件分支夹在主路径中 |
| 性能（常态成功） | 异常几乎零成本 | 每次都多一次检查 |
| 原子性 | 强（一次操作） | 弱（检查与执行间可能变） |
| 并发安全 | 高（单步操作） | 低（TOCTOU 竞态） |
| 可诊断性 | 异常自带现场 | 检查失败信息往往模糊 |

#### 6.2.3 关键陷阱：LBYL 的 TOCTOU

```python
# 多进程/多线程下危险
if os.path.exists(path):        # T1: 检查存在
    with open(path) as f:       # T2: 文件已被另一线程删 → 崩
        ...
```
EAFP 没有这个窗口：

```python
try:
    with open(path) as f:
        ...
except FileNotFoundError:
    handle_missing()
```

> Python 的 GIL 不保护你免受 I/O 竞态——LBYL 在文件/网络/共享状态场景**不安全**。

#### 6.2.4 何时用 LBYL

- 检查**代价低于**异常处理（如超大对象的存在性预检）。
- 需要**提前返回**以避免后续昂贵操作。
- 显式避免副作用（如"不想触发懒加载"）。

### 6.3 实践任务

1. **任务 A**：用 EAFP 重写 `datapipe` 的"配置可选字段读取"（字段缺失→用默认值），对比 LBYL 版本。
2. **任务 B**：构造一个并发竞态示例，展示 LBYL 在 `os.path.exists` 后文件消失会崩溃，EAFP 不会。
3. **任务 C**：列出 3 个你代码中适合 LBYL 的真实场景并说明理由。

### 6.4 验收标准

- [ ] 能解释 EAFP 在 GIL 下仍存在的 TOCTOU 风险来源。
- [ ] 对"文件/网络/共享状态"默认选 EAFP。
- [ ] 不盲目崇拜任一范式，按场景取舍。

---

## 7. M5 Context Manager 协议（2.5h）

**主线：R（异常安全资源释放）**

### 7.1 学习目标

- 实现 `__enter__`/`__exit__` 协议。
- 理解 `__exit__` 在异常时的参数与**抑制语义**。
- 用 CM 保证锁/连接/事务在异常路径下正确释放与回滚。

### 7.2 核心知识点

#### 7.2.1 协议

```python
class Resource:
    def __enter__(self):
        self._acquire()
        return self            # with 语句的目标绑定这个返回值
    def __exit__(self, exc_type, exc_val, exc_tb):
        self._release()        # 无论是否异常都释放
        return False           # 返回真值 = 抑制异常；False = 不抑制
```

**关键**：`__exit__` 的三个参数是异常的"现场"，返回 `True` 会**吞掉**异常（绝大多数情况应返回 `False`）。

#### 7.2.2 可恢复性范本：事务 CM

```python
class Transaction:
    def __init__(self, conn):
        self.conn = conn
    def __enter__(self):
        self.conn.begin()
        return self.conn
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.conn.commit()       # 成功 → 提交
        else:
            self.conn.rollback()     # 异常 → 回滚到一致状态
        return False                 # 不抑制：让上层继续处理/上报
```

**可恢复性收益**：无论 `with` 块内抛什么错，连接都回到"事务已结束"的一致状态——不会留下悬挂事务锁死表。

#### 7.2.3 锁的 RAII 风格

```python
class LockScope:
    def __init__(self, lock): self.lock = lock
    def __enter__(self): self.lock.acquire(); return self
    def __exit__(self, *a): self.lock.release()   # 异常也释放，杜绝死锁
```

### 7.3 实践任务

1. **任务 A**：为 `datapipe` 实现一个 `OpenSource` CM，管理数据源连接，异常时调用 `close()` 并**不抑制**异常。
2. **任务 B**：实现一个 `timed_block` CM，记录进入/退出耗时，异常时也记一条 error 日志（用 `exc_type`）。
3. **任务 C**：演示 `__exit__` 返回 `True` 会静默吞异常（反例，仅作理解）。

### 7.4 验收标准

- [ ] 自定义 CM 在异常路径下**必**释放资源。
- [ ] 默认 `__exit__` 返回 `False`（不抑制）。
- [ ] 能用 CM 表达"成功提交/失败回滚"的恢复语义。

---

## 8. M6 `contextlib.contextmanager`（2h）

**主线：R（轻量资源管理）**

### 8.1 学习目标

- 用生成器+装饰器实现 CM，替代样板类。
- 理解 `yield` 的位置语义与异常如何流入生成器。
- 在 CM 内部正确捕获/重抛。

### 8.2 核心知识点

#### 8.2.1 基本形态

```python
from contextlib import contextmanager

@contextmanager
def transaction(conn):
    conn.begin()
    try:
        yield conn              # with 块从这里开始执行
    except Exception:           # with 块抛的异常会在此处"着陆"
        conn.rollback()
        raise                   # 必须重抛，否则异常被吞
    else:
        conn.commit()
```

#### 8.2.2 三个易错点

1. **`yield` 只出现一次**，且是分隔线：之前是 `__enter__`，之后是 `__exit__` 的正常分支。
2. **异常会注入到 `yield` 那行**：`with` 块抛错 → 生成器在 `yield` 处收到异常 → 落到 `except`。
3. **若不在生成器里 `raise`，异常被静默吞掉**——这是 M7 反模式的隐蔽版本，务必重抛。

#### 8.2.3 与 M5 类式 CM 的取舍

| 维度 | 类式 CM | `@contextmanager` |
|------|---------|-------------------|
| 样板量 | 多（两方法） | 少（一个函数） |
| 复杂状态 | 适合 | 受限 |
| 可读性 | 显式协议 | 贴近控制流 |

### 8.3 实践任务

1. **任务 A**：用 `@contextmanager` 重写 M5 的 `timed_block`。
2. **任务 B**：实现一个 `redirect_stdout_to` CM，将 `print` 临时重定向到日志，退出恢复。
3. **任务 C**：故意在生成器里漏掉 `raise`，写测试证明异常被吞，再修正。

### 8.4 验收标准

- [ ] `@contextmanager` 实现中异常能正确上抛（非静默）。
- [ ] 能说清 `yield` 前后的语义对应 `__enter__`/`__exit__`。
- [ ] 简单资源用装饰器版，复杂状态用类式版。

---

## 9. M7 禁止静默吞异常（1.5h）

**主线：D+R（无声吞没 = 诊断与恢复双重崩坏）**

### 9.1 学习目标

- 识别四类"吞异常"反模式。
- 掌握"显式处理 / 记录 / 重抛 / 转换"的正确处置四选一。
- 理解 `except Exception: pass` 为何是生产事故温床。

### 9.2 核心知识点：四大反模式

#### 反模式 1：空 `except` / `except Exception: pass`

```python
try:
    save_to_db(record)
except Exception:
    pass          # 数据丢了，没人知道；可诊断性=0，可恢复性=0
```
**危害**：错误被完全抹除，系统带病运行，故障延迟爆发且无法追溯。

#### 反模式 2：裸 `except:`（捕获所有，含 `KeyboardInterrupt`/`SystemExit`）

```python
try:
    ...
except:                  # 连 Ctrl-C 都拦，无法优雅退出
    ...
```
**危害**：破坏信号处理、掩盖编程错误（`NameError` 等本应早崩）。

#### 反模式 3：只 `print` 不处理

```python
except Exception as e:
    print(e)             # 日志里一行，无堆栈、无上下文、无后续动作
```
**危害**：看似"处理了"，实则无法定位、无法恢复。

#### 反模式 4：CM 内漏 `raise`（见 M6.2.2）

```python
@contextmanager
def cm():
    setup()
    try:
        yield
    except Exception:
        teardown()
    # 没 raise → 异常被吞
```

### 9.3 正确处置四选一（处置矩阵）

| 处置 | 适用场景 | 示例 |
|------|----------|------|
| **显式处理** | 错误可本地恢复 | 重试、用默认值、跳过坏记录 |
| **记录日志** | 需留存但继续抛 | `log.error(..., exc_info=e); raise` |
| **重抛** | 仅转换上下文，不吞 | `raise Wrapper(e)` 或裸 `raise` |
| **转换再抛** | 跨层语义转换 | `raise ConfigError(...) from e` (M3) |

**铁律**：`except` 块里**必须**出现上述四者之一。任何 `except` 后无动作 = 缺陷。

```python
# 正确范本
try:
    save_to_db(record)
except DbUnavailable as e:
    log.error("db save failed, will retry", exc_info=e)
    raise                      # 交给上层重试/告警，不吞
```

### 9.4 实践任务

1. **任务 A**：从你现有代码或本课程的 `datapipe` 草稿中找出 ≥3 处"吞异常"，逐处重写为四选一处置，并说明选了哪种。
2. **任务 B**：配置 `logger` 使异常记录带 `exc_info=True`（含堆栈），对比只 `print` 的差异。
3. **任务 C**：编写 `pytest` 测试，验证某危险函数不再静默吞错（应上抛）。

### 9.5 验收标准

- [ ] 全课程代码中**无** `except Exception: pass` / 裸 `except:` / 仅 `print`。
- [ ] 每处 `except` 都对应"处理/日志+重抛/重抛/转换"之一。
- [ ] 能向他人解释"为何绝不能静默吞异常"。

---

## 10. M8 综合实战：可诊断可恢复的 `datapipe`（3h）

**主线：D+R 总集成**

### 10.1 任务

将前述所有能力集成为生产级组件，满足两条主线验收。

### 10.2 验收清单

**可诊断性清单**
- [ ] 任意失败都抛出继承自 `DataPipeError` 的语义异常，带 `code`。
- [ ] 多层调用链用 `from e` 保留根因，traceback 可读。
- [ ] 异常信息含业务上下文（文件路径、记录行号、字段名）。
- [ ] 所有异常经 `log.error(..., exc_info=True)` 留痕。

**可恢复性清单**
- [ ] 所有文件/连接/事务用 CM 管理，异常路径下零泄漏。
- [ ] 坏记录进入"死信队列"而非中断整批（细粒度恢复）。
- [ ] 配置缺失有默认值或清晰提示（粗粒度恢复）。
- [ ] 异常发生后组件状态一致，可安全重试。

### 10.3 交付物

- `datapipe.py`：含异常层级、CM、转换逻辑。
- `test_datapipe.py`：覆盖正常、各类异常、异常路径资源释放（用临时文件/monkeypatch 验证 fd 不泄漏）。
- `README.md`：错误模型设计说明 + 排查指引（给出"看到 X 错误先看 Y"的地图）。

---

## 11. 评估与自查清单（1h）

### 11.1 知识自测（20 题抽测，覆盖 7 知识点）

- 画出 `DataPipeError` 层级并说明为何要有根。
- `else` 与 `try` 内代码在执行上有何不同？
- `finally` 中 `return` 会怎样？
- `from e` 与无 `from` 的 traceback 差异？
- LBYL 在什么场景不安全？
- `__exit__` 返回 `True` 的含义与风险？
- `@contextmanager` 中异常如何在生成器落地？
- 列出"吞异常"四大反模式。
- …（课程提供完整题库）

### 11.2 代码审查红线（PR 必查）

> 任何 PR 触发以下任一条 → 一票否决：
> 1. `except Exception: pass` / 裸 `except:` / 仅 `print(e)`。
> 2. 裸抛 `Exception`/`RuntimeError` 且无结构化信息。
> 3. 再抛出丢失根因（无 `from` 且无正当理由）。
> 4. 资源获取后未在 `finally`/CM 中释放。
> 5. CM 的 `__exit__` 默认返回 `True` 或生成器漏 `raise`。

### 11.3 两条主线自评表

| 维度 | 1 分（差） | 5 分（优） |
|------|-----------|-----------|
| 可诊断性 | 线上报错只有 `Exception` | 报错自带根因链+业务上下文+日志堆栈 |
| 可恢复性 | 异常后资源泄漏/状态错乱 | 异常路径零泄漏+可重试+状态一致 |

---

## 12. 附录

### 12.1 速查表（贴工位）

```
异常设计：
  ✅ 单一根 + 语义分层 + 带 code
  ✅ 再抛出必 from e（或 from None 且有理由）
  ❌ 裸 Exception / RuntimeError

try/except/else/finally：
  ✅ 成功才做 → else；必做清理 → finally
  ❌ finally 里 return/break

EAFP vs LBYL：
  ✅ 文件/网络/共享状态 → EAFP（防 TOCTOU）
  ✅ 昂贵预检/提前返回 → LBYL

资源管理：
  ✅ 一切资源用 CM（类式 / @contextmanager）
  ✅ __exit__ 默认返回 False
  ❌ 吞异常：except: pass / 仅 print / 生成器漏 raise
```

### 12.2 与"大模型职业课程"的衔接

- 本课的"异常安全 + 资源不泄漏"是后续 **C++ 性能工程（CUDA 资源/流管理）** 与 **PyTorch 自定义算子异常路径** 的直接前置。
- "可诊断性"思维同样适用于 **vLLM 源码阅读**：vLLM 的 `raise ... from ...`、调度器异常恢复、KV cache block 管理的 CM，都是本课原则的生产级范例。

---

*文档版本 v1.0 · 可作为「大模型职业课程」M1 Python 进阶深潜模块，亦可独立作为工程化入职培训。*
