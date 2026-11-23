import json
from pathlib import Path

import pytest

from scamshield_ml.data import SCAM_TYPES
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import build_prompt, format_target, target_for_row

GOLDEN = Path(__file__).resolve().parents[2] / "data" / "golden" / "prompt_golden.json"


def T1_10_parserMatchesKotlinCases():
    r = parse_output('{"label":"SCAM","confidence":0.93,"reason":"Asks OTP"}')
    assert (r["label"], r["confidence"], r["reasons"]) == ("SCAM", 0.93, ["Asks OTP"])
    r = parse_output('Sure!\n```json\n{ "label": "suspicious", "confidence": 70%, "reason": "KYC claim" }\n```')
    assert r["label"] == "SUSPICIOUS" and r["confidence"] == pytest.approx(0.70)
    r = parse_output("SAFE - normal chat")
    assert r["label"] == "SAFE" and r["confidence"] == 0.6
    assert parse_output("I cannot help with that")["label"] == "UNPARSED"
    r = parse_output('{"label":"SCAM","confidence":97}')
    assert r["confidence"] == pytest.approx(0.97) and r["scam_type"] == "OTHER"


def T1_10_roundTrip():
    for label in ("SAFE", "SUSPICIOUS", "SCAM"):
        for st in sorted(SCAM_TYPES):
            r = parse_output(format_target(label, st, "Some reason"))
            assert r["label"] == label and r["reasons"] == ["Some reason"]
            assert r["scam_type"] == (None if label == "SAFE" else st)
    row = {"text": "x", "label": "SCAM", "lang": "en", "scam_type": "OTP", "template_id": "t", "source": "synthetic"}
    assert parse_output(target_for_row(row))["scam_type"] == "OTP"


def T1_10_promptShape():
    p = build_prompt('say "hi"', ["", "a", "b", "c"])
    assert p.endswith('Earlier in this call: "b" | "c"\nSTATEMENT: "say \'hi\'"\n')


def T1_10_goldenParity():
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    assert len(golden) == 21
    for e in golden:
        label = e.get("context_label", "Earlier in this call")
        assert build_prompt(e["input_text"], e.get("context") or [], label) == e["prompt"], e["id"]
        assert parse_output(e["model_output"]) == e["parsed"], e["id"]


# pytest only collects test_* by default; alias the T1_10_ names.
test_T1_10_parserMatchesKotlinCases = T1_10_parserMatchesKotlinCases
test_T1_10_roundTrip = T1_10_roundTrip
test_T1_10_promptShape = T1_10_promptShape
test_T1_10_goldenParity = T1_10_goldenParity
