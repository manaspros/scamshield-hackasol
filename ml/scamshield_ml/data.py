"""CSV dataset loading, validation, and template-level splitting."""

from __future__ import annotations

import csv
import random
from pathlib import Path
from typing import TypedDict


class Row(TypedDict):
    text: str
    label: str
    lang: str
    scam_type: str
    template_id: str
    source: str


COLUMNS = ("text", "label", "lang", "scam_type", "template_id", "source")
LABELS = {"SAFE", "SUSPICIOUS", "SCAM"}
LANGUAGES = {"en", "hi", "hinglish"}
SCAM_TYPES = {
    "OTP",
    "KYC",
    "DIGITAL_ARREST",
    "COURIER_CUSTOMS",
    "FAKE_QR",
    "LOAN_APP",
    "INVESTMENT",
    "JOB",
    "MISTAKEN_TRANSFER",
    "OTHER",
}
SOURCES = {"synthetic", "real"}


def validate_row(values: dict[str, str], line: int | None = None) -> Row:
    """Validate and normalize one row with the dataset schema."""
    where = f" at line {line}" if line is not None else ""
    if set(values) != set(COLUMNS):
        raise ValueError(f"expected columns {COLUMNS}{where}")

    row = {column: values[column].strip() for column in COLUMNS}
    if not row["text"]:
        raise ValueError(f"text must not be empty{where}")
    if row["label"] not in LABELS:
        raise ValueError(f"invalid label{where}: {row['label']!r}")
    if row["lang"] not in LANGUAGES:
        raise ValueError(f"invalid lang{where}: {row['lang']!r}")
    if row["scam_type"] not in SCAM_TYPES and not (
        row["label"] == "SAFE" and row["scam_type"] == ""
    ):
        raise ValueError(f"invalid scam_type{where}: {row['scam_type']!r}")
    if row["label"] == "SAFE" and row["scam_type"]:
        raise ValueError(f"SAFE rows must have an empty scam_type{where}")
    if not row["template_id"]:
        raise ValueError(f"template_id must not be empty{where}")
    if row["source"] not in SOURCES:
        raise ValueError(f"invalid source{where}: {row['source']!r}")
    return Row(**row)


def load_rows(path: Path) -> list[Row]:
    """Read and validate a CSV file with the exact dataset columns."""
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        if reader.fieldnames != list(COLUMNS):
            raise ValueError(f"expected CSV header {COLUMNS}: {path}")
        return [validate_row(row, reader.line_num) for row in reader]


def load_real_rows(repo_root: Path) -> list[Row]:
    """Load real evaluation CSVs, returning no rows if the directory is absent."""
    directory = repo_root / "data" / "eval" / "real"
    if not directory.is_dir():
        return []

    rows = [row for path in sorted(directory.glob("*.csv")) for row in load_rows(path)]
    if any(row["source"] != "real" for row in rows):
        raise ValueError(f"all rows in {directory} must have source='real'")
    return rows


def split_rows(
    rows: list[Row], test_fraction: float = 0.2, seed: int = 0
) -> tuple[list[Row], list[Row]]:
    """Split synthetic data by template; all real rows are assigned to test."""
    if not 0 < test_fraction < 1:
        raise ValueError("test_fraction must be between 0 and 1")

    synthetic = [row for row in rows if row["source"] == "synthetic"]
    test = [row for row in rows if row["source"] == "real"]
    templates = sorted({row["template_id"] for row in synthetic})
    shuffled = templates.copy()
    random.Random(seed).shuffle(shuffled)

    test_count = round(len(shuffled) * test_fraction)
    if len(shuffled) > 1:
        test_count = min(max(test_count, 1), len(shuffled) - 1)
    else:
        test_count = 0
    test_templates = set(shuffled[:test_count])

    train: list[Row] = []
    for row in synthetic:
        (test if row["template_id"] in test_templates else train).append(row)
    return train, test
