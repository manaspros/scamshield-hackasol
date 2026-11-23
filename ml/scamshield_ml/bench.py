"""Multi-model benchmark: accuracy plus cost for every system in configs/models.yaml, on data/bench/<split>.csv.

One JSON per system goes to ml/reports/bench/<system>.json (with per-row predictions in a .jsonl next to it),
so runs never overwrite each other; `python -m scamshield_ml.bench_report` renders docs/benchmark.md.

Runs the HF checkpoint in bf16 on CUDA/MPS/CPU. That is not the phone's quantized file, so accuracy is an
upper bound for the int4/int8 build, and GPU timings say nothing about phones. Cost is reported as tokens
(prefill = prompt tokens, decode = tokens until EOS) and as an ESTIMATED phone latency from model-card speeds.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import yaml

from scamshield_ml.data import LABELS, Row
from scamshield_ml.eval_heldout import POSITIVE, compute_metrics
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import PROMPTS
from scamshield_ml.synth_v2 import load_split

ML = Path(__file__).resolve().parents[1]
CONFIG = ML / "configs" / "models.yaml"
REPORTS = ML / "reports" / "bench"
MAX_NEW_TOKENS = 64  # eval_heldout.py uses the same cap; the JSON line is ~30 tokens


def load_config(path: Path = CONFIG) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def slug(system: str) -> str:
    return system.replace("/", "__")


def label_metrics(rows: list[Row], labels: list[str]) -> dict:
    """3-class view (SAFE/SUSPICIOUS/SCAM): accuracy, macro-F1 and the confusion matrix."""
    names = sorted(LABELS)
    conf = {g: {p: 0 for p in names + ["UNPARSED"]} for g in names}
    for r, p in zip(rows, labels):
        conf[r["label"]][p] += 1
    f1s = []
    for c in names:
        tp = conf[c][c]
        fp = sum(conf[g][c] for g in names if g != c)
        fn = sum(v for p, v in conf[c].items() if p != c)
        f1s.append(2 * tp / (2 * tp + fp + fn) if tp else 0.0)
    acc = sum(conf[c][c] for c in names) / len(rows) if rows else 0.0
    # Severe error: a real SCAM that the model called SAFE or failed to parse (the user gets no warning).
    missed = conf["SCAM"]["SAFE"] + conf["SCAM"]["UNPARSED"]
    n_scam = sum(conf["SCAM"].values())
    return {"accuracy": acc, "macro_f1": sum(f1s) / len(f1s), "scam_missed_rate": missed / n_scam if n_scam else 0.0,
            "confusion": conf}


def make_prompts(rows: list[Row], prompt: str, template: str, tok) -> list[str]:
    build = PROMPTS[prompt]
    texts = [build(r["text"]) for r in rows]
    if template == "raw":
        return texts
    kw = {"enable_thinking": False}  # Qwen3 family; ignored by other templates
    return [tok.apply_chat_template([{"role": "user", "content": t}], tokenize=False, add_generation_prompt=True, **kw)
            for t in texts]


class Generator:
    """Greedy HF generation, batched for accuracy, matching the on-device topK=1 / temperature 0 setting."""

    def __init__(self, hf_id: str, adapter: Path | None = None):
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer

        self.torch = torch
        self.device = "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
        self.tok = AutoTokenizer.from_pretrained(hf_id)
        self.tok.padding_side = "left"
        if self.tok.pad_token is None:
            self.tok.pad_token = self.tok.eos_token
        self.lm = AutoModelForCausalLM.from_pretrained(hf_id, dtype=torch.bfloat16).to(self.device).eval()
        if adapter:
            from peft import PeftModel

            self.lm = PeftModel.from_pretrained(self.lm, str(adapter)).merge_and_unload().eval()
        self.params = sum(p.numel() for p in self.lm.parameters())
        gc = self.lm.generation_config
        eos = gc.eos_token_id if isinstance(gc.eos_token_id, list) else [gc.eos_token_id]
        self.eos = {e for e in eos + [self.tok.eos_token_id] if e is not None}

    def run(self, prompts: list[str], raw: bool, batch: int = 16) -> list[dict]:
        out = []
        # Raw prompts keep the tokenizer's BOS (the .task bundle prepends <bos> too); chat templates already have it.
        add_special = raw
        for i in range(0, len(prompts), batch):
            chunk = prompts[i:i + batch]
            enc = self.tok(chunk, return_tensors="pt", padding=True, add_special_tokens=add_special).to(self.device)
            with self.torch.inference_mode():
                gen = self.lm.generate(**enc, max_new_tokens=MAX_NEW_TOKENS, do_sample=False,
                                       pad_token_id=self.tok.pad_token_id)
            new = gen[:, enc["input_ids"].shape[1]:]
            for j, ids in enumerate(new.tolist()):
                n_prompt = int(enc["attention_mask"][j].sum())
                stop = next((k for k, t in enumerate(ids) if t in self.eos), None)
                kept = ids[:stop] if stop is not None else [t for t in ids if t != self.tok.pad_token_id]
                text = self.tok.decode(kept, skip_special_tokens=True)
                out.append({"prompt_tokens": n_prompt, "output_tokens": len(kept), "hit_eos": stop is not None,
                            "raw": text})
        return out

    def latency_ms(self, prompts: list[str], raw: bool, n: int = 20) -> float:
        """Median single-request wall time on THIS machine (relative only; not a phone number)."""
        times = []
        for p in prompts[:n]:
            t = time.perf_counter()
            self.run([p], raw, batch=1)
            times.append((time.perf_counter() - t) * 1000)
        return statistics.median(times)


def first_line(raw: str) -> str:
    """Few-shot raw prompts often continue with the next 'STATEMENT:' line; the parser reads the first JSON line."""
    return raw.strip().split("\n", 1)[0]


def phone_estimate(device: dict, prompt_tokens: float, output_tokens: float) -> float | None:
    if not device.get("prefill") or not device.get("decode"):
        return None
    return 1000 * (prompt_tokens / device["prefill"] + output_tokens / device["decode"])


def summarize(system: str, spec: dict, model: dict, rows: list[Row], gens: list[dict], extra: dict) -> dict:
    parsed = [parse_output(first_line(g["raw"])) for g in gens]
    preds = [(p["label"], p["scam_type"]) for p in parsed]
    pt = statistics.mean(g["prompt_tokens"] for g in gens)
    ot = statistics.mean(g["output_tokens"] for g in gens)
    # Tokens a phone would decode if generation only stops at EOS (MediaPipe has no newline stop).
    est = phone_estimate(model.get("device", {}), pt, ot)
    return {
        "system": system, **spec, "hf_id": model["hf_id"], "licence": model.get("licence"),
        "rows": len(rows), "binary": compute_metrics(rows, preds), "labels": label_metrics(rows, [p[0] for p in preds]),
        "cost": {"prompt_tokens_mean": pt, "output_tokens_mean": ot,
                 "eos_rate": sum(g["hit_eos"] for g in gens) / len(gens),
                 "phone_ms_estimate": est, "phone_ref": model.get("device", {}).get("ref"),
                 "file_mb": model.get("device", {}).get("file_mb"), "ram_mb": model.get("device", {}).get("ram_mb"),
                 **extra},
    }


def run_system(system: str, cfg: dict, split: str, limit: int | None) -> dict:
    spec = cfg["systems"][system]
    model = cfg["models"][spec["model"]]
    rows = load_split(split)[:limit] if limit else load_split(split)
    adapter = ML / spec["adapter"] if spec.get("adapter") else None
    if adapter and not adapter.is_dir():
        raise SystemExit(f"adapter missing for {system}: {adapter} (run scamshield_ml.finetune first)")
    gen = Generator(model["hf_id"], adapter)
    prompts = make_prompts(rows, spec["prompt"], spec["template"], gen.tok)
    raw = spec["template"] == "raw"
    t = time.perf_counter()
    gens = gen.run(prompts, raw)
    elapsed = time.perf_counter() - t
    extra = {"params_m": round(gen.params / 1e6), "host_batch_s": round(elapsed, 1),
             "host_single_ms_median": round(gen.latency_ms(prompts, raw)), "host_device": gen.device}
    rep = summarize(system, spec, model, rows, gens, extra)
    rep["split"] = split
    REPORTS.mkdir(parents=True, exist_ok=True)
    with (REPORTS / f"{slug(system)}.jsonl").open("w", encoding="utf-8") as f:
        for r, g in zip(rows, gens):
            f.write(json.dumps({**r, **g, "pred": parse_output(first_line(g["raw"]))}, ensure_ascii=False) + "\n")
    (REPORTS / f"{slug(system)}.json").write_text(json.dumps(rep, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return rep


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("systems", nargs="*", help="system keys from configs/models.yaml (default: all base systems)")
    ap.add_argument("--split", default="test", choices=["train", "val", "test"])
    ap.add_argument("--limit", type=int)
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    cfg = load_config()
    if a.list:
        print("\n".join(cfg["systems"]))
        return
    for s in a.systems or [k for k, v in cfg["systems"].items() if not v.get("adapter")]:
        rep = run_system(s, cfg, a.split, a.limit)
        b, lab = rep["binary"]["overall"], rep["labels"]
        print(f"{s}: P={b['precision']:.3f} R={b['recall']:.3f} FPR={b['fpr']:.3f} acc3={lab['accuracy']:.3f} "
              f"typeF1={b['macro_f1']:.2f} unparsed={b['unparsed']} prompt_tok={rep['cost']['prompt_tokens_mean']:.0f} "
              f"out_tok={rep['cost']['output_tokens_mean']:.0f}", flush=True)


if __name__ == "__main__":
    main()
