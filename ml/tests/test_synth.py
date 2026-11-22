from collections import Counter

from scamshield_ml.data import LANGUAGES, SCAM_TYPES
from scamshield_ml.parser import parse_output
from scamshield_ml.synth import generate_rows, sft_pairs


def test_T1_9_templateCountPerLang() -> None:
    rows = generate_rows()
    counts = Counter(row["lang"] for row in rows)
    assert set(counts) == LANGUAGES
    assert all(count >= 40 for count in counts.values())
    assert len({row["template_id"] for row in rows}) == len(rows)


def test_T1_9_allScamTypesPresent() -> None:
    rows = generate_rows()
    assert {row["scam_type"] for row in rows if row["label"] == "SCAM"} == SCAM_TYPES
    assert all(row["source"] == "synthetic" for row in rows)
    assert all(row["scam_type"] == "" for row in rows if row["label"] == "SAFE")


def test_T1_9_sftPairsWellFormed() -> None:
    pairs = sft_pairs(generate_rows())
    assert pairs
    assert all(
        set(pair) == {"prompt", "target"} and pair["prompt"] and pair["target"]
        for pair in pairs
    )
    assert all(parse_output(pair["target"])["label"] != "UNPARSED" for pair in pairs)
