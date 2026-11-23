import re
from collections import Counter

from scamshield_ml.data import LANGUAGES, validate_row
from scamshield_ml.synth import _R3, generate_rows

R3_ROWS = [r for r in generate_rows() if "_r3_" in r["template_id"] or r["template_id"].endswith("_r3")]


def _gap(row: dict[str, str]) -> str:
    # ids: {lang}_{gap}_r3_NN (scam) or {lang}_safe_r3_{gap}_NN (safe)
    tid = row["template_id"]
    if "_safe_r3_" in tid:
        return tid.split("_safe_r3_")[1].rsplit("_", 1)[0].upper()
    return tid.split("_r3_")[0].split("_", 1)[1].upper()


def test_R3_COV_allNewTypesHavePositivesAndHardNegatives() -> None:
    assert set(_R3) >= {
        "ELECTRICITY_BILL", "SIM_SWAP", "CUSTOMER_CARE", "UPI_COLLECT",
        "SEXTORTION", "LOTTERY", "FAMILY_EMERGENCY", "PHISHING_LINK",
    }
    pos = Counter((_gap(r), r["lang"]) for r in R3_ROWS if r["label"] == "SCAM")
    neg = Counter((_gap(r), r["lang"]) for r in R3_ROWS if r["label"] == "SAFE")
    for gap in _R3:
        for lang in LANGUAGES:
            assert pos[(gap, lang)] >= 3, (gap, lang)
            assert neg[(gap, lang)] >= 2, (gap, lang)
    assert all(r["scam_type"] == _gap(r) for r in R3_ROWS if r["label"] == "SCAM")


def test_R3_COV_rowsValidate() -> None:
    assert R3_ROWS
    for r in R3_ROWS:
        assert validate_row(dict(r)) == r
        assert r["source"] == "synthetic"


def test_R3_COV_noRealLookingIdentifiers() -> None:
    for r in R3_ROWS:
        text = r["text"]
        assert not re.search(r"(?<![\dX])\d{10}(?!\d)", text), text
        for handle in re.findall(r"[\w.\-]+@([\w\-]+(?:\.[\w\-]+)*)", text):
            assert handle in {"example", "upi"}, text
