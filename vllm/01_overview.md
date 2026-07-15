# 本轮主题

**阶段 1：建立 vLLM 的整体认识——从“模型推理”到“高并发推理服务系统”**

> 本轮不会展开全部课程。目标是在 **60～90 分钟**内建立第一条可验证闭环：  
> **定位问题 → 看懂高层请求流程 → 完成一次离线推理 → 记录环境与现象 → 用自己的语言解释 vLLM。**

\*\*版本提醒：\*\*vLLM 迭代很快，`main`、developer preview、stable release 之间的目录、类名和参数可能不同。后续源码追踪将始终绑定到你的具体 `vllm` 版本或 Git commit，不把某个版本的实现当成永久事实。

***

## 1. 学习目标

完成本轮后，你应该能够：

1. 用两三句话解释 vLLM 解决的核心问题；
2. 区分：
   * 模型本身；
   * 推理运行时；
   * API 服务；
   * 请求调度和 KV Cache 管理；
3. 画出一次请求从 prompt 到输出 token 的高层流程；
4. 运行一个最小离线推理程序，或在无 GPU 时完成环境阻塞诊断；
5. 说明“运行成功”为什么还不能证明已经理解 vLLM；
6. 明确下一阶段需要补齐的 Prefill、Decode、KV Cache 和指标知识。

### 一句话定义

**vLLM 是面向大语言模型推理和服务的运行时/服务引擎，重点解决动态请求负载下的 KV Cache 内存管理、请求调度、批处理效率和模型执行效率问题，而不是训练模型。**

vLLM 官方仓库将其定位为高吞吐、显存高效的 LLM inference and serving engine；PagedAttention 论文进一步将主要问题描述为：KV Cache 很大、动态增长，低效分配会产生碎片和重复数据，从而限制可同时服务的请求数。 [\[github.com\]](https://github.com/vllm-project/vllm), [\[arxiv.org\]](https://arxiv.org/abs/2309.06180)

### 它试图解决什么问题？

假设多个请求具有不同的：

* 到达时间；
* prompt 长度；
* 输出长度；
* 解码状态；
* KV Cache 增长速度。

如果仍采用固定批次、静态预留和粗粒度请求执行，那么容易出现：

* GPU 等待批次中较慢的请求；
* 请求完成后不能及时把执行位置让给新请求；
* KV Cache 预留过多或产生碎片；
* 显存看似还有容量，却难以容纳更多请求；
* 单请求可以运行，但并发吞吐量差。

PagedAttention 论文的核心观察是：服务吞吐量需要足够大的并发批次，但 KV Cache 的动态增长和低效内存管理会限制批次规模；PagedAttention 借鉴分页思想，允许 KV Cache 以非连续块组织，并支持缓存共享。 [\[arxiv.org\]](https://arxiv.org/abs/2309.06180)

### 不使用 vLLM 会发生什么？

不是说“没有 vLLM 就不能推理”，而是：

* Transformers 等框架仍然可以完成模型生成；
* 自己实现服务时，需要另外处理请求队列、动态 batching、KV Cache 生命周期、流式输出、并发隔离、指标和分布式执行；
* 在低并发、短序列或简单离线任务中，vLLM 的收益可能不明显；
* 在多请求、长上下文、动态输出长度场景中，调度和缓存管理通常会成为关键问题。

**本轮暂不接受的伪解释：**

> “vLLM 比 Transformers 快，因为 PagedAttention 很快。”

这里至少混淆了三层因果关系：

1. PagedAttention 首先处理的是 **KV Cache 的存储与访问组织**；
2. Continuous Batching/调度影响的是 **每轮执行哪些请求和 token**；
3. CUDA Graph、优化 kernel、量化和并行策略影响的是 **模型执行成本**。

***

## 2. 前置知识检查

请先独立回答下面 **8 题**。不要求查资料，也不要求第一次全部正确。你的答案将决定阶段 2 的深度。

### 诊断题

1. **自回归生成**  
   一个模型已经接收了 1,000 个 prompt token，现在需要生成第 20 个输出 token。为什么它不能一次并行算出后面剩余的所有输出 token？

2. **Prefill 与 Decode**  
   你认为长度为 2,000 的 prompt 的首次模型计算，与之后逐个生成 token 的计算，在并行度和瓶颈上有什么不同？

3. **KV Cache**  
   如果不保存 KV Cache，每生成一个新 token，模型需要重复做什么？

4. **并发与批处理**  
   两个请求分别需要生成 10 和 1,000 个 token。若把它们固定在同一静态 batch 中，短请求可能受到什么影响？

5. **指标辨析**  
   服务 A 的总吞吐量更高，是否能推出服务 A 的单请求延迟一定更低？为什么？

6. **显存组成**  
   除了模型权重，请列出至少两类可能占用 GPU 显存的内容。

7. **系统设计**  
   请求生成完一个 token 后，调度器为什么可能重新选择下一轮参与执行的请求，而不是保持 batch 永远不变？

8. **源码直觉**  
   在一个推理服务中，你预计 API Server、Scheduler、Model Runner 三者分别负责什么？它们是否应该属于同一职责层？

### 评分方式

每题按 0～2 分评估：

* **0 分**：不知道，或明显混淆；
* **1 分**：方向正确，但无法解释原因或边界；
* **2 分**：能说明机制、因果关系和至少一个边界条件。

这不是考试排名。错题将分类为：

* 前置知识不足；
* 术语混淆；
* 数据流理解错误；
* 性能直觉错误；
* 边界条件缺失；
* 源码职责划分不清。

***

## 3. 核心解释

## 3.1 本轮主题的十项产物

### 1）定义

vLLM 是将模型调用转化为高效离线推理或在线推理服务的执行系统。

### 2）解决的问题

核心不是“让 Transformer 数学公式发生变化”，而是让大量长度不同、到达时间不同的生成请求更高效地共享：

* GPU 计算资源；
* 模型权重；
* KV Cache 空间；
* 每轮模型执行机会。

### 3）不使用这些服务机制时

可能出现静态 batch 等待、显存浪费、低并发、排队时间上升和服务工程复杂度增加。

### 4）工作原理——当前只建立高层模型

1. 用户提交 prompt 和采样参数；
2. 输入处理阶段完成解析、校验和 tokenization；
3. 请求进入 Engine；
4. Scheduler 决定本轮处理哪些请求以及多少 token；
5. KV Cache 管理器为这些 token 准备或映射缓存空间；
6. Executor/Worker 驱动 Model Runner；
7. 模型执行产生 logits；
8. Sampler 选择新 token；
9. 未完成的请求回到下一轮调度；
10. 已完成或流式 token 交给输出处理和调用者。

### 5）与相邻概念的区别

| 概念                       | 主要职责                    | 本轮边界                     |
| ------------------------ | ----------------------- | ------------------------ |
| Hugging Face 模型          | 模型结构、权重、配置、tokenizer 生态 | 不等于完整高并发 serving runtime |
| vLLM Engine              | 请求管理、调度、缓存与模型执行编排       | 不训练模型                    |
| PagedAttention           | KV Cache 的分块组织和注意力访问机制  | 不等于整个 vLLM               |
| Continuous Batching      | 在执行迭代边界动态组合请求           | 不等于普通静态 batch            |
| OpenAI-compatible Server | HTTP/API 协议和服务入口        | 不是主要 GPU 计算实现            |
| CUDA Graph/kernel        | 降低执行开销或优化算子             | 不能代替调度与内存管理              |

### 6）具体示例

请求 A：

* prompt：1,000 token；
* 生成：20 token。

请求 B：

* prompt：20 token；
* 生成：500 token。

它们在 Prefill、Decode、KV Cache 增长和完成时间上完全不同。高效服务不能只把二者填充到统一长度后机械地一起运行到底，而需要在执行迭代间调整请求组合。

### 7）最小实验

使用 `LLM.generate()` 完成两个 prompt 的离线推理，并记录版本、GPU 和输出行为，见第 6 节。

### 8）常见误解

> 离线 API 没有 HTTP 和高并发，因此与理解 vLLM 架构无关。

错误。离线和在线入口不同，但都能帮助我们分离：

* 前端协议层；
* 引擎层；
* 调度与模型执行层。

### 9）故障或边界场景

* 没有受支持的 GPU/加速器；
* CUDA、PyTorch 和 vLLM wheel 不兼容；
* 模型需要访问授权；
* 显存不足以容纳权重和运行时空间；
* 模型架构暂不支持；
* 使用 `main` 源码，却阅读了旧版本 V0 架构文章；
* 首次运行包含下载、编译、权重加载和 warm-up，不能当作稳定态延迟。

### 10）掌握度检查与输出任务

本轮末尾必须完成三项：

1. 解释 vLLM 解决的问题，但不得只使用“优化”“更快”两个词；
2. 画出请求生命周期，并指出至少两个循环；
3. 提交一份实验记录或明确的环境阻塞报告。

***

## 4. 请求流程或架构关系

### 4.1 整体学习地图

```text
                         ┌──────────────────────────┐
                         │ 目标：判断、部署、分析、诊断 vLLM │
                         └─────────────┬────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
┌──────────────┐              ┌────────────────┐              ┌────────────────┐
│ A 用户与部署   │              │ B 推理基础       │              │ E 性能工程       │
│ install/serve │              │ prefill/decode │              │ TTFT/TPOT/QPS  │
│ offline/API   │              │ KV/batch/memory│              │ 显存/GPU/并发    │
└──────┬───────┘              └───────┬────────┘              └───────┬────────┘
       │                              │                               │
       │                              ▼                               │
       │                     ┌────────────────┐                       │
       └────────────────────►│ C vLLM 核心机制  │◄──────────────────────┘
                             │ PagedAttention │
                             │ Scheduler      │
                             │ Prefix/Chunked │
                             └───────┬────────┘
                                     │
                                     ▼
                             ┌────────────────┐
                             │ D 架构与源码      │
                             │ API → Engine   │
                             │ Scheduler/KV   │
                             │ Worker/Runner  │
                             └───────┬────────┘
                                     │
                                     ▼
                             ┌────────────────┐
                             │ F 分布式与生产    │
                             │ TP/PP/多节点     │
                             │ 监控/限流/恢复    │
                             └────────────────┘
```

这六条路线不会串行地“一条学完再学下一条”，而会交错推进。例如，只有先分别理解 KV Cache、调度和 PagedAttention，才能审查“显存利用率提高导致吞吐量提高”这条因果链。

### 4.2 一次在线请求的文字版架构图

```text
HTTP Client
   │ OpenAI-compatible request
   ▼
API Server / Request Handler
   │ 参数校验、模板处理、tokenization、stream 管理
   ▼
Async LLM / Engine Frontend
   │ 请求 ID、输入 token、采样参数
   ▼
Engine Core
   ├── Scheduler ────────────────┐
   │   选择本轮请求和 token 数     │
   │                              ▼
   ├── KV Cache Manager ──► Block allocation / block table
   │
   └── Executor
         ▼
       Worker
         ▼
       Model Runner
         ├── 准备输入张量与 cache 映射
         ├── Model forward
         └── Sampling
                │
                ▼
          新 token / 完成状态
                │
        ┌───────┴────────┐
        │未完成           │已完成或可流式输出
        ▼                ▼
     下一轮调度      Output Processor → HTTP Client
```

当前官方仓库仍在快速变化，因此这里首先固定的是**职责与数据流**，而不是把某组类名背成永久接口。官方 V1 Scheduler API 和仓库源码将作为后续版本绑定的入口。 [\[github.com\]](https://github.com/vllm-project/vllm), [\[docs.vllm.ai\]](https://docs.vllm.ai/en/stable/api/vllm/v1/core/sched/scheduler/)

### 4.3 两个重要循环

1. **自回归循环**：新 token 依赖前面的 token；
2. **调度循环**：每轮模型执行前，系统重新决定本轮执行内容。

后续我们要验证：这两个循环如何把“模型计算问题”转化为“调度 + 缓存 + 执行”问题。

***

## 5. 最小示例

本轮使用一个较小的 instruct 模型作为示例。实际是否可用取决于模型访问权限、当前版本支持情况和硬件条件。

### 5.1 环境记录

先创建一个记录文件：

```bash
mkdir -p vllm-learning
cd vllm-learning

{
  echo "date=$(date -Iseconds)"
  echo "os=$(uname -a)"
  echo "python=$(python --version 2>&1)"
  echo "nvidia_smi:"
  nvidia-smi || true
} | tee env-before.txt
```

建议使用隔离环境。具体 Python、CUDA 和 PyTorch 兼容组合应以你最终安装的 vLLM stable 版本说明为准，不要盲目混装已有 PyTorch 环境。

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install vllm
```

记录实际版本：

```bash
python - <<'PY' | tee -a env-before.txt
import platform
import torch
import vllm

print("platform:", platform.platform())
print("python:", platform.python_version())
print("vllm:", vllm.__version__)
print("torch:", torch.__version__)
print("torch_cuda:", torch.version.cuda)
print("cuda_available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
    print(
        "gpu_memory_GiB:",
        round(torch.cuda.get_device_properties(0).total_memory / 1024**3, 2),
    )
PY
```

### 5.2 最小离线推理程序

保存为 `offline_minimal.py`：

```python
import time

from vllm import LLM, SamplingParams

MODEL = "Qwen/Qwen2.5-0.5B-Instruct"

prompts = [
    "用一句话解释什么是 KV Cache。",
    "Explain why static batching can waste GPU capacity.",
]

sampling_params = SamplingParams(
    temperature=0.0,
    max_tokens=48,
)

load_start = time.perf_counter()
llm = LLM(
    model=MODEL,
    dtype="auto",
)
load_seconds = time.perf_counter() - load_start

run_start = time.perf_counter()
outputs = llm.generate(prompts, sampling_params)
run_seconds = time.perf_counter() - run_start

print(f"model_load_seconds={load_seconds:.3f}")
print(f"generate_call_seconds={run_seconds:.3f}")

for index, output in enumerate(outputs):
    generated_text = output.outputs[0].text
    generated_token_ids = output.outputs[0].token_ids

    print(f"\n--- request {index} ---")
    print("prompt:", output.prompt)
    print("generated_token_count:", len(generated_token_ids))
    print("generated_text:", generated_text)
```

运行：

```bash
python offline_minimal.py 2>&1 | tee offline-run.log
```

### 为什么这个例子还不是 benchmark？

因为它混入了：

* 模型加载；
* 可能的模型下载；
* kernel 初始化或编译；
* GPU 内存初始化；
* 首次运行 warm-up；
* 两条 prompt 的不同 token 长度；
* Python 端计时；
* 非流式输出等待。

因此，本轮只把它作为**功能与数据流实验**，不把 `generate_call_seconds` 宣称为 TTFT、TPOT 或稳定吞吐量。

***

## 6. 动手实验

## 实验 1：确认“引擎是多请求执行者，而不是单次模型函数”

### 实验条件记录

把以下项目补充到 `experiment-01.md`：

```text
实验编号：E01
日期：
操作系统：
Python：
vLLM：
PyTorch：
CUDA：
GPU 型号：
GPU 显存：
模型：
dtype/量化：
prompt 数量：2
输入长度：运行后通过 tokenizer 或日志补充
最大输出长度：48
并发口径：同一次 generate 调用中的两个请求
关键参数：temperature=0.0
预热次数：0
正式测试次数：1
实验类型：功能观察，不是正式性能 benchmark
```

### 第一步：运行基线

```bash
python offline_minimal.py 2>&1 | tee offline-run-baseline.log
```

### 第二步：改变一个变量——请求数量

把：

```python
prompts = [
    "用一句话解释什么是 KV Cache。",
    "Explain why static batching can waste GPU capacity.",
]
```

临时改成只保留第一条，其他参数保持不变，再运行：

```bash
python offline_minimal.py 2>&1 | tee offline-run-one-request.log
```

### 第三步：观察 GPU 显存

另开终端：

```bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory \
  --format=csv -l 1 | tee gpu-memory.log
```

### 观察点

记录但不要过度解释：

* 模型加载期间的显存变化；
* `LLM()` 构造是否明显比生成阶段更慢；
* 一个请求和两个请求是否都能完成；
* 两个请求的输出是否按输入顺序返回；
* 总时间是否简单变成两倍；
* 第二次进程内调用是否比第一次更稳定；
* 日志中能否找到 cache、block、scheduler、graph 或 worker 相关信息。

### 无 GPU 时的阻塞替代

如果无法运行，不伪造结果。执行以下诊断并保留输出：

```bash
python --version
python -m pip show vllm torch
nvidia-smi
python - <<'PY'
import torch

print("torch:", torch.__version__)
print("torch CUDA build:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
PY
```

阻塞报告至少写明：

```text
阻塞阶段：
失败命令：
完整错误的第一处根因：
是否有 NVIDIA GPU：
驱动版本：
CUDA/PyTorch/vLLM 版本：
模型是否需要授权：
已验证的事实：
尚未验证的假设：
下一项最小诊断：
```

***

## 7. 运行前预测

运行实验前，先写下预测，不能事后补写。

1. `LLM(...)` 与 `generate(...)` 哪一个更可能包含权重加载和大块显存分配？
2. 从一个请求增加成两个请求，总时间是否一定精确翻倍？
3. 两个 prompt 长度不同时，引擎是否必须把它们永久填充到一样长？
4. `temperature=0.0` 是否意味着不同硬件、版本和执行配置下绝对逐 bit 可复现？
5. 第二次运行更快，能否直接断言是 Continuous Batching 带来的？
6. 当程序结束后，为什么 `nvidia-smi` 中的显存可能被释放？

### 预测记录模板

```text
P1：
预测：
因果理由：
可能推翻该预测的证据：

P2：
预测：
因果理由：
可能推翻该预测的证据：
```

***

## 8. 结果分析方法

本实验只判断以下四件事：

### 8.1 功能是否成立

* 模型能否加载；
* 两个请求能否生成；
* 输出结构中能否找到 prompt、token IDs 和文本；
* 是否发生 OOM、模型不支持或依赖错误。

### 8.2 阶段是否可区分

区分：

* 安装时间；
* 模型下载时间；
* 模型加载时间；
* 首次推理初始化；
* 稳定生成时间。

不要把这几者相加后称为“推理延迟”。

### 8.3 资源观察是否合理

显存通常不只有权重，还可能包含：

* KV Cache；
* 激活和临时工作区；
* CUDA context；
* CUDA Graph 相关缓冲区；
* 通信缓冲区；
* allocator 预留空间。

看到 OOM 后，不得直接写成“模型权重太大”。

### 8.4 为后续正式测量保留接口

在线服务的 `/metrics` 可暴露请求运行数、KV Cache 使用率、TTFT、inter-token latency、端到端延迟、prefill 时间和 decode 时间等指标。这些指标将用于后续把“引擎很慢”拆解成排队、Prefill、Decode 和缓存压力问题。 [\[docs.vllm.ai\]](https://docs.vllm.ai/en/stable/design/metrics/)

***

## 9. 关键源码入口

本轮只定位，不逐文件阅读。

> **规则：先记录本地版本，再查看对应 tag/commit 的源码。**

### 建议入口

| 层次              | 首先搜索的位置                                                 | 本轮要回答的问题                    |
| --------------- | ------------------------------------------------------- | --------------------------- |
| 离线入口            | `vllm/entrypoints/llm.py`                               | `LLM.generate()` 如何把输入交给引擎？ |
| 在线入口            | `vllm/entrypoints/openai/`                              | HTTP 请求在哪里转换成内部请求？          |
| 异步引擎            | `vllm/v1/engine/`                                       | API 前端如何与 Engine Core 交互？   |
| 调度器             | `vllm/v1/core/sched/`                                   | 本轮哪些请求被选择执行？                |
| KV Cache        | `vllm/v1/core/`、`vllm/v1/kv_cache_interface.py` 等当前版本位置 | 请求如何获得 KV block？            |
| Executor        | `vllm/v1/executor/`                                     | Engine 如何把工作派发到设备/进程？       |
| Worker          | `vllm/v1/worker/`                                       | 每个设备侧 worker 做什么？           |
| Model Runner    | 当前版本 `vllm/v1/worker/` 下相关 runner                       | 输入张量如何变成模型 forward？         |
| CUDA/C++ kernel | `csrc/`                                                 | 性能关键操作如何落到原生实现？             |

官方仓库同时包含 Python 引擎代码和 `csrc` 原生实现，而且提交变化频繁，因此后续必须保存 commit，避免“文件名对但版本错”。 [\[github.com\]](https://github.com/vllm-project/vllm)

### 本地定位命令

```bash
python - <<'PY'
import inspect
import os
import vllm

from vllm import LLM

print("vllm package:", os.path.dirname(inspect.getfile(vllm)))
print("LLM source:", inspect.getfile(LLM))
PY
```

如果克隆源码：

```bash
git clone https://github.com/vllm-project/vllm.git
cd vllm
git rev-parse HEAD
git describe --tags --always
```

随后进行职责搜索，而不是漫无目的地逐文件阅读：

```bash
grep -R "class Scheduler" -n vllm/v1 | head
grep -R "class.*ModelRunner" -n vllm/v1 | head
grep -R "class.*KVCache" -n vllm/v1 | head
grep -R "def generate" -n vllm/entrypoints/llm.py
```

***

## 10. 常见误区

1. **“vLLM 是一个更快的模型。”**  
   错。模型权重和架构可以来自同一个 Hugging Face 模型；vLLM 主要改变推理服务的执行、调度和缓存管理。

2. **“PagedAttention 就等于 vLLM。”**  
   错。PagedAttention 是核心机制之一；完整系统还包括入口、Scheduler、KV Cache Manager、Executor、Worker、Model Runner、采样、统计和分布式支持。

3. **“成功运行示例就掌握了 vLLM。”**  
   错。成功只证明当前环境能够运行一个路径。

4. **“多个 prompt 一次传给 `generate()` 就证明 Continuous Batching 有效。”**  
   不成立。你还没有观察迭代级请求加入/退出，也没有对照静态批处理。

5. **“GPU utilization 100% 就说明性能很好。”**  
   不成立。可能存在低有效吞吐、排队、冗余计算或过高延迟。

6. **“PagedAttention 一定能让单请求延迟显著下降。”**  
   不成立。它的主要价值与 KV Cache 管理、可容纳并发和由此带来的吞吐能力相关；具体收益取决于负载。

7. **“论文的 2～4 倍提升可以直接套到我的机器。”**  
   不成立。论文结果来自特定模型、硬件、基线、序列分布和系统版本，只能作为论文实验结论，不能作为你的预测值。 [\[arxiv.org\]](https://arxiv.org/abs/2309.06180)

***

## 11. 对抗性审查

### 审查质疑 1：你说 vLLM 提升吞吐量，证据是什么？

**当前证据：**

* 官方定位；
* PagedAttention 论文在其特定实验条件下报告的结果。 [\[github.com\]](https://github.com/vllm-project/vllm), [\[arxiv.org\]](https://arxiv.org/abs/2309.06180)

**尚缺证据：**

* 你的硬件环境；
* 相同模型和精度；
* 相同输入/输出长度分布；
* 相同并发；
* 相同请求速率；
* 稳定态、预热后结果；
* 公平的对照系统配置。

\*\*结论：\*\*本轮不能宣称你的环境获得任何吞吐提升。

### 审查质疑 2：两个请求总时间没有翻倍，是否证明了调度优化？

不能。还可能来自：

* GPU 并行执行；
* 模型权重在请求间复用；
* 首次运行初始化差异；
* 计时噪声；
* 输入长度不同；
* batch 形状差异。

需要重复实验、预热、token 统计和明确的执行日志才能缩小因果范围。

### 审查质疑 3：显存上涨是不是 KV Cache？

不能仅凭 `nvidia-smi` 判断。还需：

* 模型权重估算；
* vLLM cache 配置；
* KV block 使用指标；
* 不同序列长度的对照；
* 进程初始化前后的差量；
* allocator 和 CUDA Graph 等额外占用。

### 审查质疑 4：高层调用链是否与当前源码一致？

未完全验证。当前只是职责模型。消除质疑需要：

1. 记录 `vllm.__version__`；
2. 对应到 release tag/commit；
3. 从本地 `LLM.generate()` 逐级跟踪；
4. 找到请求对象进入 Scheduler 和 Model Runner 的实际路径。

***

## 12. 掌握度测试

完成实验后，请回答下面三题：

### 问题 1

不能使用“优化得好”“更快”“PagedAttention”作为完整答案，解释：

> vLLM 相比直接逐请求调用模型，多管理了哪些系统状态？

### 问题 2

请画出至少包含以下节点的数据流：

```text
Prompt
API/LLM entrypoint
Engine
Scheduler
KV Cache Manager
Worker
Model Runner
Sampler
Output
```

并标出：

* 自回归循环；
* 调度循环；
* 哪一部分属于控制面；
* 哪一部分属于执行面。

### 问题 3

如果服务出现：

* TTFT 很高；
* TPOT 正常；
* 请求队列持续增长；
* KV Cache 利用率不高；

你能否直接得出“PagedAttention 性能差”的结论？还需要哪些证据？

### 本轮输出任务

提交以下四项即可进入下一轮：

1. 8 道诊断题答案；
2. 运行前预测；
3. `env-before.txt` 的关键版本信息；
4. 成功时的实验摘要，或失败时的阻塞报告。

***

## 13. 学习路线状态更新

这是初始登记表。**“学习中”不代表掌握，仅表示已产生具体任务。**

| 路线          | 当前状态 | 学习目标                                         | 已掌握内容        | 尚未理解            | 关键证据            | 可运行实验                        | 阻塞原因      | 下一步行动                    |
| ----------- | ---- | -------------------------------------------- | ------------ | --------------- | --------------- | ---------------------------- | --------- | ------------------------ |
| A 用户与部署     | 学习中  | 安装、模型加载、离线/在线推理、API                          | 暂无可验证证据      | 环境兼容、模型加载、服务参数  | 待提交版本记录和 E01 日志 | E01 离线双请求                    | 待诊断       | 运行最小离线推理                 |
| B 推理基础      | 学习中  | Prefill、Decode、KV Cache、batch、延迟与显存          | 默认只有基础认识，未验证 | 阶段差异、KV 大小、指标定义 | 8 题诊断结果         | 后续 KV 估算和长度对照                | 待诊断       | 完成诊断题                    |
| C vLLM 核心机制 | 未开始  | PagedAttention、Continuous Batching、Scheduler | 无            | 逻辑块/物理块、调度约束    | 无               | 后续 block 模拟与对比实验             | 缺少 B 路线证据 | 先建立 Prefill/Decode/KV 模型 |
| D 架构与源码     | 学习中  | 追踪入口到 token 输出                               | 已给出待验证高层职责图  | 当前版本真实调用链       | 待提交版本及源码定位结果    | `inspect.getfile()` 和 `grep` | 版本未知      | 固定 release/tag           |
| E 性能工程      | 未开始  | TTFT、TPOT、吞吐、并发、显存                           | 无            | 测量边界和控制变量       | 无               | 后续在线 `/metrics` 与 benchmark  | 未完成基础指标学习 | E01 不做性能结论               |
| F 分布式与生产    | 未开始  | TP/PP、多 GPU、监控、恢复                            | 无            | 全部              | 无               | 最终综合项目                       | 前置路线未完成   | 暂不展开                     |

### 当前证据等级

```text
概念定义：已提供，未复述验证
架构图：已提供，未与具体版本源码核对
运行证据：无
性能证据：无
源码证据：无
故障诊断证据：无
掌握状态：没有任何路线可标记为“已掌握”
```

***

## 14. 下一步任务

## 第一个 60～90 分钟学习单元

### 0～10 分钟：诊断

* 独立回答 8 题；
* 每题标注信心：高 / 中 / 低；
* 不查资料。

### 10～25 分钟：整体认识

* 阅读本轮核心解释；
* 手画请求生命周期；
* 圈出自回归循环和调度循环；
* 写下 vLLM 与“模型本身”的边界。

### 25～45 分钟：环境与最小运行

* 建立虚拟环境；
* 安装并记录版本；
* 运行 `offline_minimal.py`；
* 保存日志和错误。

### 45～60 分钟：单变量观察

* 一个请求与两个请求对比；
* 同时观察显存；
* 不做吞吐量优劣结论。

### 60～75 分钟：源码定位

* 用 `inspect.getfile(LLM)` 找入口；
* 找 `generate()`；
* 只向下追踪 2～3 层；
* 记录“对象 A 把什么数据传给对象 B”。

### 75～90 分钟：复述与审查

完成下面这段话：

> vLLM 不是 \_\_\_\_\_\_，而是 \_\_\_\_\_\_。  
> 它面对的动态状态至少包括******、****** 和 \_\_\_\_\_\_。  
> 本次实验只证明了 \_\_\_\_\_\_，没有证明 \_\_\_\_\_\_。  
> 要判断其性能，需要进一步测量 \_\_\_\_\_\_。

## 本轮明确完成标准

同时满足以下条件，才算本轮完成：

* [ ] 回答 8 道诊断题；
* [ ] 能在不看定义的情况下解释 vLLM 的职责边界；
* [ ] 能画出包含 Scheduler、KV Cache Manager、Worker 和 Model Runner 的流程；
* [ ] 成功运行最小实验，或提交包含版本和根因的阻塞报告；
* [ ] 至少提出一个运行前预测，并说明什么证据会推翻它；
* [ ] 没有把首次运行耗时当作正式 TTFT/吞吐量；
* [ ] 没有把“示例运行成功”标记为已掌握；
* [ ] 找到本地 `LLM` 类的源码文件并记录版本。

**完成后，下一轮优先主题将依据诊断结果在两者间选择：**

1. **Prefill、Decode 与 KV Cache 的请求生命周期**；或
2. 若环境阻塞严重，先进行 **vLLM 安装、CUDA/PyTorch 兼容与 OOM 最小诊断**。
