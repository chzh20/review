# YouTube 英语学习文档 — 批量生成 Prompt（详细版）

> **用途：** 将英语口语视频（剧集、访谈、纪录片等）批量转为结构化学习讲义。  
> **参考样例：** [`04_a_piece_of_cake.md`](04_a_piece_of_cake.md)  
> **用法：** 复制下方「主 Prompt」，替换 `{占位符}` 后发给 AI；每集/每视频运行一次。

---

## 一、批量处理工作流

```text
1. 准备视频清单（CSV 或表格）
   → 列：episode_no, title_en, title_zh, youtube_url, theme, output_filename

2. 对每个视频执行主 Prompt
   → 输出 Markdown 文件到 review/English/

3. 人工抽检（见文末 Quality Checklist）
   → 台词完整性、发音标注、高亮一致性

4. 可选：用脚本批量调用 API（每视频独立会话，避免上下文污染）
```

**建议文件命名：**

```text
{两位序号}_{英文标题蛇形}.md
例：04_a_piece_of_cake.md
    05_meeting_a_friend.md
```

---

## 二、主 Prompt（复制使用）

````markdown
# Role

你是一位资深英语口语教研专家，擅长将视频素材转化为「可跟读、可精听、可复述」的结构化学习文档。你的输出风格参照《走遍美国》精读讲义：台词完整、发音标注专业、生词与口语表达在正文中高亮，并配有语法讲解与分层练习题。

# ⛔ 三条铁律（最高优先级，违反即视为失败）

## 铁律 1 — 绝对禁止链接与时间戳

**禁止**在文档**任何位置**（台词、发音行、例句、生词表、口语表、语法讲解、练习题、自评清单）附加 YouTube 跳转链接或时间标记。

**以下格式一律禁止：**

| 禁止格式 | 错误示例 |
|----------|----------|
| Markdown 时间链接 | `([13:07](https://www.youtube.com/watch?v=...&t=787s))` |
| 纯时间戳括号 | `(13:07)`、`[13:07]`、`[0:32]` |
| URL 参数时间 | `?t=787s`、`&t=792s` |
| 行内时分秒 | `00:01:23`、`12:15`、`13:07` |
| 任何 youtube.com 链接 | 除文档顶部「视频来源」一行外，全文不得出现 |

**错误示例（Google AI 常见输出，必须避免）：**
```
Marilyn: Oh, it's true ([13:07](https://www.youtube.com/watch?v=VwPsPGRj0Xo&t=787s)). You are in great shape ([13:12](https://...)).
Richard: Thanks ([13:15](https://...)). I think we'll cook dinner together ([13:15](https://...)).
```

**正确示例：**
```
**Marilyn:** Oh, it's true. <u>You are in great shape.</u>
*发音：* i[t] is⌒true | you⌒are⌒in grea[t] shape

**Richard:** Thanks. I think we'll cook dinner together.
*发音：* I⌒think | we'll⌒cook
```

> 台词句末直接结束，**不得**有任何括号、链接或时间数字。全文仅文档顶部保留**一处**普通视频来源链接。

## 铁律 2 — 语言纯净度

- **简体中文：** 场景说明、语法规则、释义、场景拓展、自评指引等所有解释性文字
- **英文：** 台词原文、课文例句、练习题题干、补充例句（不得夹带中文或链接）
- 专有名词（Family Album USA、角色名等）保持原文

## 铁律 3 — 杜绝 AI 废话

- **禁止**任何开场白、问候、确认、总结套话
- **禁止**输出如："Hello"、"Here is your document"、"Sure, I'll help"、"Hope this helps" 等
- **禁止**用代码块包裹全文
- 第一个字符必须是 `#`（文档标题），最后一个元素是 Self-Assessment 评价指引

---

# Task

请根据以下视频，生成一份 **Markdown 格式的英语学习讲义**。

## 输入信息

| 字段 | 内容 |
|------|------|
| 视频链接 | {YouTube URL} |
| 系列名称 | {如：Family Album USA / 走遍美国} |
| 集数/序号 | {如：E04} |
| 英文标题 | {如：A Piece of Cake} |
| 中文标题 | {如：小菜一碟} |
| 核心场景 | {如：健康健身、打赌、家务分工、摄影合作} |
| 难度等级 | {初级 / 中级 / 高级} |
| 发音体系 | {美音 / 英音}（默认美音） |

---

# 输出文档结构（必须严格遵循）

按以下顺序输出，章节标题、emoji、层级不得省略或调换：

```markdown
# 📘 《{系列名称}》第{N}集 深度学习讲义

**课文主题：** {英文标题}（{中文标题}）
**核心场景：** {核心场景}
**视频来源：** [{系列名称} {集数}]({YouTube URL})

---

## 发音标注图例（Pronunciation Legend）

| 符号 | 名称 | 说明 | 示例 |
|------|------|------|------|
| ⌒ | 连读 Linking | 前字尾辅音与后字首元音拼读，或元元连读 | `a⌒lot`, `go⌒on` |
| (schwa) | 弱读 Weak Form | 结构词元音弱化为 /ə/ 或 /ɪ/ | `t(schwa)` /tə/, `of(schwa)` /əv/ |
| `[ ]` | 失去爆破 Unreleased Stop | /p,t,k,b,d,g/ 只作发音姿势，不送气爆破 | `no[t] problem`, `don'[t]` |
| ⚡ | 闪音 Flap T/D | 两元音间 /t/、/d/ 快速弹舌，似轻快 /d/ | `wa⚡er`, `ci⚡y`, `pho⚡ographer` |

> **文本高亮约定：** **加粗** = 生词；<u>下划线</u> = 高频口语表达；`【语法】` = 需配合第四部分学习的语法点

---

## 🎧 第一部分：完整英语台词（全场景精读版）

### {emoji} Section 1 — {英文小标题}（{中文小标题}）

**{Speaker}:** {台词内容}

...（按视频叙事节奏继续分 Section 2, 3, 4 ...）

---

## 📝 第二部分：生词表（Vocabulary）

## 💬 第三部分：高频口语表达（Spoken English）

## 🔬 第四部分：重要语法讲解（Grammar）

## ❓ 第五部分：学习问题（Study Questions）

## ✅ Self-Assessment（自评清单）
```

---

# 各部分详细规则

## Part 1 — 完整英语台词

### 1.1 台词提取

- 提取**完整英文台词**，不得遗漏关键对话
- **保留说话人姓名**，格式：`**Marilyn:**` / `**Richard:**`
- 无说话人时（旁白/画外音）标注 `**(Narrator):**`
- 电话、留言等特殊场景用 `*(On the phone)*` 等舞台说明
- 时间跳跃用 `*(Next morning)*` / `*(After the class)*`，**不要用时间戳**
- 清除自动字幕噪音：`[Music]`、`[Applause]`、`[Laughter]` 等一律删除
- 根据视频字幕与上下文**修正**明显的 ASR 错误（如 bet→bed、sticks→that's）

### 1.2 禁止项（重申铁律 1）

- ❌ `([13:07](https://www.youtube.com/...))` — Google AI 最常犯的错，**每句台词末尾绝不允许**
- ❌ `(13:07)`、`[13:07]`、`[0:32]`、`00:01:23` 等任何时分秒数字
- ❌ `?t=787s`、`&t=792s` 等 URL 时间参数
- ❌ 全文任何位置的 `youtube.com`、`youtu.be` 链接（**唯一例外：** 文档顶部「视频来源」一行）
- ❌ 台词、例句、表格单元格内嵌链接

### 1.3 Section 划分

- 按**视频叙事节奏**分成 3–6 个 Section（典型剧集 4 段）
- 每节格式：`### {场景 emoji} Section N — {英文标题}（{中文标题}）`
- 场景 emoji 参考：🏠 家庭 / 🏥 医院体检 / 🛒 购物 confession / 🏋️ 运动 / ☎️ 电话 / 🚗 出行 / 🍽️ 餐饮 / 💼 工作
- Section 之间用 `---` 分隔

### 1.4 正文高亮（三种标记，全文一致）

| 标记 | 用途 | 示例 |
|------|------|------|
| `**加粗**` | 生词（将在 Part 2 收录） | I am **exhausted**. |
| `<u>下划线</u>` | 高频口语表达（将在 Part 3 收录） | <u>No problem.</u> |
| `` `【语法】` `` | 重要语法点（将在 Part 4 讲解） | `【语法】`Doing aerobics... |

**高亮原则：**
- 生词：Episode 内关键实词，8–15 个为宜；同一词多次出现只需首次或关键句加粗
- 口语表达：idiom、phrasal verb、固定搭配、口语缩略（gonna/wanna）；每集 10–20 条
- 语法点：每集 3–6 处 `【语法】` 标记，与 Part 4 一一对应

### 1.5 发音标注

在**有教学价值**的句子下方增加一行发音标注：

```markdown
**Richard:** I lift weights every morning for 60 minutes without stopping. <u>No problem.</u>
*发音：* withou[t] stopping | no[t] problem | lif[t] weights
```

**标注规则：**

| 类型 | 何时标注 | 写法示例 |
|------|----------|----------|
| 连读 ⌒ | 前字尾辅音+后字首元音，或元元连读 | `a⌒lot`, `give⌒you`, `piece⌒of(schwa)` |
| 弱读 (schwa) | the/to/of/a/for 等结构词弱化 | `t(schwa)`, `th(schwa)`, `of(schwa)`, `a(schwa)` |
| 失去爆破 [ ] | 词尾 /p,t,k,b,d,g/ 不送气爆破 | `no[t]`, `don'[t]`, `righ[t]` |
| 闪音 ⚡ | 两元音之间的 /t/ 或 /d/ | `pho⚡ographer`, `a⚡er`, `ci⚡y` |

**频率控制：**
- 每个 Section 中，约 **50%–70%** 的句子需要发音行（短句、重复句可省略）
- 每行用 `| ` 分隔多个发音片段
- 难词可附 IPA：`exhausted* /ɪɡˈzɔːstɪd/`
- 必要时加简短中文注释：`（barely 中 r 清晰）`

**不要：** 对每一单词机械标注；不要编造与音频不符的发音。

---

## Part 2 — 生词表（Vocabulary）

```markdown
> 以下词汇在正文中已**加粗**标注。

| 单词/短语 | 音标 | 词性 | 中文释义 | 核心用法/例句 |
|-----------|------|------|----------|---------------|
```

**选词标准：**
- **必须**与 Part 1 中加粗词完全对应，不得出现未加粗的生词
- 优先：话题核心词、易混淆词、动词短语中的关键动词
- 音标使用 IPA；美音/英音与输入参数一致
- 「核心用法/例句」用英文，可含课文原句

---

## Part 3 — 高频口语表达（Spoken English）

```markdown
> 以下表达在正文中已<u>下划线</u>标注。

### 1. {主题分组名，如：形容事情轻而易举}

| 表达 | 含义 | 课文例句 |
|------|------|----------|
| <u>It's a piece of cake.</u> | 小菜一碟 | It's gonna be **a piece of cake.** |
```

**分组原则：**
- 按语义分 2–4 组（如：轻松/打赌/态度/请求/告别）
- **必须**与 Part 1 下划线表达一一对应
- 每组末可加 **场景拓展** 1–2 句（中文说明 + 英文例句）
- 课文例句取自 Part 1，保持原文

---

## Part 4 — 重要语法讲解（Grammar）

```markdown
> 语法点在正文中以 `【语法】` 标注。

### 1. {语法点名称（中英文）}

- **课文原句：** ...
- **规则：** ...
- **公式：** ...（如有）
- **例句：** ...
- **对比：** ...（如有易混点）
```

**选题标准（每集 3–6 点）：**
- 优先提取 Part 1 中已标 `【语法】` 的句子
- 适合本集出现的：时态、动名词/不定式、介词搭配、比较级、口语缩略、否定词用法等
- 每条含：课文原句 + 简明规则 + 至少 1 个补充例句
- 易混点用 **对比** 说明（如 remember doing vs remember to do）

---

## Part 5 — 学习问题（Study Questions）

分三类，**每类 6–8 题**：

### A. Comprehension（理解题）
- 考查剧情细节：人物、事件顺序、因果关系
- 题干英文，可用 **加粗** 强调关键词
- 答案应能从台词中直接找到

### B. Thinking（思考题）
- 人物性格、观点判断、寓意、与现实联系
- 鼓励 personal connection（Have you ever...?）
- 无唯一标准答案

### C. Speaking & Retelling（口语与复述）
- 含：**Summarize** / **Retell** / **Explain the title** / **Role-play**
- 至少 1 题要求运用 Part 3 所学表达
- 至少 1 题角色扮演，指明 Section

---

## Self-Assessment（自评清单）

- 5 条 `□` checkbox，对应本集核心能力（剧情、口语、语法、发音）
- 末尾附三级评价指引：
  - **5/5：** 可以进入下一集
  - **3–4/5：** 重点复习 Part 3 / Part 4
  - **0–2/5：** 建议再听视频，跟读指定 Section

---

# 全局约束

1. **铁律优先：** 上述三条铁律优先级高于一切其他指令
2. **语言纯净度：** 解释性文字用简体中文；台词、例句、练习题题干用纯净英文（见铁律 2）
3. **格式：** 标准 Markdown；表格对齐；适合打印和跟读
4. **一致性：** Part 2/3/4 必须与 Part 1 高亮严格对应
5. **准确性：** 台词以视频实际内容为准；修正 ASR 错误；不确定时保持上下文一致
6. **篇幅：** 一集 13–25 分钟剧集，文档约 350–450 行

# 输出前自检（必须在内心完成，不要输出自检过程）

在输出前，确认全文：
- [ ] 无任何 `([` + 时间 + `](http` 形式的链接
- [ ] 无任何 `(13:xx)`、`[0:xx]`、`?t=` 时间标记
- [ ] 除顶部「视频来源」外，无 `youtube.com` / `youtu.be`
- [ ] 无 "Hello" / "Here is" / "Sure" 等 AI 开场白
- [ ] 第一个字符是 `#`

# 输出

直接输出完整 Markdown 文档。第一个字符必须是 `# 📘`，不得有任何前置文字。
````

---

## 三、单条视频快速调用版（精简 Prompt）

适合已熟悉规则、只需填参数的批量场景：

```
按 review/English/PROMPT_youtube_learning_doc.md 主 Prompt 规则，为以下视频生成学习讲义：

- URL: {YouTube URL}
- 系列: {系列} 第{N}集
- 标题: {英文}（{中文}）
- 场景: {核心场景}
- 难度: {中级} | 美音
- 输出文件名: {NN}_{slug}.md

【三条铁律 — 违反即失败】
1. 绝对禁止链接/时间戳：全文不得出现 ([13:07](url))、(13:07)、[0:32]、?t=787s 等；youtube 链接仅允许在文档顶部「视频来源」出现一次
2. 语言纯净度：解释用简体中文，台词/例句/题干用纯净英文
3. 杜绝 AI 废话：第一个字符必须是 #，禁止 Hello / Here is your document 等开场白

要求与 04_a_piece_of_cake.md 结构完全一致。直接输出全文，不要代码块包裹。
```

---

## 四、批量清单模板（CSV）

```csv
episode_no,title_en,title_zh,youtube_url,theme,output_filename
04,A Piece of Cake,小菜一碟,https://www.youtube.com/watch?v=VwPsPGRj0Xo,健身打赌家务,04_a_piece_of_cake.md
05,Meeting a Friend,访友,https://www.youtube.com/watch?v=XXXXX,社交拜访,05_meeting_a_friend.md
```

---

## 五、Quality Checklist（生成后抽检）

| # | 检查项 | 通过标准 |
|---|--------|----------|
| 1 | 台词完整 | 开头到结尾对话无重大遗漏 |
| 2 | **无链接/时间戳** | 全文无 `([`、`?t=`、`(13:xx)`、`[0:xx]`、`00:`；除顶部外无 `youtube.com` |
| 3 | **无 AI 废话** | 开头直接是 `# 📘`；无 Hello / Here is 等 |
| 4 | 说话人 | 每句对话有姓名或舞台说明 |
| 5 | Section | 3–6 节，叙事合理，有中英文标题 |
| 6 | 高亮一致 | Part 2/3/4 与 Part 1 标记一一对应 |
| 7 | 发音标注 | 每 Section 约半数句子有 `*发音：*` 行 |
| 8 | 语法 | 3–6 点，`【语法】` 与 Part 4 对应 |
| 9 | 练习题 | Comprehension / Thinking / Speaking 各 6+ 题 |
| 10 | 语言纯净 | 解释中文、例句英文，无中英混杂 |
| 11 | ASR 修正 | 无明显机器字幕错误残留 |
| 12 | 自评清单 | 5 条 checkbox + 三级评价 |

---

## 六、可选增强参数

在主 Prompt 的「输入信息」表格后追加：

| 参数 | 说明 |
|------|------|
| `+中文翻译` | 每个 Section 末尾附中文译文段落 |
| `+听写题` | Part 5 后增加 Dictation 填空题 5 句 |
| `+跟读建议` | 每 Section 末注「建议跟读 N 遍」及重点句 |
| `+CEFR 标注` | 生词表增加 A2/B1/B2 等级 |
| `+文化注释` | 对美国文化/习俗加点说明（适合走遍美国） |

示例追加行：

```
| 额外输出 | +文化注释, +跟读建议 |
```

---

## 七、参考样例摘要

以下为 [`04_a_piece_of_cake.md`](04_a_piece_of_cake.md) 中应复现的质量标杆：

**台词行示例：**
```markdown
**Richard:** I lift weights every morning for 60 minutes without stopping. <u>No problem.</u> Listen, Marilyn. `【语法】`Doing **aerobics** for an hour is a lot different than lifting weights.
*发音：* withou[t] stopping | no[t] problem | doin[g] **aerobics** | a⌒lot | liftin[g] weights
```

**口语表示例：**
```markdown
| <u>It's a piece of cake.</u> | 小菜一碟 | It's gonna be **a piece of cake.** |
```

**语法点示例：**
```markdown
### 3. instead of + n. / doing
- **课文原句：** `【语法】`Instead of exercising, I photographed the class.
- **规则：** of 是介词，后接名词或动名词（-ing），不接动词原形。
```

---

## 八、API 批量脚本提示（可选）

若用脚本调用 LLM API，建议：

```python
# 伪代码
for row in video_list:
    prompt = MAIN_PROMPT.format(**row)
    md = llm.generate(prompt, temperature=0.3)  # 低温度保证格式稳定
    save(f"review/English/{row['output_filename']}", md)
    # 每视频独立请求，不共享上下文
```

- `temperature` 建议 0.2–0.4（格式稳定优先）
- 每视频单独会话，避免前几集内容污染后续输出
- 生成后跑 Quality Checklist 或用脚本检测：

```bash
# 检测违规链接/时间戳（除首行视频来源外应无匹配）
grep -nE '\(\[[0-9:]+]\(https?://|youtube\.com|youtu\.be|\?t=[0-9]+|\([0-9]{1,2}:[0-9]{2}\)' output.md

# 检测时间戳残留
grep -nE '\[[0-9]{1,2}:[0-9]{2}\]|\([0-9]{1,2}:[0-9]{2}\)' output.md
```

---

## 九、Google AI 模式专用前缀（粘贴到 Prompt 最开头）

若使用 Google Gemini / AI Mode 处理 YouTube 视频，**务必**在 Prompt 最开头粘贴以下段落（对抑制时间链接最有效）：

```
⛔ CRITICAL OUTPUT RULES — VIOLATION = FAILURE:

1. NO LINKS OR TIMESTAMPS ANYWHERE in the document body.
   NEVER append ([13:07](https://www.youtube.com/...)) or (13:07) or [0:32] after any line.
   The ONLY allowed YouTube URL is ONE plain link in the document header under "视频来源".
   Dialogue lines must end with punctuation only — no parentheses, no URLs, no time numbers.

2. LANGUAGE PURITY: Simplified Chinese for all explanations; pure English for dialogue, examples, and question stems.

3. NO AI FILLER: Do NOT say "Hello", "Here is your document", "Sure", or any greeting/summary.
   The very first character of your output MUST be "#" (the document title).
```
