# M1 held-out accuracy

Data: synthetic held-out by template (0 real, 26 synthetic rows). Headline: synthetic.
Positive class: SCAM or SUSPICIOUS; UNPARSED counts as negative.

| System | Slice | Precision | Recall | FPR | Type macro-F1 | n | Unparsed |
|---|---|---|---|---|---|---|---|
| rules | overall | 100.0% | 47.8% | 0.0% | 0.31 | 26 | 0 |
| rules | lang=en | 100.0% | 50.0% | 0.0% | 0.40 | 7 | 0 |
| rules | lang=hi | 100.0% | 40.0% | 0.0% | 0.31 | 11 | 0 |
| rules | lang=hinglish | 100.0% | 57.1% | 0.0% | 0.28 | 8 | 0 |
| base_gemma | overall | 100.0% | 91.3% | 0.0% | 0.39 | 26 | 0 |
| base_gemma | lang=en | 100.0% | 100.0% | 0.0% | 0.60 | 7 | 0 |
| base_gemma | lang=hi | 100.0% | 90.0% | 0.0% | 0.21 | 11 | 0 |
| base_gemma | lang=hinglish | 100.0% | 85.7% | 0.0% | 0.44 | 8 | 0 |
| finetuned_gemma | - | future work (not planned for this prototype): no --finetuned path given | | | | | |

## Future work: LoRA fine-tune

Not part of this prototype (user decision 2026-11-23): the shipped model is the base Gemma 3 1B (`google/gemma-3-1b-it`, on device as `gemma3-1b-it-int4.task`). All numbers above are on synthetic data, 0 real rows, so they are not real-world accuracy.

The scripts exist (T1.11, dry-run tested only, never run for real): `ml/scamshield_ml/finetune.py`, `ml/scamshield_ml/convert_task.py`, `ml/configs/lora.yaml`.

Run on a CUDA GPU box, from `ml/` (the box needs torch with CUDA, transformers, peft, trl, datasets, `litert-torch==0.10.0`, `mediapipe==1.2.3`; none are in `ml/pyproject.toml` today, and DEP5 in BUILD_PLAN.md covers them):

```
# 1. LoRA SFT on the train split; reads configs/lora.yaml, writes the adapter to out/lora
uv run python -m scamshield_ml.finetune --config configs/lora.yaml            # add --dry-run / --limit N to preview

# 2. merge adapter -> HF checkpoint -> int4 .tflite -> MediaPipe .task (all three steps in one script)
uv run python -m scamshield_ml.convert_task --adapter-dir out/lora --work-dir out/convert --output out/scamshield-gemma3-1b-int4.task   # add --dry-run to print the plan

# 3. held-out eval of the merged model (run from the repo root; --finetuned takes the merged HF dir)
uv run --project ml --group hf python -m scamshield_ml.eval_heldout --backend hf --finetuned ml/out/convert/merged --rules-preds ml/reports/rules_preds_heldout.jsonl
```

What would change in the app: the model URL constant (owned by T1.15) would point at the new hosted `.task`, and its SHA-256 would be pinned. Where to host the file is a human decision.

Open converter checks (from PROGRESS.md / T1.11, not resolved; check them before relying on the scripts):
- [VERIFY] litert-torch 0.10.0 supports Gemma 3 1B and its example script `litert_torch.generative.examples.gemma3.convert_gemma3_to_tflite` ships inside the wheel.
- [VERIFY] the int4 quantisation path (`--quantize=dynamic_int4_block32`) produces a model the on-device MediaPipe runtime loads.
- [VERIFY] the MediaPipe `.task` bundler import path and `BundleConfig` args (`tokenizer.model`, start token `<bos>`, stop tokens `<eos>`, `<end_of_turn>`) at mediapipe 1.2.3.
- [VERIFY] peft versus the litert-torch `torch<2.15` pin (the hf group here wants torch>=2.15), likely needing separate environments for steps 1-2 and conversion.
