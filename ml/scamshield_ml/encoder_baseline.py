"""Reference point: a small multilingual encoder (MuRIL) fine-tuned as a plain classifier.

It predicts one of 21 joint classes (SAFE, SCAM:<type>, SUSPICIOUS:<type>) with no text generation, so it cannot
give a reason line and would need its own runtime on the phone (TFLite/ONNX). It answers one question for the
benchmark: how much accuracy a tiny classifier gets compared with the generative models.

    uv run --group hf python -m scamshield_ml.encoder_baseline [--model google/muril-base-cased]

Writes ml/reports/bench/<system>.json in the same format as bench.py.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time

from scamshield_ml.bench import REPORTS, label_metrics, slug
from scamshield_ml.data import SCAM_TYPES
from scamshield_ml.eval_heldout import compute_metrics
from scamshield_ml.synth_v2 import load_split

CLASSES = ["SAFE"] + [f"{lab}:{t}" for lab in ("SCAM", "SUSPICIOUS") for t in sorted(SCAM_TYPES)]


def to_class(row) -> int:
    return 0 if row["label"] == "SAFE" else CLASSES.index(f"{row['label']}:{row['scam_type']}")


def from_class(i: int) -> tuple[str, str | None]:
    c = CLASSES[i]
    return ("SAFE", None) if c == "SAFE" else tuple(c.split(":"))  # type: ignore[return-value]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", default="google/muril-base-cased")
    ap.add_argument("--epochs", type=int, default=15)
    ap.add_argument("--lr", type=float, default=2e-5)
    a = ap.parse_args()

    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    torch.manual_seed(0)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    tok = AutoTokenizer.from_pretrained(a.model)
    model = AutoModelForSequenceClassification.from_pretrained(a.model, num_labels=len(CLASSES)).to(dev)
    train, val, test = load_split("train"), load_split("val"), load_split("test")

    def batches(rows, bs, shuffle):
        idx = torch.randperm(len(rows)).tolist() if shuffle else list(range(len(rows)))
        for i in range(0, len(idx), bs):
            chunk = [rows[j] for j in idx[i:i + bs]]
            enc = tok([r["text"] for r in chunk], padding=True, truncation=True, max_length=128, return_tensors="pt")
            yield enc.to(dev), torch.tensor([to_class(r) for r in chunk], device=dev)

    def predict(rows):
        model.eval()
        out = []
        with torch.inference_mode():
            for enc, _ in batches(rows, 64, False):
                out += model(**enc).logits.argmax(-1).tolist()
        return out

    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01)
    steps = a.epochs * ((len(train) + 15) // 16)
    warm = steps // 10
    sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min((s + 1) / warm, max(0.0, (steps - s) / (steps - warm))))
    best, best_state = -1.0, None
    for epoch in range(a.epochs):
        model.train()
        losses = []
        for enc, y in batches(train, 16, True):
            loss = torch.nn.functional.cross_entropy(model(**enc).logits, y)
            losses.append(loss.item())
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            opt.zero_grad()
        vp = predict(val)
        f1 = label_metrics(val, [from_class(i)[0] for i in vp])["macro_f1"]
        print(f"epoch {epoch + 1}: loss {sum(losses) / len(losses):.3f} val label macro-F1 {f1:.3f}", flush=True)
        if f1 > best:
            best, best_state = f1, {k: v.detach().clone() for k, v in model.state_dict().items()}
    model.load_state_dict(best_state)

    preds = [from_class(i) for i in predict(test)]
    lens = [len(tok(r["text"])["input_ids"]) for r in test]
    times = []
    model.eval()
    with torch.inference_mode():
        for r in test[:50]:
            enc = tok(r["text"], return_tensors="pt").to(dev)
            t = time.perf_counter()
            model(**enc)
            times.append((time.perf_counter() - t) * 1000)
    params = sum(p.numel() for p in model.parameters())
    system = f"{a.model.split('/')[-1]}/classifier"
    rep = {
        "system": system, "model": a.model.split("/")[-1], "prompt": "none", "template": "classifier",
        "hf_id": a.model, "licence": "Apache-2.0", "rows": len(test), "split": "test",
        "binary": compute_metrics(test, preds), "labels": label_metrics(test, [p[0] for p in preds]),
        "cost": {"prompt_tokens_mean": statistics.mean(lens), "output_tokens_mean": 0, "eos_rate": 1.0,
                 "phone_ms_estimate": None, "phone_ref": "no phone data; one forward pass, no decode",
                 # int8 weights are ~1 byte per parameter; an estimate, not a built file.
                 "file_mb": round(params / 1e6), "ram_mb": None, "params_m": round(params / 1e6),
                 "host_single_ms_median": round(statistics.median(times)), "host_device": dev},
        "val_macro_f1": best,
    }
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / f"{slug(system)}.json").write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
    b = rep["binary"]["overall"]
    print(f"{system}: acc3={rep['labels']['accuracy']:.3f} R={b['recall']:.3f} FPR={b['fpr']:.3f} typeF1={b['macro_f1']:.2f}")


if __name__ == "__main__":
    main()
