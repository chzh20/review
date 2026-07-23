"""Inference: Beam Search decoding + BLEU evaluation (sacrebleu).

Also exposes a CLI for interactive translation:
    python translate.py --checkpoint checkpoints/best.pt --spm_model ... \
        --tokenizer_type spm --text "hello world"
"""
import os
import argparse
import torch
import torch.nn.functional as F

from config import Config
from tokenizer import CharTokenizer, SPMTokenizer
from model import Transformer
from utils import make_src_mask, make_tgt_mask


# --------------------------------------------------------------------------- #
# Beam Search (paper section 3 / inference). No KV-cache (simple, clear).
# --------------------------------------------------------------------------- #
def beam_search(model, src, src_mask, tok, device, max_len=100,
                beam_size=4, alpha=0.6):
    """Returns list of token ids (without leading bos, incl. eos if produced)."""
    model.eval()
    with torch.no_grad():
        memory = model.encode(src, src_mask)  # [1, S, D]
        beams = [([tok.bos_id], 0.0)]         # (ids, score)
        for _ in range(max_len):
            cands = []
            for ids, score in beams:
                if ids[-1] == tok.eos_id:
                    cands.append((ids, score))
                    continue
                tgt = torch.tensor([ids], device=device)
                tgt_mask = make_tgt_mask(tgt, tok.pad_id)
                logits = model.decoder(tgt, memory, src_mask, tgt_mask)
                logp = F.log_softmax(logits[0, -1], dim=-1)
                topv, topi = torch.topk(logp, beam_size)
                for v, i in zip(topv, topi):
                    cands.append((ids + [i.item()], score + v.item()))
            # length-penalized sort, keep top beam_size
            cands.sort(key=lambda x: x[1] / (len(x[0]) ** alpha), reverse=True)
            beams = cands[:beam_size]
            if all(b[0][-1] == tok.eos_id for b in beams):
                break
        best = max(beams, key=lambda x: x[1] / (len(x[0]) ** alpha))
        return best[0]


# --------------------------------------------------------------------------- #
def translate_one(model, text, tok, device, cfg):
    src_ids = ([tok.bos_id] + tok.encode(text)[: cfg.max_src_len - 2]
               + [tok.eos_id])
    src = torch.tensor([src_ids], device=device)
    src_mask = make_src_mask(src, tok.pad_id)
    out = beam_search(model, src, src_mask, tok, device,
                      max_len=cfg.max_gen_len, beam_size=cfg.beam_size)
    return tok.decode(out, skip_special=True)


# --------------------------------------------------------------------------- #
def evaluate(model, pairs, tok, device, cfg, beam_size=4, max_samples=None):
    """Compute corpus BLEU over (src, tgt) pairs."""
    import sacrebleu
    model.to(device)
    preds, refs = [], []
    for i, (src, tgt) in enumerate(pairs):
        if max_samples and i >= max_samples:
            break
        preds.append(translate_one(model, src, tok, device, cfg))
        refs.append(tgt)
    bleu = sacrebleu.corpus_bleu(preds, [refs]) if preds else 0.0
    return (bleu.score if hasattr(bleu, "score") else float(bleu)), preds, refs


# --------------------------------------------------------------------------- #
def _main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--text", type=str, default="hello world")
    ap.add_argument("--tokenizer_type", default="char")
    ap.add_argument("--spm_model", default="")
    ap.add_argument("--vocab_size", type=int, default=8000)
    ap.add_argument("--d_model", type=int, default=256)
    ap.add_argument("--n_heads", type=int, default=4)
    ap.add_argument("--n_enc_layers", type=int, default=3)
    ap.add_argument("--n_dec_layers", type=int, default=3)
    ap.add_argument("--d_ff", type=int, default=1024)
    ap.add_argument("--beam_size", type=int, default=4)
    ap.add_argument("--max_gen_len", type=int, default=100)
    ap.add_argument("--char_vocab", default="")
    args = ap.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    cfg = Config()
    cfg.tokenizer_type = args.tokenizer_type
    cfg.spm_model = args.spm_model
    cfg.vocab_size = args.vocab_size
    cfg.d_model = args.d_model
    cfg.n_heads = args.n_heads
    cfg.n_enc_layers = args.n_enc_layers
    cfg.n_dec_layers = args.n_dec_layers
    cfg.d_ff = args.d_ff
    cfg.beam_size = args.beam_size
    cfg.max_gen_len = args.max_gen_len

    state = torch.load(args.checkpoint, map_location=device)
    # vocab size stored inside the model's embedding
    vocab = state["model"]["encoder.emb.emb.weight"].shape[0]
    model = Transformer(vocab, cfg.d_model, cfg.n_enc_layers, cfg.n_dec_layers,
                        cfg.n_heads, cfg.d_ff, dropout=0.0, share_emb=cfg.share_emb)
    model.load_state_dict(state["model"])
    model.to(device)

    if args.tokenizer_type == "char":
        tok = CharTokenizer.load(args.char_vocab) if args.char_vocab else None
        # char vocab must match; fallback: rebuild minimal (only for demo)
        if tok is None:
            raise SystemExit("For char tokenizer, pass --char_vocab checkpoints/char_vocab.txt")
    else:
        tok = SPMTokenizer(args.spm_model)

    print(f"Input : {args.text}")
    print(f"Output: {translate_one(model, args.text, tok, device, cfg)}")


if __name__ == "__main__":
    _main()
