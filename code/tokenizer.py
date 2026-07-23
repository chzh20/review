"""Tokenizers: shared-vocabulary BPE (sentencepiece) or zero-dep char-level.

The paper uses a *shared* BPE vocabulary between source and target (En-De).
We mirror that here: a single tokenizer/vocab is used for both languages,
which lets us tie the embedding and softmax weights.
"""
import os


class CharTokenizer:
    """Zero-dependency char-level tokenizer. Good for a quick, runnable demo
    (Chinese splits into characters; English into chars). Not paper-faithful
    but a legitimate simplification for limited compute."""

    def __init__(self):
        self.pad_id = 0
        self.bos_id = 1
        self.eos_id = 2
        self.unk_id = 3
        self.char2id = {}
        self.id2char = {}

    def build(self, texts):
        idx = 4
        for t in texts:
            for ch in t:
                if ch not in self.char2id:
                    self.char2id[ch] = idx
                    self.id2char[idx] = ch
                    idx += 1
        self.vocab_size = idx

    def encode(self, text):
        return [self.char2id.get(c, self.unk_id) for c in text]

    def decode(self, ids, skip_special=True):
        out = []
        for i in ids:
            if skip_special and i < 4:
                continue
            out.append(self.id2char.get(i, ""))
        return "".join(out)

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            for i in range(self.vocab_size):
                f.write(self.id2char.get(i, "") + "\n")

    @classmethod
    def load(cls, path):
        tok = cls()
        with open(path, encoding="utf-8") as f:
            for i, line in enumerate(f):
                ch = line.rstrip("\n")
                tok.id2char[i] = ch
                if i >= 4:
                    tok.char2id[ch] = i
        tok.vocab_size = len(tok.id2char)
        return tok


class SPMTokenizer:
    """SentencePiece BPE tokenizer with a shared vocab (paper-faithful).
    Special tokens: <pad> (user-defined), <s>=1 (bos), </s>=2 (eos), <unk>=0."""

    def __init__(self, model_path):
        import sentencepiece as spm
        self.sp = spm.SentencePieceProcessor()
        self.sp.load(model_path)
        self.vocab_size = self.sp.get_piece_size()
        self.pad_id = self.sp.piece_to_id("<pad>")
        self.bos_id = self.sp.piece_to_id("<s>")
        self.eos_id = self.sp.piece_to_id("</s>")
        self.unk_id = self.sp.unk_id()

    def encode(self, text):
        return self.sp.encode(text, out_type=int)

    def decode(self, ids, skip_special=True):
        if skip_special:
            ids = [i for i in ids if i not in (self.pad_id, self.bos_id, self.eos_id)]
        return self.sp.decode(ids)

    @staticmethod
    def train(texts, model_prefix, vocab_size, pad="<pad>"):
        import sentencepiece as spm
        tmp = model_prefix + ".corpus.txt"
        with open(tmp, "w", encoding="utf-8") as f:
            for t in texts:
                f.write(t.strip() + "\n")
        spm.SentencePieceTrainer.train(
            input=tmp,
            model_prefix=model_prefix,
            vocab_size=vocab_size,
            user_defined_symbols=pad,
            character_coverage=0.9995,
            model_type="bpe",
            bos_id=1,
            eos_id=2,
            pad_id=-1,           # pad added via user_defined_symbols instead
        )
        os.remove(tmp)
