import json

import pytest

from scamshield_ml import eval_heldout as ev


def _row(text, label, lang="en", st="OTP", src="synthetic"):
    return {"text": text, "label": label, "lang": lang, "scam_type": st if label != "SAFE" else "",
            "template_id": text, "source": src}


def T1_13_perLanguageMetrics():
    rows = [_row("a", "SCAM"), _row("b", "SAFE"), _row("c", "SUSPICIOUS"), _row("d", "SAFE"),
            _row("e", "SCAM", "hi"), _row("f", "SAFE", "hi")]
    preds = [("SCAM", "OTP"), ("SCAM", "OTP"), ("SAFE", None), ("SAFE", None), ("SCAM", "KYC"), ("UNPARSED", None)]
    m = ev.compute_metrics(rows, preds)
    en, hi = m["per_language"]["en"], m["per_language"]["hi"]
    assert (en["precision"], en["recall"], en["fpr"]) == (0.5, 0.5, 0.5)
    assert (hi["precision"], hi["recall"], hi["fpr"]) == (1.0, 1.0, 0.0)
    assert hi["unparsed"] == 1 and m["overall"]["unparsed"] == 1
    assert m["overall"]["counts"] == {"n": 6, "tp": 2, "fp": 1, "fn": 1, "tn": 2}
    assert abs(en["macro_f1"] - 2 / 3) < 1e-9  # OTP: tp=1, fn=1


def T1_13_threeSystemsInReport(tmp_path):
    rows = [_row("otp now", "SCAM"), _row("hello", "SAFE"), _row("unmatched", "SAFE")]
    f = tmp_path / "rules.jsonl"
    f.write_text("\n".join(json.dumps(d) for d in [
        {"text": "otp now", "label": "SCAM", "scamType": "OTP", "triggers": []},
        {"text": "hello", "label": "SAFE"}]), encoding="utf-8")
    rep = ev.build_report(rows, "stub", f, None)
    s = rep["systems"]
    assert set(s) == {"rules", "base_gemma", "finetuned_gemma"}
    assert s["rules"]["coverage"] == pytest.approx(2 / 3) and s["rules"]["overall"]["recall"] == 1.0
    assert s["base_gemma"]["backend"] == "stub"
    assert s["finetuned_gemma"]["status"] == "not run"
    missing = ev.build_report(rows, "stub", tmp_path / "nope.jsonl", None)["systems"]["rules"]
    assert missing == {"status": "not run", "reason": "rules_preds.jsonl missing"}


def T1_13_labelsRealVsSynthetic():
    def rep(n_real):
        rows = [_row(f"r{i}", "SAFE", src="real") for i in range(n_real)] + [_row("s", "SAFE")]
        return ev.build_report(rows, "stub", ev.ROOT / "nope.jsonl", None)["data"]
    low, high = rep(99), rep(100)
    assert (low["real_rows"], low["synthetic_rows"], low["headline"]) == (99, 1, "synthetic")
    assert (high["real_rows"], high["headline"]) == (100, "real")


test_T1_13_perLanguageMetrics = T1_13_perLanguageMetrics
test_T1_13_threeSystemsInReport = T1_13_threeSystemsInReport
test_T1_13_labelsRealVsSynthetic = T1_13_labelsRealVsSynthetic
