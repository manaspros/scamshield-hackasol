"""QA edge-case tests for the ML package (parser, prompt, data, metrics, synth, cluster)."""

import csv
import json
from datetime import date
from pathlib import Path

import pytest

from scamshield_ml import eval_heldout as ev
from scamshield_ml.cluster import cluster_records
from scamshield_ml.data import COLUMNS, LANGUAGES, load_rows, split_rows, validate_row
from scamshield_ml.finetune import train_rows
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import HEADER, build_prompt, format_target
from scamshield_ml.synth import generate_rows, sft_pairs

UNPARSED = {"label": "UNPARSED", "confidence": None, "scam_type": None, "reasons": []}


# ---------------------------------------------------------------- parser
@pytest.mark.parametrize("raw", ["", "   \n\t ", "```json\n```", "{}", "{not json", "scam", "safe"])
def test_qa_parser_empty_or_garbage_is_unparsed(raw):
    assert parse_output(raw) == UNPARSED


def test_qa_parser_truncated_json_keeps_label_and_falls_back_to_other():
    r = parse_output('{"label":"SCAM","scam_type":"OT')
    assert r["label"] == "SCAM" and r["scam_type"] == "OTHER" and r["confidence"] == 0.6
    r = parse_output('{"label":"SUSPICIOUS","scam_type":"KYC","confidence":0.7,"reason":"unterminated')
    assert (r["label"], r["scam_type"], r["reasons"]) == ("SUSPICIOUS", "KYC", [])


def test_qa_parser_extra_text_and_first_object_wins():
    raw = 'Here you go: {"label":"SAFE","confidence":0.9} and also {"label":"SCAM","confidence":0.1}'
    r = parse_output(raw)
    assert r["label"] == "SAFE" and r["confidence"] == pytest.approx(0.9) and r["scam_type"] is None


def test_qa_parser_devanagari_hinglish_reason_roundtrip():
    for reason in ("ओटीपी मांगा जा रहा है", "Aap ka KYC pending hai", "मत batao OTP"):
        r = parse_output(format_target("SCAM", "OTP", reason))
        assert r["reasons"] == [reason] and r["scam_type"] == "OTP"


def test_qa_parser_reason_capped_at_120_chars():
    r = parse_output('{"label":"SCAM","reason":"' + "क" * 300 + '"}')
    assert r["reasons"] == ["क" * 120]


def test_qa_parser_confidence_bounds_and_percent():
    assert parse_output('{"label":"SCAM","confidence":150}')["confidence"] == 1.0
    assert parse_output('{"label":"SCAM","confidence":0}')["confidence"] == 0.0
    assert parse_output('{"label":"SCAM","confidence":"50%"}')["confidence"] == pytest.approx(0.5)
    assert parse_output('{"label":"SCAM","confidence":1.0}')["confidence"] == 1.0


def test_qa_parser_safe_never_carries_scam_type_and_synonyms_map():
    assert parse_output('{"label":"SAFE","scam_type":"OTP"}')["scam_type"] is None
    assert parse_output('{"label":"fraud"}')["label"] == "SCAM"
    assert parse_output('{"label":"warning"}')["label"] == "SUSPICIOUS"
    assert parse_output('label = genuine')["label"] == "SAFE"


def test_qa_parser_unknown_label_value_falls_back_to_bare_word_or_unparsed():
    assert parse_output('{"label":"MAYBE"}') == UNPARSED
    assert parse_output('{"label":"MAYBE"} but this is a SCAM')["label"] == "SCAM"


def test_qa_parser_lowercase_bare_word_is_not_a_label():
    # Matches Kotlin bareLabelRe, which is case sensitive.
    assert parse_output("this is a scam call") == UNPARSED


# ---------------------------------------------------------------- prompt
def test_qa_prompt_text_without_context_is_header_plus_statement():
    assert build_prompt("नमस्ते OTP") == HEADER + 'STATEMENT: "नमस्ते OTP"\n'


def test_qa_prompt_newlines_preserved_and_double_quotes_replaced_only_in_text():
    p = build_prompt('line1\nline2 "q"', ['ctx "a"', "ctx\nb"])
    assert p.endswith('Earlier in this call: "ctx "a"" | "ctx\nb"\nSTATEMENT: "line1\nline2 \'q\'"\n')


def test_qa_prompt_context_takelast2_applied_before_blank_filter():
    # Kotlin: context.takeLast(2).filter { isNotBlank } -> ["a","","b"] keeps only "b".
    assert 'Earlier in this call: "b"\n' in build_prompt("x", ["a", "", "b"])
    assert "Earlier in this call" not in build_prompt("x", ["a", "  ", "\t"])
    assert "Earlier in this call" not in build_prompt("x", [])


def test_qa_prompt_length_caps_300_text_150_context():
    assert build_prompt("a" * 300).endswith('"' + "a" * 300 + '"\n')
    assert build_prompt("a" * 301).endswith('"' + "a" * 300 + '"\n')
    assert '"' + "ब" * 150 + '"' in build_prompt("x", ["ब" * 151])
    assert "ब" * 151 not in build_prompt("x", ["ब" * 151])


def test_qa_prompt_take_counts_utf16_units_for_astral_chars():
    # Kotlin take(300) counts UTF-16 units: an emoji is 2, so 150 emoji fit, the 151st does not.
    p = build_prompt("😀" * 200)
    assert p.endswith('"' + "😀" * 150 + '"\n')
    # Devanagari is BMP: 1 unit per code point (combining marks count too).
    p = build_prompt("कि" * 200)
    assert p.endswith('"' + "कि" * 150 + '"\n')


def test_qa_prompt_empty_statement():
    assert build_prompt("").endswith('STATEMENT: ""\n')


# ---------------------------------------------------------------- data
def _vals(**kw):
    base = {"text": "t", "label": "SCAM", "lang": "en", "scam_type": "OTP", "template_id": "x", "source": "synthetic"}
    base.update(kw)
    return base


def test_qa_data_validate_row_strips_and_accepts_devanagari():
    r = validate_row(_vals(text="  ओटीपी बताइए \n", lang="hi"))
    assert r["text"] == "ओटीपी बताइए"


@pytest.mark.parametrize("kw, msg", [
    ({"text": "   "}, "text must not be empty"),
    ({"label": "scam"}, "invalid label"),
    ({"lang": "fr"}, "invalid lang"),
    ({"scam_type": ""}, "invalid scam_type"),
    ({"scam_type": "BOGUS"}, "invalid scam_type"),
    ({"label": "SAFE", "scam_type": "OTP"}, "SAFE rows must have an empty scam_type"),
    ({"template_id": " "}, "template_id must not be empty"),
    ({"source": "scraped"}, "invalid source"),
])
def test_qa_data_validate_row_rejects(kw, msg):
    with pytest.raises(ValueError, match=msg):
        validate_row(_vals(**kw), line=7)


def test_qa_data_validate_row_error_names_line():
    with pytest.raises(ValueError, match="at line 7"):
        validate_row(_vals(label="X"), line=7)


def test_qa_data_validate_row_wrong_columns():
    bad = _vals()
    del bad["source"]
    with pytest.raises(ValueError, match="expected columns"):
        validate_row(bad)
    with pytest.raises(ValueError, match="expected columns"):
        validate_row({**_vals(), "extra": "x"})


def test_qa_data_safe_row_with_empty_type_ok():
    assert validate_row(_vals(label="SAFE", scam_type=""))["scam_type"] == ""


def _write(path: Path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def test_qa_data_load_rows_rejects_bad_header(tmp_path):
    _write(tmp_path / "a.csv", ["text", "label"], [["x", "SAFE"]])
    with pytest.raises(ValueError, match="expected CSV header"):
        load_rows(tmp_path / "a.csv")
    _write(tmp_path / "b.csv", list(reversed(COLUMNS)), [])
    with pytest.raises(ValueError, match="expected CSV header"):
        load_rows(tmp_path / "b.csv")


def test_qa_data_load_rows_empty_file_with_header_is_empty_list(tmp_path):
    _write(tmp_path / "a.csv", COLUMNS, [])
    assert load_rows(tmp_path / "a.csv") == []


def test_qa_data_load_rows_preserves_unicode_commas_quotes_newlines(tmp_path):
    text = 'आप "KYC", update\nkaro'
    _write(tmp_path / "a.csv", COLUMNS, [[text, "SUSPICIOUS", "hinglish", "KYC", "t1", "real"]])
    assert load_rows(tmp_path / "a.csv")[0]["text"] == text


def test_qa_data_load_rows_extra_field_raises_valueerror(tmp_path):
    (tmp_path / "a.csv").write_text(",".join(COLUMNS) + "\nt,SCAM,en,OTP,x,synthetic,EXTRA\n", encoding="utf-8")
    with pytest.raises(ValueError):
        load_rows(tmp_path / "a.csv")


# ---------------------------------------------------------------- split / heldout
def test_qa_heldout_no_template_or_text_leakage_with_train():
    train = train_rows()
    held = ev.heldout_rows()
    assert train and held
    assert {r["template_id"] for r in train}.isdisjoint({r["template_id"] for r in held})
    assert {r["text"] for r in train}.isdisjoint({r["text"] for r in held})
    assert all(r["source"] == "synthetic" for r in train)


def test_qa_heldout_covers_every_language_and_both_classes():
    held = ev.heldout_rows()
    assert {r["lang"] for r in held} == LANGUAGES
    assert {"SAFE"} < {r["label"] for r in held} and any(r["label"] != "SAFE" for r in held)


def test_qa_split_partition_is_complete_and_disjoint():
    rows = generate_rows()
    train, test = split_rows(rows)
    assert len(train) + len(test) == len(rows)
    assert sorted(r["template_id"] for r in train + test) == sorted(r["template_id"] for r in rows)


def test_qa_split_edge_sizes_and_bad_fraction():
    assert split_rows([]) == ([], [])
    one = [validate_row(_vals())]
    assert split_rows(one) == (one, [])
    for bad in (0, 1, -0.1, 1.5):
        with pytest.raises(ValueError):
            split_rows(one, test_fraction=bad)
    two = [validate_row(_vals(template_id="a")), validate_row(_vals(template_id="b"))]
    train, test = split_rows(two, test_fraction=0.01)
    assert len(train) == 1 and len(test) == 1  # both sides never empty with >1 template


def test_qa_split_real_rows_all_go_to_test_even_if_template_matches_synthetic():
    syn = [validate_row(_vals(template_id=f"s{i}")) for i in range(4)]
    real = [validate_row(_vals(template_id="s0", source="real"))]
    train, test = split_rows(syn + real, test_fraction=0.25, seed=1)
    assert real[0] in test and all(r["source"] == "synthetic" for r in train)


# ---------------------------------------------------------------- metrics
def _r(label, lang="en", st="OTP"):
    return {"text": "t", "label": label, "lang": lang, "scam_type": "" if label == "SAFE" else st,
            "template_id": "t", "source": "synthetic"}


def test_qa_metrics_empty_input():
    m = ev.compute_metrics([], [])
    assert m["per_language"] == {}
    assert m["overall"]["counts"] == {"n": 0, "tp": 0, "fp": 0, "fn": 0, "tn": 0}
    assert (m["overall"]["precision"], m["overall"]["recall"], m["overall"]["fpr"], m["overall"]["macro_f1"]) == (0, 0, 0, 0)


def test_qa_metrics_zero_positives_in_gold_no_divide_by_zero():
    rows = [_r("SAFE"), _r("SAFE")]
    m = ev.compute_metrics(rows, [("SAFE", None), ("SCAM", "OTP")])["overall"]
    assert m["recall"] == 0.0 and m["precision"] == 0.0 and m["fpr"] == 0.5 and m["macro_f1"] == 0.0
    assert m["counts"] == {"n": 2, "tp": 0, "fp": 1, "fn": 0, "tn": 1}


def test_qa_metrics_all_correct_is_perfect():
    rows = [_r("SCAM", st="OTP"), _r("SUSPICIOUS", st="KYC"), _r("SAFE")]
    m = ev.compute_metrics(rows, [("SCAM", "OTP"), ("SUSPICIOUS", "KYC"), ("SAFE", None)])["overall"]
    assert (m["precision"], m["recall"], m["fpr"], m["macro_f1"]) == (1.0, 1.0, 0.0, 1.0)


def test_qa_metrics_all_wrong_and_all_unparsed():
    rows = [_r("SCAM"), _r("SAFE")]
    wrong = ev.compute_metrics(rows, [("SAFE", None), ("SCAM", "OTP")])["overall"]
    assert (wrong["precision"], wrong["recall"], wrong["fpr"]) == (0.0, 0.0, 1.0)
    un = ev.compute_metrics(rows, [("UNPARSED", None)] * 2)["overall"]
    assert un["unparsed"] == 2 and un["recall"] == 0.0 and un["fpr"] == 0.0
    assert un["counts"] == {"n": 2, "tp": 0, "fp": 0, "fn": 1, "tn": 1}


def test_qa_metrics_right_label_wrong_type_hurts_f1_only():
    m = ev.compute_metrics([_r("SCAM", st="OTP")], [("SCAM", "KYC")])["overall"]
    assert m["recall"] == 1.0 and m["precision"] == 1.0 and m["macro_f1"] == 0.0


def test_qa_metrics_language_absent_from_rows_not_in_per_language():
    m = ev.compute_metrics([_r("SAFE", "hi")], [("SAFE", None)])
    assert set(m["per_language"]) == {"hi"}


# ---------------------------------------------------------------- synth / sft
def test_qa_synth_deterministic_per_seed():
    assert generate_rows(0) == generate_rows(0)
    assert generate_rows(5) == generate_rows(5)
    assert [r["template_id"] for r in generate_rows(0)] == [r["template_id"] for r in generate_rows(5)]


def test_qa_synth_no_unfilled_placeholders_and_hindi_is_devanagari():
    rows = generate_rows()
    assert not [r for r in rows if "{" in r["text"] or "}" in r["text"]]
    hi = [r for r in rows if r["lang"] == "hi"]
    assert hi and all(any("ऀ" <= c <= "ॿ" for c in r["text"]) for r in hi)


def test_qa_synth_every_row_passes_validate_row_unchanged():
    for r in generate_rows():
        assert validate_row(dict(r)) == r


def test_qa_sft_pairs_empty_and_format():
    assert sft_pairs([]) == []
    rows = generate_rows()
    pairs = sft_pairs(rows)
    assert len(pairs) == len(rows)
    for row, pair in zip(rows, pairs):
        assert pair["prompt"] == build_prompt(row["text"])
        assert pair["prompt"].endswith('"\n') and "\n" not in pair["target"]
        j = json.loads(pair["target"])
        assert set(j) == {"label", "scam_type", "confidence", "reason"} and j["label"] == row["label"]
        assert j["scam_type"] == (row["scam_type"] or "NONE")
        assert 0 <= j["confidence"] <= 1


def test_qa_sft_target_with_quote_in_reason_stays_valid_json():
    assert json.loads(format_target("SCAM", "OTP", 'say "hi"'))["reason"] == "say 'hi'"


# ---------------------------------------------------------------- cluster
def test_qa_cluster_empty_and_no_trigger_inputs():
    assert cluster_records([]) == []
    assert cluster_records([{"scam_type": "OTP", "triggers": []}, {"scam_type": "KYC"}]) == []


def test_qa_cluster_single_record_is_noise_and_not_a_campaign():
    out = cluster_records([{"scam_type": "OTP", "triggers": ["share otp"], "date": "2026-11-20"}],
                          as_of=date(2026, 11, 23))
    assert len(out) == 1
    assert out[0]["size"] == 1 and out[0]["cluster_id"].startswith("noise_")
    assert out[0]["first_seen"] == out[0]["last_seen"] == "2026-11-20"
    assert out[0]["is_new_campaign"] is False


def test_qa_cluster_bad_parameters_raise():
    rec = [{"triggers": ["a"]}]
    for kw in ({"window_days": -1}, {"min_recent_members": 0}, {"min_cluster_size": 1}):
        with pytest.raises(ValueError):
            cluster_records(rec, **kw)


def test_qa_cluster_tolerates_missing_and_garbage_dates_and_string_trigger():
    recs = [{"scam_type": "OTHER", "triggers": "odd marker", "date": d}
            for d in (None, "garbage", "2026-11-20", "2026-11-21T10:00:00")]
    out = cluster_records(recs, as_of=date(2026, 11, 23))
    assert sum(c["size"] for c in out) == 4
    seen = [c["last_seen"] for c in out if c["last_seen"]]
    assert seen and max(seen) == "2026-11-21"


def test_qa_cluster_old_records_outside_window_do_not_alert():
    recs = [{"scam_type": "OTHER", "triggers": ["brand new ploy", "weird"], "date": "2025-01-01"} for _ in range(6)]
    out = cluster_records(recs, as_of=date(2026, 11, 23))
    assert out and not any(c["is_new_campaign"] for c in out)


def test_qa_cluster_summary_sizes_sum_to_input_and_output_has_no_raw_text_keys():
    recs = [{"scam_type": "OTHER", "triggers": ["alpha beta", "gamma"], "date": "2026-11-2%d" % (i % 5),
             "text": "SECRET RAW MESSAGE"} for i in range(8)]
    out = cluster_records(recs, as_of=date(2026, 11, 23))
    assert sum(c["size"] for c in out) == 8
    assert "SECRET RAW MESSAGE" not in json.dumps(out)
