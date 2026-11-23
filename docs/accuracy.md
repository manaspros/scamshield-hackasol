# M1 held-out accuracy

> STUB RUN: NOT MEASURED. Gemma rows come from a keyword stub, not a model.

Data: synthetic held-out by template (0 real, 65 synthetic rows). Headline: synthetic.
Positive class: SCAM or SUSPICIOUS; UNPARSED counts as negative.

| System | Slice | Precision | Recall | FPR | Type macro-F1 | n | Unparsed |
|---|---|---|---|---|---|---|---|
| rules | overall | 100.0% | 61.4% | 0.0% | 0.45 | 65 | 0 |
| rules | lang=en | 100.0% | 50.0% | 0.0% | 0.32 | 22 | 0 |
| rules | lang=hi | 100.0% | 61.1% | 0.0% | 0.41 | 24 | 0 |
| rules | lang=hinglish | 100.0% | 80.0% | 0.0% | 0.67 | 19 | 0 |
| base_gemma | overall | 90.9% | 22.7% | 4.8% | 0.00 | 65 | 0 |
| base_gemma | lang=en | 100.0% | 25.0% | 0.0% | 0.00 | 22 | 0 |
| base_gemma | lang=hi | 100.0% | 16.7% | 0.0% | 0.00 | 24 | 0 |
| base_gemma | lang=hinglish | 75.0% | 30.0% | 11.1% | 0.00 | 19 | 0 |
| finetuned_gemma | - | future work (not planned for this prototype): no --finetuned path given | | | | | |

## How to read this table (round 3 coverage)

- All data is 100% synthetic: 65 rows (44 SCAM, 21 SAFE; en 22, hi 24, hinglish 19), template-held-out, 0 real rows. These are not real-world accuracy figures, and with n this small one row moves recall by about 2 points.
- The `rules` rows are the rules-only path (`RuleScorer` through `ml/reports/rules_preds`), not the shipped fusion. The `base_gemma` rows come from a keyword stub, so they say nothing about the on-device model and should be ignored.
- The held-out split now includes the round-3 types: SIM_SWAP 3, FAMILY_EMERGENCY 3, PHISHING_LINK 3, CUSTOMER_CARE 2, UPI_COLLECT 2, LOTTERY 2, SEXTORTION 1. ELECTRICITY_BILL has 0 held-out rows in this split, so its type score is not measured here.
- Fusion behaviour (not shown in the rules-only rows): when Gemma says SAFE and the rule score is 0.40 to 0.85, fusion raises the verdict to SUSPICIOUS and never to SCAM; SCAM from rules alone needs a score of 0.85 or more. Rules can only raise a verdict, never lower it.
- Before vs after (rules-only, held-out): before 26 rows, precision 100.0%, recall 47.8%, FPR 0.0%, type macro-F1 0.31. After 65 rows, precision 100.0%, recall 61.4%, FPR 0.0%, type macro-F1 0.45. The two splits differ, so this is not a like-for-like comparison. A Hindi safe customer-care message used to match the "customs" authority keyword (a false positive); the keyword is now `कस्टम(?!र)`, so it no longer does.
- `data/golden/eval_smoke.csv` (107 rows, rules-only): precision 98.5%, recall 92.9%, FPR 2.7%. The 65 `r3_` rows score 100% recall with 0 false positives, but the rules were written against those templates, so treat that as a smoke check rather than accuracy.

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
