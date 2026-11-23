"""LoRA SFT on the TRAIN split for any model in configs/models.yaml (Gemma 3 270M/1B, Qwen3.5 0.8B, ...).

    uv run --group hf python -m scamshield_ml.finetune --model gemma3-1b            # v2 data, out/lora/gemma3-1b
    uv run --group hf python -m scamshield_ml.finetune --model gemma3-1b --dry-run

Training text is the raw prompt (no chat turns), as GemmaClassifier.kt:127 feeds it via addQueryChunk. With
v2 data every training row appears twice, once with the shipped few-shot prompt and once with the short prompt,
so one adapter can be scored (and later shipped) with either. Loss is on the completion only.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

from scamshield_ml.data import Row, split_rows
from scamshield_ml.prompt import PROMPTS, build_prompt, target_for_row
from scamshield_ml.synth import generate_rows

ML = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ML / "configs" / "lora.yaml"
MODELS = ML / "configs" / "models.yaml"


def format_example(row: Row, prompt: str = "fewshot") -> dict[str, str]:
    """Prompt-completion pair; loss only on the completion."""
    return {"prompt": PROMPTS[prompt](row["text"]), "completion": target_for_row(row)}


def train_rows(limit: int | None = None) -> list[Row]:
    """v1 synthetic train split (kept for the T1.11 tests)."""
    train, _ = split_rows(generate_rows())
    assert all(r["source"] == "synthetic" for r in train), "real rows must stay test-only"
    return train[:limit]


def v2_examples(split: str, prompts: tuple[str, ...] = ("fewshot", "short"), limit: int | None = None) -> list[dict]:
    from scamshield_ml.synth_v2 import load_split

    rows = load_split(split)[:limit] if limit else load_split(split)
    assert all(r["source"] == "synthetic" for r in rows), "real rows must stay test-only"
    return [format_example(r, p) for r in rows for p in prompts]


def resolve(cfg: dict, model_key: str | None) -> dict:
    """Override base_model/output_dir from configs/models.yaml when --model is given."""
    if not model_key:
        return cfg
    model = yaml.safe_load(MODELS.read_text())["models"][model_key]
    out = {**cfg, "base_model": model["hf_id"], "output_dir": f"out/lora/{model_key}"}
    if model.get("lora_targets"):
        out["lora"] = {**cfg["lora"], "target_modules": model["lora_targets"]}
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    ap.add_argument("--model", help="model key in configs/models.yaml")
    ap.add_argument("--data", choices=["v1", "v2"], default="v2")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    cfg = resolve(yaml.safe_load(args.config.read_text()), args.model)
    if args.data == "v1":
        train = [format_example(r) for r in train_rows(args.limit)]
        val = []
    else:
        train = v2_examples("train", limit=args.limit)
        val = v2_examples("val", prompts=("fewshot",), limit=args.limit)
    if args.dry_run:
        print(json.dumps({"config": cfg, "train": len(train), "val": len(val), "first": train[0]},
                         ensure_ascii=False, indent=2))
        return

    # Heavy imports only on the real run.
    import torch
    from datasets import Dataset
    from peft import LoraConfig
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    tok = AutoTokenizer.from_pretrained(cfg["base_model"])
    model = AutoModelForCausalLM.from_pretrained(
        cfg["base_model"], dtype=torch.bfloat16 if cfg["bf16"] else torch.float32
    )
    lora = cfg["lora"]
    peft_cfg = LoraConfig(
        r=lora["r"], lora_alpha=lora["alpha"], lora_dropout=lora["dropout"],
        target_modules=lora["target_modules"], task_type="CAUSAL_LM",
    )
    out = ML / cfg["output_dir"]
    sft = SFTConfig(
        output_dir=str(out), learning_rate=cfg["learning_rate"],
        num_train_epochs=cfg["epochs"], per_device_train_batch_size=cfg["batch_size"],
        max_length=cfg["max_seq_len"], bf16=cfg["bf16"], completion_only_loss=True,
        eval_strategy="epoch" if val else "no", save_strategy="no", logging_steps=20,
        lr_scheduler_type="cosine", warmup_steps=30, report_to=[], seed=0,
    )
    trainer = SFTTrainer(model=model, args=sft, train_dataset=Dataset.from_list(train),
                         eval_dataset=Dataset.from_list(val) if val else None,
                         processing_class=tok, peft_config=peft_cfg)
    trainer.train()
    trainer.save_model(str(out))
    (out / "train_log.json").write_text(json.dumps(trainer.state.log_history, indent=1))


if __name__ == "__main__":
    main()
