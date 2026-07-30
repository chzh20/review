下面是整理后的标准 Markdown 文档，可以直接保存为 `python_logging_study.md`。

***

# Python Logging 学习笔记

> 基于 Python Logging HOWTO 与 mini-infer Day5《日志与可观测性》课程总结。重点理解 Logger、Handler、Formatter、Level、ContextVar 之间的协作关系。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)

***

# 一、为什么需要 Logging

很多初学者习惯：

```python
print("推理开始")
print("推理结束")
```

但工程系统中 `print()` 存在明显缺陷：

* 无法按严重程度分类
* 无法统一关闭或打开
* 无法输出到不同目标
* 无法携带上下文信息
* 不利于线上问题排查

因此生产环境通常使用 Logging 系统，而非直接使用 `print()`。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)

***

# 二、Logging 整体架构

可以将 Logging 理解为一条流水线：

```text
logger.info(...)
        │
        ▼
    Logger
        │
        ▼
   LogRecord
        │
        ▼
     Filter
        │
        ▼
    Handler
        │
        ▼
   Formatter
        │
        ▼
 Console / File / ELK
```

***

# 三、核心组件理解

## 1. Logger

Logger 是日志入口。

例如：

```python
logger = logging.getLogger(__name__)

logger.info("推理开始")
```

职责：

* 接收日志调用
* 创建 LogRecord
* 判断 Level 是否允许通过
* 将日志分发给 Handler

可以理解为：

```text
Logger = 日志生产者
```

***

## 2. LogRecord

每条日志都会被封装成一个对象：

```python
logger.info(
    "推理结束",
    extra={
        "request_id": "abc123",
        "latency": 23
    }
)
```

实际形成：

```text
LogRecord
├── message
├── level
├── module
├── filename
├── lineno
├── request_id
└── latency
```

后续所有组件都在处理这个对象。

***

## 3. Filter

Filter 相当于检查员。

作用：

* 决定是否放行
* 自动补充日志字段
* 修改日志内容

课程中的典型例子：

```python
class RequestIdFilter(logging.Filter):

    def filter(self, record):
        record.request_id = request_id_var.get()
        return True
```

这样：

```python
logger.info("分词完成")
```

自动变成：

```text
request_id=ab12cd
message=分词完成
```

无需每处都写：

```python
extra={"request_id": xxx}
```

***

## 4. Handler

Handler 决定：

> 日志最终输出到哪里

常见类型：

### 输出到终端

```python
logging.StreamHandler()
```

***

### 输出到文件

```python
logging.FileHandler()
```

***

### 输出到网络

例如：

```text
Kafka
Syslog
Fluentd
ELK
```

***

一个 Logger 可以挂多个 Handler：

```text
Logger
├── ConsoleHandler
└── FileHandler
```

因此：

```python
logger.info("启动")
```

可以同时输出到：

```text
控制台
文件
```

***

## 5. Formatter

Formatter 决定：

> 日志长什么样

例如：

```python
"%(asctime)s %(levelname)s %(message)s"
```

输出：

```text
2026-07-30 10:00:00 INFO 推理开始
```

***

包含 request\_id：

```python
"%(request_id)s %(message)s"
```

输出：

```text
ab12cd 推理开始
```

***

JSON 格式：

```json
{
  "request_id": "ab12cd",
  "message": "推理开始"
}
```

Formatter 只负责格式化，不负责决定是否记录。

***

# 四、Level（日志级别）

日志级别从低到高：

```text
DEBUG      10
INFO       20
WARNING    30
ERROR      40
CRITICAL   50
```

课程中强调：

> Level 本质上是一个阈值（Threshold）。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)

***

## Level 过滤规则

```text
日志级别 >= 当前Level
保留

日志级别 < 当前Level
过滤
```

例如：

```python
logger.setLevel(logging.INFO)
```

结果：

| 日志级别     | 是否保留 |
| -------- | ---- |
| DEBUG    | ❌    |
| INFO     | ✅    |
| WARNING  | ✅    |
| ERROR    | ✅    |
| CRITICAL | ✅    |

***

# 五、Logger Level 与 Handler Level

Level 可以同时存在于：

* Logger
* Handler

例如：

```python
logger.setLevel(INFO)
handler.setLevel(ERROR)
```

执行：

```python
logger.info("A")
logger.error("B")
```

流程：

```text
INFO
 ↓
Logger通过
 ↓
Handler拒绝

ERROR
 ↓
Logger通过
 ↓
Handler通过
```

最终输出：

```text
ERROR B
```

因此：

> 实际生效的是更严格的限制。

***

# 六、Logger 的树状结构

项目中通常写：

```python
logger = logging.getLogger(__name__)
```

假设目录结构：

```text
mini_infer
├── engine/session.py
├── model/runner.py
└── scheduler/core.py
```

则自动生成：

```text
mini_infer.engine.session
mini_infer.model.runner
mini_infer.scheduler.core
```

形成树：

```text
root
└── mini_infer
    ├── engine
    │   └── session
    ├── model
    │   └── runner
    └── scheduler
        └── core
```

***

# 七、Logger Level 继承机制

很多 Logger 实际上没有设置 Level：

```python
logger.level == NOTSET
```

此时会向父节点查找：

```text
session
  ↑
engine
  ↑
mini_infer
  ↑
root
```

找到最近的有效 Level。

例如：

```python
root = WARNING
mini_infer = INFO
session = NOTSET
```

最终：

```text
session → INFO
```

而不是 WARNING。

***

# 八、为什么不推荐修改 Root Logger

危险做法：

```python
logging.getLogger().setLevel(DEBUG)
```

这会修改：

```text
root logger
```

整个进程受影响：

```text
requests
urllib3
grpc
pytest
torch
```

统统变成：

```text
DEBUG
```

可能导致：

```text
日志暴增
性能下降
排查困难
```

课程明确强调：

> 库只负责产生记录，不负责修改 root logger。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)

***

# 九、推荐实践

## 库内部

只做：

```python
logger = logging.getLogger(__name__)

logger.info(...)
```

不要：

```python
logging.basicConfig(...)
logging.getLogger().setLevel(...)
```

***

## 应用入口

统一配置：

```python
configure_logging()
```

负责：

* Handler
* Formatter
* Level

管理。

***

# 十、如何统一控制所有模块

推荐设置项目根 Logger：

```python
logging.getLogger("mini_infer").setLevel(
    logging.INFO
)
```

此时：

```text
mini_infer.engine.*
mini_infer.model.*
mini_infer.scheduler.*
```

全部继承：

```text
INFO
```

但：

```text
requests
urllib3
grpc
```

不受影响。

***

## 单独开启某模块 DEBUG

例如：

```python
logging.getLogger(
    "mini_infer.scheduler"
).setLevel(logging.DEBUG)
```

结果：

```text
mini_infer.engine      INFO
mini_infer.model       INFO
mini_infer.scheduler   DEBUG
```

这是生产环境定位问题的常见方法。

***

# 十一、ContextVar 的意义

日志系统需要把同一次请求串起来：

```text
tokenizer
 ↓
model
 ↓
scheduler
 ↓
cache
 ↓
decode
```

输出：

```text
request_id=ab12 tokenize
request_id=ab12 forward
request_id=ab12 decode
```

***

## 方案比较

### 方案1：参数传递

```python
def func(request_id):
```

缺点：

```text
污染所有函数签名
```

***

### 方案2：全局变量

```python
current_request_id
```

缺点：

```text
并发场景会串台
```

***

### 方案3：ContextVar

```python
request_id_var = ContextVar(
    "request_id",
    default="-"
)
```

优点：

* 自动传播
* asyncio安全
* 不需要传参
* 不会串请求

这也是课程推荐方案。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)

***

# 十二、ContextVar 与 Filter 配合

请求开始：

```python
request_id_var.set("ab12")
```

Filter：

```python
class RequestIdFilter(logging.Filter):

    def filter(self, record):
        record.request_id = request_id_var.get()
        return True
```

业务代码：

```python
logger.info("模型前向")
```

最终输出：

```text
INFO request_id=ab12 模型前向
```

实现：

```text
一次设置
全链路自动携带
```

***

# 十三、什么情况下调整 Log Level

## 开发阶段

```text
DEBUG
```

查看细节。

***

## 测试环境

```text
INFO
```

验证流程。

***

## 生产环境

通常：

```text
INFO
```

保留：

```text
INFO
WARNING
ERROR
CRITICAL
```

过滤：

```text
DEBUG
```

***

## 线上故障排查

临时切换：

```text
DEBUG
```

收集更多信息。

***

## 日志量过大

临时提高：

```text
WARNING
```

减少日志量。

***

# 十四、配置文件统一管理

推荐配置：

```yaml
logging:
  loggers:
    mini_infer: INFO
    mini_infer.scheduler: DEBUG
    requests: WARNING
```

启动时：

```python
logging.config.dictConfig(...)
```

效果：

```text
mini_infer.*            INFO
mini_infer.scheduler.*  DEBUG
requests.*              WARNING
```

无需修改代码即可调整日志策略。

***

# 最终心智模型

```text
Logger
   │
   ├── Level
   │
   ▼
LogRecord
   │
   ▼
Filter
(补充 request_id)
   │
   ▼
Handler
(决定去哪)
   │
   ▼
Formatter
(决定长什么样)
   │
   ▼
Console / File / ELK
```

## 五条必须记住的原则

1. 使用 `logging.getLogger(__name__)`
2. Level 是阈值，不是精确匹配
3. Logger 和 Handler 都会过滤日志
4. 库不要修改 Root Logger
5. 使用 `ContextVar + Filter` 实现 request\_id 自动传播

这是现代 Python 项目可观测性的基础设计。 [\[github.com...ability.md\]](https://github.com/chzh20/review/blob/workbuddy/mini-infer-course/day5-logging-observability.md)
