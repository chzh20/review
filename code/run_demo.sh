#!/usr/bin/env bash
# Quick end-to-end smoke test (char tokenizer, synthetic data, tiny model, CPU).
# Demonstrates the full pipeline without external data or GPU.
set -e
PY=python
if [ -x "../bin/python" ]; then PY=python; fi

echo "=== Demo: train tiny Transformer on synthetic en->zh ==="
$PY train.py \
    --tokenizer_type char \
    --max_examples 20000 \
    --train_steps 5000 \
    --eval_every 1000 \
    --save_every 1000 \
    --batch_size 32 \
    --d_model 256 \
    --d_ff 1024 \
    --n_heads 4 \
    --n_enc_layers 3 \
    --n_dec_layers 3 \
    --warmup_steps 1000 \
    --fp16 False

echo "=== Interactive translation with best checkpoint ==="
$PY translate.py \
    --checkpoint checkpoints/best.pt \
    --tokenizer_type char \
    --char_vocab checkpoints/char_vocab.txt \
    --text "hello world i love you"
