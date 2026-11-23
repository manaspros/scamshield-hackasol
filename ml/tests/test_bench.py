"""Benchmark v2: dataset splits, metrics, prompts and report rendering (no model needed)."""

import json
import sys

from scamshield_ml import bench_report, synth_v2
from scamshield_ml.bench import first_line, label_metrics, load_config, phone_estimate, summarize
from scamshield_ml.data import LANGUAGES, SCAM_TYPES
from scamshield_ml.finetune import v2_examples
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import HEADER, SHORT_HEADER, build_prompt, build_short_prompt

HEAVY = ("torch", "transformers", "peft", "trl", "litert_lm")


def test_templates_cover_every_language_type_and_label():
    t = synth_v2.load_templates()
    assert len(t) == 780
    for lang in LANGUAGES:
        mine = [x for x in t if x["lang"] == lang]
        assert sum(x["label"] == "SAFE" for x in mine) == 80
        for st in SCAM_TYPES:
            kinds = [x["label"] for x in mine if x["scam_type"] == st]
            assert kinds.count("SCAM") == 12 and kinds.count("SUSPICIOUS") == 6


def test_split_is_by_template_and_stratified():
    t = synth_v2.load_templates()
    split = synth_v2.assign_splits(t)
    assert set(split) == {x["template_id"] for x in t}
    groups = {(x["lang"], x["label"], x["scam_type"]) for x in t}
    for g in groups:
        ids = [x["template_id"] for x in t if (x["lang"], x["label"], x["scam_type"]) == g]
        assert {"train", "test"} <= {split[i] for i in ids}, g
    assert synth_v2.assign_splits(t) == split  # deterministic


def test_committed_splits_match_generator_and_do_not_leak():
    built = synth_v2.build()
    for name in synth_v2.SPLITS:
        assert synth_v2.load_split(name) == built[name], f"data/bench/{name}.csv is stale: rerun synth_v2"
    tids = {n: {r["template_id"] for r in synth_v2.load_split(n)} for n in synth_v2.SPLITS}
    assert not tids["train"] & tids["test"] and not tids["train"] & tids["val"] and not tids["val"] & tids["test"]


def test_slot_filling_leaves_no_placeholders_or_double_currency():
    for name in synth_v2.SPLITS:
        for r in synth_v2.load_split(name):
            assert "{" not in r["text"] and "₹₹" not in r["text"], r["text"]


def test_short_prompt_keeps_statement_and_context_lines():
    full = build_prompt("abc", ["x", "y"])
    short = build_short_prompt("abc", ["x", "y"])
    assert short.startswith(SHORT_HEADER) and short[len(SHORT_HEADER):] == full[len(HEADER):]
    assert len(short) < len(full) / 5


def test_v2_examples_train_on_both_prompts_and_parse_back():
    ex = v2_examples("train", limit=4)
    assert len(ex) == 8
    assert ex[0]["prompt"].startswith(HEADER) and ex[1]["prompt"].startswith(SHORT_HEADER)
    rows = synth_v2.load_split("train")[:4]
    for r, e in zip(rows, ex[::2]):
        assert parse_output(e["completion"])["label"] == r["label"]


def test_label_metrics_and_scam_missed():
    rows = [{"label": l} for l in ("SCAM", "SCAM", "SUSPICIOUS", "SAFE")]
    m = label_metrics(rows, ["SCAM", "SAFE", "SUSPICIOUS", "SAFE"])
    assert m["accuracy"] == 0.75 and m["scam_missed_rate"] == 0.5
    assert m["confusion"]["SCAM"]["SAFE"] == 1


def test_first_line_drops_fewshot_continuation():
    raw = '{"label":"SAFE","scam_type":"NONE"}\nSTATEMENT: "next"\n{"label":"SCAM"}'
    assert parse_output(first_line(raw))["label"] == "SAFE"


def test_phone_estimate_uses_card_speeds():
    assert phone_estimate({"prefill": 100, "decode": 10}, 200, 30) == 5000
    assert phone_estimate({"ref": "none"}, 200, 30) is None


def _fake_report(system, model, acc, adapter=None, ram=1100, prompt_tokens=600):
    rows = [{"text": "t", "label": "SCAM", "lang": "en", "scam_type": "OTP", "template_id": "x", "source": "synthetic"},
            {"text": "u", "label": "SAFE", "lang": "hi", "scam_type": "", "template_id": "y", "source": "synthetic"}]
    raw = ['{"label":"SCAM","scam_type":"OTP"}', '{"label":"SAFE"}' if acc else '{"label":"SCAM"}']
    gens = [{"prompt_tokens": prompt_tokens, "output_tokens": 30, "hit_eos": True, "raw": r} for r in raw]
    cfg_model = {"hf_id": "x", "device": {"prefill": 300, "decode": 40, "ram_mb": ram, "file_mb": 500}}
    spec = {"model": model, "prompt": "fewshot", "template": "raw", **({"adapter": adapter} if adapter else {})}
    return summarize(system, spec, cfg_model, rows, gens, {})


def test_report_renders_deltas_and_tiers():
    reps = [_fake_report("m/fewshot/raw", "m", acc=False), _fake_report("m+ft/short/raw", "m", acc=True, adapter="a",
                                                                         prompt_tokens=60)]
    md = bench_report.render(reps, load_config())
    assert "What fine-tuning changes" in md and "+50.0%" in md and "0.10x" in md
    tiers = bench_report.recommend(reps, load_config())
    assert tiers[0]["system"] == "rules-only" and tiers[1]["system"] == "m+ft/short/raw"
    json.dumps(tiers)


def test_config_systems_reference_known_models():
    cfg = load_config()
    for name, s in cfg["systems"].items():
        assert s["model"] in cfg["models"], name
        assert s["prompt"] in ("fewshot", "short") and s["template"] in ("raw", "chat")


def test_no_heavy_imports():
    assert not [m for m in HEAVY if m in sys.modules]
