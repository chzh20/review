"""Training script: reproduce Attention Is All You Need for zh-en translation.

Run (quick demo, CPU/GPU):
    python train.py --tokenizer_type char --max_examples 20000 \
        --train_steps 20000 --batch_size 32 --d_model 256 --n_heads 4 \
        --n_enc_layers 3 --n_dec_layers 3

Run (paper Base, WMT en-zh, needs GPU + sentencepiece + datasets):
    python train.py --hf_dataset wmt19 --hf_config en-zh \
        --tokenizer_type spm --vocab_size 32000
"""
import os
import random
import time

import torch
import torch.nn.functional as F
from torch.nn.parallel import DistributedDataParallel as DDP
import torch.distributed as dist
from tqdm import tqdm

from config import Config
from tokenizer import CharTokenizer, SPMTokenizer
from dataset import ParallelDataset, build_loader, load_pairs, demo_pairs
from model import Transformer
from utils import (LabelSmoothingLoss, NoamScheduler, make_src_mask,
                   make_tgt_mask, count_params)
from translate import beam_search, evaluate


# --------------------------------------------------------------------------- #
def set_seed(s):
    random.seed(s)
    torch.manual_seed(s)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(s)


def build_tokenizer(cfg, train_pairs):
    src_texts = [p[0] for p in train_pairs]
    tgt_texts = [p[1] for p in train_pairs]
    all_texts = src_texts + tgt_texts
    if cfg.tokenizer_type == "char":
        tok = CharTokenizer()
        tok.build(all_texts)
        return tok
    # spm
    os.makedirs(cfg.save_dir, exist_ok=True)
    prefix = os.path.join(cfg.save_dir, "spm")
    model_path = prefix + ".model"
    if cfg.spm_model:
        return SPMTokenizer(cfg.spm_model)
    if not os.path.exists(model_path):
        SPMTokenizer.train(all_texts, prefix, cfg.vocab_size)
    return SPMTokenizer(model_path)


def prepare_data(cfg):
    """Returns (train_pairs, val_pairs, test_pairs, tok)."""
    if cfg.data_path == "" and cfg.hf_dataset == "":
        # fully synthetic demo
        train_pairs = demo_pairs(n=max(cfg.max_examples, 20000), seed=cfg.seed)
        val = demo_pairs(n=1000, seed=cfg.seed + 1)
        test = demo_pairs(n=1000, seed=cfg.seed + 2)
        return train_pairs, val, test

    if cfg.data_path:
        all_pairs = load_pairs(cfg, "train")
        if cfg.max_examples:
            all_pairs = all_pairs[: cfg.max_examples]
        random.shuffle(all_pairs)
        n = len(all_pairs)
        n_val = max(1, int(0.01 * n))
        n_test = max(1, int(0.01 * n))
        test = all_pairs[:n_test]
        val = all_pairs[n_test:n_test + n_val]
        train = all_pairs[n_test + n_val:]
        return train, val, test

    # HuggingFace datasets
    train = load_pairs(cfg, "train")
    val = load_pairs(cfg, "validation")
    test = load_pairs(cfg, "test")
    if cfg.max_examples:
        train = train[: cfg.max_examples]
    return train, val, test


# --------------------------------------------------------------------------- #
def main():
    cfg = Config.parse_args()
    set_seed(cfg.seed)
    use_cuda = torch.cuda.is_available()
    device = torch.device("cuda" if use_cuda else "cpu")
    fp16 = cfg.fp16 and use_cuda

    # DDP (optional)
    ddp = cfg.distributed and "RANK" in os.environ
    if ddp:
        dist.init_process_group("nccl")
        rank = dist.get_rank()
    else:
        rank = 0

    # ---- data ----
    train_pairs, val_pairs, test_pairs = prepare_data(cfg)
    tok = build_tokenizer(cfg, train_pairs)
    # persist tokenizer for later inference
    os.makedirs(cfg.save_dir, exist_ok=True)
    if cfg.tokenizer_type == "char":
        tok.save(os.path.join(cfg.save_dir, "char_vocab.txt"))
    print(f"[rank {rank}] vocab_size={tok.vocab_size}, "
          f"train={len(train_pairs)}, val={len(val_pairs)}, test={len(test_pairs)}")

    train_ds = ParallelDataset(train_pairs, tok, cfg.max_src_len, cfg.max_tgt_len)
    val_ds = ParallelDataset(val_pairs, tok, cfg.max_src_len, cfg.max_tgt_len)
    train_loader = build_loader(train_ds, cfg, tok.pad_id, shuffle=True, ddp=ddp)
    val_loader = build_loader(val_ds, cfg, tok.pad_id, shuffle=False, ddp=False)

    # ---- model ----
    model = Transformer(
        vocab=tok.vocab_size,
        d_model=cfg.d_model,
        n_enc=cfg.n_enc_layers,
        n_dec=cfg.n_dec_layers,
        n_heads=cfg.n_heads,
        d_ff=cfg.d_ff,
        dropout=cfg.dropout,
        share_emb=cfg.share_emb,
    ).to(device)

    if ddp:
        model = DDP(model, device_ids=[int(os.environ["LOCAL_RANK"])])
    print(f"[rank {rank}] parameters: {count_params(model)/1e6:.2f}M")

    # ---- optimizer / scheduler / loss ----
    optimizer = torch.optim.Adam(
        model.parameters(), lr=0.0,
        betas=(cfg.beta1, cfg.beta2), eps=cfg.eps, weight_decay=cfg.weight_decay)
    scheduler = NoamScheduler(optimizer, cfg.d_model, cfg.warmup_steps, cfg.lr_factor)
    criterion = LabelSmoothingLoss(tok.vocab_size, tok.pad_id, cfg.label_smoothing)

    scaler = torch.cuda.amp.GradScaler(enabled=fp16)
    os.makedirs(cfg.save_dir, exist_ok=True)
    cfg.to_json(os.path.join(cfg.save_dir, "config.json"))

    # ---- training loop (step-based, as in the paper) ----
    model.train()
    train_iter = iter(train_loader)
    running_loss = 0.0
    best_bleu = -1.0
    t0 = time.time()

    for step in range(1, cfg.train_steps + 1):
        try:
            src, tgt_in, tgt_out = next(train_iter)
        except StopIteration:
            train_iter = iter(train_loader)
            src, tgt_in, tgt_out = next(train_iter)

        src, tgt_in, tgt_out = src.to(device), tgt_in.to(device), tgt_out.to(device)
        src_mask = make_src_mask(src, tok.pad_id)
        tgt_mask = make_tgt_mask(tgt_in, tok.pad_id)

        optimizer.zero_grad()
        with torch.cuda.amp.autocast(enabled=fp16):
            logits = model(src, tgt_in, src_mask, tgt_mask)
            loss = criterion(logits.view(-1, tok.vocab_size), tgt_out.view(-1))
            loss = loss / cfg.accum_steps

        scaler.scale(loss).backward()

        if step % cfg.accum_steps == 0:
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), cfg.clip_grad)
            scaler.step(optimizer)
            scaler.update()
            scheduler.step()

        running_loss += loss.item() * cfg.accum_steps

        if step % 100 == 0 and rank == 0:
            lr = optimizer.param_groups[0]["lr"]
            print(f"step {step}/{cfg.train_steps} | loss {running_loss/100:.3f} "
                  f"| lr {lr:.2e} | {time.time()-t0:.0f}s")
            running_loss = 0.0

        # ---- evaluation ----
        if step % cfg.eval_every == 0 and rank == 0:
            bleu, _, _ = evaluate(model, val_pairs[:2000], tok, device, cfg,
                                  beam_size=1)  # greedy for speed
            print(f"  >> val BLEU (greedy): {bleu:.2f}")
            if bleu > best_bleu:
                best_bleu = bleu
                save(model, optimizer, scheduler, cfg, f"best.pt")
            model.train()

        # ---- checkpoint ----
        if step % cfg.save_every == 0 and rank == 0:
            save(model, optimizer, scheduler, cfg, f"step_{step}.pt")

    if rank == 0:
        save(model, optimizer, scheduler, cfg, "last.pt")
        # final test BLEU with beam search
        bleu, _, _ = evaluate(model, test_pairs[:2000], tok, device, cfg,
                              beam_size=cfg.beam_size)
        print(f"=== Test BLEU (beam={cfg.beam_size}): {bleu:.2f} ===")
        print("Paper reference: WMT14 En-De Base = 27.3 BLEU; "
              "En-Zh numbers differ by corpus (see notes).")
    if ddp:
        dist.destroy_process_group()


def save(model, optimizer, scheduler, cfg, name):
    path = os.path.join(cfg.save_dir, name)
    state = {
        "model": (model.module.state_dict() if hasattr(model, "module")
                  else model.state_dict()),
        "optimizer": optimizer.state_dict(),
        "scheduler": scheduler.state_dict(),
    }
    torch.save(state, path)
    print(f"  saved -> {path}")


if __name__ == "__main__":
    main()
