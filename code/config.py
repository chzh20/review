"""Configuration for the Transformer (Attention Is All You Need) zh-en reproduction.

All hyperparameters follow the paper's Base configuration. For limited compute,
reduce d_model / n_heads / n_*_layers (see the "scaled" preset in run_demo.sh).
"""
from dataclasses import dataclass, asdict
import json
import argparse


@dataclass
class Config:
    # ---------------- data ----------------
    data_path: str = ""        # local .tsv file (src\tgt); empty -> use hf_dataset
    hf_dataset: str = "wmt19"  # e.g. wmt19 / wmt14 / iwslt2017 / opus100
    hf_config: str = "en-zh"   # language pair
    src_lang: str = "en"
    tgt_lang: str = "zh"
    max_src_len: int = 80
    max_tgt_len: int = 80
    max_examples: int = 0      # 0 = use all examples (cap for quick runs)

    # ---------------- tokenizer ----------------
    tokenizer_type: str = "spm"   # 'spm' (paper-faithful BPE) or 'char' (zero-dep)
    vocab_size: int = 8000        # spm vocab size (paper uses ~37k for en-de)
    spm_model: str = ""           # pretrained .model path; if set, skip training

    # ---------------- model (paper Base) ----------------
    d_model: int = 512
    d_ff: int = 2048
    n_heads: int = 8
    n_enc_layers: int = 6
    n_dec_layers: int = 6
    dropout: float = 0.1
    share_emb: bool = True        # tie encoder/decoder embeddings + softmax (paper)

    # ---------------- training ----------------
    batch_size: int = 32          # lower to 8/16 on small GPUs
    accum_steps: int = 1          # gradient accumulation steps
    train_steps: int = 100000     # paper trains 100k (base) / 300k (big)
    warmup_steps: int = 4000      # Noam scheduler warmup
    lr_factor: float = 1.0        # lr scaling factor
    beta1: float = 0.9
    beta2: float = 0.98           # paper uses 0.9 / 0.98
    eps: float = 1e-9
    weight_decay: float = 0.0
    clip_grad: float = 1.0        # gradient clipping (added for stability)
    label_smoothing: float = 0.1  # paper uses 0.1
    eval_every: int = 1000
    save_every: int = 1000
    keep_checkpoints: int = 3

    # ---------------- precision / distributed ----------------
    fp16: bool = True             # AMP on CUDA
    distributed: bool = False     # DDP via torchrun (optional)

    # ---------------- paths / misc ----------------
    save_dir: str = "checkpoints"
    experiment: str = "transformer_zh_en"
    seed: int = 42
    beam_size: int = 4
    max_gen_len: int = 100

    @staticmethod
    def from_json(path):
        with open(path, encoding="utf-8") as f:
            return Config(**json.load(f))

    def to_json(self, path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, indent=2, ensure_ascii=False)

    @staticmethod
    def parse_args():
        p = argparse.ArgumentParser()
        defaults = asdict(Config())
        for k, v in defaults.items():
            p.add_argument(f"--{k}", type=type(v), default=v)
        p.add_argument("--config", type=str, default="")
        a = p.parse_args()
        cfg = Config.from_json(a.config) if a.config else Config()
        for k in defaults.keys():
            val = getattr(a, k)
            if val is not None and val != defaults[k]:
                setattr(cfg, k, val)
        return cfg
