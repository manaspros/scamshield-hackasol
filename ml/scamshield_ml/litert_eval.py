"""Score a quantized on-device `.litertlm` file with the LiteRT-LM runtime (the library the app moves to).

This measures what the HF bf16 benchmark cannot: accuracy after int4/int8 quantization, and real
prefill/decode speed of the phone runtime, here on the host CPU (x86, XNNPACK). Host CPU speed is NOT phone
speed, but the ratio between models and between prompts carries over; phone numbers come from Phase 4.

Runs in a separate venv (litert-lm and litert-torch pin their own torch):

    uv venv -p 3.12 ml/.cache/convert-venv && VIRTUAL_ENV=ml/.cache/convert-venv uv pip install litert-lm pyyaml
    ml/.cache/convert-venv/bin/python -m scamshield_ml.litert_eval --file gemma3-1b-it-int4.litertlm \
        --system gemma3-1b/fewshot/litertlm-int4 --model gemma3-1b --prompt fewshot

Writes ml/reports/bench/<system>.json in the bench.py format, with measured host-CPU timings in `cost`.
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from scamshield_ml.bench import MAX_NEW_TOKENS, REPORTS, first_line, load_config, slug, summarize
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import PROMPTS
from scamshield_ml.synth_v2 import load_split


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", type=Path, required=True)
    ap.add_argument("--system", required=True, help="report name, e.g. gemma3-1b/fewshot/litertlm-int4")
    ap.add_argument("--model", required=True, help="model key in configs/models.yaml")
    ap.add_argument("--prompt", choices=sorted(PROMPTS), default="fewshot")
    ap.add_argument("--threads", type=int, default=4, help="4 threads matches the model-card CPU setting")
    ap.add_argument("--split", default="test")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--adapter", help="recorded only: which LoRA adapter the file was merged from")
    a = ap.parse_args()

    import litert_lm

    cfg = load_config()
    model = cfg["models"][a.model]
    rows = load_split(a.split)[:a.limit] if a.limit else load_split(a.split)
    engine = litert_lm.Engine(str(a.file), backend=litert_lm.Backend.CPU(thread_count=a.threads),
                              max_num_tokens=1024, enable_benchmark=True)
    gens, ttft, prefill_tps, decode_tps = [], [], [], []
    for r in rows:
        # Raw text like GemmaClassifier.kt (no chat template); the runtime prepends BOS itself.
        s = engine.create_session(apply_prompt_template=False, max_output_tokens=MAX_NEW_TOKENS)
        s.run_prefill([PROMPTS[a.prompt](r["text"])])
        text = s.run_decode().texts[0]
        bi = s.get_benchmark_info()
        s.close()
        gens.append({"prompt_tokens": bi.last_prefill_token_count, "output_tokens": bi.last_decode_token_count,
                     "hit_eos": bi.last_decode_token_count < MAX_NEW_TOKENS, "raw": text})
        ttft.append(bi.time_to_first_token_in_second * 1000)
        prefill_tps.append(bi.last_prefill_tokens_per_second)
        decode_tps.append(bi.last_decode_tokens_per_second)
    total = [t + 1000 * g["output_tokens"] / d for t, g, d in zip(ttft, gens, decode_tps) if d]
    extra = {
        "file": a.file.name, "file_mb_measured": round(a.file.stat().st_size / 1e6),
        "host_cpu_threads": a.threads,
        "host_cpu_ttft_ms_median": round(statistics.median(ttft)),
        "host_cpu_total_ms_median": round(statistics.median(total)) if total else None,
        "host_cpu_prefill_tps_median": round(statistics.median(prefill_tps)),
        "host_cpu_decode_tps_median": round(statistics.median(decode_tps), 1),
    }
    spec = {"model": a.model, "prompt": a.prompt, "template": "raw", "runtime": "litert-lm", "adapter": a.adapter}
    rep = summarize(a.system, spec, model, rows, gens, extra)
    rep["split"] = a.split
    rep["cost"]["file_mb"] = extra["file_mb_measured"]
    REPORTS.mkdir(parents=True, exist_ok=True)
    with (REPORTS / f"{slug(a.system)}.jsonl").open("w", encoding="utf-8") as f:
        for r, g in zip(rows, gens):
            f.write(json.dumps({**r, **g, "pred": parse_output(first_line(g["raw"]))}, ensure_ascii=False) + "\n")
    (REPORTS / f"{slug(a.system)}.json").write_text(json.dumps(rep, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    b, lab = rep["binary"]["overall"], rep["labels"]
    print(f"{a.system}: acc3={lab['accuracy']:.3f} F1={lab['macro_f1']:.3f} R={b['recall']:.3f} FPR={b['fpr']:.3f} "
          f"typeF1={b['macro_f1']:.2f} unparsed={b['unparsed']} ttft={extra['host_cpu_ttft_ms_median']}ms "
          f"total={extra['host_cpu_total_ms_median']}ms")


if __name__ == "__main__":
    main()
