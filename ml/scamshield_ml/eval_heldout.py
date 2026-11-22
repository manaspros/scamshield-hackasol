"""Device-free held-out eval (T1.13): rules-only, base Gemma, fine-tuned Gemma on one held-out set."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

from scamshield_ml.data import COLUMNS, LANGUAGES, Row, load_real_rows, split_rows
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import build_prompt
from scamshield_ml.synth import generate_rows

ROOT = Path(__file__).resolve().parents[2]
POSITIVE = {"SCAM", "SUSPICIOUS"}
MODEL_ID = "google/gemma-3-1b-it"
Pred = tuple[str, str | None]  # (label, scam_type)


def heldout_rows(root: Path = ROOT, limit: int | None = None) -> list[Row]:
    _, test = split_rows(generate_rows() + load_real_rows(root))
    return test[:limit] if limit else test


def _f1(gold: list[str | None], pred: list[str | None]) -> float:
    classes = sorted({g for g in gold if g})
    scores = []
    for c in classes:
        tp = sum(g == c and p == c for g, p in zip(gold, pred))
        fp = sum(g != c and p == c for g, p in zip(gold, pred))
        fn = sum(g == c and p != c for g, p in zip(gold, pred))
        scores.append(2 * tp / (2 * tp + fp + fn) if tp else 0.0)
    return sum(scores) / len(scores) if scores else 0.0


def _node(rows: list[Row], preds: list[Pred]) -> dict:
    tp = fp = fn = tn = unparsed = 0
    for r, (label, _) in zip(rows, preds):
        gold, pos = r["label"] in POSITIVE, label in POSITIVE
        tp += gold and pos
        fn += gold and not pos
        fp += (not gold) and pos
        tn += (not gold) and not pos
        unparsed += label == "UNPARSED"
    scam = [(r, p) for r, p in zip(rows, preds) if r["label"] in POSITIVE]
    return {
        "precision": tp / (tp + fp) if tp + fp else 0.0,
        "recall": tp / (tp + fn) if tp + fn else 0.0,
        "fpr": fp / (fp + tn) if fp + tn else 0.0,
        "macro_f1": _f1([r["scam_type"] for r, _ in scam], [p[1] if p[0] in POSITIVE else None for _, p in scam]),
        "counts": {"n": len(rows), "tp": tp, "fp": fp, "fn": fn, "tn": tn},
        "unparsed": unparsed,
    }


def compute_metrics(rows: list[Row], preds: list[Pred]) -> dict:
    """Overall + per-language. Positive = SCAM or SUSPICIOUS; UNPARSED counts as negative."""
    per_lang = {}
    for lang in sorted(LANGUAGES):
        idx = [i for i, r in enumerate(rows) if r["lang"] == lang]
        if idx:
            per_lang[lang] = _node([rows[i] for i in idx], [preds[i] for i in idx])
    return {"overall": _node(rows, preds), "per_language": per_lang}


def stub_predict(prompts: list[str], rows: list[Row]) -> list[str]:
    """Deterministic keyword fake, tests only; raw output goes through the real parser."""
    hit = re.compile(r"otp|kyc|arrest|ओटीपी", re.I)
    return ['{"label":"SCAM","type":"OTP"}' if hit.search(r["text"]) else '{"label":"SAFE"}' for r in rows]


def hf_predict(model: str, prompts: list[str]) -> list[str]:
    """Matches GemmaClassifier.kt: raw prompt (no chat template, line 127), greedy (lines 122-123)."""
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    tok = AutoTokenizer.from_pretrained(model)
    lm = AutoModelForCausalLM.from_pretrained(model, torch_dtype=torch.bfloat16).to(device)
    out = []
    for p in prompts:
        ids = tok(p, return_tensors="pt").to(device)
        gen = lm.generate(**ids, max_new_tokens=64, do_sample=False)
        out.append(tok.decode(gen[0][ids["input_ids"].shape[1]:], skip_special_tokens=True))
    return out


def _parse(raws: list[str]) -> list[Pred]:
    parsed = [parse_output(r) for r in raws]
    return [(p["label"], p["scam_type"]) for p in parsed]


def load_rules_preds(path: Path, rows: list[Row]) -> dict:
    if not path.is_file():
        return {"status": "not run", "reason": "rules_preds.jsonl missing"}
    by_text = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            d = json.loads(line)
            by_text[d["text"]] = (str(d["label"]).upper(), d.get("scam_type") or d.get("scamType") or d.get("type"))
    matched = [(r, by_text[r["text"]]) for r in rows if r["text"] in by_text]
    if not matched:
        return {"status": "not run", "reason": "no rows matched held-out texts"}
    m = compute_metrics([r for r, _ in matched], [p for _, p in matched])
    return {"coverage": len(matched) / len(rows), "matched": len(matched), **m}


def llm_system(backend: str, model: str, rows: list[Row]) -> dict:
    prompts = [build_prompt(r["text"]) for r in rows]
    raws = stub_predict(prompts, rows) if backend == "stub" else hf_predict(model, prompts)
    return {"backend": backend, "model": model if backend == "hf" else "stub", **compute_metrics(rows, _parse(raws))}


def build_report(rows: list[Row], backend: str, rules_path: Path, finetuned: str | None) -> dict:
    real = sum(r["source"] == "real" for r in rows)
    headline = "real" if real >= 100 else "synthetic"
    return {
        "data": {
            "real_rows": real,
            "synthetic_rows": len(rows) - real,
            "headline": headline,
            "label": "real held-out" if headline == "real" else "synthetic held-out by template",
        },
        "positive_class": "SCAM or SUSPICIOUS; UNPARSED counts as negative",
        "systems": {
            "rules": load_rules_preds(rules_path, rows),
            "base_gemma": llm_system(backend, MODEL_ID, rows),
            "finetuned_gemma": llm_system(backend, finetuned, rows)
            if finetuned
            else {"status": "not run", "reason": "no --finetuned path given"},
        },
    }


def render_md(rep: dict) -> str:
    d = rep["data"]
    stub = any(s.get("backend") == "stub" for s in rep["systems"].values())
    out = ["# M1 held-out accuracy", ""]
    if stub:
        out += ["> STUB RUN: NOT MEASURED. Gemma rows come from a keyword stub, not a model.", ""]
    out += [
        f"Data: {d['label']} ({d['real_rows']} real, {d['synthetic_rows']} synthetic rows). Headline: {d['headline']}.",
        f"Positive class: {rep['positive_class']}.", "",
        "| System | Slice | Precision | Recall | FPR | Type macro-F1 | n | Unparsed |", "|---|---|---|---|---|---|---|---|",
    ]
    for name, s in rep["systems"].items():
        if "overall" not in s:
            out.append(f"| {name} | - | not run: {s['reason']} | | | | | |")
            continue
        slices = {"overall": s["overall"], **{f"lang={k}": v for k, v in s["per_language"].items()}}
        for sl, m in slices.items():
            out.append(
                f"| {name} | {sl} | {m['precision']:.1%} | {m['recall']:.1%} | {m['fpr']:.1%} | "
                f"{m['macro_f1']:.2f} | {m['counts']['n']} | {m['unparsed']} |"
            )
    return "\n".join(out) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["stub", "hf"], required=True)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--rules-preds", default="android/app/build/rules_preds.jsonl")
    ap.add_argument("--finetuned")
    ap.add_argument("--out", default="ml/reports/m1.json")
    ap.add_argument("--md", default="docs/accuracy.md")
    a = ap.parse_args()
    rows = heldout_rows(ROOT, a.limit)
    rep = build_report(rows, a.backend, ROOT / a.rules_preds, a.finetuned)
    out, md, csv_path = ROOT / a.out, ROOT / a.md, ROOT / "ml/reports/heldout.csv"
    for p in (out, md, csv_path):
        p.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rep, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    md.write_text(render_md(rep), encoding="utf-8")
    # Same rows for the Kotlin rules exporter, so rules-only scores the same held-out set.
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(rows)
    print(render_md(rep))


if __name__ == "__main__":
    main()
