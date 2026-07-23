# 技术笔记：亲手实现 GPT Tokenizer（"Let's build the GPT Tokenizer"）

> 来源：Andrej Karpathy — YouTube 视频 *Let's build the GPT Tokenizer*（https://www.youtube.com/watch?v=zduSFxRajkE）
> 整理：结构化技术笔记（忠实还原字幕原意，去除口语冗余）
> 说明：本笔记按"基础概念 → BPE 算法与实现 → 真实分词器（GPT-2 / GPT-4 / SentencePiece）→ 词汇表权衡与多模态 → 现象归因"的逻辑组织；并在末尾补充**第十一部分（Tokenizer 原理进阶）**与**第十二部分（工程实践）**，横向对比 BPE / WordPiece / Unigram、详解编解码与特殊 token、系统小结词表构建与大小影响、Subword 优势，以及训练流程、推理优化、多语言处理与 HuggingFace 实践。

---

## 目录

1. [第一部分：动机、字符级回顾与现代 Tokenization 基础](#第一部分动机字符级回顾与现代-tokenization-基础)
2. [第二部分：为何不用原始字节、BPE 算法原理与从零实现](#第二部分为何不用原始字节bpe-算法原理与从零实现)
3. [第三部分：解码 / 编码实现、回合一致性与 GPT-2 预分词正则](#第三部分解码--编码实现回合一致性与-gpt-2-预分词正则)
4. [第四部分：GPT-2 预分词正则细则、Tiktoken 与特殊 Token](#第四部分gpt-2-预分词正则细则tiktoken-与特殊-token)
5. [第五部分：从零实现 GPT-4 分词器、SentencePiece 与词表大小权衡（上）](#第五部分从零实现-gpt-4-分词器sentencepiece-与词表大小权衡上)
6. [第六部分：词汇表大小权衡、扩展词汇表与多模态 Tokenization](#第六部分词汇表大小权衡扩展词汇表与多模态-tokenization)
7. [第七部分：开篇"怪现象"根因解析（拼写 / 非英语 / 算术 / Python / 特殊 token / 尾随空格 / 部分 token）](#第七部分开篇怪现象根因解析拼写--非英语--算术--python--特殊-token--尾随空格--部分-token)
8. [第八部分：Solid Gold Magikarp 与 Token 经济性](#第八部分solid-gold-magikarp-与-token-经济性)
9. [第九部分：总结与建议](#第九部分总结与建议)
10. [第十一部分：Tokenizer 原理进阶补充（算法对比 / 编解码与特殊 Token / 词表构建 / Subword 优势）](#十一tokenizer-原理进阶补充)
11. [第十二部分：工程实践补充（训练 / 推理优化 / 多语言 / HuggingFace）](#十二工程实践补充)

---
# 第一部分：动机、字符级回顾与现代 Tokenization 基础

## 1. 为什么必须理解 Tokenization
- **Tokenization（分词 / 令牌化）** 是把文本字符串转换为**整数 token 序列**的过程，是 LLM 流水线的第一环，也是 Karpathy 认为"最不喜欢但最必要"的一环。
- 它"毛刺很多（hairy）"，存在大量**隐藏的 footguns（陷阱）**。许多看起来像模型或架构的问题，追根溯源其实是 **tokenization 的问题**。

## 2. 朴素方案回顾：字符级 Tokenization
- 在 "Let's Build GPT from scratch" 中，对莎士比亚文本采用**字符级（character-level）分词**：
  - 统计所有出现过的字符，建立大小为 **65** 的**词表（vocabulary）**。
  - 维护一张**查找表（lookup table）**，把每个字符映射到整数 token。
  - 例："Hi there" → 一串 token；取前 1000 个字符 → 恰好 1000 个 token（**一一对应**）。
- 这些整数 token 通过 **Embedding 表** 查表得到可训练向量，再送入 **Transformer**。
- 嵌入表行数 = 词表大小（65 行），每行向量经**反向传播**训练。

## 3. 现代 LLM 采用子词级（chunk-level）分词
- 实际 SOTA 模型不用字符级，而用更复杂的方案在**字符块（chunk）** 层面构造词表。
- 核心算法之一是 **Byte Pair Encoding（BPE，字节对编码）**，本视频将从零实现。
- 起源参考：**GPT-2 论文**的 *Input Representation* 一节——提出词表大小为 **50,257**，上下文长度 **1,024** token。

## 4. Token 是 LLM 的"原子"
- **Token 是 LLM 的基本单位（atom）**：一切以 token 计，一切都围绕 token。
- **Tokenization** = 字符串 ⇄ token 序列 的双向转换。
- 在 Transformer 的 **attention（注意力）** 层中，每个 token 最多关注序列中前 **1,024** 个 token（GPT-2）。
- 论文佐证：**Llama 2** 中提到在 **2 万亿（2 trillion）token** 数据上训练，"token" 一词出现 63 次，说明其无处不在。

## 5. Tokenization 引发的典型"怪异"现象（footguns）
许多 LLM 的异常表现可归因于分词方式：
- **拼写任务**困难（如拼单词）——因为字母被打包进子词 token。
- **非英语语言**效果变差——训练语料中英语占比大，对应 token 更长更省。
- **简单算术**容易出错——数字被任意切分。
- **GPT-2 对 Python 支持差**——缩进空格被拆成大量独立 token，浪费序列长度（非模型本身问题）。
- ** trailing whitespace（尾部空格）** 警告——分词边界问题。
- **"Solid Gold Magikarp"** 等诡异输出——与特定 token 相关。
- **推荐用 YAML 而非 JSON** 传递结构化数据——同样是 token 层面的考量。

## 6. 可视化演示：Tiktokenizer（tiktokenizer.vercel.app）
- 浏览器内用 JavaScript 实时分词，适合直观观察。以 **GPT-2 tokenizer** 为例：
  - "tokenization" → 2 个 token：`3642`、`1634`。
  - 空格常作为 token 的**前缀**被并入块中（如 ` the` = 379，` the` = 262）。
- **算术切分是任意的**：`127` 是 1 个 token；`677` 拆成 2 个；`804` 拆成 2 个；四位数拆分方式无规律。
- **"egg" 的歧义**：句首单独 `egg` = 2 个 token；带前导空格 ` egg` = 1 个 token；**大小写敏感**（不同颜色 = 不同 token）。
  - 含义完全相同的 "egg"，因位置/大小写不同 → 完全不同的 token id；模型只能从海量数据中自行学会它们是"近义"概念。
- **非英语更费 token**：同一句话，韩语/日语等译文的 token 数通常远大于英文 → 序列被"拉长" → 更快耗尽 **最大上下文长度**。

## 7. Tokenizer 设计差异：GPT-2 vs GPT-4（CL100K）
- 同一段文本：GPT-2 tokenizer 产生 **300** token；换成 **CL100K（GPT-4）** 降至 **185**。
- 原因：GPT-4 词表约 **100K**，约为 GPT-2（~50K）的两倍 → 文本被"压缩"进一半的 token，**输入更稠密**，单 token 可关注到的上文长度翻倍。
- 但词表并非越大越好：词表增大 → **Embedding 表**与输出层 **softmax** 同步变大，需权衡"稠密度"与"效率"的**甜点区（sweet spot）**。
- GPT-4 针对 Python **空白字符**做了改进：4 个空格 → 1 个 token；7 个空格 → 1 个 token。这是 OpenAI 的**刻意设计**，使 Python 更稠密 → 编码能力从 GPT-2 到 GPT-4 的提升，部分来自 tokenizer 设计而非仅模型/架构。

## 8. 编码基础：从字符串到字节
- 目标：把字符串 → 固定词表内的整数 → 查嵌入表 → 送入 Transformer；需支持多语言（韩语 "안녕"）、特殊字符、emoji。
- Python 中字符串是 **Unicode 码点（code point）** 的不可变序列。
  - **Unicode**：由 Unicode 联盟定义，当前约 **150,000** 个字符、覆盖 **161** 个书写系统（标准 15.1，2023-09）；仍在演进。
  - `ord()` 取单字符码点：H → 104；某 emoji → 128512；안 → 50403。
- **为什么不直接用码点当 token？**
  - 词表过大（~150,000）；
  - Unicode 标准持续变化，**表示不稳定**。
- **编码（encoding）**：把 Unicode 文本转为字节流。Unicode 联盟定义三种：
  - **UTF-8**：最常用，**变长编码**，每码点占 **1–4 字节**；与 **ASCII 向后兼容**；"UTF-8 Everywhere" 宣言推崇之。
  - **UTF-16**：对 ASCII 字符出现 `0x00` 浪费（如 `0x?? 0x00`），较不经济。
  - **UTF-32**：**定长**但更浪费，实际少用。
- Python 实操：`s.encode('utf-8')` 得到 `bytes` 对象；用 `list(...)` 可查看原始字节序列。
# 第二部分：为何不用原始字节、BPE 算法原理与从零实现

## 9. 为什么不直接用 UTF-8 原始字节
- 若直接把 UTF-8 字节流当 token，**词表只有 256**（一个字节的取值域）。
- 问题：文本会被拉成**极长的字节序列** → **Embedding 表**虽小，但 **注意力（attention）** 计算随序列变长而急剧变贵，且受**有限上下文长度**制约 → 单 token 能关注到的上文太短，效率低。
- 因此目标：保留 UTF-8 编码，但用 **BPE** 把字节序列**压缩**成可调节大小的更大词表。
- 旁注：存在"免分词（tokenization-free）"方向的研究（层级化 Transformer 直接吃字节流，论文称 "tokenization free autoregressive sequence modeling at scale"），但尚**未被充分大规模验证**，目前仍需 BPE。

## 10. Byte Pair Encoding（BPE，字节对编码）算法原理
- 核心思想：**迭代式贪心合并**。
  1. 统计序列中**相邻 token 对（pair）** 的出现频次；
  2. 取**最频繁**的一对，铸造（mint）一个**新 token** 加入词表；
  3. 把序列中所有该相邻对替换为新 token；
  4. 重复，直到达到目标词表大小。
- 直觉示例：初始词表 `{a,b,c,d}`、序列长 11 → 经多轮合并，序列压缩到 5，词表增长到 7。即**序列变短、词表变大**，实现无损压缩式表示。
- 用于 LLM：起点是**字节序列（256 词表）**，对最频繁的**字节对**反复合并、铸造新 token（ID 从 256 起），最终得到压缩后的训练数据与一套 **encode / decode** 算法。

## 11. 从零实现 BPE（代码要点）
- 文本 → `text.encode('utf-8')` → `bytes` → 转成整数列表便于操作。
  - 示例段落：**533 个码点** → **616 字节**（因复杂 Unicode 字符占多字节）；即此阶段 1 码点可对应多 token。
- **`get_stats(ids)`**：遍历相邻元素，用字典统计每对 `(a, b)` 的频次。
  - 最频繁对为 `(101, 32)`，出现 20 次；`chr(101)='e'`、`chr(32)=' '`（很多单词以 e 结尾）。
- **`merge(ids, pair, idx)`**：顺序扫描，命中 pair 则替换为新 `idx`；否则原样复制。
  - 注意**边界保护**：在最右元素处避免越界访问。
  - 小例：`[5,6,6,7,9,1]` 把 `(6,7)` 替换为 99 → `[5,6,99,9,1]`。
- 取最优对：`max(stats, key=stats.get)`。
- 效果验证：序列长度 616 → 596（减少 20，即该对被合并的次数）；原数组中不再出现 `(101,32)`。

## 12. 合并次数 = 超参数（决定词表大小）
- 合并轮数越多 → **词表越大、序列越短**，存在工程**甜点区（sweet spot）**。
- 当前主流大模型词表约 **10 万**（如 GPT-4）。
- 实操设定：目标词表 **276** = 基础 256 字节 + **20 次合并**；新 token ID 从 256 递增。
- `merges` 字典记录 `(child1, child2) → new_token` 的映射，形成的是**二叉森林（binary forest）**而非单棵树：从叶子（字节）向上两两合并，新铸 token 在下一轮**也可参与合并**（如第 20 次合并 `256` 与 `259` → `275`）。
- **压缩率（compression ratio）**：24,000 字节 → 20 轮合并后约 19,000 token，压缩比约 **1.27**；词表越大压缩越强。

## 13. Tokenizer 是独立于 LLM 的预处理阶段
- **Tokenizer 与 LLM 是完全分离的对象**：本讲座全程只训练 tokenizer，不碰模型本身。
- 它有**自己的训练集**（一批文档），在其上跑 BPE 得到词表与 merges；通常**只在最开始运行一次**。
- 训练完成后具备双向能力：
  - **Encoding（编码）**：原始文本（Unicode 码点序列）→ token 序列；
  - **Decoding（解码）**：token 序列 → 原始文本。
- 工程惯例：把所有 LLM 训练数据**先过 tokenizer** 转成巨型 token 序列落盘，**原始文本可丢弃**，LLM 实际读取的是 token。
- **Tokenizer 训练集可与 LLM 训练集不同**：为兼顾多语言与代码，应在 tokenizer 语料中混入不同语言与代码比例；某类语言/代码占比越高，其合并越多、在该类数据上的**表示越稠密**。
# 第三部分：解码 / 编码实现、回合一致性，以及 GPT-2 的预分词正则

## 14. 解码（Decoding）：token 序列 → 文本
- 构建 `vocab` 字典：**token ID → bytes 对象**。
  - 先放入原始字节 `0–255`；再按 `merges` 的插入顺序，令 `vocab[new_id] = vocab[child1] + vocab[child2]`（bytes **拼接**，因是 bytes 对象相加）。
  - **关键点**：必须按 merges 的**插入顺序**遍历 —— Python 3.7+ 保证字典插入有序（之前版本不保证，会出错）。
- 解码流程：对每个 ID 用 `vocab` 查出 bytes → 拼接 → `bytes.decode('utf-8')` 得字符串。
- **陷阱：非法 UTF-8 起始字节**。例如单独解码 token `128`（`0x80`）：其二进制 `10...` 不符合 UTF-8 编码格式 → 报错 `invalid start byte`。
  - 原因：并非所有字节序列都是合法 UTF-8（多字节字符需特定的"信封"格式）。
  - **修复**：`bytes.decode('utf-8', errors='replace')`，无法解码处用 **替换字符（replacement character）** 代替。这是 OpenAI 官方代码也采用的做法。
  - 含义：若 LLM 预测出的 token 拼不出合法 UTF-8，就会出现该替换字符——说明输出"坏掉了"。

## 15. 编码（Encoding）：文本 → token 序列
- 流程：文本 `encode('utf-8')` → 字节列表（即**初始 token**，原始字节）→ 按 `merges` 反复合并。
- `merges` 是**自顶向下**构建的，合并必须**按训练顺序**进行（后面的合并依赖前面产生的新 token，如某合并依赖 `256`）。
- 循环逻辑（伪代码）：
  1. `get_stats(tokens)` 统计相邻对频次，只取**键**作为候选对；
  2. 选出在 `merges` 中 **index 最小（即最早）** 的可合并对：`min(stats, key=lambda p: merges.get(p, float('inf')))`；
     - `float('inf')` 兜底：不在 merges 中的对不可合并，必被排除；
  3. 若该对不在 `merges`（全为 inf）→ 无可合并项，**break**；
  4. 否则 `merge(tokens, pair, idx)` 替换并继续。
- **边界 bug 修复**：单个字符或空串时 `stats` 为空，`min` 会失败 → 加 `if len(tokens) < 2: return tokens`。

## 16. 回合一致性与 BPE 小结
- **编码→解码** 对训练文本与未见过（验证）文本均能得到原串（round-trip 一致）。
- **解码→编码 不是恒等映射**：并非所有 token 序列都对应合法 UTF-8，故无法保证反向还原。
- BPE 最简设定回顾：tokenizer 的**全部参数就是 `merges` 字典**，它在原始字节之上建起**二叉森林**；凭此即可在文本与 token 间双向转换。

## 17. 真实分词器的复杂化：以 GPT-2（2019）为例
- GPT-2 论文 *Input Representation*：在 **UTF-8 字节级**上做 BPE（与我们前述一致）。
- **对朴素 BPE 的改进（动机）**：像 `dog` 这样的高频词常紧贴标点（`dog.` `dog!` `dog?`）。朴素 BPE 会把"词+标点"也合并成大量 token，等于把**语义与标点耦合**在一起，实验证明**次优**。
- **解决方案**：在 BPE 之上**人为强制合并规则**——某些字符类型**永不被合并**。实现手段是一个复杂的 **正则表达式（regex）预拆分模式**。
- GPT-2 代码（OpenAI GitHub `encoder.py`）要点：
  - `import regex as re`：用的是第三方 **`regex` 包**（非标准库 `re`），功能更强。
  - 用 `re.compile(pattern)` 编译一个由大量 `|`（OR 分支）组成的**原始字符串（raw string）** 模式。
  - `re.findall(pattern, text)` 先把文本**切分成若干片段**，每个片段**独立地**走 BPE，最后结果直接拼接。
  - 模式示意：匹配 "`可选空格` + 一个或多个 `\p{L}`（任意语言的字母）"。例："hello world how are you" 被切成 `['hello', ' world', ' how', ' are', ' you']` 等片段——空格常被保留为片段前缀，从而保证"字母串"内部才参与合并，标点/空格等不被随意并入词 token。
- 这就是 GPT-2 的 **预分词（pre-tokenization）** 正则：先按规则把文本分段，再对每段分别 BPE。
# 第四部分：GPT-2 预分词正则细则、Tiktoken 与特殊 Token

## 18. GPT-2 预分词正则的细则（为何这样切分）
- 预切分后，BPE **只在每个片段内部**合并，**绝不跨片段**合并。这正是"强制某些合并不发生"的机制（例如 e 与空格被分隔在不同片段，永不合并）。
- 各分支含义：
  - `\p{L}`：任意语言**字母** → 把"字母串"聚为一段；
  - `\p{N}`：任意语言**数字** → 字母与数字被分开（"Hello World 123" 中 world 在数字处断片）；
  - **撇号分支**（硬编码 ASCII `'` 的 `'s 't 're 've 'm 'd` 等）：但 **Unicode 撇号（'）未被处理**，会变成独立 token；且 GPT-2 **未用 `re.IGNORECASE`**，导致大写 `'S`（如 `HOUSE'S`）的切分与小写不一致——典型的"毛刺"。
  - 兜底分支：`可选空格 + 一个或多个非字母/非数字/非空格字符` → 把**标点**单独切出；
  - **空白负向先行断言**：匹配空格但**不含最后一个空格**，使最后那个空格能拼到下一词（如 ` you` 是常见 token）。GPT-2 偏好 `空格 + 字母/数字` 的形式；末尾残余空格由最后的兜底分支捕获。
- 实战示例：一段 Python 代码被切成很多片段，片段内永不合并；这也解释了为何 GPT-2 对 Python 缩进空格极不友好。

## 19. OpenAI 的隐藏规则与 GPT-2 训练代码未公开
- 在 Tiktoken 中，连续空格**始终各自独立**（都是 token `220`）——说明 OpenAI 实际上**强制空格永不被合并**，在"切分 + BPE"之外还有未公开的额外规则。
- **GPT-2 的训练代码从未发布**，只发布了**推理代码**（用已有的 merges 套用到新文本）。因此"他们到底怎么训练的"并不完全清楚，并非简单的"切分后跑 BPE"。

## 20. Tiktoken 官方库与 GPT-4 的模式变更
- **Tiktoken**（`pip install tiktoken`）是 OpenAI 官方分词库，仅做**推理**（非训练）。
  - GPT-2：空格不合并；**GPT-4（CL100K）**：空格合并（更省 token）。
- GPT-4 的预切分正则（`tiktoken/extensions/openai_public.py` 中 CL100K 定义）相对 GPT-2 的主要改动：
  - 加 **`i`（忽略大小写）** 标志 → 修复了 GPT-2 撇号大小写不一致问题；
  - 重做了空白字符处理；
  - **数字只匹配 1–3 位**：超过 3 位的数字永不被合并，避免产生超长数字 token；
  - 词表从约 **50K** 增至约 **100K**。
- 注：这些改动大多**无公开文档**，只能从发布的模式字符串反推。

## 21. GPT-2 `encoder.py` 文件剖析
- 加载两个文件即完整表示一个 tokenizer：
  - `encoder.json` = 我们的 `vocab`（ID → bytes）；
  - `vocab.bpe` = 我们的 `merges`（合并表）。
  - 结论：**一个 tokenizer = `vocab` + `merges` 两个变量**即可完成编解码。
- 另有 `byte_encoder` / `byte_decoder`（字节编/解码层），是与 tokenizer 串行叠加的实现细节，不深究。
- 核心 `bpe` 函数与我们的 while 循环一致：反复找下一对待合并对并替换，直到无可合并项；外加 `encode` / `decode` 函数。算法上与我们从零实现**完全相同**。

## 22. 特殊 Token（Special Tokens）
- 除原始字节与 BPE 合并出的 token 外，可插入**特殊 token** 用于**分隔数据 / 构造 token 流结构**。
- **GPT-2 词表 = 50,257**：256（原始字节）+ 50,000（合并）= 50,256，第 50,257 个是特殊 token **`end of text`（EOT）**。
  - 作用：在训练集中**分隔文档**——各文档 token 流（0–50256）之间插入 EOT，作为"前文与后文无关"的信号。LM 需从数据中学会：遇到 EOT 应"遗忘"此前上下文。
  - 在 Tiktokenizer 中输入 "end of text"，识别后直接变 token `50256`——这是**特殊分支处理**，不走 BPE 合并（`encoder.py` 里没有，Rust 实现的 Tiktoken 才有）。
- 特殊 token 在**对话 / 微调**中无处不在：如 GPT-3.5-turbo 的 `<|im_start|>`、`<|im_end|>` 等，用于分隔用户/助手的多轮消息。
- Tiktoken 可**扩展** CL100K：自行注册任意特殊 token（带新 ID），库会自动替换。
- **GPT-4 的特殊 token**：`end of text` + 4 个：`FIM_PREFIX` / `FIM_MIDDLE` / `FIM_SUFFIX`（**FIM = Fill In the Middle，来自相关论文**）+ 另 1 个。
- **重要代价**：新增特殊 token 属于**模型手术（model surgery）**——必须扩展 Transformer 的 **Embedding 矩阵**与输出 **softmax**（为新增 ID 增加对应行/列），因为词表整数域变大了。
# 第五部分：从零实现 GPT-4 分词器、SentencePiece 与词表大小权衡

## 23. 自己实现 GPT-4 Tokenizer（minbpe）与训练函数
- 新增特殊 token 的代价（续）：需为 Transformer 的 **Embedding 矩阵**新增一行，并把末端的 **LM Head（分类投影层）** 也扩展一列——即"模型手术"。这是 base→chat 微调时常见操作。
- Karpathy 在讲课时从零实现并发布了 **minbpe** 仓库（含 `exercise.md` 四步练习，逐步逼近 GPT-4 tokenizer）。
  - **Tiktoken 只提供推理**；minbpe 额外提供了 `train` 函数，可训练自己的词表。
- 可视化对比：GPT-4 的第一次合并是"两个空格 → token 256"。在 Taylor Swift 维基页上训练的 minbpe 词表与 GPT-4 词表"看起来相同"——差异**仅来自训练集**（GPT-4 含大量 Python，故空格合并更多）。说明同一算法、不同语料 → 不同词表。

## 24. SentencePiece：与 Tiktoken 的核心差异
- **SentencePiece**（Google，被 **Llama、Mistral** 等采用）能同时做**训练与推理**，效率高；支持 BPE 等多种算法。
- **根本区别——操作层级不同**：
  - Tiktoken：先把码点 `encode('utf-8')` → **字节**，再在**字节**层面做 BPE 合并。
  - SentencePiece：直接在 **码点（code point）** 层面做 BPE 合并。
  - 稀有码点（由 `character_coverage` 超参决定"稀有"阈值）的处理：
    - 映射到特殊 **`<unk>`** token；或
    - 开启 **`byte_fallback=true`** 时，用 UTF-8 把该码点编码成字节，再把各字节映射为加入词表的**字节 token**。
  - Karpathy 认为 Tiktoken 更干净；这是"微妙但重大"的差别。

## 25. SentencePiece 训练配置与词表结构
- 配置项繁多（历史包袱）。可照搬 Meta 发布的 Llama 2 tokenizer 的 protobuf 选项来复现其行为。
- 关键配置点：
  - **Normalization（归一化）**：传统 NLP 会小写化、去重空格等；但 LLM 倾向**不改动原始数据**，故尽量关闭归一化。
  - **"sentences（句子）"概念**：SentencePiece 按独立"句子"训练（含最大句长、shuffle 等）——Karpathy 认为在 LLM 场景很别扭，更愿把文件当作**巨型字节流**。
  - 内置对数字/空白的切分规则（等价于 Tiktoken 用正则按类别切分）。
  - 硬编码 **`<unk>`**、**`<bos>`**（句首）、**`<eos>`**（句尾）、**`<pad>`**；其中 **`<unk>` 必须存在**。
- 训练产物 `*.model` / `*.vocab`，其词表**排列顺序**为：
  1. **特殊 token**（unk=0, bos=1, eos=2）；
  2. **字节 token**（256 个，因 Llama 开启 `byte_fallback`）；
  3. **合并 token**（父节点，仅显示父节点及其 ID）；
  4. **独立码点 token**（末尾，训练集中出现过的所有码点）。
  - 极稀有码点（按 `character_coverage`，如在百万句中仅出现一次）会被忽略、不进词表。

## 26. SentencePiece 的字节回退与 dummy prefix
- 编码"hello 안녕"：韩语不在训练集 → 码点未收录 → 因 `byte_fallback=true`，回退到 UTF-8 字节（整体 ID 因前 3 个特殊 token 而偏移 +3）。
- 若 `byte_fallback=false`：所有未登录内容 → 全部坍缩成 **`<unk>`（token 0）** 喂给 LM，丢失信息——这是不良属性，故 Llama 正确地设为 `true`。
- **`add_dummy_prefix=true`**：预处理时在文本**开头加一个空格**，使句首词 "world" 与句中 " world" 变成同一个 ` world` token。这**缓解了** Tiktoken 中"句首词与句中词 ID 不同、模型需自行学其相似"的问题。**Llama 2 也开启此选项**。

## 27. 词表大小的权衡（架构视角 · 上）
- 回到 "build GPT from scratch" 的 Transformer：`vocab_size` 只出现在**两处**：
  1. **Token Embedding 表**：二维数组，行数 = `vocab_size`，每行是可训练的 `n_embd` 维向量；
  2. **LM Head（线性层）**：在 Transformer 末端产出 **logits**（即下一 token 的概率分布）。
- 直觉：`vocab_size` 越大，LM Head 需为每个可能的下一 token 多算一次点积。
- 为何词表不能无限大？① **Embedding 表**随词表线性增大；② 末端的 **LM Head 线性层**也随之增大（参数与计算都涨）。
# 六、词汇表大小权衡、扩展词汇表与多模态 Tokenization

## 1. 词汇表大小（vocab size）的设计权衡

词汇表大小是一个**经验性超参数**，主流现代架构通常在 **数万（high 10,000）到约 100,000** 之间。增大 vocab size 同时带来利弊：

- **优点（倾向更大的 vocab）**
  - **LM Head 层计算量增大**：输出投影层（unembedding）参数量随 vocab 增加而增加。
  - **序列变短**：文本被压缩成更少的 token，Transformer 注意力可覆盖更多"文本量"，推理更高效。

- **缺点（倾向更小的 vocab）**
  - **训练不充分（under-training）风险**：若 vocab 过大（如 100 万 token），每个 token 在训练数据中出现的频率急剧下降，对应 embedding 向量参与前向/反向传播的机会少，容易训练不足。
  - **信息被过度压缩**：过长文本被压进单个 token，模型单次前向传播来不及充分处理该 token 携带的信息。

> 补充：vocab size 本质是"序列长度 vs 单 token 信息密度"的折中，需结合数据量、模型容量经验确定。

## 2. 扩展预训练模型的词汇表（扩展 vocab）

常见场景：为 ChatGPT 微调引入大量**特殊 token**（special tokens）以维护用户/助手对话对象的元数据与结构；或为浏览器、工具调用等新功能加入专用 token。

扩展操作本质是**轻微的模型手术（model surgery）**：

- **步骤**
  1. **扩展 embedding 矩阵**：为 token embedding 新增行，用小的随机值初始化这些新参数。
  2. **扩展 LM Head 权重**：在输出线性层中同步增加对应参数，以计算新 token 的概率（点积）。
- **训练策略**：通常**冻结基座模型**，只训练新增的 token 参数（参数高效微调的一种）。

> 补充：这是 LoRA、adapter 之外另一类轻量改造手段——只动 token embedding，不动主体权重。

## 3. 扩展词汇表的设计空间：Gist Tokens（提示压缩）

**Gist tokens**（论文 "Learning to Compress Prompts with Gist Tokens"）是一类参数高效微调技术：

- **动机**：长 prompt 编码、注意力开销大、推理慢。
- **方法**：引入少量新 token，插入序列；**冻结整个模型**，仅通过**蒸馏（distillation）**训练这些新 token 的 embedding，使模型行为与原"超长 prompt"近似一致。
- **效果**：将超长 prompt **压缩**进少数 gist token，推理时丢弃原 prompt、仅用这几个 token 占位，性能几乎不变。
- **本质**：训练对象不是模型权重（非 LoRA），仅是 token embedding。

## 4. 多模态 Tokenization：万物皆可 token

- **核心观点**：处理图像、视频、音频等多模态时，**架构无需改变**，仍用 Transformer——只需把输入域"tokenize"成 token，再像文本 token 一样处理。
- **图像 token**：早期论文将图像切块（patch）转为整数，成为图像 token；可分为**硬 token（离散整数）**或**软 token（经自编码器等瓶颈的连续表示）**。
- **视频 token（Sora）**：OpenAI Sora 用**视觉 patch（visual patches）**作为 token，把视频切块成自有词汇表的 token；可用**自回归模型**处理离散 token，或用**扩散模型**处理软 token。

> 补充：这印证了"token 是 Transformer 的统一原子"这一视角，多模态只是换一种 encoder 产出 token。

---

# 七、回到开篇：tokenization 导致的 LLM "怪现象"解析

视频开头列举的多个现象，根因都在 tokenization。

## 1. 为什么 LLM 不擅长拼写 / 字符级任务

- **根因**：字符被合并成长 token，"单 token 内信息过密"，模型看不到内部字符。
- **实例**：GPT-4 词汇表中 `default style` 是一个**单独 token**（含 12 个字符）。提问"其中有多少个字母 l"——模型答"3 个"，实为 **4 个**。
- **字符反转任务**：要求反转 `default style`，模型直接给出乱码；但当先"逐字符空格分隔列出、再反转"时却能正确完成——因为分步后字符变为独立 token，模型才"看得见"。

## 2. 为什么 LLM 在非英语上更弱

- **双重原因**：① 训练数据中非英语语料更少；② **tokenizer 本身在非英语数据上训练不足**。
- **实例**：`hello how are you` 是 **5 个 token**，其翻译（如韩语"안녕하세요"）是 **15 个 token**（约 3 倍膨胀）；常见韩语问候竟需 3 个 token，而英语 `hello` 仅 1 个。
- **结果**：非英语文本 token 更"臃肿弥散"，压缩率低，推理成本高、效果差。

## 3. 为什么 LLM 做简单算术差

- **根因**：数字的 tokenization 是**任意的**——数字被如何合并取决于 BPE 训练时的偶然合并，而非按"数位"切分。
- **参考**：博客 "Integer tokenization is insane" 系统分析发现，4 位数可能是一个 token（4 位）、两个 token（1+3、2+2、3+1 等组合）……完全无规律。
- **对策**：Meta 训练 **LLaMA 2** 时（用 SentencePiece）**强制把每个数字拆成单独数位**，以改进基础算术能力。

## 4. 为什么 GPT-2 的 Python 能力较弱

- **部分原因在 tokenization**：GPT-2 对 Python 中**空格的编码效率极差**——每个空格都是一个独立 token，大幅缩短模型可注意的上下文长度。
- **状态**：这近乎 GPT-2 的一个 **tokenization bug**，在 GPT-4 中被修复。

## 5. 为什么 LLM 见到 `end of text` 会突然中断

- **现象**：让 GPT-4 打印字符串 `end of text`，模型解析异常、不输出内容。
- **推测原因**：在调用 encode 时若把 `end of text` 作为**特殊 token 放行**（`allowed_special`），用户输入（攻击者可控）中的该字符串会被当作真正的特殊 token 处理，触发停止序列。
- **启示**：特殊 token 是一个**攻击面（attack surface）**，应谨慎对待用户输入中特殊 token 的解析。

## 6. 尾部空格（trailing whitespace）问题

- **现象**：在 Completion 模型（如 GPT-3.5 Turbo Instruct）提示末尾加一个空格，会收到警告"文本以尾随空格结尾，会因 API 切分方式导致性能下降"。
- **根因（关键）**：GPT 中**空格是 token 的前缀**而非独立字符。例如不是 `O` 而是 ` O`（空格 O 合为一 token，编号 8840）。
  - 正常续写时，模型可采样 ` O` 这个 token；
  - 若手动在末尾加空格，该空格被单独编码为 token 220，本应属于下一 token 前缀的空格被提前消耗，使模型**脱离训练数据分布**，续写出错甚至直接预测停止序列。
- **本质**：token 是 LM 感知的"原子"，而非人类视角的字符；任何"半截 token"都会把模型推离分布。

## 7. 部分 token 与 unstable tokens（非文档化的坑）

- **现象延伸**：补全下一个 token 时若只给了"下一 token 的首字符"，或长 token 被截去部分字符，都属于 **部分 token（partial tokens）** 问题，会把模型推离分布、产生混乱输出。
- **tiktoken 源码佐证**：在 tiktoken 的 Rust 代码里搜索 `unstable`，可见大量 **unstable tokens** 的特殊处理代码——专门处理这类边界情况，但**官方文档从未说明**。
- **理想 API**：Completion API 应更智能——当输入 `default cel sta` 请求续写时，应搜索"以这些字符为前缀的候选 token 集合"，而非机械拼接下一 token。
# 八、Solid Gold Magikarp：未训练 token 的"未分配内存"陷阱

## 1. 现象来源（博客 "Solid Gold Magikarp"）

对 token embedding 表做**聚类（clustering）**时，发现一个异常 token 簇，包含如 `solid gold magikarp`、`streamer bot`、`rothestream fame`、`signet message` 等奇特的专有字符串。

- **触发行为**：只要提问或提示中包含这些"触发词（trigger words）"，模型就会**行为失常**——回避（"我听不见"）、产生幻觉、甚至**辱骂用户**、突破安全对齐（swearing）。极其简单的字符串就能"击碎"模型。

## 2. 根因：tokenization 数据集 ≠ 语言模型训练数据集

- **成因推演**：
  1. **tokenization 数据集**含大量 Reddit 数据，`solid gold magikarp` 是高频出现的用户名，因此 BPE 把它合并成 GPT-2 5 万词表中的一个**专属 token**。
  2. 但**后续训练语言模型时**，该 Reddit 数据**未纳入**训练集，于是这个 token 在 LM 训练集中**从未出现**。
  3. 该 token 的 embedding 行向量初始化为随机值后，**从未被前向/反向传播采样更新**——等同于 C 程序中**未分配内存（unallocated memory）**。
  4. 推理时一旦激活该 token，就抽取了一个**完全未训练的 embedding 行**送入 Transformer，产生**未定义行为（undefined behavior）**——即观察到的失常。

> 补充：这是 tokenization 与模型训练数据**不一致**导致的典型坑；也是把 tokenization 当作独立阶段（见第四部分）的代价之一。

---

# 九、Token 经济性：不同格式的编码密度

- 在"按 token 计费"时代，**token 密度**直接影响上下文长度与成本，需时刻关注。
- **实例对比**（相同内容）：
  - **JSON**：116 个 token
  - **YAML**：99 个 token（更省）
- **建议**：在结构化数据场景下**优先用 YAML 而非 JSON**；多用 tiktoken 等工具实测不同格式/设置的 token 效率。

---

# 十、总结与建议

## 1. 不要轻视 tokenization 阶段

- 该阶段充满 **footguns（暗坑）、安全隐患、AI 安全（对齐）问题**（如注入未分配内存）。
- 作者本人也不喜欢这一独立阶段，但强调"别草率对待"。

## 2. 实用选型建议

- **推理复用 GPT-4 词汇表**：若应用可行，直接复用 GPT-4 的 token 与词汇表，用 **tiktoken**（高效、推理友好的 BPE 库）。
- **偏好字节级 BPE**：tiktoken / OpenAI 采用的 **byte-level BPE** 作者很认可。
- **从零训练自己的词汇表**：用 **SentencePiece 的 BPE**——但作者**不推荐**：
  - 不喜欢其 `byte_fallback` 机制；
  - 不喜欢它在 **Unicode 码点（code point）** 层级做 BPE；
  - 超参数极多、易配错（可能误裁句子）。
  - 建议：若用 SentencePiece，**精确照搬 Meta 等的配置**，并通读其代码核对超参。
- **理想状态**：想要"tiktoken 般的效率 + 可训练"，当前尚不存在；minbpe 是其 Python 实现雏形，期待未来出现高效的训练版。

## 3. 尾声

- 视频开头 loop back 的若干"怪现象"（拼写差、非英语弱、算术弱、Python 弱、特殊 token 中断、尾随空格、部分 token、Solid Gold Magikarp）**根因统一指向 tokenization**。
- 作者寄望未来有人能"干掉"这一独立阶段（已出现相关论文尝试）。

---

# 十一、Tokenizer 原理进阶补充（算法对比、编解码与特殊 Token、词表构建、Subword 优势）

> 本节在视频内容基础上，系统补充主流分词算法的横向对比、编解码与特殊 token 的全谱系、词表构建过程，以及 subword 相对传统分词的优越性，帮助建立完整知识体系。

## 1. 主流分词算法：流程与对比

Transformer 时代的子词分词主要有三类算法；SentencePiece 则是封装前两类（BPE / Unigram）的统一训练与推理框架。

### 1.1 Byte Pair Encoding（BPE）
- **流程**：① 词表初始化为所有基础单元（字符或字节；GPT 系为 256 字节）；② 统计语料中**相邻符号对**频次；③ 合并**最频繁**的一对，铸造新 token；④ 重复 ②③ 直至达到目标词表大小。
- **本质**：自底向上（bottom-up）的**贪心合并**，纯数据驱动，无语言学先验（视频第二、三部分已逐行实现）。
- **代表**：GPT-2 / GPT-3 / GPT-4、RoBERTa、BLOOM。

### 1.2 WordPiece（BERT 系）
- **流程**：同样自底向上合并，但**选择准则不同**——不取"出现频次最高"的相邻对，而取使训练数据**整体似然（likelihood）增益最大**的 pair，近似按 `score = count(pair) / (count(left) · count(right))`（互信息式）挑选。
- **词片段标记**：非词首子词加 `##` 前缀（如 `playing` → `play` + `##ing`），解码时去掉 `##` 并拼回。
- **代表**：BERT、Electra、Albert、DistilBERT。

### 1.3 Unigram（SentencePiece 支持，T5 采用）
- **流程**：与 BPE **方向相反**——先以**较大**词表起步（含单字符到常见词），再**迭代删除**使训练语料总损失（基于每个 token 的 unigram 语言模型概率）增加**最小**的 token，逐步剪枝到目标大小。
- **特点**：每个 token 带有概率，可输出**多候选分词**（采样友好）；对稀有 token 的处理更平滑。
- **代表**：T5、mBART 及部分多语模型（经 SentencePiece + Unigram）。

### 1.4 三者对比一览

| 算法 | 构建方向 | 选择 / 剪枝准则 | 词片段标记 | 操作层级 | 代表模型 |
|------|---------|---------------|-----------|---------|---------|
| **BPE** | 自底向上合并 | 相邻对频次最高 | 空格前缀（byte-level） | 字节 | GPT-2/3/4、RoBERTa |
| **WordPiece** | 自底向上合并 | 似然增益最高 | `##` 前缀 | 字符 | BERT、Electra |
| **Unigram** | 自顶向下剪枝 | 损失增加最小 | `▁` 前缀（SentencePiece） | 字符 / 码点 | T5、mBART |

> **SentencePiece 的定位**：它并非第三种算法，而是 Google 推出的**统一框架**，可封装 BPE 或 Unigram，并把空格规范表示为 `▁`（U+2581），从而**原生适配无空格语言**（中文、日文、泰文），且能直接吃原始文本、不依赖语言相关的预分词正则。其与 tiktoken（byte-level BPE）在"操作层级（码点 vs 字节）"上的差异见本文第五部分。

## 2. 编码 / 解码流程与特殊 Token 详解

### 2.1 编码流程（文本 → token id 序列）
1. **归一化（Normalization）**：可选 NFKC、小写化、空白折叠；现代大模型倾向**关闭**以保留原文（见第五部分第 25 点）。
2. **预分词（Pre-tokenization）**：按正则 / 空白边界切分为片段（如 GPT-2 正则，见第三、四部分）。
3. **子词切分（Subword segmentation）**：在片段内部按算法（BPE 合并或 Unigram 查表）得到子词 token 字符串。
4. **映射为 id**：查 `vocab` 得到整数 id。
5. **特殊 token 分流**：特定字符串（如 `[CLS]`、`<|im_start|>`）走特殊分支直接映射，**不参与** BPE 合并。

### 2.2 解码流程（token id 序列 → 文本）
- 反向：id → token 字符串 → 拼接 → 还原；需处理各框架的合并规则（`##` 去前缀、`▁` 还原为空格、byte-level 的 bytes 拼接）。
- 陷阱同第三部分所述：非法 UTF-8 起始字节需 `errors='replace'`，否则报错。

### 2.3 特殊 Token 的全谱系（补齐 BERT 系）
原文已讲 GPT 系的 `end of text`、`<|im_start|>`、`FIM_*` 等，补充 **BERT 系及通用特殊 token**：

- **`[CLS]`**：句首**分类标志**。BERT 将其最终隐藏状态作为整句表征，用于句子级分类（情感、蕴含等）。
- **`[SEP]`**：**分隔符**。分隔句对（句子 A 与 B），也用于问答 / 段落边界；BERT 段嵌入（segment embedding）据此区分上下句。
- **`[PAD]`**：**填充符**。使一个 batch 内序列等长；通过 `attention_mask` 屏蔽，不计入 loss 与注意力。解码时应被忽略、不还原为可见字符。
- **`[MASK]`**：BERT **掩码语言模型（MLM）** 预训练用的占位符，推理一般不出现。
- **`[UNK]`**：**未登录词兜底**（SentencePiece 强制要求存在）；输入无法由词表表示时坍缩于此。
- **GPT 系对照**：以 `<|endoftext|>`、对话模板 `<|im_start|>` / `<|im_end|>`、FIM 系列为代表（见第四、五部分）。

> **工程提醒**：特殊 token 既是结构工具也是**攻击面**（见第七部分第 5 点）。解码时务必 `skip_special_tokens=True`，避免把 `[CLS]`/`[PAD]` 输出给用户；编码时谨慎设置 `allowed_special`，防止用户输入被当作特殊 token 触发停止序列。

## 3. 词表（Vocabulary）的构建过程

- **构建步骤**：① 选定算法（BPE / WordPiece / Unigram）；② 准备训练语料（文本或 UTF-8 字节流，分布需匹配下游任务）；③ 跑算法得到 `vocab`（符号 → id）与配套表（`merges` 或 token 概率）；④ 固化保存（GPT 系为 `vocab + merges` 两文件，SentencePiece 为 `*.model` / `*.vocab`，HF 为 `tokenizer.json`）。
- **词表即"原子字典"**：Transformer 的 Embedding 表与 LM Head 都按 `vocab_size` 维度定义（见第五部分第 27 点）——词表一旦确定，模型结构即被锁定，新增 token 需"模型手术"（见第六部分第 2 点）。

## 4. 词表大小对模型性能的影响（系统小结）

综合本文第六、十一部分，词表大小是**序列长度 vs 单 token 信息密度**的折中：

- **过小**（如纯字符级）：序列极长 → 注意力计算昂贵、上下文受限；且丢失词内语义。
- **过大**：① 单 token 在训练集中出现频率骤降 → embedding **训练不足（under-training）**；② Embedding 表 + LM Head 参数量线性膨胀；③ 信息被过度压缩进单 token，单次前向难充分处理。
- **经验甜点（需与训练数据量匹配）**：BERT-base 约 30K、GPT-2 约 50K、Llama 约 32K（后扩至 128K）、GPT-4 约 100K。数据量越大越能支撑更大词表。

## 5. Subword 分词相较传统分词的优越性

- **词级（按空格切分，word-level）**：词表随语料无限膨胀，**未登录词（OOV）** 无 embedding，罕见词无法表示。
- **字符级（char-level）**：词表小、无 OOV，但序列极长、注意力昂贵，且**丢失词内语义**（"cat" / "cats" 毫无关联）。
- **Subword（BPE / WordPiece / Unigram）取折中**：
  - 罕见 / 未登录词可**拆成已知子词**（如 `unbelievable` → `un` + `believ` + `able`），**彻底消除 OOV**；
  - 常见词与词根保持**紧凑表示**，序列长度可控；
  - 跨语言 / 形态丰富语言间**共享子词**，利于迁移与多语；
  - 对拼写变化、派生、拼错更鲁棒。

---

# 十二、工程实践补充：训练、推理优化、多语言与 HuggingFace

> 本节结合真实应用场景，补充如何训练自定义 tokenizer、推理期性能优化、多语言处理与 HuggingFace Tokenizers 最佳实践。

## 1. 训练自定义 Tokenizer：流程与配置要点

### 1.1 通用流程
1. **收集语料**：语料分布应与下游任务一致（代码、医学、多语等）；分布决定词表质量（见第五部分第 13、23 点）。
2. **选择工具**：`tokenizers`（HuggingFace，Rust 后端，快）/ `sentencepiece` / `minbpe`（教学）。
3. **配置算法与超参**：算法类型、目标词表大小、特殊 token、预分词正则、归一化策略。
4. **训练**：在语料上跑算法，产出词表与合并 / 概率表。
5. **保存与版本化**：与模型权重一起保存（如 `tokenizer.json` + `special_tokens_map.json`）。

### 1.2 常用参数（以 HuggingFace / SentencePiece 为例）
- **`vocab_size`**：目标词表大小（需结合数据量与性能预算权衡，见第十一部分第 4 点）。
- **`min_frequency`**：合并 / 保留的最小频次阈值，过滤噪声 token。
- **`special_tokens`**：必须在训练**前**注册，避免被算法切分。
- **`byte_fallback`**（HF BPE / SentencePiece）：无法表示时回退到字节 token，避免 `<unk>` 丢信息（Llama 即开启，见第五部分第 26 点）。
- **`character_coverage`**（SentencePiece，默认 0.9999）：纳入词表的字符覆盖比例，其余走 unk / byte_fallback。
- **`model_prefix` / `add_dummy_prefix`**（SentencePiece）：见第五部分第 24–26 点。

> **要点**：语言模型训练集与 tokenizer 训练集**应当一致**（见第五部分第 13 点），否则会出现 Solid Gold Magikarp 类的"未分配内存"token（见第八部分）。引入新领域（如代码、医学）后，应**重训或扩展**词表，而非沿用通用词表。

## 2. 推理期性能优化策略

### 2.1 批处理（Batching）
- 一次编码多条文本，利用向量化与 GPU 并行：`tokenizer(texts, padding=True, truncation=True, return_tensors="pt")`。
- 对话场景按**轮次聚合**编码，避免逐句重复处理系统提示。

### 2.2 缓存机制
- **静态提示缓存**：system prompt、few-shot 示例等固定文本，其编码结果按内容哈希缓存，避免每次请求重复 encode（呼应第九部分 token 经济性，省算力也省 token）。
- **Rust 后端加速**：HuggingFace `tokenizers` 库为 Rust 实现，默认多线程、正则预编译，比纯 Python "slow" tokenizer 快 **10 倍以上**。

### 2.3 截断与填充策略
- **截断（truncation）**：`truncation=True` + `max_length`；超长文本按策略截断（对话常保留**系统提示 + 最近历史**，丢弃中间）。
- **填充（padding）**：`max_length`（补到固定长）/ `longest`（补到 batch 内最长）/ `True`。
- **`attention_mask`**：标记真实 token 位置，PAD 不进入注意力与 loss。
- **滑动窗口（stride）**：长文档分块时设 `stride` 保留重叠区，维持语义连贯。

> **注意**：`TOKENIZERS_PARALLELISM=false` 可消除多进程训练时的 fork 警告；同时要区分 Fast（Rust）与 Slow（Python）tokenizer，新模型优先用 Fast。

## 3. 多语言场景的处理与注意事项

- **无空格语言**（中 / 日 / 泰等）：用 SentencePiece（`▁` 表示空格）或 byte-level BPE，避免依赖空白边界切分；纯按空格切分会把整段中文当一个"词"。
- **字符覆盖**：`character_coverage` 控制多少比例的字符进入词表，长尾字符走 `unk` / `byte_fallback`。
- **跨语言共享子词**：多语模型（mBERT、XLM）用**单一词表**，子词跨语言共享，利于零样本迁移；但各语言 token 密度差异大（见第七部分第 2 点），需评估成本与上下文。
- **语料比例**：训练语料中各语言占比直接决定该语言的压缩率（某语言占比越高 → 合并越多 → 表示该语言越稠密）。
- **脚本均衡**：形态丰富语言（芬兰语、土耳其语等黏着语）子词更多、序列更长，需适当增大词表或调高 `character_coverage`。

## 4. HuggingFace Tokenizers 使用要点与最佳实践

### 4.1 架构与加载
- `tokenizers` 库（Rust 内核 + Python 绑定）提供 `Tokenizer` 类；`transformers` 的 `AutoTokenizer` 在此之上封装模型专属逻辑。
- 加载预训练：`AutoTokenizer.from_pretrained("bert-base-uncased")`。
- 加载自定义：`Tokenizer.from_file("tokenizer.json")`。

### 4.2 核心 API
```python
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained("bert-base-uncased")
ids = tok.encode("Hello world")
text = tok.decode(ids, skip_special_tokens=True)   # 解码忽略 [CLS]/[SEP]/[PAD]
# 批处理 + 截断 + 填充
batch = tok(["s1", "s2"], padding=True, truncation=True,
            max_length=512, return_tensors="pt",
            return_offsets_mapping=True)           # 用于 NER / 问答定位原文 span
```

### 4.3 最佳实践清单
- **始终保存并版本化** `tokenizer.json` + 特殊 token 配置，与模型权重一同管理，避免"词表漂移"。
- **解码用 `skip_special_tokens=True`**，防止把 `[CLS]` / `[PAD]` 输出给用户。
- **Fast vs Slow**：新模型优先用 Fast（Rust）以支持偏移映射、批处理加速；不支持的模型才回退 Slow。
- **多进程训练设 `TOKENIZERS_PARALLELISM=false`**，消除 fork 警告。
- **长 system prompt 缓存**编码结果，降低重复开销（见 2.2）。
- **自定义训练用 Trainer**：`BpeTrainer` / `WordPieceTrainer` / `UnigramTrainer`，配合 `special_tokens` 与 `vocab_size` 配置（见 1.2）。
- **对齐训练 / 推理分词**：确保微调与推理使用**同一** tokenizer 文件，否则 id 错位（呼应第五部分第 13 点的一致性原则）。
