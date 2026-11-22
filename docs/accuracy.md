# M1 held-out accuracy

> STUB RUN: NOT MEASURED. Gemma rows come from a keyword stub, not a model.

Data: synthetic held-out by template (0 real, 26 synthetic rows). Headline: synthetic.
Positive class: SCAM or SUSPICIOUS; UNPARSED counts as negative.

| System | Slice | Precision | Recall | FPR | Type macro-F1 | n | Unparsed |
|---|---|---|---|---|---|---|---|
| rules | - | not run: rules_preds.jsonl missing | | | | | |
| base_gemma | overall | 100.0% | 30.4% | 0.0% | 0.05 | 26 | 0 |
| base_gemma | lang=en | 100.0% | 33.3% | 0.0% | 0.00 | 7 | 0 |
| base_gemma | lang=hi | 100.0% | 20.0% | 0.0% | 0.10 | 11 | 0 |
| base_gemma | lang=hinglish | 100.0% | 42.9% | 0.0% | 0.08 | 8 | 0 |
| finetuned_gemma | - | not run: no --finetuned path given | | | | | |
