import csv
from pathlib import Path

from scamshield_ml.data import COLUMNS, load_real_rows, split_rows


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def row(template_id: str, source: str = "synthetic") -> dict[str, str]:
    return {
        "text": f"sample {template_id}",
        "label": "SCAM",
        "lang": "en",
        "scam_type": "OTP",
        "template_id": template_id,
        "source": source,
    }


def test_T1_8_noTemplateInBothSplits(tmp_path: Path) -> None:
    path = tmp_path / "synthetic.csv"
    write_rows(
        path,
        [row("template-a"), row("template-a"), row("template-b"), row("template-c")],
    )
    from scamshield_ml.data import load_rows

    rows = load_rows(path)
    train, test = split_rows(rows, test_fraction=0.34, seed=17)

    train_templates = {item["template_id"] for item in train}
    test_templates = {item["template_id"] for item in test}
    assert train_templates.isdisjoint(test_templates)
    assert train and test
    assert (train, test) == split_rows(rows, test_fraction=0.34, seed=17)


def test_T1_8_realRowsTestOnly(tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    real_dir = repo_root / "data" / "eval" / "real"
    write_rows(real_dir / "real.csv", [row("real-template", source="real")])
    write_rows(tmp_path / "synthetic.csv", [row("syn-a"), row("syn-b")])

    real_rows = load_real_rows(repo_root)
    train, test = split_rows(
        real_rows + [row("syn-a"), row("syn-b")], test_fraction=0.5, seed=0
    )

    assert load_real_rows(tmp_path / "missing-repo") == []
    assert len(real_rows) == 1
    assert real_rows[0] in test
    assert all(item["source"] != "real" for item in train)
