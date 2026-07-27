# LLM 推理系统工程师培养课程（就业 + 开源双主线版）

> 版本：v3.0（整合版）
> 前序文档：`llm-inference-course.md`（v1 大纲）→ `course-review-and-optimization.md`（通用求职审查）
> → `eda-to-llm-path-review.md`（EDA+A100 复审）。本文档为最终整合设计，取代前序版本。
> 学员画像：EDA 领域工程师，C++ 系统背景，可使用 A100 算力，每天 2 小时，周期 24 周。

---

## 一、课程定位

### 1.1 就业方向定位

| 定位 | 目标岗位 | 年薪区间（2026 市场） | 选择理由 |
|------|----------|----------------------|----------|
| **主攻** | AI Infra / 推理引擎工程师 | 80–150 万 | 供需比 0.15 全市场最紧缺；EDA 的 C++/性能工程背景直接迁移 |
| **主攻** | AI 芯片公司编译器/算子工程师 | 70–120 万 | EDA + CUDA 是芯片软件栈岗的理想画像 |
| **侧翼** | AI4EDA 工程师（EDA 公司 AI 团队/大厂芯片团队） | 60–100 万 | 垂直复合人才溢价 20–30%，竞争者极少 |
| 明确放弃 | 大模型算法研究员 | — | 为"千亿训练经验"付费，课程无法替代，底座已过剩 |

### 1.2 课程总目标

24 周后，学员应同时持有两张"通行证"：

1. **就业通行证**：3 个作品集项目 + 量化 benchmark 数据 + 可通过 Infra 岗全套面试的能力；
2. **开源通行证**：vLLM/SGLang 生态 ≥3 个 merged PR（含 1 个代码级 PR）+ 社区可见的贡献记录。

**双主线的关系**：开源贡献不是附加任务，而是就业策略的一部分——
Infra 岗招聘方就是这些开源项目的维护者；PR review 过程即技术面试预演；
merged PR 是比任何简历措辞都硬的能力证明。

### 1.3 设计原则

- **就业导向**：每个模块结束时回答"这在简历上写什么、面试怎么考"；
- **开源贯穿**：按「读者 → 文档 → 测试 → 修复 → 功能」五级阶梯递进，与技术水平同步解锁；
- **理论实践闭环**：所有算子/kernel 必有 golden test；所有性能结论必有 benchmark 数据；
- **A100 充分利用**：微调对照、多卡分布式、生产级压测均真实执行；
- **可评估**：每阶段设硬门禁（gate），不过门禁不进入下一阶段。

---

## 二、总体结构（三阶段 24 周 × 14h/周 ≈ 336h）

```text
阶段一 · 基础筑基（W1–6）   工程能力 + PyTorch/Transformer 原理
           开源角色：读者 → 文档贡献者
阶段二 · 进阶攻坚（W7–15）  推理系统全栈：调度/CUDA/性能工程/推理进阶
           开源角色：测试贡献者 → bug 修复者
阶段三 · 实战收口（W16–24） 训练微调（A100）+ 旗舰项目 + vLLM 深水区 + 求职冲刺
           开源角色：代码贡献者 → 活跃参与者
```

---

## 三、阶段一：基础筑基（W1–6）

### 学习目标

建立工程级 Python 与 PyTorch 双重地基；开源侧完成从"使用者"到"首次贡献者"的转变。

### 课程设置

| 周 | 模块 | 理论要点 | 实践任务 | 开源实践 |
|----|------|----------|----------|----------|
| W1 | Python 工程基线 | pyproject/src layout、对象模型、异常层级、logging | mini-infer 骨架 + 异常体系 + 20 测试 | 在 vLLM repo 跑通 quickstart；阅读 issue 区，记录 3 个已关闭 issue 的修复过程（学习 bug 报告结构） |
| W2 | 类型与设计模式 | Protocol vs ABC、Strategy/Factory/Adapter | 可替换 tokenizer/sampler，mypy strict | 提交**第一个 PR**：vLLM/Transformers 文档 typo 或示例修复（good-first-contribution 标签） |
| W3 | 并发与性能测量 | GIL、asyncio、benchmark 方法论 | 异步请求队列 + tokenizer benchmark + CI | PR 跟进：响应 maintainer review 意见直至 merge（学习开源协作流程） |
| W4 | PyTorch 执行模型 | Tensor/stride、Module 调用协议、dispatcher 地图 | stride 实验 + hook 调试 + `pytorch-execution-model.md` | 阅读 PyTorch contribution guide；用 `torch.profiler` 数据在 discussions 回答/提问 1 次 |
| W5 | Attention 与 Transformer | SDPA、RoPE、RMSNorm/SwiGLU/GQA/MoE | 手写 multi-head attention（数值验证全过） | 对照阅读 HF Transformers 某模型的 attention 实现，输出对照笔记（发布为博客 #1） |
| W6 | 生成与 KV cache | prefill/decode、cache 复用推导、MHA/GQA 容量 | mini-infer v0.2：KV cache 一致性测试 | **门禁 G1**（见 §六）；整理前 6 周笔记为公开博客 2 篇 |

### 阶段一门禁 G1

- 手写 causal attention 通过数值验证（不看资料）；
- mini-infer v0.2 测试/CI 全绿；
- ≥1 个 docs PR 被 merge；
- 面试自测：Transformer 细节 20 题正确率 ≥80%（录音自答）。

---

## 四、阶段二：进阶攻坚（W7–15）

### 学习目标

掌握推理系统全栈核心（这是主攻岗位的能力内核）；开源侧升级到测试与代码修复贡献。

### 课程设置

| 周 | 模块 | 理论要点 | 实践任务 | 开源实践 |
|----|------|----------|----------|----------|
| W7 | 推理性能模型 | roofline、算术强度、TTFT/TPOT | A100 上实测 batch/seq 扫描曲线，理论 vs 实测偏差分析 | 把压测方法论写成博客 #3；在 vLLM issue 区找 1 个性能类 issue 尝试本地复现 |
| W8 | 调度与分页缓存 | continuous batching、PagedAttention 论文 | scheduler + BlockManager + 不变量测试 | 阅读 vLLM scheduler 相关 PR 的讨论（学习 review 标准） |
| W9 | 优化全景 + vLLM 导航 | chunked prefill、prefix caching、FlashAttention 论文 | `vllm-request-lifecycle.md` | **复现一个 issue**：提交带最小复现脚本 + 环境信息的高质量 bug report（或为已有 issue 补充复现确认） |
| W10 | CPU 性能工程 | cache 层级、false sharing、GEMM tiling/向量化/OpenMP | GEMM 优化 ≥10x 完整数据链 | 无（专注攻坚） |
| W11 | C++ 扩展 | pybind11、torch.ops、GIL 释放 | mini-infer v0.4：C++ 算子 + golden test | 阅读 vLLM `csrc/` 一个文件并写源码登记笔记（博客 #4） |
| W12–14 | CUDA 三周三连 | SIMT/内存层级 → online softmax/tiled GEMM → decode/paged attention kernel + Nsight 归因 | mini-infer v0.5：三后端可切换，全部 golden test | 寻找 vLLM/SGLang 中标注 good-first-issue 的 kernel/算子相关 issue，认领评估（W14 末确定目标） |
| W15 | 推理系统进阶 | 投机解码、AWQ/FP8 量化、多卡 TP | A100 实操：量化精度/速度对照表；多卡 TP 部署压测报告 | **门禁 G2** |

### 阶段二门禁 G2

- CUDA attention kernel 通过全部边界 golden test + Nsight 归因报告；
- 能量化解释 prefill/decode 的 bound 类型（面试白板题）；
- ≥1 个高质量 issue 复现报告被 maintainer 确认；
- 已认领 1 个代码级 issue（为阶段三 PR 做准备）。

---

## 五、阶段三：实战收口（W16–24）

### 学习目标

补齐训练/应用广度；交付旗舰项目；完成代码级开源贡献；启动求职。

### 课程设置

| 周 | 模块 | 理论要点 | 实践任务 | 开源实践 |
|----|------|----------|----------|----------|
| W16 | 训练基础（A100） | 训练循环、混合精度、梯度累积、继续预训练 | 1B 级模型继续预训练实验（领域语料） | 向 PEFT/Transformers 提 1 个 docs/example PR（训练侧社区混熟） |
| W17 | 微调对照实验 | LoRA/QLoRA/全参原理与显存账 | **P2 项目**：7B–13B 三种微调方式效果/成本对照表 | 实验数据整理为博客 #5（微调对照类内容社区需求高） |
| W18 | 分布式训练 | FSDP/DeepSpeed 切分逻辑、通信开销 | 多卡 A100 FSDP 跑通 + 扩展效率曲线 | 无（专注攻坚） |
| W19–20 | **旗舰项目：EDA 智能助手** | RAG 全链路（chunking/混合检索/rerank）、vLLM 生产部署、评测集构建 | **P4 项目**：EDA 知识库 RAG（工艺文档/PDK 手册）+ vLLM 部署 7B + 并发压测 + 评测流水线；可选 Verilog 生成实验 | 项目开源（GitHub 公开，MIT/Apache）；写英文 README（国际可见性） |
| W21 | vLLM 深水区 | scheduler/cache manager/attention backend 实现细节 | 源码阅读报告（每个结论附 commit hash + 行号） | **代码 PR #1 提交**：W14 认领的 issue 完成修复并提 PR；同时开始 review 他人 PR（学习 + 曝光） |
| W22 | mini-infer 集成验收 | 三后端一致性、三组验收实验 | mini-infer v1.0 + benchmark 报告 | **代码 PR #2**（SGLang/vLLM 任选）；更新 GitHub profile/pinned repos |
| W23 | 求职冲刺 I | Infra 面试题库总复习 | 简历定稿（EDA 经历用性能工程语言重写）；模拟面试 #1–2（手撕 attention kernel + 项目深挖） | 开源贡献页整理：PR 列表 + issue 记录 + 博客，形成"贡献者档案" |
| W24 | 求职冲刺 II | 系统设计专项（"设计 X QPS 推理服务"） | 模拟面试 #3；目标公司清单触达（§七） | **门禁 G3** |

### 阶段三门禁 G3

- 旗舰项目达到作品集五标准（§6.2）且公开；
- ≥1 个代码级 PR merged（或进入 maintainer 深度 review 轮次）；
- 模拟面试三项（手撕/深挖/系统设计）全部通过外部评价；
- 投递启动：≥10 家目标公司进入流程。

---

## 六、学习成果评估机制

### 6.1 三维评估体系

| 维度 | 指标 | 达标线 |
|------|------|--------|
| **技术能力** | 阶段门禁 G1/G2/G3 | 全部通过 |
| | 测试与质量 | mini-infer ≥100 测试、CI 绿、mypy strict |
| | 性能数据 | 每个优化项有可复现 benchmark（环境/输入/次数/偏差齐全） |
| **开源影响力** | merged PR 总数 | ≥3（docs ≥1、issue 复现 ≥1、代码 ≥1） |
| | 技术博客 | ≥5 篇（其中 1 篇英文） |
| | 社区互动 | review 他人 PR ≥2 次；discussions/issue 有效参与 ≥5 次 |
| **就业就绪度** | 作品集 | 3 个项目全部满足五标准 |
| | 面试 | 题库自测 ≥80%；3 轮模拟面试通过 |
| | 简历 | 每条项目 bullet 含量化结果 |

### 6.2 作品集五标准（每个项目逐项打勾）

1. README 含问题定义与方案取舍；
2. 一键复现（依赖锁定 + 脚本）；
3. 量化结果（指标/曲线/对照实验）；
4. 配套技术拆解文章；
5. GitHub 公开 + 真实 commit 历史。

### 6.3 过程性评估（每周）

- 周日 30 分钟自测：本周主题面试题录音自答 → 回听修正（"以为懂但讲不清"是最常见的挂点）；
- 每周开源时间盒：固定 2h（从 14h/周中划出），防止开源任务被挤压；
- 每阶段末写复盘：哪些结论有数据支撑、哪些还是"以为"。

---

## 七、行业对接设计

### 7.1 项目与 JD 的映射

| 项目 | 对接 JD 要求 | 简历表述锚点 |
|------|--------------|--------------|
| mini-infer（三后端推理框架） | 推理引擎开发、KV cache/调度优化 | "实现 continuous batching + paged KV cache，短请求等待降低 XX%" |
| P2 微调对照实验 | 模型微调与领域适配 | "A100 上完成 7B/13B 三种微调路径对照，给出成本-效果选型结论" |
| P4 EDA 智能助手 | LLM 应用落地、vLLM 部署运维 | "EDA 领域 RAG 系统，vLLM 部署，X QPS 下 TPOT XXms，答案正确率 XX" |
| 开源贡献档案 | 工程协作能力、社区影响力 | "vLLM/SGLang contributor，N 个 merged PR" |

### 7.2 目标公司与触达路径

- **大厂 Infra**（字节 Seed/AML、腾讯混元、阿里 PAI、美团、快手）＋ **大模型公司 infra 团队**（DeepSeek/智谱/MiniMax 等）：以开源 PR + 博客触达；
- **AI 芯片公司**（寒武纪/地平线/燧原/壁仞/摩尔线程/沐曦）：EDA 人脉优先内推，编译器/算子岗；
- **AI4EDA**（华大九天/概伦/Cadence/Synopsys AI 团队/华为海思）：旗舰项目直接对话，竞争最小；
- 云厂商 MaaS 平台（火山/阿里云/腾讯云）：推理平台岗，压测报告直接匹配。

### 7.3 技术趋势对齐（课程内容时效性声明）

- 课程内容每 8 周校对一次 vLLM/SGLang 最新 release notes，重点跟踪：attention backend 演进、
  量化格式（FP8 普及度）、投机解码工业落地、MCP 生态；
- 所有源码阅读固定 commit hash，但笔记中标注"截至 YYYY-MM 的 master 变化"；
- 面试题库每季度按最新面经更新。

---

## 八、风险与应对

| 风险 | 应对 |
|------|------|
| 公司 A100 使用政策限制 | 开课前确认；受限时降级为云端租用（全程预算 ≤ 千元级） |
| 开源 PR 周期长、不可控 | 门禁允许"进入深度 review 轮次"作为等价达成；同时并行提多个 PR 对冲 |
| 代码级 issue 难度超预期 | 备选路径：测试增强 PR、benchmark 工具 PR 同样算代码贡献 |
| 24 周后市场变化 | 每 8 周校对趋势（§7.3）；主攻岗与 AI 芯片/AI4EDA 三线并行投递 |
| 首份薪资不及 P50 | 现实区间 60–90 万（EDA 年限部分折算）；先入行，Infra 岗 2.8 年平均在职期 + 25% 年涨幅支撑后续兑现 |
