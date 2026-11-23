"""Benchmark dataset v2: hand-written EN/HI/Hinglish templates (data/synth_v2/*.json) expanded with slot fills.

The v1 generator (synth.py) has 132 rows, no SUSPICIOUS rows and 12 SAFE rows, which is too small to rank
models. v2 has 780 templates (per language: 10 scam types x (12 SCAM + 6 SUSPICIOUS) + 80 SAFE hard
negatives) and splits train/val/test BY TEMPLATE, stratified by (lang, label, scam_type), so no test template
is ever trained on. Real rows (data/eval/real/*.csv) always go to test.

Caveat that every report must carry: train and test come from the same writers and slot lists, so a
fine-tuned model's test score is optimistic versus real traffic. Only real rows can remove that bias.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import re
from pathlib import Path

from scamshield_ml.data import COLUMNS, LANGUAGES, SCAM_TYPES, Row, load_real_rows, load_rows, validate_row

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_DIR = ROOT / "data" / "synth_v2"
OUT_DIR = ROOT / "data" / "bench"
SPLITS = ("train", "val", "test")
FRACTIONS = {"train": 0.7, "val": 0.1, "test": 0.2}
FILLS_PER_TEMPLATE = 3

# Fictitious or generic values only (no real phone numbers, URLs or UPI handles).
SLOTS = {
    "bank": ["SBI", "HDFC Bank", "ICICI Bank", "Axis Bank", "PNB", "Bank of Baroda", "Canara Bank", "Kotak Bank"],
    "otp": ["482913", "190375", "736204", "551890", "908112", "317645"],
    "amount": ["499", "1,250", "2,999", "5,000", "9,800", "15,000", "49,999", "1,20,000"],
    "track": ["IN48D2931", "BD7781220", "DTX902114", "EK3307719"],
    "domain": ["kyc-update-help.in.net", "parcel-release.co", "quickloan-apk.top", "verify-acct.info",
               "india-post-track.xyz", "rewards-claim.online"],
    "upi": ["refund.help@okaxis", "pay.verify@ybl", "rk.sharma21@paytm", "support.desk@ibl"],
    "name": ["Ramesh", "Sunita", "Rahul", "Priya", "Amit", "Pooja", "Vikram", "Neha"],
    "company": ["Bluedart", "Delhivery", "Amazon", "Flipkart", "TCS", "Infosys", "Reliance Jio", "Airtel"],
    "city": ["Mumbai", "Delhi", "Lucknow", "Patna", "Jaipur", "Kolkata", "Hyderabad", "Indore"],
    "phone": ["98XXXXXX12", "70XXXXXX45", "88XXXXXX03", "91XXXXXX77"],
    "app": ["AnyDesk", "TeamViewer", "QuickSupport", "RupeeFast", "CashNow"],
}
_AMOUNT = re.compile(r"(₹|Rs\.?\s?|INR\s?)?\{amount\}(\s?(रुपये|रुपए|rupees|rupaye|rs))?", re.I)


def _fill(text: str, rng: random.Random) -> str:
    def amount(m: re.Match) -> str:
        n = rng.choice(SLOTS["amount"])
        # Keep the template's own currency word; otherwise prefix the rupee sign.
        return (m.group(1) or "") + n + (m.group(2) or "") if (m.group(1) or m.group(2)) else "₹" + n

    text = _AMOUNT.sub(amount, text)
    return re.sub(r"\{(\w+)\}", lambda m: rng.choice(SLOTS[m.group(1)]), text)


def _asr(text: str) -> str:
    """Live Caption style: lowercase Latin letters, punctuation dropped."""
    return re.sub(r"\s+", " ", re.sub(r"[,.!?;:\"'।]", " ", text.lower())).strip()


def load_templates(directory: Path = TEMPLATE_DIR) -> list[dict]:
    """Flatten the JSON files to [{template_id, text, label, lang, scam_type, channel}]."""
    out = []
    for lang in sorted(LANGUAGES):
        doc = json.loads((directory / f"{lang}.json").read_text(encoding="utf-8"))
        assert doc["lang"] == lang and set(doc["scam"]) == SCAM_TYPES, f"bad template file for {lang}"
        for scam_type in sorted(doc["scam"]):
            for i, e in enumerate(doc["scam"][scam_type]):
                out.append({"template_id": f"v2_{lang}_{scam_type.lower()}_{i:02d}", "text": e["text"],
                            "label": e["label"], "lang": lang, "scam_type": scam_type, "channel": e["channel"]})
        for i, e in enumerate(doc["safe"]):
            out.append({"template_id": f"v2_{lang}_safe_{e['category']}_{i:02d}", "text": e["text"],
                        "label": "SAFE", "lang": lang, "scam_type": "", "channel": e["channel"]})
    return out


def assign_splits(templates: list[dict], seed: int = 0) -> dict[str, str]:
    """template_id -> split, stratified by (lang, label, scam_type) so every split covers every type."""
    groups: dict[tuple, list[str]] = {}
    for t in templates:
        groups.setdefault((t["lang"], t["label"], t["scam_type"]), []).append(t["template_id"])
    rng = random.Random(seed)
    out = {}
    for key in sorted(groups):
        ids = sorted(groups[key])
        rng.shuffle(ids)
        n = len(ids)
        n_test = max(1, round(n * FRACTIONS["test"]))
        n_val = max(1, round(n * FRACTIONS["val"])) if n - n_test > 2 else 0
        for i, tid in enumerate(ids):
            out[tid] = "test" if i < n_test else "val" if i < n_test + n_val else "train"
    return out


def expand(templates: list[dict], fills: int = FILLS_PER_TEMPLATE, seed: int = 0) -> list[tuple[Row, str]]:
    """(row, template_id) pairs; templates without slots give one row (plus an ASR variant for calls)."""
    rng = random.Random(seed)
    rows: list[tuple[Row, str]] = []
    for t in templates:
        texts = {_fill(t["text"], rng) for _ in range(fills)} if "{" in t["text"] else {t["text"]}
        texts = sorted(texts)
        if t["channel"] == "call":
            texts.append(_asr(texts[-1]))  # one caption-style variant per spoken template
        for text in dict.fromkeys(texts):
            rows.append((validate_row({"text": text, "label": t["label"], "lang": t["lang"],
                                       "scam_type": t["scam_type"], "template_id": t["template_id"],
                                       "source": "synthetic"}), t["template_id"]))
    return rows


def build(seed: int = 0, root: Path = ROOT) -> dict[str, list[Row]]:
    templates = load_templates(root / "data" / "synth_v2")
    split_of = assign_splits(templates, seed)
    out: dict[str, list[Row]] = {s: [] for s in SPLITS}
    for row, tid in expand(templates, seed=seed):
        out[split_of[tid]].append(row)
    out["test"] += load_real_rows(root)
    return out


def load_split(name: str, root: Path = ROOT) -> list[Row]:
    """Read a committed split (data/bench/<name>.csv)."""
    return load_rows(root / "data" / "bench" / f"{name}.csv")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", type=Path, default=OUT_DIR)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    a.out_dir.mkdir(parents=True, exist_ok=True)
    splits = build(a.seed)
    for name, rows in splits.items():
        with (a.out_dir / f"{name}.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=COLUMNS)
            w.writeheader()
            w.writerows(rows)
        by = {}
        for r in rows:
            by[r["label"]] = by.get(r["label"], 0) + 1
        print(name, len(rows), dict(sorted(by.items())))


if __name__ == "__main__":
    main()
