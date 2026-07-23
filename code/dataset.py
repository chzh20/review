"""Datasets, collation, and data loading for parallel corpora."""
import random
import torch
from torch.utils.data import Dataset, DataLoader, DistributedSampler


# --------------------------------------------------------------------------- #
# Synthetic demo corpus (deterministic, learnable English->Chinese mapping)
# Used when no real data is available so the whole pipeline runs end-to-end.
# --------------------------------------------------------------------------- #
_EN2ZH = {
    "hello": "你好", "world": "世界", "i": "我", "you": "你", "he": "他",
    "she": "她", "eat": "吃", "apple": "苹果", "book": "书", "water": "水",
    "fire": "火", "cat": "猫", "dog": "狗", "run": "跑", "sleep": "睡",
    "big": "大", "small": "小", "red": "红", "blue": "蓝", "green": "绿",
    "happy": "高兴", "sad": "伤心", "today": "今天", "tomorrow": "明天",
    "love": "爱", "hate": "恨", "read": "读", "write": "写", "go": "去",
    "come": "来", "see": "看", "hear": "听", "good": "好", "bad": "坏",
}


def demo_pairs(n=20000, seed=0):
    rng = random.Random(seed)
    words = list(_EN2ZH.keys())
    pairs = []
    for _ in range(n):
        k = rng.randint(3, 8)
        sel = [rng.choice(words) for _ in range(k)]
        en = " ".join(sel)
        zh = "".join(_EN2ZH[w] for w in sel)
        pairs.append((en, zh))
    return pairs


# --------------------------------------------------------------------------- #
# Data loading
# --------------------------------------------------------------------------- #
def load_pairs(cfg, split="train"):
    if cfg.data_path:
        pairs = []
        with open(cfg.data_path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    pairs.append((parts[0].strip(), parts[1].strip()))
        return pairs
    from datasets import load_dataset
    ds = load_dataset(cfg.hf_dataset, cfg.hf_config, split=split)
    return [(ex[cfg.src_lang], ex[cfg.tgt_lang]) for ex in ds]


class ParallelDataset(Dataset):
    def __init__(self, pairs, tokenizer, max_src_len, max_tgt_len):
        self.tok = tokenizer
        self.data = []
        for src, tgt in pairs:
            s = tokenizer.encode(src)[: max_src_len - 2]
            t = tokenizer.encode(tgt)[: max_tgt_len - 2]
            src_ids = [tokenizer.bos_id] + s + [tokenizer.eos_id]
            tgt_ids = [tokenizer.bos_id] + t + [tokenizer.eos_id]
            self.data.append((src_ids, tgt_ids))

    def __len__(self):
        return len(self.data)

    def __getitem__(self, i):
        return self.data[i]


def collate(batch, pad_id):
    """Returns (src, tgt_in, tgt_out) all [B, L] (long)."""
    srcs, tgts = zip(*batch)
    src_len = max(len(s) for s in srcs)
    tgt_len = max(len(t) for t in tgts)
    src_mat = torch.full((len(batch), src_len), pad_id, dtype=torch.long)
    tgt_mat = torch.full((len(batch), tgt_len), pad_id, dtype=torch.long)
    for i, (s, t) in enumerate(batch):
        src_mat[i, :len(s)] = torch.tensor(s)
        tgt_mat[i, :len(t)] = torch.tensor(t)
    # Teacher forcing: decoder input = tgt without last token,
    # target         = tgt without first token.
    tgt_in = tgt_mat[:, :-1]
    tgt_out = tgt_mat[:, 1:]
    return src_mat, tgt_in, tgt_out


def build_loader(dataset, cfg, pad_id, shuffle=True, ddp=False):
    sampler = DistributedSampler(dataset) if ddp else None
    loader = DataLoader(
        dataset,
        batch_size=cfg.batch_size,
        shuffle=(shuffle and sampler is None),
        sampler=sampler,
        collate_fn=lambda b: collate(b, pad_id),
        num_workers=2,
        pin_memory=True,
    )
    return loader
