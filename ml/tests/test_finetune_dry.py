from pathlib import Path
import sys

from scamshield_ml import convert_task
from scamshield_ml.finetune import format_example, train_rows
from scamshield_ml.parser import parse_output
from scamshield_ml.prompt import build_prompt, target_for_row

HEAVY = ("torch", "transformers", "peft", "trl", "datasets", "litert_torch", "ai_edge_torch", "mediapipe")


def T1_11_formatsExamples():
    rows = train_rows()
    assert rows and all(r["source"] == "synthetic" for r in rows)
    for r in rows[:50]:
        ex = format_example(r)
        assert ex == {"prompt": build_prompt(r["text"]), "completion": target_for_row(r)}
        p = parse_output(ex["completion"])
        assert p["label"] == r["label"]
        assert p["scam_type"] == (r["scam_type"] or None)
    assert len(train_rows(3)) == 3


def T1_11_convertDryRunArgs():
    steps = convert_task.plan(Path("a"), Path("w"), Path("w/m.task"))
    text = str(steps)
    for needle in ("google/gemma-3-1b-it", "int4", "m.task", "litert-torch==", "mediapipe=="):
        assert needle in text
    assert not [m for m in HEAVY if m in sys.modules]


test_T1_11_formatsExamples = T1_11_formatsExamples
test_T1_11_convertDryRunArgs = T1_11_convertDryRunArgs
