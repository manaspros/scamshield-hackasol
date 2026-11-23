# ScamShield — Final Problem Statement, Scope & Test Plan

**HackASol 5.0 · Gov-Tech · GT-02 Cyber Fraud Detection & Digital Financial Literacy Platform**
Items marked **[verify]** still need a primary source or a device test. Team handoff with the real code map and build notes: `SCAMSHIELD_HANDOFF.md`.

> **Scope (2026-11-23, revised):** we build on the team's **existing ScamShield app** (Flutter + Kotlin, Android, package `com.hackasol.scamshield`), not a rewrite. Target phone: 12 GB RAM; main test phone OnePlus 10T. Prototype mode: no prompt-injection defences, no edge-hardening tasks. Device testing and live-call reach are owned by teammates; this plan covers device-free work plus `[BLOCKED:device]` integration tasks.

## Current state (ScamShield)
Source: handoff §2-3. The code lives on a teammate's Windows machine (`D:\HackASol26\scamshield`) and is imported into this repo in T0.1.

| Exists (do not rebuild) | Gap (this plan builds) |
|---|---|
| Text API `classify(text, context[], source) → {label SAFE/SUSPICIOUS/SCAM, confidence, reason, triggers[], engine, latencyMs}` | `Source` enum, scam-type label on the verdict |
| `RuleScorer` (weighted EN/HI/Hinglish phrases) + Gemma 3 1B int4 (MediaPipe, downloaded from a GitHub release) fusion: Gemma decides, rules only raise, confidence = 0.7·Gemma + 0.3·rules | **SLM-first trained model**: LoRA fine-tune of the same Gemma 3 1B (scam vs genuine + scam type, EN/HI/Hinglish) + device-free eval harness (rules-only vs base Gemma vs fine-tuned) = the held-out accuracy deliverable (biggest judging gap) |
| Live Caption → `CaptionAccessibilityService` → `StatementSegmenter` → `TextApi` → `CallRiskTracker` → floating bubble | One alert dispatcher (heads-up notification and/or bubble, always with a Report action); local verdict event log |
| `InCallSignals` (OTP / UPI / AnyDesk during a call), `MicProbe` | Recorded-call path: file → offline STT → same pipeline (PS must-have) |
| Flutter Setup / Try API / Live feed / Settings; 24 Kotlin unit tests; `ModelDownloader` | Paste + share-sheet, notification listener (SMS/WhatsApp/Telegram); Report screen; Lessons + quiz + literacy score; trend dashboard; fake-QR checker |
| `core/UnicodeRegex.kt`, `proguard-rules.pro` keep-rules | Differentiators (knowledge graph, golden hour, family code, APK guard) built on the verdict log |

## 1. Problem statement
First-time digital users in Chhattisgarh lose money to scams that reach them through calls, SMS, WhatsApp, QR codes and fake apps. Chhattisgarh lost **₹107 cr in 18 months and recovered only ₹3.69 cr**. Number-reputation tools (Truecaller, Airtel spam labels) miss rotated numbers, speak no Chhattisgarhi, and stop helping once the money is gone.

**ScamShield is an offline, on-device fraud shield.** It judges **what is being said** (rules + a LoRA-fine-tuned Gemma 3 1B), warns **while it happens** (Live Caption → bubble/notification), and hands the user to the official channels with evidence ready. No audio is recorded for live use and nothing leaves the phone.

**Official PS must-haves (GT-02):** (1) ML scam message detector, EN + Hindi + Hinglish, offline, explains why · (2) scam call detector on a **recorded** call, with trigger phrases · (3) reporting handoff: 1930, cybercrime.gov.in, Chakshu (Sanchar Saathi), evidence checklist · (4) offline Hindi + Chhattisgarhi lessons + quiz → Digital Financial Literacy Score · (5) scam-trend dashboard (anonymised counts by region).
**Bonus:** live call warning (Live Caption + in-call signals) · fake-QR checker · new-scam clustering.
**Deliverables:** working prototype · **held-out accuracy on our own split** · brief `ARCHITECTURE.md`.

## 2. Architecture (one pipeline for every source)
```
caption | paste | share | sms/whatsapp (notification) | recording(STT)
        └─► StatementSegmenter ─► TextApi.classify(text, context, Source)
                RuleScorer + GemmaClassifier (SLM, outputs label + scam type + reason) ─► Fusion ─► Verdict(label, confidence, scamType, triggers…)
                     ├─► CallRiskTracker (whole-call risk, hysteresis)
                     ├─► VerdictLog (SQLite: source, scam type, triggers, time; no raw text)
                     └─► AlertDispatcher (heads-up notification and/or bubble, "Report" action)
VerdictLog ─► Report pre-fill · dashboard counts · (later) knowledge graph, golden hour
```
- **Fusion (one place, `core/Fusion.kt`):** SLM decides the label; strong rule matches can only raise it. Confidence = 0.7·Gemma + 0.3·rules, weights in one `FusionWeights` object. Scam type comes from the SLM output (prompt + `LlmOutputParser` extended); rules-only mode falls back to a rule-derived type. No separate classifier engine.
- **Recorded call:** pick a file → decode to 16 kHz mono → **Vosk** offline STT (Hindi small model; Maven AAR, no NDK build; whisper.cpp needs a JNI/NDK build and is the fallback if Vosk WER is poor) → `StatementSegmenter` → same `TextApi` → same `CallRiskTracker`.
- **Live:** Android Live Caption read by the accessibility service (built). Works for media on OnePlus 10T, not for calls there; Pixel likely works for calls **[verify]**; mic-probe results pending. Live-call reach is `[BLOCKED:device]` (Phase 6).
- **Default action:** heads-up notification for every SCAM/SUSPICIOUS result (`POST_NOTIFICATIONS` on Android 13+), bubble for live sources; both carry a Report action.
- **Dashboard:** opt-in anonymised `{district, scam_type, date}` counts only; a static page fed by sample + exported data.

## 3A. Where ML, where LLM, where plain code
| Layer | What runs there |
|---|---|
| **Plain code** (deterministic, unit-tested) | `RuleScorer`, `StatementSegmenter`, `CallRiskTracker`, `InCallSignals`, `Fusion`, `AlertPolicy`, UPI/QR parsing, notification filtering, report pack, TOTP, knowledge-graph lookups, trend export |
| **Trained model** (the PS "trained, not keywords" requirement) | **LoRA fine-tune of Gemma 3 1B** on EN/HI/Hinglish scam vs genuine data with scam-type labels, on the team's RTX 5090, converted to the MediaPipe `.task` int4 format and served through the existing `ModelDownloader`. Plus Vosk speech-to-text for recordings; optional clustering for new-scam alerts |
| **On-device SLM (Gemma 3 1B int4, MediaPipe; base now, fine-tuned after T1.14)** | Decides the label, scam type, reason and the Hindi warning line, per statement. Gemma 3n is an optional later upgrade only (T6.4) |
| **Offline generation only** | Synthetic EN/HI/Hinglish training data (deterministic templates; an optional teacher-LLM run by a human). Never in the on-device path. The held-out test is split **by scam template** and includes real collected messages where available |

## 4. Scope (impact-first build order)
| Phase | Content |
|---|---|
| P0 | Import ScamShield, JDK/Android SDK/Flutter on this Mac, baseline green |
| P1 **Foundation** | `Source` enum · scam-type label from the SLM output · verdict event log · fusion in one place · alert dispatcher · dataset + Gemma LoRA fine-tune/convert scripts + eval harness (`[BLOCKED:RTX 5090]` for the actual run) |
| P2 Input adapters | Paste/share-sheet, notification listener (SMS/WhatsApp/Telegram), recorded-call STT |
| P3 Must-have screens | Report, Lessons + quiz + literacy score, trend dashboard |
| P4 Bonus | Fake-QR checker, optional clustering |
| P5 Differentiators | Knowledge graph + claim-vs-context, mistaken-transfer, bank 1600, delivery masked numbers, golden hour + evidence ZIP, family code, APK guard |
| P6 `[BLOCKED:device]` | Pixel call captions, mic-probe path, release-APK regression on phones, optional Gemma 3n trial |
| P7 | `ARCHITECTURE.md`, demo script, accuracy slide, full gate |

## 5. Scenario specs (P5)
**Claim-vs-context:** a message claims a bill/order/bank event and the graph has no matching event, the sender is not a DLT header, or the link is not `.bank.in`/`.gov.in` → flag. **Cold start:** an empty graph says "no record since ScamShield was installed", never false certainty.
**Mistaken transfer A (fake credit SMS):** no bank-header credit event → "No money arrived. This SMS is not from your bank." **B (real credit, return request to a different UPI ID):** "This money may be stolen. Returning it yourself can get your account frozen. Ask them to request a reversal through their bank; contact your bank / 1930." **[verify RBI/NPCI wording]**
**Bank call:** banks call from the 1600 series; a 10-digit "bank" caller is flagged. **Delivery:** unknown number + "out for delivery" event within ~2 h → no alert; "parcel held, pay" with no order event → flag. **[verify patterns]**
**Fake QR:** `upi://pay?pa=a@bank&pn=Priya Stores` where the name the user was told differs → "Name does not match this UPI ID"; framing "You will PAY ₹X to <name>".
**Family code:** rotating TOTP code shared offline between two phones; a voice clone cannot know it. (No push relay: it would be a new endpoint.)

## 6. Test plan
- **Automated (Mac):** `cd android && ./gradlew :app:testDebugUnitTest` (24 existing + new), `flutter test`, `cd ml && uv run pytest -q`, `node --test dashboard/test`. Test names start with their task ID.
- **M1 held-out accuracy (device-free eval harness):** runs the held-out split through the same prompt and output parser as on device (Python port, parity-tested against Kotlin golden vectors) and reports precision / recall / FPR per language for **rules-only, base Gemma few-shot, fine-tuned Gemma**. Split by template; the report states real vs synthetic row counts; the headline is "real" only with ≥100 real rows. Scam-type macro-F1 alongside. Harness runs in bf16 via transformers; the shipped int4 `.task` is re-checked on a phone (T6.3).
- **Device (owned by teammates):** setup on OnePlus 10T, Live Caption on media and calls, mic probe, Pixel call captions, notification access, recorded-call run, airplane-mode demo. Always test **release** APKs (JVM tests miss Android behaviour). Device matrix kept in `SCAMSHIELD_HANDOFF.md` §8.
- **Privacy:** airplane mode: everything works except model download; dashboard export payload has exactly three keys.

## Key technical facts
- TRAI DLT headers like `VM-AMAZON`, suffix `-P/-S/-T/-G` **[verify]**; regex `^[A-Z]{2}-[A-Z0-9]{3,6}(-[PSTG])?$`. Scam SMS come from 10-digit numbers. Banks call from 1600-series numbers.
- Offline allowlists: `.bank.in`, `.gov.in`, SEBI `@valid` handles. No public API for I4C, Chakshu, NPCI payee name: deep-link the user.
- Public Hinglish scam data is tiny (`bolewara/hinglish-scam-text-dataset` ~35 rows): the team must collect real messages for the held-out test.
- Android pitfalls (handoff §7): no `(?U)` regex (use `core/UnicodeRegex.kt`), no accessibility-node work on the main thread, wrap accessibility callbacks, keep `proguard-rules.pro` rules, Play Protect blocks sideloaded accessibility apps (install with adb), Android 13+ restricted settings.
- Gemma terms: https://ai.google.dev/gemma/terms; model mirror: https://github.com/AB527/open-model (release `v1`, 555 MB).
