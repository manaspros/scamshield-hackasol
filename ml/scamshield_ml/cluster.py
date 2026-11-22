"""Cluster exported scam trigger features and flag emerging campaigns."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import numpy as np
from sklearn.cluster import HDBSCAN
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_distances

_TOKEN = re.compile(r"[^\W_]+", re.UNICODE)
_DEFAULT_WINDOW_DAYS = 30
_DEFAULT_MIN_RECENT = 3
_NOVEL_DISTANCE = 0.65


def _date(value: Any) -> date | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _triggers(record: dict[str, Any]) -> list[str]:
    values = record.get("triggers", [])
    if isinstance(values, str):
        values = [values]
    if not values and record.get("trigger"):
        values = [record["trigger"]]
    return [str(value).strip() for value in values if str(value).strip()]


def _type(record: dict[str, Any]) -> str:
    return str(
        record.get("scam_type", record.get("scamType", "OTHER")) or "OTHER"
    ).upper()


def cluster_records(
    records: list[dict[str, Any]],
    *,
    as_of: date | None = None,
    window_days: int = _DEFAULT_WINDOW_DAYS,
    min_recent_members: int = _DEFAULT_MIN_RECENT,
    min_cluster_size: int = 3,
) -> list[dict[str, Any]]:
    """Return dashboard-ready cluster summaries; inputs need no raw message text."""
    if not records:
        return []
    if window_days < 0 or min_recent_members < 1 or min_cluster_size < 2:
        raise ValueError(
            "window_days must be nonnegative; member counts must be positive"
        )

    triggers = [_triggers(record) for record in records]
    # Binary trigger-token features avoid weighting repeated phrase words more heavily.
    documents = [
        " ".join(
            dict.fromkeys(
                token.lower() for phrase in phrases for token in _TOKEN.findall(phrase)
            )
        )
        for phrases in triggers
    ]
    if not any(documents):
        return []
    vectorizer = TfidfVectorizer(
        binary=True, use_idf=False, norm="l2", token_pattern=r"(?u)\b\w+\b"
    )
    matrix = vectorizer.fit_transform(documents).toarray()

    if len(records) == 1:
        labels = np.array([-1])
    else:
        labels = HDBSCAN(
            min_cluster_size=min(min_cluster_size, len(records)),
            min_samples=1,
            metric="euclidean",
            copy=True,
        ).fit_predict(matrix)

    types = [_type(record) for record in records]
    known = sorted(
        {
            kind
            for kind in types
            if kind not in {"OTHER", "SAFE", "SUSPICIOUS", "UNKNOWN", ""}
        }
    )
    centroids: list[np.ndarray] = []
    if known:
        centroids = [
            matrix[[i for i, kind in enumerate(types) if kind == known_kind]].mean(
                axis=0
            )
            for known_kind in known
        ]

    today = as_of or max(
        (
            _date(r.get("date", r.get("timestamp")))
            for r in records
            if _date(r.get("date", r.get("timestamp")))
        ),
        default=date.today(),
    )
    cutoff = today - timedelta(days=window_days)
    groups: dict[int, list[int]] = defaultdict(list)
    for index, label in enumerate(labels.tolist()):
        groups[int(label)].append(index)

    summaries = []
    for label, indices in groups.items():
        type_counts = Counter(types[i] for i in indices)
        dominant_type = sorted(
            type_counts, key=lambda kind: (-type_counts[kind], kind)
        )[0]
        cluster_center = matrix[indices].mean(axis=0).reshape(1, -1)
        far_from_known = (
            not centroids
            or float(cosine_distances(cluster_center, np.vstack(centroids)).min())
            >= _NOVEL_DISTANCE
        )
        recent_count = sum(
            (_date(records[i].get("date", records[i].get("timestamp"))) or date.min)
            >= cutoff
            for i in indices
        )
        parsed_dates = [
            _date(records[i].get("date", records[i].get("timestamp"))) for i in indices
        ]
        parsed_dates = [value for value in parsed_dates if value is not None]
        trigger_counts = Counter(phrase for i in indices for phrase in triggers[i])
        top_triggers = [
            phrase
            for phrase, _ in sorted(
                trigger_counts.items(), key=lambda item: (-item[1], item[0])
            )[:5]
        ]
        is_new = recent_count >= min_recent_members and (
            dominant_type == "OTHER" or far_from_known
        )
        summaries.append(
            {
                "cluster_id": f"cluster_{label}"
                if label >= 0
                else f"noise_{indices[0]}",
                "size": len(indices),
                "top_triggers": top_triggers,
                "dominant_type": dominant_type,
                "is_new_campaign": bool(is_new),
                "first_seen": min(parsed_dates).isoformat() if parsed_dates else None,
                "last_seen": max(parsed_dates).isoformat() if parsed_dates else None,
            }
        )
    return sorted(summaries, key=lambda item: item["cluster_id"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--in", dest="input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    records = [
        json.loads(line)
        for line in args.input.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    summaries = cluster_records(records)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(summaries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
