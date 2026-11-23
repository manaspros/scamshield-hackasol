"""Fine-tuned model -> on-device `.litertlm`: merge the LoRA adapter, then run Google's `litert-torch export_hf`.

    uv run --group hf python -m scamshield_ml.export_litertlm --model qwen3.5-0.8b
    # -> ml/out/merged/<model>/ (bf16 safetensors), ml/out/litertlm/<model>-ft/model.litertlm

Replaces convert_task.py's MediaPipe `.task` path (Gemma 3 1B only, never verified) with the route Google now
documents for LiteRT-LM: https://developers.google.com/edge/litert-lm/tutorials/convert-and-run
The exporter needs its own venv (litert-torch pins torch); pass it with --converter.

Verified on 2026-11-23 for Qwen3.5-0.8B: the exported file loads and scores with litert-lm-nightly
0.20.0.dev20261122. litert-lm 0.19.2 cannot run Qwen3.5's gated-delta layers on CPU (neither ours nor the
official litert-community file), so the app needs LiteRT-LM >= 0.20 for Qwen3.5.
"""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

import yaml

ML = Path(__file__).resolve().parents[1]
CONVERTER = ML / ".cache" / "convert-venv" / "bin" / "litert-torch"
# The app never sends more than 1024 tokens (GemmaClassifier maxTokens); the exporter default (32k) wastes KV memory.
CACHE_LENGTH = 2048


def plan(model_key: str, converter: Path = CONVERTER, quantization: str | None = None) -> dict:
    hf_id = yaml.safe_load((ML / "configs" / "models.yaml").read_text())["models"][model_key]["hf_id"]
    merged = ML / "out" / "merged" / model_key
    out = ML / "out" / "litertlm" / f"{model_key}-ft"
    cmd = [str(converter), "export_hf", str(merged), "--output_dir", str(out), f"--cache_length={CACHE_LENGTH}"]
    if quantization:
        cmd.append(f"--quantization_recipe={quantization}")
    return {"hf_id": hf_id, "adapter": ML / "out" / "lora" / model_key, "merged": merged, "out": out, "export": cmd}


def merge(hf_id: str, adapter: Path, merged: Path) -> None:
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    model = AutoModelForCausalLM.from_pretrained(hf_id, dtype=torch.bfloat16)
    model = PeftModel.from_pretrained(model, str(adapter)).merge_and_unload()
    model.save_pretrained(merged)
    AutoTokenizer.from_pretrained(hf_id).save_pretrained(merged)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--converter", type=Path, default=CONVERTER)
    ap.add_argument("--quantization", help="litert-torch recipe; default is the exporter's (dynamic_wi8_afp32)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    p = plan(a.model, a.converter, a.quantization)
    if a.dry_run:
        print(p)
        return
    if not p["adapter"].is_dir():
        raise SystemExit(f"no adapter at {p['adapter']}: run scamshield_ml.finetune --model {a.model}")
    merge(p["hf_id"], p["adapter"], p["merged"])
    # CPU-only export; keeps the GPU free and matches the documented flow.
    subprocess.run(p["export"], check=True, env={**os.environ, "CUDA_VISIBLE_DEVICES": ""})
    print(p["out"] / "model.litertlm")


if __name__ == "__main__":
    main()
