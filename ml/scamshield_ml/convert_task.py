"""Merge LoRA -> HF checkpoint -> int4 LiteRT .tflite -> MediaPipe .task. Heavy imports only on a real run."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml

# Converter: ai-edge-torch was renamed litert-torch (PyPI marks ai-edge-torch DEPRECATED). 0.10.0 = newest
# release >= 7 days before 2026-11-23 (published 2026-10-20). Its Gemma 3 1B example reads HF safetensors.
# [VERIFY] that the example script ships inside the wheel, and that the mediapipe bundler is still
# importable at the pinned mediapipe version (bundler docs are from the 0.10.x tree).
CONVERTER_PKG = "litert-torch==0.10.0"
BUNDLER_PKG = "mediapipe==1.2.3"  # newest >= 7 days old (2026-11-11)
CONVERTER_MODULE = "litert_torch.generative.examples.gemma3.convert_gemma3_to_tflite"
QUANTIZE = "dynamic_int4_block32"
KV_LEN = 1024  # same as on-device setMaxTokens(1024); prompt + answer
CFG = Path(__file__).resolve().parents[1] / "configs" / "lora.yaml"


def plan(adapter_dir: Path, work_dir: Path, output: Path) -> list[dict]:
    base = yaml.safe_load(CFG.read_text())["base_model"]
    merged = work_dir / "merged"
    tflite = work_dir / f"gemma3_1b_scamshield_q4_block32_ekv{KV_LEN}.tflite"
    return [
        {"step": "merge_lora", "base_model": base, "adapter": str(adapter_dir), "out": str(merged), "packages": ["peft", "transformers", "torch"]},
        {"step": "convert_int4", "package": CONVERTER_PKG, "cmd": [
            sys.executable, "-m", CONVERTER_MODULE, f"--quantize={QUANTIZE}", f"--checkpoint_path={merged}",
            f"--output_path={work_dir}", "--output_name_prefix=gemma3_1b_scamshield",
            f"--prefill_seq_lens={KV_LEN}", f"--kv_cache_max_len={KV_LEN}", "--mask_as_input=True"]},
        # No prompt prefix/suffix: device sends raw text (GemmaClassifier.kt:127), same as training.
        {"step": "bundle_task", "package": BUNDLER_PKG, "tflite": str(tflite), "tokenizer": str(merged / "tokenizer.model"),
         "start_token": "<bos>", "stop_tokens": ["<eos>", "<end_of_turn>"], "out": str(output)},
    ]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--adapter-dir", type=Path, default=Path("out/lora"))
    ap.add_argument("--work-dir", type=Path, default=Path("out/convert"))
    ap.add_argument("--output", type=Path, default=Path("out/scamshield-gemma3-1b-int4.task"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    steps = plan(args.adapter_dir, args.work_dir, args.output)
    if args.dry_run:
        print(json.dumps(steps, indent=2))
        return

    merge, convert, bundle = steps
    from peft import AutoPeftModelForCausalLM
    from transformers import AutoTokenizer

    model = AutoPeftModelForCausalLM.from_pretrained(merge["adapter"]).merge_and_unload()
    model.save_pretrained(merge["out"])
    AutoTokenizer.from_pretrained(merge["base_model"]).save_pretrained(merge["out"])  # includes tokenizer.model
    subprocess.run(convert["cmd"], check=True)
    from mediapipe.tasks.python.genai import bundler

    bundler.create_bundle(bundler.BundleConfig(
        tflite_model=bundle["tflite"], tokenizer_model=bundle["tokenizer"], start_token=bundle["start_token"],
        stop_tokens=bundle["stop_tokens"], output_filename=bundle["out"]))


if __name__ == "__main__":
    main()
