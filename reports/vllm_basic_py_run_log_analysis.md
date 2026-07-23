# vLLM `basic.py` 运行日志分析

> 对象：`examples/basic/offline_inference/basic.py`（`LLM` 类离线推理）
> 模型：`facebook/opt-125m`（125M 参数，非指令微调）
> 引擎：V1（`EngineCore` 独立进程，多进程流水线）

## 一、阶段拆解：日志 → 架构组件

| 日志阶段 | 对应代码 / 组件 | 说明 |
|---|---|---|
| `non-default args: {model: ...}` | `LLM.__init__` → `EngineArgs` | `LLM` 门面解析参数（我们上一轮分析的对象） |
| `Unknown vLLM environment variable` ×5 | `envs.py:validate_environ()` | 环境里 5 个 `VLLM_*` 变量未注册 → warning（见 §三.1） |
| `unauthenticated requests to HF Hub` | `huggingface_hub` | 未设 `HF_TOKEN`，仅限流，不影响（见 §三.4） |
| `Resolved architecture: OPTForCausalLM` | `vllm/model_executor/models/opt.py` | 自动按 `config.json` 解析架构类 |
| `Chunked prefill is enabled` / `Asynchronous scheduling is enabled` | `v1/core/scheduler.py`、`v1/engine/` | V1 默认开启的调度特性 |
| `(EngineCore pid=697213) Initializing a V1 LLM engine (v0.22.0)` | `v1/engine/core.py` | **关键**：引擎跑在独立子进程；版本号见 §三.2 |
| `FLASH_ATTN attention backend` | `v1/attention/backends/flash_attn.py` | 在 FLASHINFER/TRITON_ATTN/FLEX_ATTENTION 中胜出 |
| `PyTorch-native sampler` | `v1/sample/topk_topp_sampler.py` | `VLLM_USE_FLASHINFER_SAMPLER=0` |
| `Loading weights took 1.21 s` | `vllm/model_executor/model_loader/` | 单 shard 权重加载 |
| `torch.compile` 段 | `v1/compilation/backends.py` | Dynamo 字节码 7.66s + 图编译 4.71s，**复用缓存** `/torch_compile_cache/4301898f79/` |
| `CUDA graph memory profiling` | `gpu_model_runner.py` | 自 v0.21.0 起默认开启；PIECEWISE=51 / FULL=35 |
| `Available KV cache memory: 72.11 GiB` / `GPU KV cache size: 2,100,352 tokens` | `v1/worker/gpu_worker.py`、`kv_cache_utils.py` | 约 80GB 级 GPU；理论上 2048-token 请求最大并发 **1025.56x** |
| `Triton kernel JIT compilation during inference: _compute_slot_mapping_kernel` | `utils/jit_monitor.py` | warmup 未覆盖该 shape → 推理期首次编译（见 §三.3） |
| `Generated Outputs` | `LLM.generate()` 返回 | 4 条 prompt 完成（output_kind=FINAL_ONLY） |
| `Shutdown initiated/complete` | `core.py` | 进程退出 |

## 二、确认 V1 多进程架构（与我们分析一致）

日志全程以 `(EngineCore pid=697213)` 前缀输出核心日志，证明：
- 主进程只跑 `LLM` 门面 + I/O 预处理 + Detokenizer；
- **真正的引擎、调度、Worker、KV 管理在独立 `EngineCore` 子进程**（经 ZMQ/共享内存通信，规避 GIL）。
- 这正是 `LLM`（InprocClient 单进程入口）→ `EngineCore`（多进程引擎）的拆分模型。

## 三、需要你注意的 5 个问题

### 1. 5 个 "Unknown vLLM environment variable"（无害但需清理）
来源 `envs.py:2088 validate_environ()`：遍历 `os.environ`，凡 `VLLM_` 前缀且**不在已注册表**中的变量一律告警。
触发变量：`VLLM_SRC`、`VLLM_PRECOMPILED_WHEEL_VARIANT`、`VLLM_ENV_ROOT`、`VLLM_SOURCE_ROOT`、`VLLM_PRECOMPILED_WHEEL_LOCATION`。

这些名字明显是**预编译 wheel 的内部构建/CI 变量**（路径里有 `VLLM_PRECOMPILED_WHEEL_LOCATION`、`VLLM_SOURCE_ROOT`）。其中 `VLLM_PRECOMPILED_WHEEL_LOCATION` 在 `envs.py:616` 被代码引用，但未登记到注册表，所以仍告警。
**建议**：运行推理前 `unset` 这 5 个变量；它们不影响功能，只会刷屏。若来自你的 shell profile / CI 脚本，可考虑在 vLLM 中注册或改名。

### 2. ⚠️ 版本不一致：源码 v0.23.1rc0 vs 运行 v0.22.0
- 你的 git checkout：`v0.23.1rc0+1062`（我们前两轮分析的对象）。
- 本次运行日志：`Initializing a V1 LLM engine (v0.22.0)`。

说明 `basic.py` 实际加载的是**已安装的 vLLM 0.22.0 wheel**，而不是你当前这个 0.23.1rc0 源码树（日志中的 `VLLM_PRECOMPILED_WHEEL_LOCATION` 也印证了"预编译 wheel"环境）。
**影响**：你若想测试 0.23.1rc0 的新特性（Rust 前端、IR、renderers、Ubatch 等），必须确保 `pip install -e .` 生效或设置 `PYTHONPATH` 指向源码；否则跑的是旧版。
**建议**：`python -c "import vllm; print(vllm.__version__)"` 核对当前生效版本。

### 3. 推理期 Triton JIT 编译告警 `_compute_slot_mapping_kernel`
来自 `utils/jit_monitor.py`（我们架构报告里提过的"Kernel JIT monitor"）：
- 它在 **warmup 完成后**激活，监控 Triton/@triton.jit 首次编译、autotune cache miss、CuTeDSL/TileLang JIT。
- `_compute_slot_mapping_kernel` 是 **KV cache slot/block 映射**的 Triton kernel（PagedAttention 块管理）。它没被 warmup 覆盖，于首个真实推理步首次编译 → 触发延迟尖峰告警。

**严重度**：对本次 4 条短 prompt 可忽略；但**生产低延迟服务**下这是实打实的卡顿。
**修复**：扩展 warmup 覆盖该 shape/config（增大 `--num-warmup-iters` / 覆盖更全的 batch size 区间），或预编译该 kernel 编入缓存。

### 4. HF_TOKEN 未设置（仅限流）
`unauthenticated requests to the HF Hub` —— 集群能下完权重（走内部镜像或直连），但匿名限流更慢。设 `HF_TOKEN` 可提速；非必须。

### 5. 输出"胡言乱语"是正常现象，不是 bug
`"Joel, my dad is my friend..."`、`"all set to open a new gateway to the most notorious terror camps..."` 等完全 incoherent。原因：`opt-125m` 是 125M 参数的 base 预训练模型（训练语料 BookCorpus/CC-NEWS 等），**既非指令微调也非对话模型**，续写本就发散。流水线本身正确（tokenizer、调度、KV、采样、detokenizer 全部跑通），只是模型太小无法生成连贯文本。**若要看到"正常"输出，换 1B+ 或 instruct 模型（如 `meta-llama/Llama-3.2-1B-Instruct`）。**

## 四、性能数据速读（本机）
- 模型加载：12.57s（权重 1.21s + 编译 13.54s 含 torch.compile）
- torch.compile 总耗时：13.54s（Dynamo 7.66s + 图编译 4.71s），**已命中缓存**，下次冷启更快
- CUDA graph 捕获：51(PIECEWISE)+35(FULL)，~2s，占 0.19 GiB
- 推理吞吐（4 条短 prompt）：input 43.23 toks/s，output 106.42 toks/s
- KV cache：72.11 GiB 可用 → 2,100,352 tokens，2048-token 请求理论最大并发 ~1025x

## 五、行动建议（按优先级）
1. **核对生效版本**：`python -c "import vllm; print(vllm.__version__)"`，确认是 0.22.0 还是你期望的 0.23.1rc0。若要做源码级实验，重装 editable wheel。
2. **清理 5 个未知环境变量**：`unset VLLM_SRC VLLM_PRECOMPILED_WHEEL_VARIANT VLLM_ENV_ROOT VLLM_SOURCE_ROOT VLLM_PRECOMPILED_WHEEL_LOCATION`。
3. **生产环境消除 Triton JIT 尖峰**：扩展 warmup 或预编译 slot-mapping kernel。
4. **换更大/指令模型**以验证"正常"生成质量。
