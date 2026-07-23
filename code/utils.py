"""Utility functions: masks, loss, scheduler, helpers."""
import math
import torch
import torch.nn as nn
import torch.nn.functional as F


# --------------------------------------------------------------------------- #
# Mask builders
# --------------------------------------------------------------------------- #
def make_src_mask(src, pad_id):
    """src: [B, S] -> padding mask [B, 1, 1, S] (True = keep)."""
    return (src != pad_id).unsqueeze(1).unsqueeze(2)


def make_tgt_mask(tgt, pad_id):
    """tgt: [B, T] -> causal+padding mask [B, 1, T, T] (True = keep)."""
    B, T = tgt.shape
    device = tgt.device
    # upper-triangular = future positions (to be masked)
    future = torch.triu(torch.ones(T, T, device=device), diagonal=1).bool()
    pad = (tgt != pad_id).unsqueeze(1)          # [B, 1, T]
    mask = pad & ~future                        # broadcast -> [B, 1, T, T]
    return mask


# --------------------------------------------------------------------------- #
# Label Smoothing Cross-Entropy (paper section 5.4)
# --------------------------------------------------------------------------- #
class LabelSmoothingLoss(nn.Module):
    """KL-divergence label smoothing. Smoothed value = smoothing/(V-2),
    correct class = 1 - smoothing, pad class = 0 and excluded from loss."""

    def __init__(self, vocab_size, pad_id, smoothing=0.1):
        super().__init__()
        self.vocab = vocab_size
        self.pad = pad_id
        self.smoothing = smoothing
        self.crit = nn.KLDivLoss(reduction="sum")

    def forward(self, x, target):
        # x: [N, V] (raw logits), target: [N]
        x = F.log_softmax(x, dim=-1)
        true_dist = x.new_zeros(x.size())
        true_dist.fill_(self.smoothing / (self.vocab - 2))
        true_dist.scatter_(1, target.unsqueeze(1), 1.0 - self.smoothing)
        true_dist[:, self.pad] = 0
        mask = (target != self.pad)
        loss = self.crit(x, true_dist) / mask.sum().item()
        return loss


# --------------------------------------------------------------------------- #
# Noam learning-rate scheduler (paper section 5.3)
#   lr = factor * d_model^-0.5 * min(step^-0.5, step * warmup^-1.5)
# --------------------------------------------------------------------------- #
class NoamScheduler:
    def __init__(self, optimizer, d_model, warmup, factor=1.0):
        self.opt = optimizer
        self.d_model = d_model
        self.warmup = warmup
        self.factor = factor
        self._step = 0

    def step(self):
        self._step += 1
        lr = self.factor * (self.d_model ** -0.5) * min(
            self._step ** -0.5, self._step * (self.warmup ** -1.5))
        for g in self.opt.param_groups:
            g["lr"] = lr
        return lr

    def state_dict(self):
        return {"step": self._step}

    def load_state_dict(self, s):
        self._step = s["step"]


def count_params(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)
