# 日志与可观测性：从 `print` 到请求生命周期追踪

> 一门以「可定位请求生命周期」为主线的日志工程化课程，并贯穿「敏感数据不出日志」的安全红线。
> 学完应能：设计分层 logger 体系、用结构化字段描述一次推理请求、用 request ID 串起全链路、并划清"日志"与"异常"的职责边界。

---

## 0. 课程定位与目标

### 0.1 为什么不能只靠 `print`

`print` 的问题：无级别、无时间戳、无请求归属、无结构、进 stdout 难采集、且**无法在异常路径保留上下文**。当线上一次推理变慢或报错，你面对一堆无标识的 stdout，无法回答："这是哪个请求？卡在哪一步？prompt 多大？cache 用了多少？"

可观测的日志系统要回答三件事：**谁（request ID）、做了什么（event）、关键度量是多少（structured fields）**。

### 0.2 两条主线

| 主线 | 含义 | 设计问题 |
|------|------|----------|
| **可定位性（Locatability）** | 单条请求的全生命周期可被串起、被检索 | "给定 request ID，能否还原这次请求从进入到完成的每一步与耗时？" |
| **安全性（Safety）** | 敏感数据不落日志 | "prompt / token / 用户 PII 是否以明文出现在任何一条日志里？" |

> 本课程与《异常设计与资源管理》是姊妹篇：异常管"错误如何表达与恢复"，日志管"过程如何被观测"。两门合起来构成"可诊断性"的完整地基。

### 0.3 学习目标

1. 用 `logging.getLogger(__name__)` 建立**分层、可控**的 logger 体系。
2. 说清 **logger / handler / formatter / level** 四件套职责，能独立配置。
3. 理解**库代码不应配置 root logger** 的原因，并会用 `NullHandler` 替代。
4. 定义**结构化日志字段**并输出为可采集格式（JSON Lines）。
5. 用 `contextvars` + `Filter` 实现 **request ID / correlation ID 的注入与跨调用传播**。
6. 划清**日志与异常处理的职责边界**（何时记、何时抛、记几次）。
7. 落地**敏感数据脱敏**，确保 prompt / token 等不以明文进日志。

### 0.4 前置与贯穿案例

- 前置：Python 基础 + 本课程姊妹篇《异常设计与资源管理》（尤其是 `raise ... from ...` 与"禁止静默吞异常"）。
- 贯穿案例：为**一次 LLM 推理请求**构建日志能力。最终交付一个 `inference_logging` 模块，使单次请求产出含 `request_id / tokenizer_ms / prompt_tokens / decode_tokens / cache_usage / total_latency_ms` 的结构化日志，并用 `pytest` + `caplog` 验证三条性质。

---

## 1. 模块总览

| 模块 | 主题 | 主线 | 课时 |
|------|------|------|------|
| M0 | 导论：从 print 到可观测性 | 定位+安全 | 1h |
| M1 | `getLogger(__name__)` 正确用法 | 定位 | 1h |
| M2 | 四件套职责分工与配置 | 定位 | 2h |
| M3 | 库代码不应配置 root logger | 定位 | 1h |
| M4 | 结构化日志：字段定义与输出 | 定位 | 2h |
| M5 | request ID 注入与传播 | 定位 | 2.5h |
| M6 | 日志 vs 异常处理的边界 | 定位+安全 | 1.5h |
| M7 | 敏感数据不出日志 | 安全 | 1.5h |
| M8 | 综合实战：推理请求日志 + caplog 验证 | 定位+安全 | 3h |
| — | 评估与自查 | — | 1h |

**总课时约 16.5h**。

---

## 2. M0 导论（1h）

### 2.1 一个真实排查场景

> 用户反馈："刚才那次翻译好慢，还报错了。"  
> 你只有两行 stdout：`start` / `error`。  
> 无法知道：哪个用户、哪次请求、卡在 tokenizer 还是 decode、prompt 多长、cache 命中如何。

### 2.2 可观测日志的最小信息模型

```
[ts][level][request_id][event] {structured_fields}
```

- `request_id`：把同一次请求的所有日志收拢到一条线索。
- `event`：生命周期阶段（`request.received` / `request.complete` / `request.failed`）。
- `structured_fields`：机器可检索的度量（延迟、token 数、cache）。

### 2.3 自查题

找出你代码里所有 `print(...)`，按"这条信息如果出现在线上排查中，能否定位请求与阶段"打分 1–5。

---

## 3. M1 `logging.getLogger(__name__)` 正确用法（1h）

**主线：可定位性**

### 3.1 学习目标

- 理解 `__name__` 带来的**层级命名**（如 `inference.server`）。
- 区分"模块级 logger"与"root logger"。
- 掌握层级 level 继承与按模块调级别。

### 3.2 核心知识点

#### 3.2.1 永远用模块名，绝不裸用 root

```python
# ✅ 库/模块代码：以 __name__ 命名，层级自动形成
import logging
logger = logging.getLogger(__name__)   # 例：在 inference/server.py 中 => "inference.server"

def handle(req):
    logger.info("handling request", extra={"request_id": req.id})
```

```python
# ❌ 反例：直接拿 root
logging.getLogger().info("...")         # 匿名、无法按模块控制、易与第三方冲突
logging.info("...")                     # 同上，且绕过任何层级策略
```

#### 3.2.2 层级带来的能力

logger 名称用 `.` 分隔即形成树。`inference.server` 的父是 `inference`，再上是 `root`。
- 可单独给 `inference.server` 调成 `DEBUG`，其余保持 `INFO`。
- 配置只在**应用入口**做一次，库代码不配置（见 M3）。

```python
logging.getLogger("inference.server").setLevel(logging.DEBUG)  # 精准调级别
```

### 3.3 实践任务

1. 把上一门课的 `datapipe` 模块里的 `print` 全部替换为 `getLogger(__name__)` + 结构化字段。
2. 验证：仅把 `datapipe.source` 调到 `DEBUG`，其余模块不受影响。

### 3.4 验收

- [ ] 全模块使用 `getLogger(__name__)`，无裸 root 调用。
- [ ] 能解释 `__name__` 如何自然形成层级。
- [ ] 能对单个子模块独立调级别。

---

## 4. M2 四件套：logger / handler / formatter / level（2h）

**主线：可定位性**

### 4.1 学习目标

- 说清四者职责边界。
- 独立完成"控制台 + 文件 + JSON"的多 handler 配置。
- 理解 effective level 的继承规则。

### 4.2 核心知识点

#### 4.2.1 职责表

| 组件 | 职责 | 类比 |
|------|------|------|
| **logger** | 入口。决定"这条记不记"（按 level），生成 `LogRecord` | 前台：接单 |
| **handler** | 决定"记到哪"（console/file/network/syslog），可有自己的 level | 快递：送到不同目的地 |
| **formatter** | 决定"长什么样"（格式、结构化） | 包装：贴标签 |
| **level** | 过滤阈值。`DEBUG<INFO<WARNING<ERROR<CRITICAL` | 门槛 |

> 关键认知：**logger 有 level（决定发不发），handler 也有 level（决定它收不收）**。一条记录要输出，必须**两者**都放行。

#### 4.2.2 一个完整配置

```python
import logging

logger = logging.getLogger("inference")
logger.setLevel(logging.DEBUG)          # 入口门槛：DEBUG 及以上都产生记录

# handler 1：控制台（人类读），INFO 起
console = logging.StreamHandler()
console.setLevel(logging.INFO)
console.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))

# handler 2：文件（机器采集），DEBUG 起，JSON
file_h = logging.FileHandler("inference.jsonl")
file_h.setLevel(logging.DEBUG)
file_h.setFormatter(JsonFormatter())     # 见 M4

logger.addHandler(console)
logger.addHandler(file_h)
logger.propagate = False                 # 自有 handler，别再冒泡到 root 重复输出
```

#### 4.2.3 effective level

若 logger 未设 level，它继承**最近祖先**的有效 level（最终到 root 默认 `WARNING`）。所以"没日志"的常见原因是：忘记给 logger 设 level，被 root 的 `WARNING` 挡掉。

### 4.3 实践任务

为 `inference` logger 配置：控制台 `INFO`（文本）、文件 `DEBUG`（JSON）、错误单独一个 `error.log`（`ERROR`）。验证一条 `DEBUG` 只进文件、一条 `ERROR` 三处都在。

### 4.4 验收

- [ ] 能口述四件套职责与"双 level"放行规则。
- [ ] 多 handler 配置正确，无重复日志（propagate=False）。
- [ ] 能解释"为何没日志"的根因（effective level）。

---

## 5. M3 库代码不应配置 root logger（1h）

**主线：可定位性**

### 5.1 学习目标

- 说清"库配置 root"为何是反模式。
- 掌握 `NullHandler` 替代方案。
- 让库"零配置即静默"，由应用统一接管。

### 5.2 核心知识点

#### 5.2.1 为什么不能碰 root

```python
# ❌ 库代码里的灾难：调用了 basicConfig
import logging
logging.basicConfig(level=logging.DEBUG)   # 全局生效、无法撤销、与宿主应用打架
```

`basicConfig` 只生效一次（后续调用被忽略），且配置的是 **root**。问题：
1. 库单方面决定了整个进程的日志格式/级别，宿主应用失控。
2. 多个库各自 `basicConfig` 互相覆盖，行为不确定。
3. 测试里一旦触发，污染所有用例的输出。

#### 5.2.2 正确做法：库用 `NullHandler`，应用来配置

```python
# ✅ 库代码标准做法（Python 官方 logging 文档推荐）
import logging
logger = logging.getLogger(__name__)
logger.addHandler(logging.NullHandler())   # 没被应用配置时 = 完全静默
# 注意：不要 setLevel、不要 addHandler(StreamHandler)、不要 basicConfig
```

宿主应用在入口处统一 `configure_logging()`（如 M2/M8），配置 root 或顶层 logger，库日志随之被接管。

### 5.3 实践任务

把 M1 中改造的 `datapipe` 改成"库形态"：移除任何 `basicConfig`/控制台 handler，只留 `NullHandler`。写一个 `app/main.py` 在入口配置，验证 datapipe 的日志被应用格式捕获。

### 5.4 验收

- [ ] 库代码中无 `basicConfig`、无 `StreamHandler` 直连。
- [ ] 库默认静默（NullHandler），由应用配置后才有输出。
- [ ] 能解释 root 被库污染的三类后果。

---

## 6. M4 结构化日志：字段定义与输出（2h）

**主线：可定位性**

### 6.1 学习目标

- 定义一套**稳定、可检索**的结构化字段 schema。
- 用 `Formatter` 输出 JSON Lines，便于日志系统采集。
- 区分"事件字段"与"上下文字段"。

### 6.2 核心知识点

#### 6.2.1 字段 schema（推理请求示例）

| 字段 | 类型 | 说明 |
|------|------|------|
| `ts` | str(ISO8601) | 时间戳 |
| `level` | str | 级别 |
| `request_id` | str | 请求标识（M5 注入） |
| `event` | str | 生命周期阶段 |
| `model` | str | 模型名 |
| `prompt_tokens` | int | 输入 token 数（**不记 prompt 文本**） |
| `decode_tokens` | int | 输出 token 数 |
| `tokenizer_ms` | float | tokenizer 耗时 |
| `cache_usage` | float | KV cache 占用（0–1 或 MB） |
| `total_latency_ms` | float | 总延迟 |

> 字段设计原则：**只记"度量与标识"，不记"内容"**。这正是 M7 安全红线的前置约定。

#### 6.2.2 JSON Formatter 实现

```python
import json, logging
from datetime import datetime, timezone

class JsonFormatter(logging.Formatter):
    def format(self, record):
        ts = (datetime.fromtimestamp(record.created, tz=timezone.utc)
              .strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(record.msecs):03d}Z")
        payload = {
            "ts": ts,
            "level": record.levelname,
            "logger": record.name,
            "request_id": getattr(record, "request_id", "-"),
            "event": record.getMessage(),
        }
        payload.update(getattr(record, "structured", {}) or {})  # 合并业务字段
        return json.dumps(payload, ensure_ascii=False)
```

使用：`extra={"structured": {...}}` 把业务字段附到记录上。

```python
logger.info("request.complete",
            extra={"structured": {"prompt_tokens": 128, "decode_tokens": 32,
                                  "total_latency_ms": 412.5}})
# => {"ts":"...","level":"INFO","request_id":"req-1","event":"request.complete",
#     "prompt_tokens":128,"decode_tokens":32,"total_latency_ms":412.5}
```

#### 6.2.3 生产选项

`structlog` / `python-json-logger` 可免写 Formatter，但**先掌握 stdlib**，理解"事件 + 结构化字段"的本质，再上框架。

### 6.3 实践任务

1. 用 `JsonFormatter` 重构 M2 的文件 handler。
2. 定义你项目的字段 schema（至少 8 个字段），写注释说明每个字段的检索用途。

### 6.4 验收

- [ ] 日志为合法 JSON，字段可被 `jq`/`json.loads` 解析。
- [ ] 业务字段经由 `extra={"structured": ...}` 注入，不混进 message。
- [ ] schema 文档化，区分标识/度量字段。

---

## 7. M5 request ID 注入与传播（2.5h）

**主线：可定位性（本课核心）**

### 7.1 学习目标

- 用 `contextvars` 在请求生命周期内持有 request ID。
- 用 `logging.Filter` 把 request ID 自动注入每条记录。
- 理解其在 `asyncio` 与多线程下的传播语义。

### 7.2 核心知识点

#### 7.2.1 为什么不用全局变量 / 函数参数透传

全局变量在并发下串号；参数透传污染每个函数签名。正确方案：**`contextvars` + Filter**——请求 ID 存于"上下文"，自动随调用链/协程流动，Filter 在每条记录格式化前把上下文值贴上去。

#### 7.2.2 注入：ContextVar + Filter

```python
import contextvars, logging

request_id_ctx = contextvars.ContextVar("request_id", default="-")

class RequestIDFilter(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_ctx.get()   # 每条记录自动带 ID
        return True

# 配置时挂上
handler.addFilter(RequestIDFilter())
```

#### 7.2.3 传播：在请求入口设值

```python
def handle_request(req):
    token = request_id_ctx.set(req.id)        # 进入请求，设置 ID
    try:
        run_inference(req)
        # 同一请求内任何深层函数打的日志，都自动带 req.id
    finally:
        request_id_ctx.reset(token)           # 退出请求，清理（防连接复用串号）
```

#### 7.2.4 并发语义（重要）

- **asyncio**：每个 `Task` 自动复制当前 context，`await` 切换不串号——天然安全。
- **多线程**：`threading` 默认**不**复制 context。跨线程需手动携带：

```python
import contextvars
ctx = contextvars.copy_context()
thread = threading.Thread(target=ctx.run, args=(worker,))
```

> 推理服务常把请求丢进线程池/进程池，务必确认 context 被带过去，否则 request ID 串号，全链路追踪失效。

### 7.3 实践任务

1. 在 `inference` 模块实现 `RequestIDFilter` 与 `request_id_ctx`。
2. 写一个 `handle_request`，深层函数 `tokenize()` 内打日志，验证不需要传参也能带 ID。
3. 构造并发场景：两个请求交错，验证各自的 ID 不串。

### 7.4 验收

- [ ] 深层函数日志无需传参即携带正确 request ID。
- [ ] 请求结束 `reset`，连接复用不串号。
- [ ] 能解释 asyncio / 多线程下 context 的传播差异与对策。

---

## 8. M6 日志与异常处理的职责边界（1.5h）

**主线：可定位性 + 安全性（衔接姊妹篇）**

### 8.1 学习目标

- 说清"何时该记日志、何时该抛异常、记几次"。
- 避免"每层都 log-and-reraise"的噪声。
- 与《异常设计与资源管理》的 `raise ... from ...` 协作。

### 8.2 核心知识点

#### 8.2.1 一句话边界

> **异常**是给**调用方**的控制信号（"这事没成，你要不要处理"）；**日志**是给**未来排查者**的观测记录（"这事发生了， context 如下"）。

#### 8.2.2 四条规则

1. **记一次，在处理边界记**。不要每层都 `except: log(); raise`——会在日志里刷出 N 条相同错误。只在**真正处理/决定恢复**的那一层记。
2. **转换异常用 `raise ... from e`，不要为"记录"而捕获**。`from e` 已保留因果链（见姊妹篇 M3），无需额外 `log()` 再抛。
3. **ERROR/CRITICAL = 需人介入**；`INFO` = 生命周期；`DEBUG` = 内部细节。别把正常分支打成 ERROR。
4. **日志不替代异常**：捕获后只 `log` 不 `raise` 且不恢复 = 静默吞异常（姊妹篇 M7 反模式）。要么恢复、要么重抛、要么转换，不能只记。

```python
# ✅ 正确：底层抛（带 from），中间层不拦，顶层处理边界记一次
def load_config(path):
    try:
        return yaml.safe_load(open(path))
    except OSError as e:
        raise ConfigError(f"load {path} failed") from e   # 不在此 log

# 顶层（应用入口/请求处理）统一记：
try:
    cfg = load_config(p)
except ConfigError as e:
    logger.error("config load failed, using fallback",  # 仅此一次
                 extra={"request_id": ..., "path": p}, exc_info=e)
    cfg = DEFAULT
```

### 8.3 实践任务

审查 `datapipe` 与 `inference` 现有代码，找出"每层 log-and-reraise"或"只 log 不抛"的实例，按四条规则重构。

### 8.4 验收

- [ ] 同一错误在日志中只出现一次（在处理边界）。
- [ ] 异常转换用 `from e`，不靠 log 保留上下文。
- [ ] 无"只 log 不抛/不恢复"的静默路径。

---

## 9. M7 敏感数据不出日志（1.5h）

**主线：安全性（红线）**

### 9.1 学习目标

- 识别 LLM 场景的敏感数据类别（prompt、token、PII）。
- 用脱敏 Filter 在"出口"统一拦截，而非依赖每人记得不记。
- 理解日志常流向第三方采集，属合规（PIPL/GDPR）范畴。

### 9.2 核心知识点

#### 9.2.1 敏感字段清单（LLM 特有关注）

| 类别 | 示例 | 处理 |
|------|------|------|
| 用户输入 prompt | 用户原话、系统提示词 | 只记长度/token 数，**不记文本** |
| token 序列 | input_ids / output_ids | 只记数量，不记原始 id |
| 解码文本 | 模型输出全文 | 仅错误排查可记截断摘要 |
| 用户 PII | 姓名/手机号/邮箱 | 哈希或完全剔除 |

#### 9.2.2 用 Filter 在出口拦截（防御性，不靠自觉）

```python
SENSITIVE_FIELDS = {"prompt", "raw_tokens", "decoded_text", "user_input"}

class RedactionFilter(logging.Filter):
    def filter(self, record):
        struct = getattr(record, "structured", {}) or {}
        for key in SENSITIVE_FIELDS:
            if key in struct:
                struct[key] = "<redacted>"     # 统一脱敏，写日志的人无需记得
        return True

handler.addFilter(RedactionFilter())
```

> 这是**纵深防御**：即使某处误把 `prompt` 塞进了 `structured`，Formatter 输出前也会被替换为 `<redacted>`。配合 M4 的 schema 约定（字段里根本不该有 prompt），双重保险。

#### 9.2.3 需要部分可见时

用**截断 + 哈希**：`hash(prompt)[:8]` 用于关联同内容请求，但不还原文本；或只存 `len(prompt)`。

### 9.3 实践任务

1. 在 `inference` handler 上挂 `RedactionFilter`。
2. 故意在结构化字段塞入 `prompt="机密内容..."`，验证输出中被 `<redacted>`。
3. 列出你系统的敏感字段清单，写进 schema 文档的"禁止字段"区。

### 9.4 验收

- [ ] 任何 `prompt` / token / PII 明文不会出现在最终日志输出。
- [ ] 脱敏在 Filter 层统一做，不依赖开发者自觉。
- [ ] 文档明确列出禁止字段。

---

## 10. M8 综合实战：推理请求日志模块 + caplog 验证（3h）

**主线：可定位性 + 安全性总集成**

### 10.1 交付物

- `inference_logging.py`：配置函数 + request ID 机制 + 结构化字段 + 脱敏。
- `test_inference_logging.py`：用 `pytest` + `caplog` 验证三条性质。
- `README.md`：字段 schema + 排查指引（"看到 `request.failed` 先看 `error` 字段与 `request_id`"）。

### 10.2 完整实现（`inference_logging.py`）

```python
"""inference_logging.py — 一次推理请求的可观测性日志模块。

设计要点：
- logger 用 __name__，由应用侧 configure_logging 统一配置（库不碰 root）。
- request_id 经 contextvars 在请求生命周期内传播，Filter 自动注入每条记录。
- 结构化字段只含"度量与标识"，prompt/token 文本绝不进日志（脱敏 Filter 兜底）。
"""
import json
import time
import logging
import contextvars
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone

# —— 请求级上下文：随协程/线程隔离传播 ——
request_id_ctx = contextvars.ContextVar("request_id", default="-")

# —— 模块级 logger（正确命名，不碰 root）——
logger = logging.getLogger(__name__)

# 安全字段：绝不以明文出现在日志（防御性脱敏）
SENSITIVE_FIELDS = {"prompt", "raw_tokens", "decoded_text", "user_input"}


class RequestIDFilter(logging.Filter):
    """把当前请求 ID 注入每条记录。"""
    def filter(self, record):
        record.request_id = request_id_ctx.get()
        return True


class RedactionFilter(logging.Filter):
    """结构化字段出口脱敏。"""
    def filter(self, record):
        struct = getattr(record, "structured", {}) or {}
        for key in SENSITIVE_FIELDS:
            if key in struct:
                struct[key] = "<redacted>"
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record):
        ts = (datetime.fromtimestamp(record.created, tz=timezone.utc)
              .strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(record.msecs):03d}Z")
        payload = {
            "ts": ts,
            "level": record.levelname,
            "logger": record.name,
            "request_id": getattr(record, "request_id", "-"),
            "event": record.getMessage(),
        }
        payload.update(getattr(record, "structured", {}) or {})
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level=logging.INFO, redact=True, stream=None):
    """应用侧一次性配置。库代码禁止调用。"""
    logger.handlers.clear()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(RequestIDFilter())
    if redact:
        handler.addFilter(RedactionFilter())
    logger.addHandler(handler)
    logger.setLevel(level)
    logger.propagate = False
    return logger


@dataclass
class InferenceMetrics:
    request_id: str
    tokenizer_ms: float = 0.0
    prompt_tokens: int = 0
    decode_tokens: int = 0
    cache_usage: float = 0.0
    total_latency_ms: float = 0.0


@contextmanager
def inference_request(request_id, *, prompt, prompt_tokens, model="default"):
    """一次推理请求的生命周期上下文。

    注意：prompt 仅用于内部逻辑，绝不写入日志；
    日志只记录 prompt_tokens（数量），不记录 prompt 内容（安全红线）。
    """
    token = request_id_ctx.set(request_id)
    start = time.perf_counter()
    metrics = InferenceMetrics(request_id=request_id, prompt_tokens=prompt_tokens)
    logger.info("request.received",
                extra={"structured": {"model": model, "prompt_tokens": prompt_tokens}})
    try:
        yield metrics
        # 调用方在 with 块内更新 metrics（tokenizer_ms / decode_tokens / cache_usage）
        metrics.total_latency_ms = round((time.perf_counter() - start) * 1000, 3)
        logger.info("request.complete", extra={"structured": metrics.__dict__})
    except Exception as e:
        metrics.total_latency_ms = round((time.perf_counter() - start) * 1000, 3)
        logger.error("request.failed", exc_info=e,
                     extra={"structured": {
                         "request_id": request_id,
                         "prompt_tokens": prompt_tokens,
                         "total_latency_ms": metrics.total_latency_ms,
                         "error": type(e).__name__,
                     }})
        raise  # 异常仍上抛，由调用方按 M6 边界处理
    finally:
        request_id_ctx.reset(token)
```

### 10.3 验证用例（`test_inference_logging.py`）

> 关键测试技巧：生产配置 `propagate=False`（避免向 root 重复输出，见 M2/M3），但 `caplog` 默认只捕获冒泡到 root 的记录。测试时需**把 `caplog.handler` 直接挂到推理 logger**，显式捕获——这本身正是 M3"不碰 root"原则的体现。

```python
import json
import logging
import io
import pytest
import inference_logging as il


def _attach_caplog(caplog):
    """把 caplog 的捕获 handler 直接挂到推理 logger（绕过 root 传播）。"""
    il.logger.addHandler(caplog.handler)
    il.logger.setLevel(logging.DEBUG)


def _records(caplog):
    return [json.loads(r.message) for r in caplog.records
            if r.message.strip().startswith("{")]


def test_normal_path_complete_lifecycle(caplog):
    il.configure_logging(level=logging.DEBUG, stream=io.StringIO())
    _attach_caplog(caplog)

    with il.inference_request("req-1", prompt="translate hello", prompt_tokens=5) as m:
        m.tokenizer_ms = 1.2
        m.decode_tokens = 10
        m.cache_usage = 0.4

    recs = _records(caplog)
    events = [r["event"] for r in recs]
    assert "request.received" in events
    assert "request.complete" in events

    complete = [r for r in recs if r["event"] == "request.complete"][0]
    for f in ["request_id", "tokenizer_ms", "prompt_tokens",
              "decode_tokens", "cache_usage", "total_latency_ms"]:
        assert f in complete, f"缺失字段 {f}"
    assert complete["request_id"] == "req-1"
    assert complete["prompt_tokens"] == 5
    assert complete["decode_tokens"] == 10


def test_error_path_retains_request_id_and_context(caplog):
    il.configure_logging(level=logging.DEBUG, stream=io.StringIO())
    _attach_caplog(caplog)

    with pytest.raises(ValueError):
        with il.inference_request("req-2", prompt="x", prompt_tokens=2):
            raise ValueError("boom")

    err = [r for r in caplog.records if r.levelno >= logging.ERROR]
    assert err, "错误路径应产出 ERROR 日志"
    payload = json.loads(err[-1].message)
    assert payload["request_id"] == "req-2"        # 异常路径保留 request ID
    assert payload["event"] == "request.failed"
    assert err[-1].exc_info is not None             # 异常上下文（堆栈）保留


def test_prompt_not_logged(caplog):
    il.configure_logging(level=logging.DEBUG, stream=io.StringIO())
    _attach_caplog(caplog)

    secret = "SECRET_PROMPT_" * 50
    with il.inference_request("req-3", prompt=secret, prompt_tokens=3):
        pass

    full_log = "\n".join(r.message for r in caplog.records)
    assert "SECRET_PROMPT_" not in full_log         # 完整 prompt 不落日志
```

### 10.4 验收清单

- [ ] 正常路径日志含 `request.received` + `request.complete` 完整生命周期。
- [ ] `request.complete` 含全部 6 个必填结构化字段。
- [ ] 错误路径日志保留 `request_id` 与异常堆栈（`exc_info`）。
- [ ] 任何形式的 prompt 明文均不出现在日志中。
- [ ] 三个 `caplog` 用例全部通过。

---

## 11. 评估与自查（1h）

### 11.1 知识自测（覆盖 7 必学点）

1. 为什么库代码要用 `getLogger(__name__)` 而非 `getLogger()`？
2. logger level 与 handler level 的关系？"没日志"先查哪个？
3. `basicConfig` 在库里调用的三类后果？替代方案？
4. 结构化日志相比文本日志，对"可定位请求"有何增益？
5. `contextvars` 在 asyncio 与多线程下传播差异？跨线程如何带 context？
6. 同一错误为何只应在处理边界记一次？`raise ... from e` 与"为记录而捕获"的区别？
7. 列出 LLM 日志的敏感字段与脱敏策略。

### 11.2 代码审查红线（PR 必查）

> 触发任一即一票否决：
> 1. 库代码调用 `basicConfig` / 直连 `StreamHandler` 到 root。
> 2. 使用裸 `getLogger()`（root）而非 `__name__`。
> 3. 日志以明文含 `prompt` / token 序列 / PII。
> 4. 同一错误在多层重复 log-and-reraise。
> 5. 异常路径下 `request_id` 丢失（未用 contextvars 贯穿）。

### 11.3 两主线自评表

| 维度 | 1 分 | 5 分 |
|------|------|------|
| 可定位性 | 日志无 request ID、无结构、无法串链路 | 任意 request ID 可还原完整生命周期与各级耗时 |
| 安全性 | prompt/token 明文落日志 | 出口脱敏兜底，敏感字段零明文 |

---

## 12. 附录

### 12.1 速查表

```
✅ logger = logging.getLogger(__name__)
✅ 库：只加 NullHandler；配置只在应用入口
✅ 结构化：extra={"structured": {...}}，字段只度量不记内容
✅ request ID：contextvars + Filter 注入；退出 reset
✅ 异常 vs 日志：异常给调用方，日志给排查者；记一次在处理边界
❌ 库里 basicConfig / 裸 getLogger() / root 直连
❌ prompt / token / PII 明文进日志
❌ 每层 log-and-reraise
```

### 12.2 与课程体系衔接

- 姊妹篇《异常设计与资源管理》：M6 边界依赖其 `raise ... from ...` 与"禁止静默吞异常"；本课是"可诊断性"的另一半。
- 大模型职业课程：本课是 **M1 Python 进阶 → M2 PyTorch（算子异常路径日志）→ M5 推理系统（vLLM 请求级 tracing）** 的前置。vLLM / SGLang 的 request-level logging 与 metrics，正是本课原则的生产级范例。

---

*文档版本 v1.0 · 可作为「大模型职业课程」M1 Python 进阶深潜模块，与《异常设计与资源管理》配套。*
