# ScamShield — Team Handoff

**Hackathon:** HackASol 5.0 · Track 5 Gov-Tech · **GT-02 Cyber Fraud Detection & Digital Financial Literacy Platform**
**Last updated:** 23 Nov 2026 (updated 23 Nov 2026: SLM-first)
**Code:** `D:\HackASol26\scamshield` (Flutter + Kotlin, Android only)
**Model mirror:** https://github.com/AB527/open-model (release `v1`, `gemma3-1b-it-int4.task`, 555 MB)

---

## 1. What we are building (one paragraph)
An offline Android app that warns people about scams **while they happen**. During a call, Android's
**Live Caption** turns speech into on-screen text; our **accessibility service** reads that text, splits it into
statements, and runs each one through an on-device **Text API** (keyword rules + **Gemma 3 1B** running on
the phone). A floating bubble shows *"🔴 This statement is SCAM · 87%"* with the reason, a Hindi line and a
**Call 1930** button. No audio is recorded and nothing leaves the phone.

## 2. Status at a glance

| Area | Status |
|---|---|
| Text API (rules + Gemma fusion, confidence, reasons) | ✅ Built, unit-tested |
| On-device Gemma 3 1B (MediaPipe) + in-app download from GitHub | ✅ Built; download verified, model loads on device |
| Live Caption → statements → verdict bubble | ✅ Works for **media** (YouTube, voice notes) |
| Live Caption during **calls** | ❌ Not on OnePlus 10T (Live Caption there captions media only). Pixel phones likely work |
| In-call signals (OTP arrives / UPI / AnyDesk opened during a call) | ✅ Built, needs on-phone test |
| Call-audio mic probe (can the mic hear calls?) | ✅ Built, **results not collected yet** |
| Crash fixes (main-thread scan, model crash loop, unhandled errors) | ✅ Fixed in latest APK |
| `NoClassDefFoundError` / `PlatformException CLASSIFY` on Analyse | 🔧 **Fixed, being verified** (see §7) |

## 3. Problem-statement checklist (what judges will look for)

| PS must-have | Where we are | Owner |
|---|---|---|
| **ML scam message detector** — trained model (not only keywords), English + Hindi + Hinglish, offline, explains why | ⚠️ Partly. We have rules + Gemma (few-shot, not *trained by us*). **SLM-first:** no separate classifier. **Need:** LoRA fine-tune of Gemma 3 1B (scam vs genuine + scam type) on the RTX 5090, converted to the MediaPipe `.task` int4 format and served via `ModelDownloader`; scam-type label comes from the SLM output | **TODO** |
| **Accuracy on our own held-out split** (deliverable) | ❌ Not done. **Need:** device-free eval harness (same prompt + `LlmOutputParser` format as on device) reporting precision/recall/FPR per language for rules-only, base Gemma few-shot and fine-tuned Gemma; split **by scam template**, real messages where available | **TODO** |
| **Scam call detector** — analyse a *recorded* call, transcribe, flag scripts + trigger phrases | ⚠️ We do live captions. **Need:** "pick a recording → offline speech-to-text (Vosk / whisper.cpp) → same Text API" | **TODO** |
| **Official reporting handoff** — 1930, cybercrime.gov.in, Chakshu (Sanchar Saathi) + evidence checklist | ⚠️ Only a "Call 1930" button in the bubble. **Need:** a Report screen | **TODO** |
| **Safety lessons + quiz (Hindi & Chhattisgarhi, offline)** → Digital Financial Literacy Score | ❌ Not started | **TODO** |
| **Scam-trend dashboard (policy view)**, anonymised counts by region | ❌ Not started | **TODO** |
| Bonus: live call warning | ✅ via Live Caption (on supported phones) + in-call signals | — |
| Bonus: fake-QR checker (UPI ID vs payee name) | ❌ Easy win (~3 h): parse `upi://pay?pa=&pn=` | **TODO** |
| Bonus: new-scam alerts (cluster similar reports) | ❌ | optional |

> **Biggest gaps vs judging:** trained classifier + accuracy number, lessons/quiz, reporting screen, dashboard.
> These are independent of the call work and can be done in parallel.

## 4. Architecture

```
Live Caption window ─► CaptionAccessibilityService (Kotlin, runs in background)
                          ├─ CaptionExtractor   reads caption text (background thread, caption windows only)
                          ├─ StatementSegmenter turns rolling caption text into sentences
                          ├─ TextApi.classify   RuleScorer (instant) + GemmaClassifier (1–3 s) → fused Verdict
                          ├─ CallRiskTracker    whole-call risk + red-alert hysteresis
                          ├─ InCallSignals      OTP / UPI / AnyDesk during a call
                          └─ OverlayController  floating bubble (TYPE_ACCESSIBILITY_OVERLAY)
                                  │ EventBus
Flutter UI (lib/) ◄── MethodChannel "scamshield/api" + EventChannel "scamshield/events"
  Setup · Try API · Live feed · Settings
```

**Text API contract** (same for captions, pasted messages, future SMS/recordings):
```
classify(text, context[], source) → { label: SAFE|SUSPICIOUS|SCAM, confidence 0..1, reason,
                                      triggers[], engine: "gemma+rules"|"rules-only", latencyMs }
```
Fusion: Gemma decides the label; strong rule matches can only *raise* it; confidence = 0.7·Gemma + 0.3·rules.

## 5. Code map

| Path | What it does |
|---|---|
| `android/app/src/main/kotlin/com/hackasol/scamshield/core/` | **Pure Kotlin, unit-tested:** `RuleScorer` (weighted EN/HI/Hinglish phrases), `StatementSegmenter`, `LlmOutputParser`, `CallRiskTracker`, `InCallSignals`, `UnicodeRegex`, `Models` |
| `…/GemmaClassifier.kt` | MediaPipe LLM inference, few-shot prompt, crash-loop guard |
| `…/TextApi.kt` | The single classify API + conflated caption queue |
| `…/CaptionAccessibilityService.kt` | Live pipeline, call detection, signals, mic probe trigger |
| `…/CaptionExtractor.kt` · `CaptionToggler.kt` · `OverlayController.kt` | Caption reading (+ OCR fallback) · Live Caption auto-toggle · bubble |
| `…/ModelDownloader.kt` | DownloadManager from GitHub release, progress events, auto-load |
| `…/MicProbe.kt` | Records 3 s per mic source during a call, reports HAS_AUDIO/SILENT, saves WAV |
| `…/MainActivity.kt` | Flutter ↔ Kotlin bridge |
| `lib/` | Flutter UI: `screens/setup_screen.dart`, `try_api_screen.dart`, `live_feed_screen.dart`, `settings_screen.dart` |
| `android/app/proguard-rules.pro` | **Keep rules — release build breaks without them** (MediaPipe/protobuf) |

## 6. Build, install, run

```bash
# Windows Git Bash — Gradle needs Android Studio's JDK
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd D:/HackASol26/scamshield

flutter run                                   # phone connected, USB debugging on
flutter build apk --release --split-per-abi   # → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (~41 MB)
flutter build apk --release                   # universal (~109 MB), any phone

cd android && ./gradlew :app:testDebugUnitTest   # Kotlin tests (24)
flutter test                                      # Dart tests
```

**Install on a phone**
- Best: `adb install -r ScamShield-arm64.apk` (Play Protect's India fraud protection blocks sideloaded
  accessibility apps installed from WhatsApp/browser).
- Otherwise: Play Store → Play Protect → ⚙ → turn off scanning temporarily.
- **Uninstall any older build first** if installing fails ("package conflicts").

**First-run setup on the phone**
1. Setup → Open Accessibility → **ScamShield call protection → On**.
   Greyed out / "Restricted setting" → App info → ⋮ → **Allow restricted settings**.
2. Settings → Apps → ScamShield → Battery → **Unrestricted** (OnePlus/Samsung kill it otherwise).
3. Setup → **Download model** (555 MB from GitHub, Wi-Fi by default) → status **READY**.
4. Setup → **Show test bubble**.
5. Turn on Live Caption (volume key → captions icon) → play a scam-call video → bubble + Live tab.

## 7. Known issues & lessons learned

| Issue | Cause | Status |
|---|---|---|
| `PlatformException(CLASSIFY, qr.k…)` on Analyse, `NoClassDefFoundError: q2.d` in Live tab | Regex flag `(?U)` works on desktop Java (tests passed) but **Android's ICU regex rejects it** → RuleScorer/InCallSignals fail to initialise | Fixed via `core/UnicodeRegex.kt`; verifying on emulator |
| App crashes; accessibility turns itself off; Samsung "clear cache" | Main-thread scanning of all windows (ANR) + model load crash loop + unhandled exceptions | Fixed (background scan, crash guard, `safe{}` wrappers) |
| Obfuscated names (`qr.k`) in errors | R8 renames classes in release | App classes now kept in `proguard-rules.pro` |
| No captions during calls on OnePlus 10T | Phone limitation (Live Caption = media only) | Use in-call signals + mic probe; demo live captions on a Pixel or with media |
| Gemma `.task` SHA-256 ≠ Hugging Face API hash | Unclear (size identical, all internal CRCs pass) | File is valid; noted |

**Rules of thumb:** always test release APKs on a real phone (JVM tests miss Android-only behaviour);
never do accessibility-node work on the main thread; anything in an accessibility callback must be wrapped.

## 8. Phone findings so far
| Phone | Live Caption media | Live Caption calls | Notes |
|---|---|---|---|
| OnePlus 10T | ✅ | ❌ | Strong for Gemma (8 GB+ RAM). Mic probe result pending |
| Samsung (model?) | ? | ? | Accessibility showed "disabled" → follow setup step 1 |

**Please add rows** as you test: run Setup → step 4 "Test on my next call", call on speaker, and note which
mic sources show HAS_AUDIO in the Live tab and whether the *caller* is audible on playback.

## 9. Suggested split of remaining work (36-hour plan)

| Person | Task | Est. |
|---|---|---|
| A | **Dataset + SLM fine-tune + eval harness**: collect/generate EN/HI/Hinglish scam & genuine messages with scam-type labels, split by template, LoRA fine-tune Gemma 3 1B on the RTX 5090, convert to `.task` int4, publish via `ModelDownloader`; eval harness reports held-out accuracy (rules-only vs base vs fine-tuned) | 6–8 h |
| B | **Lessons + quiz** (Hindi + Chhattisgarhi visual cards, offline JSON) → Digital Financial Literacy Score | 5–6 h |
| C | **Report screen** (1930 dial, cybercrime.gov.in, Chakshu/Sanchar Saathi links, evidence checklist) + **Fake-QR checker** | 4–5 h |
| D | **Scam-trend dashboard** (anonymised counts by district; can be a small web page fed by sample data) | 4–5 h |
| E (me/Claude) | Verify fixes, recorded-call analysis (offline STT), WhatsApp message scanning, device testing | ongoing |

## 10. Demo script (3 minutes)
1. **Problem** (20 s): first-time UPI users, digital-arrest/OTP scams, resources only in English & online.
2. **Try API** (30 s): paste a Hinglish OTP scam → *SCAM 95%, "Asks you to share OTP"*, `gemma+rules`, offline (airplane mode on!).
3. **Live caption** (60 s): play a "digital arrest" call recording on the phone → bubble turns 🟡 then 🔴 with Hindi warning and **Call 1930**.
4. **In-call signal** (30 s): during a call, open PhonePe → 🟡 "Is the caller asking you to pay?"
5. **Lessons/quiz + report + dashboard** (30 s) once built.
6. **Privacy line:** "We never record your call. We read captions Android already shows you, on the device."

## 11. Contacts / links
- Problem statement: `D:\HackASol26\Hackasol_5.0_Problem_Statement.pdf` (GT-02, page 10)
- Model: https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task
- Gemma terms: https://ai.google.dev/gemma/terms
