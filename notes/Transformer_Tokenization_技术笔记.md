# Transformer Tokenization 详解

> 配套笔记：与《Transformer论文精读_技术笔记.md》《Transformer数据组织结构.md》及 `transformer_zh_en/` 复现项目配套阅读。

## 1. 定义与作用

**Tokenization（分词/令牌化）** 把连续文本字符串切分为模型可处理的最小单元（token）。三个核心作用：

1. **离散 → 连续**：文本 → token → 词表整数 ID（`input_ids`）→ Embedding 查表得到 `[B, S, D]` 浮点向量，Transformer 才能运算。
2. **控制词表规模**：切分粒度决定词表大小。粒度越细 → 词表越小、越不易 OOV；粒度越粗 → 序列越短、算得越快，但词表爆炸且 OOV 严重。
3. **注入结构信息（中文尤其重要）**：英文有空格天然分词，中文无词边界，分词策略决定模型学到“词”还是“字”。

## 2. 在 Transformer 流程中的位置

```
原始文本 → Tokenizer(切分+归一化) → Token 序列 → input_ids [B,S] → Embedding 查表 → [B,S,D] 张量 → Transformer
```
- 离散张量（`input_ids` / `attention_mask` / `labels` / `position_ids`）形状为 `[B, S]`。
- 连续张量（`inputs_embeds` / `hidden_states` / `positional_encoding`）形状为 `[B, S, D]`。
- `logits` 形状为 `[B, S, vocab_size]`。

## 3. 三类粒度方法对比

| 方法 | 切分单元 | 词表规模 | 序列长度 | 优点 | 缺点 | 典型场景 |
|------|----------|----------|----------|------|------|----------|
| **Word-level** | 整词（空格/词典） | 大（数万~百万） | 最短 | 语义单元完整，序列短算得快 | 极易 OOV（新词/变体变 `<unk>`）；中文无词边界难直接用 | 封闭小词表任务（词性标注、固定类别） |
| **Character-level** | 单字符/单字 | 极小（几十~几百） | 最长 | 永不 OOV，对拼写/形态极鲁棒 | 序列很长→注意力开销大、长程依赖难学；语义需模型自组 | 拼写敏感任务（DNA/蛋白质）、极稀缺语言 |
| **Subword-level** | 子词（词根+词缀） | 中等（数千~数万） | 中等 | 兼顾两者：罕见词拆子词避免 OOV，常见词保完整 | 实现稍复杂，需先训练合并规则 | 现代 LLM/翻译事实标准（BPE/WordPiece/SentencePiece） |

**关键直觉**：`unbelievable`
- Word 级：1 个 token（不在词表则 `<unk>`）。
- Char 级：12 个 token（序列长但绝不 OOV）。
- Subword 级：`un` + `believ` + `able` 共 3 个 token——既短又不 OOV。

→ 这就是为什么 Transformer 原论文（中英翻译）与几乎所有大模型都选 Subword。

## 4. Subword 三大主流实现

- **BPE（Byte-Pair Encoding）**：从字符出发，反复合并语料中**最高频的相邻对**，学到 `merge rules`。GPT-2/3、RoBERTa 使用。
  - 示例 `love`：`[l,o,v,e]` → 合并 l+o, v+e → `[lo, ve]` → 合并 → `[love]`。
- **WordPiece**（BERT 用）：合并依据**似然增益**（使语言模型概率提升最大的一对），而非纯频率；子词以 `##` 开头表示接前词后。
- **Unigram / SentencePiece**（LLaMA、T5、多语言模型）：从全字符开始**逐步删除**对整体损失影响最小的子词，保留带概率的子词词表。SentencePiece 直接对原始字符串操作（空格用 `▁` 表示），**天然支持无空格语言（中文/日文）且可中英共享词表**。

## 5. 如何选择合适的策略（决策树）

```
选择分词策略
   └─ 语料/任务的主要挑战?
        ├─ 多语言 / 罕见词 / 专业术语  → Subword (BPE / WordPiece)  【推荐默认】
        ├─ 极受限算力 / 拼写 DNA 敏感  → Character
        └─ 封闭小词表（固定类别任务）  → Word
```

经验法则：**默认 Subword**。仅在字符级信号本身有意义（如基因序列）或词表极小时才退到 Character；仅在任务类别封闭且已知时用 Word。

## 6. 中文的特殊处理

- 中文无空格，Word-level 需先依赖 jieba 等分词器或退化为字级。
- 工业界主流：直接用 **SentencePiece / BPE 对原始中文字符串做 Subword**，模型自学到“字→词根→词”组合，且可**中英共享词表**（shared vocab，省参数、跨语言迁移更好）。
- 与 `transformer_zh_en/` 项目一致：英文/中文共用一份 BPE 词表，Encoder/Decoder Embedding 与 Softmax 权重共享。

## 7. 特殊 Token 约定

分词后插入：`<bos>`/`<eos>`（序列起止）、`<pad>`（批次对齐填充）、`<unk>`（兜底）。
- `<pad>` 位置在 Attention 中用 mask 屏蔽，不计入 loss。
- HuggingFace 约定 `labels` 中 `-100` 位置在 CrossEntropy 中被忽略。

## 8. 主流工具

- **HuggingFace `tokenizers`**：Rust 实现，BPE/WordPiece/Unigram 全支持，极快。
- **`sentencepiece`**：Google 出品，原生无空格语言友好。
- 训练流程：训练集统计频次 → 学合并规则 → 定词表大小（论文 32000~37000；小算力可缩到 8000）。

## 9. 与整体知识链衔接

分词产出 `input_ids [B,S]` → Embedding(×√d) + Positional Encoding → `[B,S,D]` → 进入 Transformer 各层（见《Transformer数据组织结构.md》）。
