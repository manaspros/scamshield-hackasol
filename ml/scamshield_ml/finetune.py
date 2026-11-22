"""Gemma 3 1B LoRA SFT on the TRAIN split. Real run needs torch/transformers/peft/trl (DEP5, GPU box)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

from scamshield_ml.data import Row, split_rows
from scamshield_ml.prompt import build_prompt, target_for_row
from scamshield_ml.synth import generate_rows

DEFAULT_CONFIG = Path(__file__).resolve().parents[1] / "configs" / "lora.yaml"


def format_example(row: Row) -> dict[str, str]:
    """Prompt-completion pair; loss only on the completion.

    On device GemmaClassifier.kt:127 feeds raw `Prompt.build(...)` text via addQueryChunk (no Gemma chat
    turns), so training uses the same raw text, not <start_of_turn> wrapping.
    """
    return {"prompt": build_prompt(row["text"]), "completion": target_for_row(row)}


def train_rows(limit: int | None = None) -> list[Row]:
    train, _ = split_rows(generate_rows())
    assert all(r["source"] == "synthetic" for r in train), "real rows must stay test-only"
    return train[:limit]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    cfg = yaml.safe_load(args.config.read_text())
    examples = [format_example(r) for r in train_rows(args.limit)]
    if args.dry_run:
        print(json.dumps({"config": cfg, "examples": len(examples), "first": examples[0]}, ensure_ascii=False, indent=2))
        return

    # Heavy imports only on the real run.
    import torch
    from datasets import Dataset
    from peft import LoraConfig
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    tok = AutoTokenizer.from_pretrained(cfg["base_model"])
    model = AutoModelForCausalLM.from_pretrained(
        cfg["base_model"], torch_dtype=torch.bfloat16 if cfg["bf16"] else torch.float32
    )
    lora = cfg["lora"]
    peft_cfg = LoraConfig(
        r=lora["r"], lora_alpha=lora["alpha"], lora_dropout=lora["dropout"],
        target_modules=lora["target_modules"], task_type="CAUSAL_LM",
    )
    sft = SFTConfig(
        output_dir=cfg["output_dir"], learning_rate=cfg["learning_rate"],
        num_train_epochs=cfg["epochs"], per_device_train_batch_size=cfg["batch_size"],
        max_length=cfg["max_seq_len"], bf16=cfg["bf16"], completion_only_loss=True,
    )
    trainer = SFTTrainer(model=model, args=sft, train_dataset=Dataset.from_list(examples),
                         processing_class=tok, peft_config=peft_cfg)
    trainer.train()
    trainer.save_model(cfg["output_dir"])


if __name__ == "__main__":
    main()
