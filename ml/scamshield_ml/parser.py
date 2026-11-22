"""Port of Kotlin `LlmOutputParser` (core/LlmOutputParser.kt) plus scam-type extraction."""

from __future__ import annotations

import re

try:
    from typing_extensions import TypedDict
except ImportError:  # pragma: no cover
    from typing import TypedDict

from scamshield_ml.data import SCAM_TYPES


class Parsed(TypedDict):
    label: str
    confidence: float | None
    reason: str
    scam_type: str | None


_LABEL_RE = re.compile(r'"?label"?\s*[:=]\s*"?([A-Za-z]+)', re.I)
_CONF_RE = re.compile(r'"?confidence"?\s*[:=]\s*"?([0-9]*\.?[0-9]+)\s*(%)?', re.I)
_REASON_RE = re.compile(r'"?reason"?\s*[:=]\s*"([^"]*)"', re.I)
_TYPE_RE = re.compile(r'"?type"?\s*[:=]\s*"?([A-Za-z_]+)', re.I)  # provisional, see prompt.format_target
_BARE_RE = re.compile(r"\b(SCAM|SUSPICIOUS|SAFE)\b")
# Kotlin Label.parse (core/Models.kt) synonyms.
_SYN = {
    **dict.fromkeys(("SAFE", "GENUINE", "NEUTRAL", "POSITIVE"), "SAFE"),
    **dict.fromkeys(("SUSPICIOUS", "SUSPECT", "WARNING"), "SUSPICIOUS"),
    **dict.fromkeys(("SCAM", "FRAUD", "NEGATIVE"), "SCAM"),
}


def parse_output(raw: str) -> Parsed:
    """Kotlin returns null on unparseable output; here that is label "UNPARSED", confidence None."""
    text = raw.replace("```json", "").replace("```", "").strip()
    label = None
    for rx in (_LABEL_RE, _BARE_RE):
        m = rx.search(text)
        label = _SYN.get(m.group(1).strip().upper()) if m else None
        if label:
            break
    if not label:
        return {"label": "UNPARSED", "confidence": None, "reason": "", "scam_type": None}
    cm = _CONF_RE.search(text)
    conf = float(cm.group(1)) if cm else 0.6
    if (cm and cm.group(2) == "%") or conf > 1.0:
        conf /= 100.0
    rm = _REASON_RE.search(text)
    tm = _TYPE_RE.search(text)
    kind = tm.group(1).upper() if tm else None
    scam_type = None if label == "SAFE" else (kind if kind in SCAM_TYPES else "OTHER")
    return {
        "label": label,
        "confidence": min(1.0, max(0.0, conf)),
        "reason": (rm.group(1).strip() if rm else "")[:120],
        "scam_type": scam_type,
    }
