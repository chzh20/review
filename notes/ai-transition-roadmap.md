# 转型 AI 综合路线图（Roadmap）

> 独立决策文档 · 整合自「vLLM 源码阅读 + mini-infer 课程大纲」「20 周计划」「两轮审查」
> 「EDA→LLM 复审」「就业+开源双主线设计」「每日面试手册」
> 「异常设计与资源管理课程」「日志与可观测性课程」。
> 读者仅凭本文即可掌握完整转型路径、阶段目标、技术要点与落地节奏。

---

## 0. 执行摘要（决策层速读）

| 项 | 结论 |
|----|------|
| **学员画像** | EDA 领域工程师，C++ 大型系统/性能优化背景，可使用公司 A100 算力，每天 3h（2h 学习 + 1h 面试练习） |
| **核心策略** | 主攻 **AI Infra / 推理系统工程师**（市场最紧缺交叉点），侧翼 **AI+EDA 复合岗**；**放弃**大模型算法研究员路线 |
| **时间投入** | 24 周课程（≈336h）+ 入职后 1–2 年成长；开源贡献贯穿全程 |
| **预期薪资** | Infra 岗 P50 = 80 万/年（超 60 万目标）；首份 LLM 工作现实区间 **60–90 万**，2–3 年兑现至 P50 |
| **最大杠杆** | ① EDA 的 C++/性能工程背景直接迁移到推理引擎岗；② A100 让微调/分布式/压测真实可跑；③ 开源 PR = 硬简历 + 内推弱关系 |
| **关键风险** | A100 合规政策、开源 PR 周期不可控、芯片公司波动、首份薪资非 P50；均有对冲方案（见 §10） |

---

## 1. 市场研判与定位

### 1.1 2026 就业市场关键数据

| 赛道 | P50 年薪 | 同比 | 供需状况 | 对转行门槛 |
|------|----------|------|----------|------------|
| 大模型算法研究员 | 120 万 | +35% | 千亿训练经验者被 8 家争抢；无经验者简历关难过 | 极高（论文/训练实战硬通货） |
| **AI Infra（CUDA/分布式/推理优化）** | **80 万** | **+25%** | **高性能计算工程师供需比 0.15，约 7 家抢 1 人，全市场最紧缺** | 中高（**不卡论文/学历，卡工程能力**） |
| AI 应用开发（RAG/Agent） | 45–60 万 | +30% | 需求最大但同质化严重 | 低 |

### 1.2 定位结论（EDA 背景的差异化打法）

1. **AI Infra 是 EDA 工程师的最短路径，没有之一**：EDA 日常（C++ 大型系统、性能优化、复杂算法工程化）正是推理引擎岗能力内核，而 Python 出身的算法工程师普遍不擅长——这是不对称优势。
2. **算法研究员路线明确放弃**：该岗为"千亿训练经验"付费，课程无法替代，且底座已过剩。
3. **AI+EDA 复合岗是定价权来源**：垂直行业经验 2026 年溢价 20–30%，既懂 EDA 又懂 LLM 的人几乎不存在。

### 1.3 目标岗位与薪资

| 优先级 | 岗位 | 年薪 | 适配理由 |
|--------|------|------|----------|
| 主攻 | 推理引擎 / AI Infra 工程师（vLLM/SGLang/TensorRT-LLM） | 80–150 万 | 供需比 0.15；C++/性能工程直接迁移 |
| 主攻 | AI 芯片公司编译器/算子/推理框架工程师 | 70–120 万 | EDA + CUDA = 芯片软件栈理想画像 |
| 侧翼 | AI4EDA 工程师（华大九天/概伦/Cadence AI/Synopsys AI/华为海思） | 60–100 万 | 竞争者极少，EDA 知识是他人无法速成的壁垒 |
| 备选 | AI 应用开发 | 45–60 万 | 仅作兜底 |

---

## 2. 总体路径与阶段划分

```text
近期（W1–15，约 3.5 个月）  地基 + 推理系统全栈攻坚
   └ 目标：工程地基 + 推理系统能力内核；门禁 G1（W6）、G2（W15）
中期（W16–24，约 2 个月）  实战收口 + 求职冲刺
   └ 目标：作品集 + 开源代码 PR + 拿到 offer；门禁 G3（W24）
远期（入职后 1–2 年）       职业落地与成长
   └ 目标：Infra 岗 onboarding → 技术 owner；薪资向 P50 兑现
```

开源贡献五级阶梯（贯穿 W1–24）：`读者 → 文档贡献者 → 测试贡献者 → bug 修复者 → 代码贡献者/活跃参与者`。

---

## 3. 近期阶段（W1–15）：地基 + 推理系统攻坚

### 3.1 目标

建立工程级 Python + PyTorch 双重地基；掌握推理系统全栈核心（主攻岗位能力内核）；完成从"使用者"到"首次贡献者"的转变。

### 3.2 核心任务与周计划

| 周 | 模块 | 关键技术要点 | 交付物 |
|----|------|--------------|--------|
| W1 | Python 工程基线 | pyproject/src layout、对象模型、**异常层级设计**、**logging 基础** | mini-infer v0.1 骨架 + 异常体系 + 20 测试 |
| W2 | 类型与设计模式 | Protocol vs ABC、Strategy/Factory/Adapter、mypy strict | 可替换 tokenizer/sampler |
| W3 | 并发与性能测量 | GIL、asyncio、benchmark 方法论 | 异步请求队列 + tokenizer benchmark + CI |
| W4 | PyTorch 执行模型 | Tensor/stride、Module 调用协议、dispatcher 地图 | stride 实验 + hook 调试 |
| W5 | Attention 与 Transformer | SDPA、RoPE、RMSNorm/SwiGLU/GQA/MoE | 手写 multi-head attention（数值验证全过） |
| W6 | 生成与 KV cache | prefill/decode、cache 复用、MHA/GQA 容量 | mini-infer v0.2（KV cache 一致性测试）→ **G1** |
| W7 | 推理性能模型 | roofline、算术强度、TTFT/TPOT | A100 实测 batch/seq 扫描曲线 + 偏差分析 |
| W8 | 调度与分页缓存 | continuous batching、PagedAttention | scheduler + BlockManager + 不变量测试 |
| W9 | 优化全景 + vLLM 导航 | chunked prefill、prefix caching、FlashAttention | `vllm-request-lifecycle.md` |
| W10 | **CPU 性能工程**（恢复全周） | cache 层级、false sharing、GEMM tiling→向量化→OpenMP | GEMM 优化 ≥10x 完整数据链 |
| W11 | C++ 扩展 | pybind11、torch.ops、GIL 释放 | mini-infer v0.4（C++ 算子 + golden test） |
| W12–14 | **CUDA 三周**（完整轨道） | SIMT/内存层级 → online softmax/tiled GEMM → decode/paged attention kernel + Nsight 归因 | mini-infer v0.5（三后端可切换） |
| W15 | 推理系统进阶（新增） | 投机解码、AWQ/FP8 量化、多卡 TP | 量化对照表 + 多卡 TP 压测报告 → **G2** |

> **A100 杠杆**：W10–W15 全部依赖 A100——CPU GEMM 为 CUDA GEMM 预演；多卡 TP/量化压测为面试三大热点（2026）提供真实数据。

### 3.3 Python 工程化深潜模块（W1 起贯穿，约 36h）

作为 M1 的工程化深度补充，含两门独立课程，直接映射 Infra 岗"工程素养"红线：

**A. 异常设计与资源管理**（可诊断性 + 可恢复性双主线，19.5h）
- 7 必学点：① 异常层级（单一根 + 语义分层 + `code`）② `try/except/else/finally`（`else` 隔离"成功才做"，`finally` 禁 `return`）③ `raise ... from e` 保留因果链（`__cause__` vs `__context__`，`from None` 切断噪声）④ EAFP vs LBYL（LBYL 在文件/网络/共享状态有 TOCTOU 竞态）⑤ Context Manager 协议（`__exit__` 默认返回 `False`，事务提交/回滚）⑥ `contextlib.contextmanager`（异常注入 `yield`，漏 `raise` = 静默吞）⑦ 禁止静默吞异常（四大反模式 + 处置四选一：显式处理/日志+重抛/重抛/转换）。
- 贯穿案例 `datapipe`；**PR 审查红线**：静默吞异常 / 裸抛 Exception / 丢失根因 / 资源未释放 / `__exit__` 返回 True 任一即否决。

**B. 日志与可观测性**（可定位性 + 安全性双主线，16.5h）
- 7 必学点：① `logging.getLogger(__name__)`（层级命名，绝不用 root）② logger/handler/formatter/level 四件套（双 level 放行）③ 库代码用 `NullHandler`、不配 root ④ 结构化日志（JSON Lines，字段只度量不记内容）⑤ request ID 经 `contextvars` + `Filter` 注入传播（asyncio 天然安全，多线程需 `copy_context`）⑥ 日志 vs 异常边界（异常给调用方、日志给排查者，记一次在处理边界）⑦ 敏感数据脱敏（`RedactionFilter` 出口兜底，prompt/token/PII 零明文）。
- 实战模块 `inference_logging.py`：单次推理请求输出含 `request_id / tokenizer_ms / prompt_tokens / decode_tokens / cache_usage / total_latency_ms` 结构化字段；`pytest` + `caplog` 三验证：① 正常路径含完整生命周期 ② 错误路径保留 request ID + `exc_info` ③ 完整 prompt 明文不落日志。

### 3.4 关键里程碑（门禁）

- **G1（W6 末）**：手写 causal attention 通过数值验证（不看资料）；mini-infer v0.2 测试/CI 全绿；≥1 个 docs PR merged；Transformer 细节 20 题录音自测 ≥80%。
- **G2（W15 末）**：CUDA attention kernel 通过全部边界 golden test + Nsight 归因；能量化解释 prefill/decode 的 bound 类型（白板）；≥1 个高质量 issue 复现被 maintainer 确认；已认领 1 个代码级 issue。

### 3.5 所需资源

- A100（≥1 张，多卡更佳）；Python 3.11+/PyTorch 2.x/CUDA 12；vLLM/SGLang 源码；CI（GitHub Actions）。
- 开源账号（GitHub）+ 目标项目 issue/PR 区。

### 3.6 预期成果

- mini-infer v0.1–v0.5（三后端可切换、golden test 全过）。
- ≥1 个 docs PR merged；≥1 个高质量 bug report 被确认。
- 6 篇技术博客（前 2 篇为工程化笔记）。
- 通过 G1、G2 双门禁。

---

## 4. 中期阶段（W16–24）：实战收口 + 求职冲刺

### 4.1 目标

补齐训练/应用广度；交付旗舰项目；完成代码级开源贡献（≥1 merged）；启动并拿下 offer。

### 4.2 核心任务与周计划

| 周 | 模块 | 关键技术要点 | 交付物 |
|----|------|--------------|--------|
| W16 | 训练基础（A100） | 训练循环、混合精度、梯度累积、继续预训练 | 1B 级模型继续预训练实验（领域语料） |
| W17 | 微调对照实验 | LoRA/QLoRA/全参原理与显存账 | **P2**：7B–13B 三种微调方式效果/成本对照表 |
| W18 | 分布式训练 | FSDP/DeepSpeed 切分、通信开销 | 多卡 A100 FSDP 跑通 + 扩展效率曲线 |
| W19–20 | **旗舰项目：EDA 智能助手** | RAG 全链路（chunking/混合检索/rerank）、vLLM 生产部署、评测集 | **P4**：EDA 知识库 RAG + vLLM 部署 7B + 并发压测 + 评测流水线（开源，英文 README） |
| W21 | vLLM 深水区 | scheduler/cache manager/attention backend | 源码阅读报告（结论附 commit hash + 行号）→ **代码 PR #1** |
| W22 | mini-infer 集成验收 | 三后端一致性、三组验收实验 | mini-infer v1.0 + benchmark 报告 → **代码 PR #2** |
| W23 | 求职冲刺 I | Infra 面试题库总复习 | 简历定稿（EDA 经历用性能工程语言重写）；模拟面试 #1–2 |
| W24 | 求职冲刺 II | 系统设计（"设计 X QPS 推理服务"） | 模拟面试 #3；目标公司触达 → **G3** |

### 4.3 旗舰项目叙事（简历核心）

> "EDA 背景工程师，系统掌握 LLM 推理栈：手写 CUDA attention kernel（Nsight 调优）→
> 自研 mini-infer 推理框架（三后端/continuous batching/paged KV cache）→
> vLLM 源码级理解（含 PR）→ 落地为 EDA 领域智能助手（RAG + 7B 模型 vLLM 部署，生产级压测数据）。"

同时命中 Infra 岗与 AI4EDA 岗 JD。

### 4.4 每日 1 小时面试练习（贯穿 W1–24，W16 起升级）

- **周节奏**：一/四 八股问答（抽题录音→回听→修正）；二 手撕题（无 IDE 限时写）；三 项目深挖（5 层 why）；五 自我介绍+行为题；六 错题重练/双周全真模拟；日 复盘+动态调整。
- **手撕重点**：W1–6 LeetCode + Python；W7–15 **手撕 attention / 数值稳定 softmax / top-k sampling**（目标 20min 无参考）；W16+ CUDA 伪代码/简单 kernel。
- **录音复盘六维**：结论先行 / 结构 / 准确 / 量化 / 流畅 / 时长（卡顿 >3 次或单题 >4min 不合格）；**当天重答同一题对比**是进步最快环节。
- **题库四状态**：未答→卡壳→合格→熟练；卡壳题 48h 内重答，同题卡壳 3 次→回学习侧补理论。
- **阶段重心**：G1 前八股 50%/手撕 30%；G2 前手撕升 40%（主攻手撕 attention）；W16 后深挖 40%+系统设计 30%；冲刺期模拟 60%。

### 4.5 关键里程碑（门禁 G3，W24 末）

- 旗舰项目达作品集五标准且公开；≥1 个代码级 PR merged（或进入深度 review）；
- 模拟面试三项（手撕/深挖/系统设计）通过外部评价（含 ≥1 次真人）；
- 投递启动：≥10 家目标公司进入流程。

### 4.6 所需资源

- A100 持续可用（训练/微调/压测）；公开数据集 + 开源模型（合规）。
- 模拟面试对象（同行/平台付费，每月 ≥1 次真人）；目标公司清单与人脉。
- 简历/作品集托管（GitHub Pages / 个人站）。

### 4.7 预期成果

- 3 个作品集项目（mini-infer v1.0 / 微调对照 / EDA 智能助手）全部达五标准并公开。
- ≥3 merged PR（docs≥1、issue 复现≥1、代码≥1）；≥5 篇博客（含 1 英文）。
- 开源贡献者档案（PR 列表 + issue + 博客）。
- 简历定稿 + 模拟面试通过 + offer 在途。

---

## 5. 远期阶段（入职后 1–2 年）：职业落地与成长

### 5.1 目标

从 onboarding 到技术 owner；薪资向 Infra 岗 P50（80 万）兑现；建立行业内的技术声誉与晋升通道。

### 5.2 核心任务

- **入职 0–3 月（落地）**：吃透团队推理栈代码；用课程积累的"可诊断/可恢复"工程素养快速定位线上问题（异常体系 + 结构化日志直接复用）；独立完成首个 oncall 周期。
- **3–12 月（贡献）**：主导一个推理优化子项目（kernel/调度/量化任一），复用 CUDA/性能工程能力；持续向 vLLM/SGLang 上游回灌 PR（维持 contributor 身份）。
- **12–24 月（成长）**：技术 owner + 跨团队影响；评估 AI 芯片公司/AI4EDA 溢价机会（EDA 背景的二次变现）；年化涨幅参考 Infra 岗 2.8 年平均在职期 + 25% 年涨幅。

### 5.3 关键里程碑

- 通过试用期；首个独立优化项上线并有益 benchmark；晋升/调薪一轮；≥2 个上游 PR（含 feature 级）。

### 5.4 所需资源

- 团队 mentorship；持续算力（公司）；社区活跃度维护时间。

### 5.5 预期成果

- 薪资达 80–120 万区间；技术影响力从"contributor"升至"owner"；形成"EDA+LLM Infra"复合个人品牌。

---

## 6. 开源贡献五级阶梯（跨阶段主线）

| 级别 | 周窗口 | 具体动作 | 验收 |
|------|--------|----------|------|
| 读者 | W1–3 | 跑通 vLLM quickstart；读 issue 区 3 个已关闭 issue 的修复过程 | 笔记 |
| 文档贡献者 | W2–6 | 首个 docs/typo PR；响应 review 直至 merge | ≥1 docs PR merged |
| 测试贡献者 | W7–9 | 提交带最小复现脚本的 bug report；本地复现性能 issue | ≥1 复现被确认 |
| bug 修复者 | W10–15 | 认领 good-first-issue；完成修复提 PR | 认领 1 代码级 issue |
| 代码贡献者 | W16–24 | ≥2 代码级 PR（W14 认领的 + SGLang/vLLM 任选）；开始 review 他人 PR | ≥1 代码 PR merged |

**机制**：每周固定 2h 开源时间盒（从 14h/周划出），防被学习挤压；PR review = 面试预演 + 与维护者（目标公司在职工程师）建立弱关系。

---

## 7. 评估体系与门禁

### 7.1 三维评估

| 维度 | 达标线 |
|------|--------|
| 技术能力 | G1/G2/G3 全过；mini-infer ≥100 测试 + CI 绿 + mypy strict；每优化项有可复现 benchmark |
| 开源影响力 | ≥3 merged PR（docs/issue/代码各≥1）；≥5 博客（含 1 英文）；review 他人 PR ≥2 次 |
| 就业就绪度 | 3 项目全达五标准；题库自测 ≥80%；3 轮模拟面试通过；≥10 家进入流程 |

### 7.2 作品集五标准（每个项目必过）

1. README 含问题定义与方案取舍；2. 一键复现（依赖锁定 + 脚本）；3. 量化结果（指标/曲线/对照）；4. 配套技术拆解文章；5. GitHub 公开 + 真实 commit 历史。

### 7.3 工程红线（PR 一票否决，源自两门工程课）

- 静默吞异常（`except: pass` / 裸 `except:` / 仅 `print`）；裸抛 `Exception` 无结构化信息；再抛出丢失根因。
- 资源未用 `finally`/CM 释放；`__exit__` 返回 `True` 或生成器漏 `raise`。
- 日志用裸 `getLogger()` 或库内 `basicConfig`/直连 root；prompt/token/PII 明文进日志。

---

## 8. 每周节奏总览

```text
每日 3h = 2h 学习（按 §3/§4 周表）+ 1h 面试练习（按 §4.4）
每周日 30min：本周面试题录音自答 → 回听修正（治"以为懂但讲不清"）
每阶段末：写复盘，区分"有数据支撑的结论"与"以为"
每 8 周：校对 vLLM/SGLang release notes + 面试题库（防课程过时）
```

---

## 9. 目标公司与触达

| 类别 | 代表 | 切入岗位 | 触达方式 |
|------|------|----------|----------|
| 大厂 AI Infra | 字节 Seed/AML、腾讯混元、阿里 PAI、美团、快手 | 推理引擎工程师 | 开源 PR + 博客 |
| 大模型公司 | DeepSeek、智谱、月之暗面、MiniMax、阶跃 | 推理优化/Serving | 开源 PR 直触维护者 |
| **AI 芯片公司**（重点） | 寒武纪、地平线、燧原、壁仞、摩尔线程、沐曦 | 编译器/算子/推理框架 | EDA 旧人脉内推优先 |
| **AI4EDA**（差异化） | 华大九天、概伦、Cadence/Synopsys AI、华为海思 | AI4EDA 工程师 | 旗舰项目直接对话 |
| 云厂商 MaaS | 火山、阿里云、腾讯云 | 推理平台工程师 | 压测报告匹配 |

**内推策略**：Infra 岗 PR 被 merge 后，维护者多为目标公司在职工程师——PR review = 技术面试预演 + 弱关系；EDA 旧人脉（前同事流向芯片/大厂芯片团队比例高）作为第一轮触达。

---

## 10. 风险与应对

| 风险 | 应对 |
|------|------|
| A100 使用政策限制 | 开课前确认；受限降级为云端租用（预算 ≤ 千元级）；全程用公开数据/开源模型，产出不含公司数据 |
| 开源 PR 周期不可控 | 门禁允许"进入深度 review"等价达成；并行提多个 PR 对冲 |
| 代码级 issue 难度超预期 | 备选：测试增强 PR、benchmark 工具 PR 同样算代码贡献 |
| 芯片公司波动 | 大厂 Infra 与芯片公司并行投递，不押单一赛道 |
| 首份薪资不及 P50 | 现实区间 60–90 万（EDA 年限部分折算）；先入行，Infra 岗 2.8 年在职期 + 25% 年涨幅支撑后续兑现 |
| 市场 24 周后变化 | 每 8 周校对趋势；主攻 + 芯片 + AI4EDA 三线并行 |

---

## 11. 关键技术实施要点速查

**异常设计**：单一根 + 语义分层 + 带 `code`；再抛出必 `from e`（或 `from None` 且有理由）；`else` 放"成功才做"、`finally` 禁 `return`；文件/网络/共享状态用 EAFP 防 TOCTOU；一切资源用 CM（`__exit__` 默认返 `False`）；永不静默吞异常。

**日志与可观测**：`getLogger(__name__)`；库用 `NullHandler` 不配 root；结构化字段只度量不记内容；request ID 用 `contextvars` + `Filter` 注入；异常给调用方、日志给排查者、记一次在处理边界；prompt/token/PII 经 `RedactionFilter` 出口脱敏。

**推理系统**：decode 是 memory-bound（要求现场推导算术强度）；KV cache 显存公式会算数；PagedAttention 解决碎片；FlashAttention = tiling + online softmax；投机解码用小模型 draft；量化对 decode 帮助大；TTFT/TPOT 随 batch 变化曲线。

**CUDA**：SIMT/内存层级/coalescing/shared memory tiling；手写 kernel 优化路径 + Nsight 归因；多卡 TP 切分与通信开销。

---

*路线图版本 v1.0 · 整合 8 份源文档 · 可作为汇报/决策/执行三用途统一底稿。*
