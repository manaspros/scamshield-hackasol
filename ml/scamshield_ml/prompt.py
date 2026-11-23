"""Port of the on-device Gemma prompt (Kotlin `GemmaPrompt` in core/GemmaPrompt.kt) and SFT target format."""

from __future__ import annotations

from collections.abc import Sequence

from scamshield_ml.data import Row

# Verbatim from GemmaPrompt.kt `HEADER` (raw string, no escapes).
HEADER = """You are a fraud detector for Indian phone calls. Classify the caller's STATEMENT as SAFE, SUSPICIOUS or SCAM. Text may be English, Hindi (Devanagari) or Hinglish.
SCAM: asks for OTP/PIN/CVV/password, threatens arrest or "digital arrest", says police/CBI/customs/courier has a case against you, asks to move money to a "safe account", install AnyDesk/an app, or keep the call secret.
SUSPICIOUS: unsolicited bank/KYC/prize/loan/refund claims, urgency, asks for personal details, but no direct demand yet.
SAFE: normal conversation.
For SCAM or SUSPICIOUS also give scam_type: OTP, KYC, DIGITAL_ARREST, COURIER_CUSTOMS, FAKE_QR, LOAN_APP, INVESTMENT, JOB, MISTAKEN_TRANSFER or OTHER. For SAFE use NONE.
Answer with ONLY one line of JSON: {"label":"SAFE|SUSPICIOUS|SCAM","scam_type":"OTP|KYC|DIGITAL_ARREST|COURIER_CUSTOMS|FAKE_QR|LOAN_APP|INVESTMENT|JOB|MISTAKEN_TRANSFER|OTHER|NONE","confidence":0.0-1.0,"reason":"max 10 words"}

STATEMENT: "Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye"
{"label":"SCAM","scam_type":"OTP","confidence":0.97,"reason":"Asks you to share OTP"}
STATEMENT: "मैं सीबीआई ऑफिस से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं"
{"label":"SCAM","scam_type":"DIGITAL_ARREST","confidence":0.98,"reason":"Fake CBI digital arrest threat"}
STATEMENT: "Your parcel to Taiwan has drugs, press 1 to talk to customs officer"
{"label":"SCAM","scam_type":"COURIER_CUSTOMS","confidence":0.93,"reason":"Fake customs parcel story"}
STATEMENT: "Main SBI bank se bol raha hoon, aapka KYC pending hai"
{"label":"SUSPICIOUS","scam_type":"KYC","confidence":0.75,"reason":"Unsolicited bank KYC claim"}
STATEMENT: "Beta khana kha liya? Kal shaam ko milte hain"
{"label":"SAFE","scam_type":"NONE","confidence":0.95,"reason":"Normal family conversation"}
STATEMENT: "Your order will be delivered tomorrow between 10 and 12"
{"label":"SAFE","scam_type":"NONE","confidence":0.85,"reason":"Routine delivery update"}
"""

_CONF = {"SAFE": 0.95, "SUSPICIOUS": 0.75, "SCAM": 0.95}


def _take(s: str, n: int) -> str:
    """Kotlin `String.take(n)`: n UTF-16 code units (a lone cut surrogate is kept, as in Kotlin)."""
    return s.encode("utf-16-le")[: 2 * n].decode("utf-16-le", errors="surrogatepass")


def build_prompt(text: str, context: Sequence[str] = (), context_label: str = "Earlier in this call") -> str:
    """Byte-exact port of Kotlin `GemmaPrompt.build` (last 2 non-blank context lines, 150/300 char caps; Kotlin counts UTF-16 units)."""
    parts = [HEADER]
    ctx = [c for c in list(context)[-2:] if c.strip()]
    if ctx:
        parts.append(f"\n{context_label}: " + " | ".join(f'"{_take(c, 150)}"' for c in ctx) + "\n")
    parts.append('STATEMENT: "' + _take(text, 300).replace('"', "'") + '"\n')
    return "".join(parts)


# Short instruction for fine-tuned models: the few-shot HEADER is ~700 tokens of prefill on every call,
# which dominates phone latency. Not used on device yet (GemmaPrompt.kt would need a matching variant).
SHORT_HEADER = (
    "Classify the Indian call or message STATEMENT as SAFE, SUSPICIOUS or SCAM with scam_type "
    "(NONE for SAFE). Answer with one line of JSON.\n"
)


def build_short_prompt(text: str, context: Sequence[str] = (), context_label: str = "Earlier in this call") -> str:
    """Same context and STATEMENT lines as build_prompt, with SHORT_HEADER instead of the few-shot HEADER."""
    return SHORT_HEADER + build_prompt(text, context, context_label)[len(HEADER):]


PROMPTS = {"fewshot": build_prompt, "short": build_short_prompt}


def format_target(label: str, scam_type: str | None, reason: str) -> str:
    """Model output in the one-line JSON GemmaPrompt.kt documents and LlmOutputParser reads."""
    # Confidence is a fixed per-label value (matches the few-shot examples); the dataset carries none.
    kind = "NONE" if label == "SAFE" else (scam_type or "OTHER")
    reason = reason.replace('"', "'")
    return f'{{"label":"{label}","scam_type":"{kind}","confidence":{_CONF[label]},"reason":"{reason}"}}'


def target_for_row(row: Row) -> str:
    """SFT target for a dataset row; reason is deterministic."""
    label = row["label"]
    if label == "SAFE":
        return format_target(label, None, "Normal conversation")
    st = row["scam_type"] or "OTHER"
    reason = f"Looks like {st.replace('_', ' ').lower()} scam" if label == "SCAM" else "Unsolicited risky claim"
    return format_target(label, st, reason)
