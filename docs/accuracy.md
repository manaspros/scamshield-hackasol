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
| finetuned_gemma | - | not run: no --finetuned path given | | | | | |
