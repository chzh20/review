"""Transformer model (Attention Is All You Need) — full architecture.

Encoder-Decoder with: sinusoidal Positional Encoding, Token Embedding
(scaled by sqrt(d_model)), Multi-Head Self-Attention, Multi-Head
Cross-Attention, Position-wise FFN, post-norm LayerNorm + residual
connections, and weight-tied embedding/softmax (paper section 3).
"""
import math
import torch
import torch.nn as nn
import torch.nn.functional as F


# --------------------------------------------------------------------------- #
# Positional Encoding (sinusoidal, paper section 3.5)
# --------------------------------------------------------------------------- #
class PositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=5000, dropout=0.1):
        super().__init__()
        self.drop = nn.Dropout(p=dropout)
        pe = torch.zeros(max_len, d_model)
        pos = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div = torch.exp(torch.arange(0, d_model, 2).float() *
                         (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        pe = pe.unsqueeze(0)  # [1, max_len, d_model]
        self.register_buffer("pe", pe)

    def forward(self, x):
        x = x + self.pe[:, : x.size(1)]
        return self.drop(x)


class TokenEmbedding(nn.Module):
    def __init__(self, vocab, d_model):
        super().__init__()
        self.emb = nn.Embedding(vocab, d_model)

    def forward(self, x):
        return self.emb(x)


# --------------------------------------------------------------------------- #
# Scaled Dot-Product Attention + Multi-Head Attention (paper section 3.2)
# --------------------------------------------------------------------------- #
def scaled_dot_product_attention(q, k, v, mask=None):
    d_k = q.size(-1)
    scores = torch.matmul(q, k.transpose(-2, -1)) / math.sqrt(d_k)
    if mask is not None:
        scores = scores.masked_fill(mask == 0, -1e9)
    attn = F.softmax(scores, dim=-1)
    return torch.matmul(attn, v), attn


class MultiHeadAttention(nn.Module):
    def __init__(self, d_model, n_heads, dropout=0.1):
        super().__init__()
        assert d_model % n_heads == 0
        self.d_k = d_model // n_heads
        self.h = n_heads
        self.W_q = nn.Linear(d_model, d_model)
        self.W_k = nn.Linear(d_model, d_model)
        self.W_v = nn.Linear(d_model, d_model)
        self.W_o = nn.Linear(d_model, d_model)
        self.drop = nn.Dropout(dropout)

    def forward(self, q, k, v, mask=None):
        B = q.size(0)
        Q = self.W_q(q).view(B, -1, self.h, self.d_k).transpose(1, 2)
        K = self.W_k(k).view(B, -1, self.h, self.d_k).transpose(1, 2)
        V = self.W_v(v).view(B, -1, self.h, self.d_k).transpose(1, 2)
        if mask is not None and mask.dim() == 3:
            mask = mask.unsqueeze(1)  # [B,1,Lq,Lk]
        out, _ = scaled_dot_product_attention(Q, K, V, mask)
        out = out.transpose(1, 2).contiguous().view(B, -1, self.h * self.d_k)
        return self.W_o(out)


class PositionwiseFFN(nn.Module):
    def __init__(self, d_model, d_ff, dropout=0.1):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(d_model, d_ff),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(d_ff, d_model),
        )

    def forward(self, x):
        return self.net(x)


class LayerNorm(nn.Module):
    def __init__(self, d_model, eps=1e-6):
        super().__init__()
        self.a = nn.Parameter(torch.ones(d_model))
        self.b = nn.Parameter(torch.zeros(d_model))
        self.eps = eps

    def forward(self, x):
        mean = x.mean(-1, keepdim=True)
        std = x.std(-1, keepdim=True, unbiased=False)
        return self.a * (x - mean) / (std + self.eps) + self.b


# --------------------------------------------------------------------------- #
# Encoder / Decoder layers (post-norm: x = Norm(x + Dropout(Sublayer(x))))
# --------------------------------------------------------------------------- #
class EncoderLayer(nn.Module):
    def __init__(self, d_model, n_heads, d_ff, dropout):
        super().__init__()
        self.self_attn = MultiHeadAttention(d_model, n_heads, dropout)
        self.ffn = PositionwiseFFN(d_model, d_ff, dropout)
        self.norm1 = LayerNorm(d_model)
        self.norm2 = LayerNorm(d_model)
        self.drop1 = nn.Dropout(dropout)
        self.drop2 = nn.Dropout(dropout)

    def forward(self, x, src_mask):
        x = self.norm1(x + self.drop1(self.self_attn(x, x, x, src_mask)))
        x = self.norm2(x + self.drop2(self.ffn(x)))
        return x


class DecoderLayer(nn.Module):
    def __init__(self, d_model, n_heads, d_ff, dropout):
        super().__init__()
        self.self_attn = MultiHeadAttention(d_model, n_heads, dropout)
        self.cross_attn = MultiHeadAttention(d_model, n_heads, dropout)
        self.ffn = PositionwiseFFN(d_model, d_ff, dropout)
        self.norm1 = LayerNorm(d_model)
        self.norm2 = LayerNorm(d_model)
        self.norm3 = LayerNorm(d_model)
        self.drop1 = nn.Dropout(dropout)
        self.drop2 = nn.Dropout(dropout)
        self.drop3 = nn.Dropout(dropout)

    def forward(self, x, memory, src_mask, tgt_mask):
        x = self.norm1(x + self.drop1(self.self_attn(x, x, x, tgt_mask)))
        x = self.norm2(x + self.drop2(self.cross_attn(x, memory, memory, src_mask)))
        x = self.norm3(x + self.drop3(self.ffn(x)))
        return x


class Encoder(nn.Module):
    def __init__(self, vocab, d_model, n_layers, n_heads, d_ff, dropout):
        super().__init__()
        self.emb = TokenEmbedding(vocab, d_model)
        self.pe = PositionalEncoding(d_model, dropout=dropout)
        self.layers = nn.ModuleList(
            [EncoderLayer(d_model, n_heads, d_ff, dropout) for _ in range(n_layers)])

    def forward(self, x, mask):
        x = self.pe(self.emb(x) * math.sqrt(self.emb.emb.embedding_dim))
        for l in self.layers:
            x = l(x, mask)
        return x


class Decoder(nn.Module):
    def __init__(self, vocab, d_model, n_layers, n_heads, d_ff, dropout):
        super().__init__()
        self.emb = TokenEmbedding(vocab, d_model)
        self.pe = PositionalEncoding(d_model, dropout=dropout)
        self.layers = nn.ModuleList(
            [DecoderLayer(d_model, n_heads, d_ff, dropout) for _ in range(n_layers)])

    def forward(self, x, memory, src_mask, tgt_mask):
        x = self.pe(self.emb(x) * math.sqrt(self.emb.emb.embedding_dim))
        for l in self.layers:
            x = l(x, memory, src_mask, tgt_mask)
        return x


class Transformer(nn.Module):
    def __init__(self, vocab, d_model, n_enc, n_dec, n_heads, d_ff,
                 dropout, share_emb=True):
        super().__init__()
        self.encoder = Encoder(vocab, d_model, n_enc, n_heads, d_ff, dropout)
        self.decoder = Decoder(vocab, d_model, n_dec, n_heads, d_ff, dropout)
        self.generator = nn.Linear(d_model, vocab)
        if share_emb:
            # tie decoder embedding <-> softmax, and encoder embedding (shared vocab)
            self.generator.weight = self.decoder.emb.emb.weight
            self.encoder.emb.emb.weight = self.decoder.emb.emb.weight

    def encode(self, src, src_mask):
        return self.encoder(src, src_mask)

    def forward(self, src, tgt, src_mask, tgt_mask):
        memory = self.encoder(src, src_mask)
        out = self.decoder(tgt, memory, src_mask, tgt_mask)
        return self.generator(out)
