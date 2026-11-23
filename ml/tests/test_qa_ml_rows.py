"""Pending: tests that fail because of product bugs. Uncommitted by design."""

from scamshield_ml.data import COLUMNS, load_rows

import pytest


def test_qa_data_load_rows_short_row_raises_valueerror_not_crash(tmp_path):
    (tmp_path / "a.csv").write_text(",".join(COLUMNS) + "\nonly text\n", encoding="utf-8")
    with pytest.raises(ValueError):
        load_rows(tmp_path / "a.csv")
