# Day 5：日志与可观测性 — 课程方案

> 所属项目：`mini-infer`（可扩展的迷你 LLM 推理流水线框架）
> 前置基础：Day 4 异常设计与资源管理（已落地 `MiniInferError` 层级、`ModelSession`、`logger.exception` + `request_id` 边界记录）
> 学员画像：EDA 工程师，C++ 系统背景（熟悉 spdlog/glog 的 level/sink/pattern、trace context 概念）
> 设计依据：`roadmap.md` Day 5「从『打印信息』升级到『可定位请求生命周期』」

---

## 0. 课程概览与时间分配（总时长 ≈ 2.8 小时）

| 环节 | 内容 | 时长 |
|------|------|------|
| 开场 | 课程目标、与 Day 4 的衔接（异常留痕 → 可观测性） | 5 min |
| 3.1 | 为什么从 `print` 升级到 logging（可观测性视角） | 12 min |
| 3.2 | logging 四件套：logger / handler / formatter / level | 18 min |
| 3.3 | 库代码为何不碰 root logger + `getLogger(__name__)` | 12 min |
| 3.4 | 结构化字段与 request_id / correlation ID（含 `contextvars`） | 18 min |
| 3.5 | 日志与异常的职责边界（衔接 Day 4 §3.6） | 10 min |
| 3.6 | 敏感数据防护：不记录 prompt / token | 8 min |
| 练习 1 | 结构化日志配置模块 `logging.py` | 22 min |
| 练习 2 | 推理链路埋点：生命周期字段输出 | 28 min |
| 练习 3 | `pytest` `caplog` 断言 + `contextvars` 跨模块关联 | 22 min |
| 收尾 | 课后测验讲解 + 总结与延伸阅读 | 14 min |

> 标注「可压缩」：3.6 可与 3.5 合并为 12 min；练习 3 的 `contextvars` 部分可作进阶选做。核心不可删：**四件套语义、库不碰 root、结构化 request_id、不记录敏感数据、caplog 三断言**。

---

## 1. 课程目标

学完今天，学员应当能够：

1. **讲清动机**：说清 `print` 在工程中为什么不够，以及日志如何支撑「请求生命周期可定位」。
2. **用对四件套**：理解 logger（入口）、handler（出口/落点）、formatter（形状）、level（阈值）的分工，能画出数据流。
3. **守住库边界**：用 `logging.getLogger(__name__)` 只产出记录，把 handler 安装交给应用入口（CLI），绝不污染宿主的 root logger。
4. **结构化 + 关联**：用 `extra` / `contextvars` 给每条日志注入 `request_id` 与业务字段，使一次请求跨 tokenizer/model/scheduler 多模块被串成一条线。
5. **划清职责**：在异常边界用 `logger.exception` 留痕并重新抛出；理解「异常带走错误、日志留下痕迹」的分工。
6. **保护敏感数据**：只记长度/token 数/截断前缀，绝不把完整 prompt 或 token 写进日志。

---

## 2. 知识点大纲

```text
日志与可观测性
├── 2.1 为什么不用 print
│      ├── print 的 5 个工程缺陷
│      └── 可观测性视角：日志是系统对自己说的话
├── 2.2 logging 四件套
│      ├── logger（入口，按 level 决定记不记）
│      ├── handler（出口，决定记到哪）
│      ├── formatter（形状）
│      └── level（阈值过滤）
├── 2.3 库与应用的日志分工
│      ├── getLogger(__name__) 命名空间隔离
│      ├── 为何不配置 root logger / 不 basicConfig
│      └── handler 交给应用入口（cli.py）
├── 2.4 结构化与关联
│      ├── 文本日志 vs 结构化字段（extra）
│      ├── request_id / correlation ID
│      └── contextvars 跨调用传播（对标 C++ trace context）
├── 2.5 日志 vs 异常职责边界
│      ├── 异常带走错误 / 日志留下痕迹
│      └── logger.exception 在边界留痕 + 重新抛出
└── 2.6 敏感数据防护
       ├── 不记完整 prompt / token
       └── 记录长度、token 数、截断前缀
```

---

## 3. 详细讲解内容

### 3.1 为什么从 `print` 升级到 logging（可观测性视角）

**类比（C++ 工程师最熟）**：你不会在推理引擎里到处写 `std::cout << ...`。你会用 `spdlog`/`glog`，因为它们带 level、sink、pattern。`print` 就是 Python 里的「裸 `cout`」。

`print` 的工程缺陷（逐条对照）：

| `print` 的问题 | 后果 |
|----------------|------|
| 不可分级 | 线上没法把调试信息关掉 |
| 不可路由 | 全挤进 stdout，无法分离到文件/采集系统 |
| 无上下文 | 没有时间、模块名、级别，事后看不懂谁打的 |
| 不可关闭/调级 | 只能改代码，不能运行时调整 |
| 混入 stdout | 和真实输出（如 CLI 结果）混在一起，难采集 |

**可观测性视角**：日志不是「给人临时看一眼」，而是**系统对自己说的话**，要能被收集、检索、关联、告警。一次推理跨 tokenizer → model → sampler → cache → decode 多个模块，没有结构化日志，线上出问题只能靠「猜」。

> 一句话：Day 4 让错误「带上下文地传播」；Day 5 让系统的每一步「带上下文地留痕」。两者合起来，一个失败请求才能被完整重建。

---

### 3.2 logging 四件套：logger / handler / formatter / level

这是今天最核心的心智模型，先给一张数据流图：

```text
代码调用 logger.info("推理结束", extra={...})
        │
        ▼
   [logger] 按 level 过滤（DEBUG<INFO<WARNING<ERROR<CRITICAL）
        │ 通过
        ▼
   [handler × N] 每个 handler 再按自己的 level 过滤
        │
        ▼
   [formatter] 把 record 拼成字符串（时间/级别/模块/消息/字段）
        │
        ▼
   目的地：控制台 / 文件 / 网络(syslog/kafka) / 采集 agent
```

四个角色职责（用 spdlog 类比更好记）：

| 角色 | 职责 | C++ 类比 |
|------|------|----------|
| **logger** | 你在代码里调用的入口；决定「这条记不记」（按自身 level） | `spdlog::info(...)` 的 logger 对象 |
| **handler** | 出口；决定「记到哪」；一个 logger 可挂多个 handler | spdlog 的 **sink**（stdout/file/rotating） |
| **formatter** | 决定「长什么样」（时间、级别、模块、消息） | spdlog 的 **pattern_formatter** |
| **level** | 阈值过滤；低于阈值的直接丢弃 | spdlog 的 **level**（debug/info/...） |

最小可用示例（后续会被练习 1 结构化）：

```python
import logging

logger = logging.getLogger("mini_infer.engine")   # 命名空间，见 3.3
logger.setLevel(logging.INFO)                      # logger 自身阈值

handler = logging.StreamHandler()                   # 出口：控制台
handler.setLevel(logging.INFO)
handler.setFormatter(
    logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
)
logger.addHandler(handler)

logger.info("推理开始")   # 经过 level + handler + formatter 才落地
```

> 易错点：level 在两个地方都可能过滤——**logger 自身 level** 和 **handler level**，取更严格的。新手常只设了一个，另一个默认 WARNING 把 INFO 吃掉。

---

### 3.3 库代码为何不碰 root logger + `getLogger(__name__)`

**铁律**：`mini-infer` 作为**库**，只负责「产出记录」，不负责「安装 handler / 改 root」。handler 的安装交给**应用入口**（`cli.py` 或 `main`）。

为什么不能碰 root / `basicConfig`：

1. **污染宿主**：调用方可能是 CLI、pytest、Jupyter、另一个服务，它们有自己的日志配置。库若在模块顶层调用 `logging.basicConfig()` 或 `logging.getLogger().setLevel(...)`，会改写全局 root，抢走宿主日志、造成重复输出。
2. **重复 handler**：模块被 import 多次或多次调用配置函数，会叠多个 handler，日志翻倍。
3. **级别打架**：库把 root 设成 DEBUG，宿主的第三方依赖瞬间刷屏。

正确分工：

```python
# ✅ 库内部：只取自己命名空间下的 logger，只打记录
# src/mini_infer/engine/session.py
import logging

logger = logging.getLogger(__name__)   # 自动变成 "mini_infer.engine.session"

def generate(self, prompt):
    logger.info("推理开始", extra={"stage": "start"})
    ...
```

```python
# ✅ 应用入口：在这里装 handler（练习 1 会实现 configure()）
# src/mini_infer/cli.py
from mini_infer import logging as mi_logging

def main():
    mi_logging.configure()          # 只在应用层配置一次
    ...
```

命名空间隔离的好处：`getLogger(__name__)` 让每条日志带「来自哪个模块」的天然标签，宿主可以针对 `mini_infer.*` 单独调级、单独路由，而不动全局。

---

### 3.4 结构化字段与 request_id / correlation ID（含 `contextvars`）

**文本日志 vs 结构化字段**：

```python
# ❌ 文本：人能读，机器难查
logger.info(f"推理结束, prompt_tokens={n_p}, 耗时={ms}ms")

# ✅ 结构化：extra 里放字段，可被 JSON/ELK 索引
logger.info("推理结束", extra={"stage": "end", "prompt_tokens": n_p, "total_ms": ms})
```

**request_id / correlation ID**：一次推理跨 tokenizer、model、sampler、cache、decode 多个模块，甚至并发多请求。用一个**稳定 ID** 把同一次请求的所有日志串成一条线，这就是 correlation ID。

传递方式的演进（关键设计取舍）：

| 方式 | 侵入性 | 并发安全 | 评价 |
|------|--------|----------|------|
| 每个函数加 `request_id` 参数 | 高（污染所有签名） | 安全 | 能用但丑，Day 4 之前的临时方案 |
| 全局变量 | 无 | **不安全**（多请求串台） | ❌ |
| `contextvars.ContextVar` | 低（自动随调用/协程传播） | 安全（每上下文独立） | ✅ 推荐 |

`contextvars` 对标你在 C++ 里「把一个 `trace_context` 结构沿调用栈往下传」的直觉，但 Python 用 ContextVar 自动完成，且不破坏函数签名，还能在 asyncio 里正确隔离不同 task。

```python
# src/mini_infer/context.py
from contextvars import ContextVar
from uuid import uuid4

# 默认值 "-" 表示「非请求上下文」（如库内部启动日志）
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")


def new_request_id() -> str:
    return uuid4().hex


class RequestIdFilter(logging.Filter):
    """让任意模块 logger.info("x") 自动带上当前 request_id，无需手写 extra。"""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        return True
```

```python
# 在请求入口设置一次，之后整条链路自动携带
def generate(request):
    request_id = request.id or new_request_id()
    token = request_id_var.set(request_id)   # 进入请求上下文
    try:
        _run_pipeline(request)
    finally:
        request_id_var.reset(token)           # 离开请求上下文
```

这样 `tokenizer.py`、`model/transformer.py`、`engine/scheduler.py` 里只要 `logger.info(...)`，记录的 `request_id` 字段就会自动一致——无需每个函数都传参。

---

### 3.5 日志与异常的职责边界（衔接 Day 4 §3.6）

一句话分工：**异常负责「把错误沿调用栈带走」到能处理它的地方；日志负责「在关键边界留下痕迹」供事后复盘**。

正确做法（边界处留痕 + 重新抛出）：

```python
import logging
logger = logging.getLogger(__name__)

def generate(request):
    request_id = request.id or new_request_id()
    request_id_var.set(request_id)
    logger.info("推理开始", extra={"stage": "start"})
    try:
        return _run(request)
    except MiniInferError:
        # logger.exception == logger.error(..., exc_info=True)
        # 自动带上异常栈与 Day4 讲的 __cause__ 因果链
        logger.exception("推理失败", extra={"stage": "error"})
        raise   # 重新抛出，让上层决定如何恢复——绝不吞掉
```

**与 Day 4 铁律呼应**：`logger.exception` 是「留痕」，不是「处理」。处理错误的是 `except MiniInferError` 的调用方；日志只是把这次失败记下来。两者缺一不可，也不可互相替代——**不要为了省事把异常转成日志吞掉**。

---

### 3.6 敏感数据防护：不记录 prompt / token

推理系统的日志潜规则：**prompt 可能含用户隐私、商业机密、PII**。把它写进日志 = 合规事故。

```python
# ❌ 危险：完整 prompt 进日志
logger.info("推理", extra={"prompt": request.prompt, "token_ids": token_ids})

# ✅ 安全：只记元信息
logger.info("推理", extra={
    "prompt_len": len(request.prompt),
    "prompt_preview": request.prompt[:8] + "…" if request.prompt else "",
    "prompt_tokens": len(token_ids),
    # token_ids 同样不记全文，必要时只记数量
})
```

**防护清单**：
- 不记完整 prompt 原文；可记长度、截断预览（前 N 字符 + `…`）。
- 不记完整 token id 序列；可记数量。
- 不记生成结果原文（除非用户明确开启 debug 且脱敏）。
- 结构化字段名避免叫 `prompt` / `text` / `tokens`，从命名上降低误用。

---

## 4. 练习设计（3 个递进，全部基于 mini-infer 真实代码场景）

> 前置假设：项目有 `exceptions.py`（Day 4 已完成）、`engine/session.py`、`tokenizer/`、`engine/request.py`，以及空壳 `logging.py`、`context.py`。

### 练习 1（基础 · 22 min）：结构化日志配置模块 `logging.py`

**目标**：建立「库只产出、应用装 handler」的分工，支持 `request_id` 字段。

**任务**：
1. 在 `src/mini_infer/logging.py` 实现 `configure()`：配置 `mini_infer` 根 logger，挂 `StreamHandler`，formatter 含 `request_id` 占位符；用 `RequestIdFilter` 给缺省记录补 `-`；**幂等**（已有 handler 直接返回）；`propagate=False` 避免上抛到可能被宿主改过的 root。
2. 在 `src/mini_infer/context.py` 实现 `request_id_var` 与 `RequestIdFilter`（§3.4）。
3. 在 `cli.py` 的 `main()` 里调用 `configure()`，验证模块内 `logger.info("x")` 能带上 `request_id=-`。

**检查点 / 预期输出**：
```python
from mini_infer import logging as mi_logging
mi_logging.configure()
from mini_infer.engine import session
session.logger.info("启动自检")   # 注意：未进入请求上下文
# 控制台输出示例：
# 2026-07-27 22:30:01 INFO [mini_infer.engine] request_id=- 启动自检
```
断言：输出含 `request_id=-`；重复调用 `configure()` 后 handler 数量不变（幂等）；调用方（pytest）的 root 未被修改。

---

### 练习 2（进阶 · 28 min）：推理链路埋点 — 生命周期字段输出

**目标**：一次推理输出 roadmap 要求的全部可观测字段。

**任务**：在 `generate()` 主链路埋点，用 `time.perf_counter()` 计时，输出结构化字段：

| 字段 | 含义 |
|------|------|
| `request_id` | 关联 ID |
| `tokenizer_ms` | 分词耗时 |
| `prompt_tokens` | prompt token 数 |
| `decode_tokens` | 解码 token 数 |
| `cache_used` | cache 使用量 |
| `total_ms` | 总延迟 |

**参考骨架**：
```python
import time
from mini_infer.context import request_id_var, new_request_id

def generate(request):
    request_id = request.id or new_request_id()
    token = request_id_var.set(request_id)
    t0 = time.perf_counter()
    try:
        logger.info("推理开始", extra={"stage": "start"})
        t_tok = time.perf_counter()
        token_ids = tokenizer.encode(request.prompt)
        logger.info("分词完成", extra={
            "stage": "tokenize",
            "tokenizer_ms": round((time.perf_counter() - t_tok) * 1000, 2),
            "prompt_tokens": len(token_ids),
        })
        result = _run_model(token_ids, request)     # 内部也会 logger.info
        logger.info("推理结束", extra={
            "stage": "end",
            "decode_tokens": result.num_tokens,
            "cache_used": cache.usage(),
            "total_ms": round((time.perf_counter() - t0) * 1000, 2),
        })
        return result
    finally:
        request_id_var.reset(token)
```

**检查点 / 预期输出**：
```text
INFO [mini_infer.engine] request_id=ab12cd... 推理开始
INFO [mini_infer.engine] request_id=ab12cd... 分词完成  tokenizer_ms=0.42 prompt_tokens=5
INFO [mini_infer.model]  request_id=ab12cd... 模型前向 ...
INFO [mini_infer.engine] request_id=ab12cd... 推理结束  decode_tokens=12 cache_used=128 total_ms=23.7
```
断言：一次正常请求至少出现 `start / tokenize / end` 三条日志；`prompt_tokens` 与 `decode_tokens` 数值正确；所有记录 `request_id` 一致。

---

### 练习 3（挑战 · 22 min）：`pytest` `caplog` 断言 + `contextvars` 跨模块关联

**目标**：用测试固化「可观测性契约」，覆盖 roadmap 的三条校验。

**任务**：写 `tests/unit/test_logging.py`，断言：
1. **正常路径**包含生命周期日志（`start/tokenize/end`）。
2. **错误路径**包含 `request_id` 与异常上下文（`exc_info` 非空）。
3. **不记录完整 prompt**（敏感数据防护）。
4. （进阶）`tokenizer.py` 与 `engine.py` 的日志自动带同一 `request_id`（验证 `contextvars` 关联生效）。

**检查点 / 预期输出**：
```python
import logging
from mini_infer.exceptions import MiniInferError

def test_normal_path_lifecycle(caplog):
    with caplog.at_level(logging.INFO, logger="mini_infer"):
        generate(make_request("hello"))
    msgs = [r.getMessage() for r in caplog.records]
    assert any("推理开始" in m for m in msgs)
    assert any("分词完成" in m for m in msgs)
    assert any("推理结束" in m for m in msgs)
    assert all(r.request_id != "-" for r in caplog.records)

def test_error_path_has_request_id_and_cause(caplog):
    with caplog.at_level(logging.INFO, logger="mini_infer"):
        try:
            generate(make_request("boom", config=BAD))
        except MiniInferError:
            pass
    assert any(r.request_id != "-" for r in caplog.records)
    assert any(r.exc_info is not None for r in caplog.records)   # 异常上下文在

def test_no_full_prompt_in_logs(caplog):
    with caplog.at_level(logging.DEBUG, logger="mini_infer"):
        generate(make_request("这是一段敏感prompt内容"))
    full = "\n".join(r.getMessage() for r in caplog.records)
    assert "这是一段敏感prompt内容" not in full
```
断言：三个测试全绿；`test_error_path` 中 `exc_info` 非空证明异常因果链被日志捕获；敏感 prompt 未出现在任何记录中。

---

## 5. 课后测验 / 思考题

### 选择题（概念自检）

1. 关于库代码的日志，正确的是？
   a) 在模块顶层调用 `logging.basicConfig()` 最方便
   b) 用 `getLogger(__name__)` 只产出记录，handler 交给应用入口
   c) 直接配置 root logger 保证全局生效
   d) 用 `print` 调试更直观，发布前再删

2. 一次推理跨多个模块，要把日志串成一条线，最佳实践是？
   a) 每个函数都加 `request_id` 参数
   b) 用全局变量存当前 request_id
   c) 用 `contextvars.ContextVar` 自动随调用/协程传播
   d) 把 request_id 写进文件再读

3. 日志与异常的职责边界，正确的是？
   a) 日志负责处理错误，异常负责记录
   b) 异常带走错误、日志留下痕迹，边界处 `logger.exception` + `raise`
   c) 两者重复，只用一个即可
   d) 异常应转成日志以免中断流程

4. 以下哪项**不应**写入日志？
   a) `request_id`  b) `tokenizer_ms`  c) 完整 prompt 原文  d) `cache_used`

### 编码思考题

5. 实现 `RequestIdFilter`：让任意模块 `logger.info("x")` 自动带上当前 `request_id`（用 `contextvars`，默认 `-`），并说明为何用 Filter 而非每处手写 `extra`。

6. 为什么库里调用 `logging.getLogger().setLevel(logging.DEBUG)` 会「污染」宿主？给出一个最小危害示例（例如导致 pytest 输出被打满、或宿主第三方依赖日志泄露）。

### 开放思考题

7. 可观测性三支柱是 **logs / metrics / traces**。本课的 `request_id` 更接近哪一支柱的「锚点」？如果要做 metrics（如 p95 延迟、token 吞吐），这些数值应存在哪、用什么方式暴露给监控系统（提示：metrics 与 logs 的关注点不同）？

---

## 6. 总结与延伸阅读建议

### 今日一句话总结
**日志是系统对自己说的话：库只负责「说」（getLogger + 结构化 extra + request_id），应用负责「接」（handler/formatter）；异常带走错误，日志留下痕迹，敏感数据一律不记。**

### 三条今天必须刻进肌肉记忆的规则
1. 库只用 `getLogger(__name__)` 产出记录，handler 安装交给应用入口，**绝不碰 root**。
2. 每条关键日志都带 `request_id` 与结构化字段；跨模块用 `contextvars` 自动关联，不再逐层传参。
3. 不记录完整 prompt / token；异常边界用 `logger.exception` 留痕后**重新抛出**。

### 延伸阅读
- **Python 官方文档**：[logging — Logging facility](https://docs.python.org/3/library/logging.html) 与 [Logging HOWTO](https://docs.python.org/3/howto/logging.html) — 四件套、LoggerAdapter、`exc_info`。
- **`contextvars` 文档**：[contextvars — Context Variables](https://docs.python.org/3/library/contextvars.html) — correlation ID 的现代实现基础。
- **12-Factor App · Logs**：日志是「事件流」，由执行环境收集，应用只管写到 stdout——理解「库不配 root、应用接 handler」的哲学来源。
- **`structlog`**（可选进阶）：把「结构化日志」做成一等公民，输出 JSON，接入 ELK/Loki 更顺。课程先用标准库打底，后续可平滑替换。
- **OpenTelemetry**（前瞻）：traces 与 correlation ID 的关系——`request_id` 其实就是 trace 的雏形。
- **roadmap 衔接**：Day 6 用 `pytest` 的 `caplog` / `pytest.raises` 把今天的日志与 Day 4 的异常行为写成测试；Day 25 KV cache、Day 26 scheduler 会持续产出 `cache_used` 等字段，今天的埋点规范会被一直沿用。

### 给讲师的复盘提示
- 开场用 spdlog 的 sink/pattern/level 类比四件套，学员秒懂。
- 练习 1 的「幂等 + 不污染 root」最易被忽略，务必让学员用 pytest 验证「重复 configure 后 handler 数不变」「root 未被改」。
- 练习 3 的三条 `caplog` 断言直接对应 roadmap Day 5 的验收标准，是今天最重要的交付物。
- 收尾强调：Day 4 的异常层级 + 今天的 request_id 日志，就是后续所有模块（cache/scheduler/model）可观测性的底座——**这套日志规范会一直活到 v0.1.0**。
