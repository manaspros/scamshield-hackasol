"""Port of the on-device Gemma prompt (Kotlin `Prompt` in GemmaClassifier.kt) and SFT target format."""

from __future__ import annotations

from collections.abc import Sequence

from scamshield_ml.data import Row

# Verbatim from GemmaClassifier.kt `Prompt.HEADER` (raw string, no escapes).
HEADER = """You are a fraud detector for Indian phone calls. Classify the caller's STATEMENT as SAFE, SUSPICIOUS or SCAM. Text may be English, Hindi (Devanagari) or Hinglish.
SCAM: asks for OTP/PIN/CVV/password, threatens arrest or "digital arrest", says police/CBI/customs/courier has a case against you, asks to move money to a "safe account", install AnyDesk/an app, or keep the call secret.
SUSPICIOUS: unsolicited bank/KYC/prize/loan/refund claims, urgency, asks for personal details, but no direct demand yet.
SAFE: normal conversation.
Answer with ONLY one line of JSON: {"label":"SAFE|SUSPICIOUS|SCAM","confidence":0.0-1.0,"reason":"max 10 words"}

STATEMENT: "Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye"
{"label":"SCAM","confidence":0.97,"reason":"Asks you to share OTP"}
STATEMENT: "मैं सीबीआई ऑफिस से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं"
{"label":"SCAM","confidence":0.98,"reason":"Fake CBI digital arrest threat"}
STATEMENT: "Your parcel to Taiwan has drugs, press 1 to talk to customs officer"
{"label":"SCAM","confidence":0.93,"reason":"Fake customs parcel story"}
STATEMENT: "Main SBI bank se bol raha hoon, aapka KYC pending hai"
{"label":"SUSPICIOUS","confidence":0.75,"reason":"Unsolicited bank KYC claim"}
STATEMENT: "Beta khana kha liya? Kal shaam ko milte hain"
{"label":"SAFE","confidence":0.95,"reason":"Normal family conversation"}
STATEMENT: "Your order will be delivered tomorrow between 10 and 12"
{"label":"SAFE","confidence":0.85,"reason":"Routine delivery update"}
"""

_CONF = {"SAFE": 0.95, "SUSPICIOUS": 0.75, "SCAM": 0.95}


def build_prompt(text: str, context: Sequence[str] = ()) -> str:
    """Byte-exact port of Kotlin `Prompt.build` (last 2 non-blank context lines, 150/300 char caps)."""
    parts = [HEADER]
    ctx = [c for c in list(context)[-2:] if c.strip()]
    if ctx:
        parts.append("\nEarlier in this call: " + " | ".join(f'"{c[:150]}"' for c in ctx) + "\n")
    parts.append('STATEMENT: "' + text[:300].replace('"', "'") + '"\n')
    return "".join(parts)


def format_target(label: str, scam_type: str | None, reason: str) -> str:
    """Model output in the one-line JSON the Kotlin parser reads."""
    # shortcut: scam-type line provisional until data/golden/prompt_golden.json (T1.2) exists, then align
    # Kotlin has no type field yet; `"type"` goes between label and confidence. Confidence is a fixed
    # per-label value (matches few-shot examples) since the API carries none.
    kind = f'"type":"{scam_type}",' if label != "SAFE" and scam_type else ""
    reason = reason.replace('"', "'")
    return f'{{"label":"{label}",{kind}"confidence":{_CONF[label]},"reason":"{reason}"}}'


def target_for_row(row: Row) -> str:
    """SFT target for a dataset row; reason is deterministic."""
    label = row["label"]
    if label == "SAFE":
        return format_target(label, None, "Normal conversation")
    st = row["scam_type"] or "OTHER"
    reason = f"Looks like {st.replace('_', ' ').lower()} scam" if label == "SCAM" else "Unsolicited risky claim"
    return format_target(label, st, reason)
