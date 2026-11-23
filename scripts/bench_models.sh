#!/usr/bin/env bash
# Reproduce docs/benchmark.md: dataset -> base models -> LoRA fine-tunes -> .litertlm export -> quantized eval.
# Needs a CUDA GPU (tested on an RTX 5090, ~1 h end to end) and `hf auth login` with the Gemma licence accepted
# for the google/gemma-3-* models. Usage: scripts/bench_models.sh [model ...]   (default: every fine-tune model)
set -euo pipefail
cd "$(dirname "$0")/../ml"
export HF_HOME="${HF_HOME:-$PWD/.cache/hf}"
MODELS=("${@:-qwen3.5-0.8b gemma3-270m gemma3-1b gemma4-e2b}")
read -r -a MODELS <<<"${MODELS[*]}"

# Separate venvs: litert-torch (exporter) and litert-lm-nightly (runtime; 0.19.2 cannot run Qwen3.5 on CPU).
[ -x .cache/convert-venv/bin/litert-torch ] || { uv venv -q -p 3.12 .cache/convert-venv;
  VIRTUAL_ENV=.cache/convert-venv uv pip install -q litert-torch-nightly; }
[ -x .cache/lm-nightly-venv/bin/python ] || { uv venv -q -p 3.12 .cache/lm-nightly-venv;
  VIRTUAL_ENV=.cache/lm-nightly-venv uv pip install -q litert-lm-nightly pyyaml; }

uv run python -m scamshield_ml.synth_v2                       # data/bench/{train,val,test}.csv
uv run --group hf python -m scamshield_ml.bench               # every base system in configs/models.yaml
uv run --group hf python -m scamshield_ml.encoder_baseline --model distilbert/distilbert-base-multilingual-cased --epochs 6

for m in "${MODELS[@]}"; do
  uv run --group hf python -m scamshield_ml.finetune --model "$m"
  uv run --group hf python -m scamshield_ml.bench "$m+ft/fewshot/raw" "$m+ft/short/raw"
  uv run --group hf python -m scamshield_ml.export_litertlm --model "$m"
  .cache/lm-nightly-venv/bin/python -m scamshield_ml.litert_eval --file "out/litertlm/$m-ft/model.litertlm" \
    --system "$m+ft/short/litertlm-int8" --model "$m" --prompt short --adapter "out/lora/$m"
done

uv run python -m scamshield_ml.bench_report                  # docs/benchmark.md + reports/bench/summary.json
