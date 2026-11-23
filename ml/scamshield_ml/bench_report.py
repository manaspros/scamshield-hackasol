"""Render ml/reports/bench/*.json into docs/benchmark.md and ml/reports/bench/summary.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from scamshield_ml.bench import REPORTS, load_config

ROOT = Path(__file__).resolve().parents[2]
CAVEAT = (
    "Test rows are synthetic, held out BY TEMPLATE (no test template is trained on), written by the same "
    "authors as the training rows. Fine-tuned scores are therefore optimistic versus real traffic; only real "
    "rows in data/eval/real/ remove that bias. Accuracy is the bf16 HF checkpoint, not the quantized phone file."
)


def load_reports(directory: Path = REPORTS) -> list[dict]:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(directory.glob("*.json")) if p.name != "summary.json"]


def _pct(x: float | None) -> str:
    return "-" if x is None else f"{x:.1%}"


def _num(x: float | None, fmt: str = "{:.0f}") -> str:
    return "-" if x is None else fmt.format(x)


def row_cells(r: dict) -> list[str]:
    b, lab, c = r["binary"]["overall"], r["labels"], r["cost"]
    return [
        f"`{r['system']}`", _pct(lab["accuracy"]), f"{lab['macro_f1']:.2f}", _pct(b["recall"]), _pct(b["fpr"]),
        _pct(lab["scam_missed_rate"]), f"{b['macro_f1']:.2f}", str(b["unparsed"]),
        _num(c["prompt_tokens_mean"]), _num(c["output_tokens_mean"]), _num(c["phone_ms_estimate"]),
        _num(c.get("file_mb")), _num(c.get("ram_mb")),
    ]


def finetune_deltas(reports: list[dict]) -> list[list[str]]:
    """Base (few-shot raw) vs each fine-tuned system of the same model."""
    by = {r["system"]: r for r in reports}
    out = []
    for r in reports:
        if not r.get("adapter"):
            continue
        base = by.get(f"{r['model']}/fewshot/raw")
        if not base:
            continue
        acc = r["labels"]["accuracy"] - base["labels"]["accuracy"]
        f1 = r["labels"]["macro_f1"] - base["labels"]["macro_f1"]
        rec = r["binary"]["overall"]["recall"] - base["binary"]["overall"]["recall"]
        fpr = r["binary"]["overall"]["fpr"] - base["binary"]["overall"]["fpr"]
        typ = r["binary"]["overall"]["macro_f1"] - base["binary"]["overall"]["macro_f1"]
        tok = r["cost"]["prompt_tokens_mean"] / base["cost"]["prompt_tokens_mean"]
        out.append([f"`{base['system']}`", f"`{r['system']}`", f"{acc:+.1%}", f"{f1:+.2f}", f"{rec:+.1%}",
                    f"{fpr:+.1%}", f"{typ:+.2f}", f"{tok:.2f}x"])
    return out


def recommend(reports: list[dict], cfg: dict) -> list[dict]:
    """Draft device-tier picks: best 3-class macro-F1 among systems whose published RAM fits the tier.

    A starting point for the on-device recommender (Phase 3); it must be re-derived from phone measurements.
    """
    tiers = [("A: 3-4 GB RAM", 700), ("B: 4-6 GB RAM", 1400), ("C: 8 GB+ RAM", 4000)]
    picks = []
    for name, budget in tiers:
        fit = []
        for r in reports:
            ram = r["cost"].get("ram_mb")
            file_mb = r["cost"].get("file_mb") or 0
            # Unknown RAM: fall back to ~2x the file size as a rough working-set guess.
            need = ram if ram else 2 * file_mb if file_mb else None
            if need is not None and need <= budget:
                fit.append(r)
        best = max(fit, key=lambda r: (r["labels"]["macro_f1"], -r["cost"]["prompt_tokens_mean"]), default=None)
        picks.append({"tier": name, "ram_budget_mb": budget, "system": best["system"] if best else "rules-only",
                      "macro_f1": best["labels"]["macro_f1"] if best else None})
    return picks


CHARTS = [("accuracy", "Accuracy"), ("false_alarms", "False alarms"), ("scam_type", "Scam type"),
          ("prompt_tokens", "Prompt cost"), ("latency", "Measured time per message")]


def second_test_set(cfg: dict, name: str = "eval_smoke") -> list[str]:
    """Same comparison on data/golden/eval_smoke.csv: written earlier by other people, never used in training."""
    from scamshield_ml.bench_charts import pairs

    rows = pairs(load_reports(REPORTS / name), cfg) if (REPORTS / name).is_dir() else []
    if not rows:
        return []
    out = [f"### Second test set: `data/golden/{name}.csv` (written separately, never trained on)", "",
           "42 hand-written messages (29 SCAM, 2 SUSPICIOUS, 11 SAFE) that were already in the repo, written separately from the v2 templates, so "
           "neither their templates nor their style are in the training data. Nearest-neighbour check: no test row in "
           "either set shares 50% or more of its 4-character chunks with any training row. Expect the fine-tuned numbers "
           "here, not the main table, to be closer to real traffic. Small set: one row is 2.4 points.", "",
           "| Model | Accuracy | False alarms | Scams warned (SCAM or SUSPICIOUS) |", "|---|---|---|---|"]
    for r in rows:
        b, t = r["base"], r["tuned"]
        cell = lambda f: f"{f(b):.1%} → **{f(t):.1%}**"  # noqa: E731
        out.append(f"| {r['name']} | {cell(lambda x: x['labels']['accuracy'])} | "
                   f"{cell(lambda x: x['binary']['overall']['fpr'])} | {cell(lambda x: x['binary']['overall']['recall'])} |")
    out += ["", "Most remaining fine-tuned errors are SCAM answered SUSPICIOUS (still a warning). The two sets draw that "
            "line differently: e.g. 'KYC pending, account will be blocked' is SCAM here but SUSPICIOUS under the v2 "
            "template rules (no direct demand yet).", ""]
    return out


def headline(reports: list[dict], cfg: dict) -> list[str]:
    """Slide-ready section: base (app's prompt) vs fine-tuned (short prompt) per model, plus the charts."""
    from scamshield_ml.bench_charts import pairs

    rows = pairs(reports, cfg)
    if not rows:
        return []
    out = ["## Fine-tuning at a glance", "",
           "Base = the model with the prompt the app ships today (few-shot, raw). Fine-tuned = LoRA on the train split, "
           "short prompt. Charts are regenerated by `uv run --group viz python -m scamshield_ml.bench_charts` "
           "(PNG for slides, SVG to scale).", "",
           "| Model | Accuracy | False alarms | Scams missed | Scam-type F1 | Prompt tokens |", "|---|---|---|---|---|---|"]
    for r in rows:
        b, t = r["base"], r["tuned"]

        def pair(f, pct=True):
            fmt = (lambda v: f"{v:.1%}") if pct else (lambda v: f"{v:.2f}" if v < 10 else f"{v:.0f}")
            return f"{fmt(f(b))} → **{fmt(f(t))}**"

        out.append(f"| {r['name']} | {pair(lambda x: x['labels']['accuracy'])} | "
                   f"{pair(lambda x: x['binary']['overall']['fpr'])} | {pair(lambda x: x['labels']['scam_missed_rate'])} | "
                   f"{pair(lambda x: x['binary']['overall']['macro_f1'], False)} | "
                   f"{pair(lambda x: x['cost']['prompt_tokens_mean'], False)} |")
    out.append("")
    out += second_test_set(cfg)
    for name, alt in CHARTS:
        if (ROOT / "docs" / "benchmark" / f"{name}.png").exists():
            out += [f"![{alt}](benchmark/{name}.png)", ""]
    return out


def render(reports: list[dict], cfg: dict) -> str:
    split = reports[0].get("split", "test") if reports else "test"
    n = reports[0]["rows"] if reports else 0
    out = [
        "# Model benchmark", "",
        "Generated by `uv run --group hf python -m scamshield_ml.bench` then `python -m scamshield_ml.bench_report`.", "",
        f"Data: `data/bench/{split}.csv`, {n} rows (EN/HI/Hinglish, SAFE/SUSPICIOUS/SCAM).", "",
        f"> {CAVEAT}", "",
    ]
    out += headline(reports, cfg)
    out += [
        "## All systems", "",
        "Accuracy and macro-F1 are over the 3 labels. Recall and FPR treat SCAM or SUSPICIOUS as positive. "
        "Scam missed = real SCAM rows answered SAFE or unparseable (no warning shown). Type F1 = scam_type macro-F1 "
        "on scam rows. Phone ms is an ESTIMATE from model-card speeds (prompt/prefill + output/decode), not a "
        "measurement; output tokens count until EOS because MediaPipe has no newline stop.", "",
        "| System | Acc | Macro-F1 | Recall | FPR | Scam missed | Type F1 | Unparsed | Prompt tok | Out tok | Est. phone ms | File MB | RAM MB |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    ordered = sorted(reports, key=lambda r: -r["labels"]["macro_f1"])
    out += ["| " + " | ".join(row_cells(r)) + " |" for r in ordered]
    deltas = finetune_deltas(reports)
    if deltas:
        out += ["", "## What fine-tuning changes", "",
                "Each fine-tuned system against the same model's base few-shot raw prompt (what the app ships today). "
                "Prompt tokens is the ratio of prefill length (lower is faster on a phone).", "",
                "| Base | Fine-tuned | Acc | Macro-F1 | Recall | FPR | Type F1 | Prompt tokens |",
                "|---|---|---|---|---|---|---|---|"]
        out += ["| " + " | ".join(d) + " |" for d in deltas]
    out += ["", "## Per language (recall / FPR)", "", "| System | en | hi | hinglish |", "|---|---|---|---|"]
    for r in ordered:
        pl = r["binary"]["per_language"]
        cells = [f"{_pct(pl[l]['recall'])} / {_pct(pl[l]['fpr'])}" if l in pl else "-" for l in ("en", "hi", "hinglish")]
        out.append(f"| `{r['system']}` | " + " | ".join(cells) + " |")
    out += ["", "## Draft device-tier picks", "",
            "Best macro-F1 whose published peak RAM fits the tier (unknown RAM: 2x file size). Hypothesis only, to be "
            "replaced by phone measurements.", "", "| Tier | RAM budget for the model | Pick | Macro-F1 |", "|---|---|---|---|"]
    for p in recommend(reports, cfg):
        out.append(f"| {p['tier']} | {p['ram_budget_mb']} MB | `{p['system']}` | {_num(p['macro_f1'], '{:.2f}')} |")
    return "\n".join(out) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--md", type=Path, default=ROOT / "docs" / "benchmark.md")
    a = ap.parse_args()
    cfg = load_config()
    reports = load_reports()
    a.md.write_text(render(reports, cfg), encoding="utf-8")
    summary = {"caveat": CAVEAT, "systems": {r["system"]: {"labels": {k: v for k, v in r["labels"].items() if k != "confusion"},
                                                           "binary": r["binary"]["overall"], "cost": r["cost"]} for r in reports},
               "tiers": recommend(reports, cfg)}
    (REPORTS / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(a.md.read_text())


if __name__ == "__main__":
    main()
