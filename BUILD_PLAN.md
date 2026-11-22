# ScamShield — Build Plan

Source of truth: `FINAL_PLAN.md` (current state, scope, ML/LLM/code split, tests). `SCAMSHIELD_HANDOFF.md` has the real code map. This file only schedules work. We **extend the existing ScamShield app**; nothing the handoff lists as built is a task here. Target: 12 GB phone (main test phone OnePlus 10T). Prototype mode: no prompt-injection, adversarial or edge-hardening tasks. Device testing and live-call reach belong to teammates: only `[BLOCKED:device]` integration tasks appear here.

## Conventions
- Owner tag right after the ID: `[sonnet]` = Claude Sonnet subagent (Agent tool, `model: sonnet`); `[codex]` = Codex worker via Orca (`orchestration` skill). Codex: self-contained test-first code (pure Kotlin core rules and parsers, Python ML, rule additions). Sonnet: UI, Android services, wiring, anything needing judgment. Max 4 workers in parallel; parallel tasks need disjoint **Files** and finished deps. Tasks sharing a file (`Models.kt`, `TextApi.kt`, `MainActivity.kt`, `try_api_screen.dart`, `report_screen.dart`) are serialised through **Depends on**. Only the orchestrator edits `BUILD_PLAN.md`/`PROGRESS.md`.
- Other tags: `[UI]` Sonnet worker invokes `frontend-design` first (`[UI+DATAVIZ]` also `dataviz`); `[NEEDS-OK:DEPn]` runnable only when DEPn is `yes`; `[BLOCKED:reason]` needs a human, device, RTX 5090 or real data (loop skips and lists it, never fakes it); `[VERIFY:x]` an assumption a human confirms, never blocks; `[OPTIONAL]` skipped unless its trigger holds.
- Paths (repo root = Flutter project root after T0.1): `K/` = `android/app/src/main/kotlin/com/hackasol/scamshield/` · `K/core/` = pure Kotlin, unit-tested, no Android imports · `KT/` = `android/app/src/test/kotlin/com/hackasol/scamshield/` (T0.5 records the real test path) · `lib/` Flutter UI (`lib/screens/*`) · `ml/` Python (`uv`) · `dashboard/` static page + zero-dep Node helpers · `data/` golden vectors, trend samples, `data/eval/real/` (gitignored: real messages never enter git) · `scripts/`.
- Shorthands: `KT(x)` = `cd android && ./gradlew :app:testDebugUnitTest --tests '*x*'` · `KALL` = `cd android && ./gradlew :app:testDebugUnitTest` · `FT(x)` = `flutter test test/x` · `PT(x)` = `cd ml && uv run pytest -q x` · `NT(x)` = `node --test dashboard/test/x` · `APP` = `flutter build apk --debug` · `REL` = `flutter build apk --release --split-per-abi`.
- Test names start with their task ID (`T1_5_...`; Dart `testWidgets('T3_2_...')`). Done-when = exit 0 and the named tests actually ran (not "0 tests"). `scripts/trace_report.sh` maps results to task IDs.
- Keep the fusion rule: SLM (Gemma) decides, rules can only raise, confidence = 0.7·Gemma + 0.3·rules, all weights in `K/core/Fusion.kt`. No third classifier engine. Scam type comes from the SLM output; rules-only mode uses a rule-derived type.
- Placement: every consumer of the verdict needs `Source`, scam type, the log and the dispatcher, so they live in the shared layer (`K/core`, `TextApi`); screens and adapters stay consumer-specific. No new endpoint, env var, flag or dependency unless the Dependencies table lists it.
- **Android pitfalls (handoff §7):** no `(?U)` regex flag, use `core/UnicodeRegex.kt` (Android ICU rejects it; JVM tests pass anyway) · never do accessibility-node work on the main thread · wrap every accessibility callback (`safe{}`) · keep the keep-rules in `android/app/proguard-rules.pro` (MediaPipe/protobuf; add rules for any new library) · release APKs must be device-tested: JVM tests miss Android behaviour, so every `REL` Done-when is compile-only and the behaviour check is T6.3.
- `[VERIFY]` items become named constants with a comment: DLT suffix rule, RBI/NPCI mistaken-transfer wording, 1600 series, delivery patterns, Chakshu URL, Chhattisgarh district list.
- Python, Dart and Node tasks (T1.8-T1.12, T1.14, T3.3, T3.4, T3.7, T3.9) do not need the imported app code, so the loop keeps moving while T0.1 awaits the source.

## Requirements & external dependencies
| Feature | Needs | Fallback if it fails |
|---|---|---|
| Live Caption warning | Phone with caption support (media: OnePlus 10T works; calls: Pixel likely [verify]) | In-call signals + recorded-call path |
| Notification guard | Notification access granted by user | Paste / share-sheet |
| Recorded call | Vosk hi model on device (T2.6), 12 GB phone | Pre-recorded demo audio |
| Fine-tuned Gemma | RTX 5090 box, Gemma licence acceptance, human uploads `.task` to a release | Base Gemma 3 1B keeps working |
| M1 headline number | 100+ real messages in `data/eval/real/` | Report labelled "synthetic held-out by template" |
Humans must supply: ScamShield source (git URL or zip); RTX 5090 Linux box; real scam/benign messages; the 12 GB phone, a Pixel; a native Chhattisgarhi speaker; a release host for the fine-tuned `.task`.

## Dependencies to approve
Loop must not install anything whose row says `no`. On approval it records the pinned version (newest public >=7 days) in `PROGRESS.md`. No `pip install` (uv only); no new install-time scripts. Already shipped by ScamShield (not listed): Kotlin/AGP, MediaPipe `tasks-genai`, Flutter template packages, JUnit.
| ID | Dependency | Purpose | Approved |
|---|---|---|---|
| DEP1 | JDK 17 (`brew install --cask temurin@17`); `JAVA_HOME=$(/usr/libexec/java_home -v 17)` | Gradle | yes |
| DEP2 | Android cmdline-tools, `platform-tools`, platforms/build-tools matching `compileSdk` in the imported project; no emulator; licence acceptance is a human step | Build APK, adb | yes |
| DEP3 | Flutter SDK, stable >=7 days (`brew install --cask flutter`, analytics disabled) | Flutter UI | yes |
| DEP4 | Python via uv (Mac): numpy, pyyaml, pytest; scikit-learn only for T4.4 | Dataset, eval harness, optional clustering | yes |
| DEP5 | Python via uv on the RTX 5090 box only: torch (CUDA 12.8+), transformers, peft, trl, datasets, and the MediaPipe/ai-edge-torch converter (name confirmed in T1.11) | Gemma LoRA fine-tune, bf16 eval, `.task` conversion [VERIFY converter supports Gemma 3 1B at the pinned version] | yes |
| DEP6 | `com.alphacephei:vosk-android` AAR + `vosk-model-small-hi` (downloaded on device, not in git) | Offline STT for recordings. Chosen over whisper.cpp: Maven AAR, no NDK/JNI build; whisper.cpp is the fallback if Vosk WER is poor | yes |
| DEP7 | ML Kit `play-services-code-scanner` | QR scan (T4.3, optional) | yes |
| DEP8 | Gemma 3n weights (human downloads, accepts licence) | T6.4 only | yes |
Node: no npm packages (`node:test`, `node:http`). No new Flutter pub packages: use platform channels and existing persistence.

## Phase 0 — Import + toolchain
- [x] T0.1 [sonnet] Import ScamShield into the repo root; add `.gitignore` (`.dart_tool/`, `build/`, `local.properties`, `.env*`, `.venv/`, `data/eval/real/`, `*.task`, `*.keystore`); create `PROGRESS.md` (Done / Blocked / Decisions / Failures / Model ids)
  - **Files**: repo root (copy, drop nested `.git`, skip build outputs, keystores, `local.properties`), `.gitignore`, `PROGRESS.md`  **Depends on**: none
  - **Done when**: `ls android/app/src/main/kotlin/com/hackasol/scamshield/core/RuleScorer.kt lib/screens/try_api_screen.dart android/app/proguard-rules.pro` lists all three; `git status --short` clean after commit; no `*.task` or key file tracked
- [x] T0.2 [sonnet] [NEEDS-OK:DEP1] Install JDK 17  **Files**: none  **Depends on**: none
  - **Done when**: `/usr/libexec/java_home -v 17 && java -version 2>&1 | head -1` shows 17.x
- [x] T0.3 [sonnet] [NEEDS-OK:DEP2] Install Android SDK packages (human types `sdkmanager --licenses`)  **Files**: `android/local.properties` (gitignored)  **Depends on**: T0.1, T0.2
  - **Done when**: `sdkmanager --list_installed` lists platform-tools, the platform and build-tools; `adb version` runs
- [x] T0.4 [sonnet] [NEEDS-OK:DEP3] Install Flutter SDK, point it at the Android SDK  **Files**: none  **Depends on**: T0.3
  - **Done when**: `flutter --version` prints the pinned version; `flutter doctor -v` shows "Android toolchain" without errors
- [x] T0.5 [sonnet] Baseline green; record Kotlin and Dart test counts and the real test-source path in `PROGRESS.md`
  - **Files**: `PROGRESS.md`  **Depends on**: T0.1, T0.4
  - **Done when**: `KALL` exits 0 with 24 tests; `flutter test` exits 0; `APP` produces `build/app/outputs/flutter-apk/app-debug.apk`
- [ ] T0.6 [sonnet] `scripts/check.sh` (runs every suite that exists, prints skipped) and `scripts/trace_report.sh` (task ID -> pass/fail/not-run/blocked from JUnit XML, pytest `-rA`, node, flutter output)
  - **Files**: `scripts/check.sh`, `scripts/trace_report.sh`  **Depends on**: T0.5
  - **Done when**: `bash scripts/check.sh && bash scripts/trace_report.sh` exits 0

## Phase 1 — Foundation (everything else plugs into this)
- [x] T1.1 [codex] Extend TextApi `source` to a `Source` enum (CAPTION, PASTE, SHARE, SMS, WHATSAPP, NOTIFICATION, RECORDING); old string values from `MainActivity`/Dart still parse
  - **Files**: `K/core/Models.kt`, `K/TextApi.kt`, `K/MainActivity.kt`, `KT/core/SourceTest.kt`  **Depends on**: T0.5
  - **Done when**: `KT(SourceTest)` passes `T1_1_parsesLegacyStrings`; `KALL` stays green
- [x] T1.2 [codex] Scam-type label from the SLM: `ScamType` enum (OTP, KYC, DIGITAL_ARREST, COURIER_CUSTOMS, FAKE_QR, LOAN_APP, INVESTMENT, JOB, MISTAKEN_TRANSFER, OTHER; SAFE has none); extract the few-shot prompt into pure `K/core/GemmaPrompt.kt` with a scam-type output line; extend `LlmOutputParser` to read it (missing/unknown -> OTHER); `RuleScorer` triggers map to a rule-derived type for rules-only mode; Kotlin test writes `data/golden/prompt_golden.json` (prompt text + sample model outputs + parsed result)
  - **Files**: `K/core/Models.kt`, `K/core/GemmaPrompt.kt`, `K/core/LlmOutputParser.kt`, `K/core/RuleScorer.kt`, `K/GemmaClassifier.kt` (call the extracted builder), `KT/core/ScamTypeTest.kt`, `data/golden/prompt_golden.json`  **Depends on**: T1.1
  - **Done when**: `KT(ScamTypeTest)` passes `T1_2_parsesScamType`, `T1_2_ruleTypeFallback`, `T1_2_goldenWritten`; existing parser tests unchanged and green in `KALL`
- [ ] T1.3 [codex] Verdict event log, pure: `VerdictEvent{id, tsMs, source, label, confidence, scamType, triggers, engine}` (no raw text stored), `VerdictLog` interface (`append`, `since`, `latest`, `countsByType`), in-memory impl
  - **Files**: `K/core/VerdictLog.kt`, `KT/core/VerdictLogTest.kt`  **Depends on**: T1.2
  - **Done when**: `KT(VerdictLogTest)` passes `T1_3_countsByType`, `T1_3_sinceFilters`
- [ ] T1.4 [sonnet] SQLite verdict log persisting every `TextApi` result (all sources); channel methods `verdicts.recent(sinceMs)` and `verdicts.counts`
  - **Files**: `K/SqliteVerdictLog.kt`, `K/TextApi.kt`, `K/MainActivity.kt`, `KT/VerdictRowMapperTest.kt`  **Depends on**: T1.3
  - **Done when**: `APP` succeeds; `KT(VerdictRowMapperTest)` passes (row <-> event round trip); `KALL` green
- [ ] T1.5 [codex] Fusion in one place: move the existing fusion out of `TextApi` into `K/core/Fusion.kt` with a `FusionWeights` object; behaviour unchanged (regression-locked); scam type = SLM type when present, else rule type
  - **Files**: `K/core/Fusion.kt`, `K/TextApi.kt`, `KT/core/FusionTest.kt`  **Depends on**: T1.4
  - **Done when**: `KT(FusionTest)` passes `T1_5_gemmaDecides`, `T1_5_rulesOnlyRaise`, `T1_5_confidence70_30`, `T1_5_rulesOnlyMode`
- [ ] T1.6 [codex] `AlertPolicy` (pure): Verdict + Source -> `{bubble, notify, reportAction}`; SCAM -> notify + (bubble when CAPTION), SUSPICIOUS -> bubble for live sources else notify, SAFE -> nothing
  - **Files**: `K/core/AlertPolicy.kt`, `KT/core/AlertPolicyTest.kt`  **Depends on**: T1.1
  - **Done when**: `KT(AlertPolicyTest)` passes one test per label/source combo (`T1_6_...`)
- [ ] T1.7 [sonnet] `AlertDispatcher`: high-importance heads-up notification channel + bubble via existing `OverlayController`, always with a "Report" action (PendingIntent -> `MainActivity` extra `route=report`); request `POST_NOTIFICATIONS` on Android 13+ in Setup; `CaptionAccessibilityService` calls the dispatcher (callbacks stay wrapped in `safe{}`)
  - **Files**: `K/AlertDispatcher.kt`, `K/CaptionAccessibilityService.kt`, `K/MainActivity.kt`, `android/app/src/main/AndroidManifest.xml`, `lib/screens/setup_screen.dart`  **Depends on**: T1.4, T1.5, T1.6
  - **Done when**: `APP` succeeds; `KT(AlertDispatcherMappingTest)` passes (plan -> notification fields incl. Report action); `FT(setup_screen_test.dart)` passes if it exists, else `flutter test` green
- [x] T1.8 [codex] [NEEDS-OK:DEP4] `ml/` uv project + dataset schema + split by scam template (`text,label,lang,scam_type,template_id,source`, source = synthetic|real; real rows load from `data/eval/real/` and go to the test set only)
  - **Files**: `ml/pyproject.toml`, `ml/uv.lock`, `ml/scamshield_ml/data.py`, `ml/tests/test_data.py`  **Depends on**: none
  - **Done when**: `PT(tests/test_data.py)` passes `T1_8_noTemplateInBothSplits`, `T1_8_realRowsTestOnly`
- [x] T1.9 [codex] Deterministic synthetic generator: EN / Hindi (Devanagari) / Hinglish, 10 scam types plus hard genuine negatives (real bank OTP notices, delivery updates, bills), >=40 templates per language, slot-filled; output also as SFT pairs (prompt + target in the on-device output format)
  - **Files**: `ml/scamshield_ml/synth.py`, `ml/tests/test_synth.py`  **Depends on**: T1.8
  - **Done when**: `PT(tests/test_synth.py)` passes `T1_9_templateCountPerLang`, `T1_9_allScamTypesPresent`, `T1_9_sftPairsWellFormed`
- [ ] T1.10 [codex] Python port of the on-device prompt builder and output parser (the harness and training must use exactly the on-device format)
  - **Files**: `ml/scamshield_ml/prompt.py`, `ml/scamshield_ml/parser.py`, `ml/tests/test_prompt_parity.py`  **Depends on**: T1.2, T1.8
  - **Done when**: `PT(tests/test_prompt_parity.py)` passes: prompt text equals and parsed results equal every entry of `data/golden/prompt_golden.json`
- [x] T1.11 [codex] [NEEDS-OK:DEP5] Gemma 3 1B LoRA fine-tune script (peft + trl, SFT on the T1.9 pairs, config in YAML, train split only) and conversion script (merge LoRA -> HF checkpoint -> MediaPipe `.task` int4); both support `--dry-run`/`--limit` so they are testable without a GPU
  - **Files**: `ml/scamshield_ml/finetune.py`, `ml/scamshield_ml/convert_task.py`, `ml/configs/lora.yaml`, `ml/tests/test_finetune_dry.py`  **Depends on**: T1.9, T1.10
  - **Done when**: `PT(tests/test_finetune_dry.py)` passes `T1_11_formatsExamples`, `T1_11_convertDryRunArgs`; converter package name and version recorded in `PROGRESS.md`
- [ ] T1.12 [codex] Rules-only predictions exporter: a Kotlin test reads the eval CSV and writes `RuleScorer` predictions (label, scam type, triggers) as JSONL, so the Python harness reports rules-only without re-implementing the rules
  - **Files**: `KT/core/RulesEvalExportTest.kt`, `data/golden/eval_smoke.csv`  **Depends on**: T1.2, T1.8
  - **Done when**: `KT(RulesEvalExportTest)` passes `T1_12_writesJsonl` and `android/app/build/rules_preds.jsonl` has one line per CSV row
- [x] T1.13 [codex] Eval harness (device-free): held-out split -> same prompt + parser -> precision/recall/FPR per language and scam-type macro-F1 for **rules-only** (from T1.12 JSONL), **base Gemma few-shot** and **fine-tuned Gemma** (`--backend hf` on the RTX box, `--backend stub` for tests); report states real vs synthetic counts, headline "real" only with >=100 real rows; writes `ml/reports/m1.json` and `docs/accuracy.md` (table for the slide)
  - **Files**: `ml/scamshield_ml/eval_heldout.py`, `ml/tests/test_eval.py`, `docs/accuracy.md`  **Depends on**: T1.9, T1.10, T1.12
  - **Done when**: `PT(tests/test_eval.py)` passes `T1_13_perLanguageMetrics`, `T1_13_threeSystemsInReport`, `T1_13_labelsRealVsSynthetic` with the stub backend
- [ ] T1.14 [sonnet] Run it on this Mac (user 2026-11-23: no RTX 5090, keep the existing base Gemma 3 1B model): eval rules-only and base Gemma (HF bf16 on MPS, or stub if weights unavailable); fine-tuned row reported "not run"; report labelled synthetic unless >=100 real rows
  - **Files**: `ml/reports/m1.json`, `docs/accuracy.md`, `PROGRESS.md` (model id + URL)  **Depends on**: T1.11, T1.13
  - **Done when**: `ml/reports/m1.json` has numbers for rules-only and base Gemma, fine-tuned marked "not run", real row count stated
- [ ] T1.15 [sonnet] Make the model source configurable and wire the SLM scam type end to end: `ModelDownloader` URL/filename/SHA from one constant (default stays the current GitHub release; switch to the fine-tuned URL after T1.14), `GemmaClassifier` uses `GemmaPrompt`, `TextApi` fills `Verdict.scamType` from the parsed output, `proguard-rules.pro` unchanged or extended
  - **Files**: `K/ModelDownloader.kt`, `K/GemmaClassifier.kt`, `K/TextApi.kt`, `KT/ModelConfigTest.kt`  **Depends on**: T1.5, T1.2
  - **Done when**: `APP` and `REL` succeed; `KT(ModelConfigTest)` passes `T1_15_urlFromConstant`; `KALL` green

## Phase 2 — Input adapters into TextApi
- [ ] T2.1 [sonnet] [UI] Paste + share-sheet: extend Try API (source=PASTE, shows scam type chip + triggers); transparent `ShareReceiver` activity for `ACTION_SEND text/plain` (source=SHARE) -> TextApi -> dispatcher
  - **Files**: `lib/screens/try_api_screen.dart`, `K/ShareReceiver.kt`, `android/app/src/main/AndroidManifest.xml`  **Depends on**: T1.7, T1.15
  - **Done when**: `APP` succeeds; `FT(try_api_screen_test.dart)` passes `T2_1_showsTypeAndTriggers` (fake channel); `KT(ShareIntentMapperTest)` passes
- [ ] T2.2 [codex] `NotificationMapper` (pure): package -> Source (WhatsApp, Telegram, default SMS apps -> SMS, else NOTIFICATION), ignore ongoing/group-summary/own package, min length 15, dedupe same text within 60 s
  - **Files**: `K/core/NotificationMapper.kt`, `KT/core/NotificationMapperTest.kt`  **Depends on**: T1.1
  - **Done when**: `KT(NotificationMapperTest)` passes `T2_2_mapsPackages`, `T2_2_dedupes`, `T2_2_ignoresOwn`
- [ ] T2.3 [sonnet] `ScamNotificationListener` service (no `READ_SMS`; SMS arrive as notifications) -> mapper -> TextApi -> dispatcher; "Notification access" step added to Setup; all callbacks wrapped
  - **Files**: `K/ScamNotificationListener.kt`, `android/app/src/main/AndroidManifest.xml`, `lib/screens/setup_screen.dart`  **Depends on**: T2.2, T1.7, T1.15
  - **Done when**: `APP` succeeds; `KT(ListenerWiringTest)` passes (fake classify called with the right Source); manifest has no `READ_SMS`
- [ ] T2.4 [codex] `RecordingPipeline` (pure): STT segments `{text, startMs}` -> `StatementSegmenter` -> classify function (source=RECORDING) -> existing `CallRiskTracker` -> `CallReport{overall, perStatement, topTriggers}`
  - **Files**: `K/core/RecordingPipeline.kt`, `KT/core/RecordingPipelineTest.kt`  **Depends on**: T1.1
  - **Done when**: `KT(RecordingPipelineTest)` passes `T2_4_scamScriptRaisesRisk`, `T2_4_genuineCallStaysSafe` (fake classify, real tracker)
- [ ] T2.5 [sonnet] `AudioDecoder`: MediaExtractor/MediaCodec -> 16 kHz mono PCM16 chunks; pure `PcmResampler` for downmix/resample
  - **Files**: `K/AudioDecoder.kt`, `K/core/PcmResampler.kt`, `KT/core/PcmResamplerTest.kt`  **Depends on**: T0.5
  - **Done when**: `APP` succeeds; `KT(PcmResamplerTest)` passes `T2_5_downmixAndRate`
- [ ] T2.6 [sonnet] [NEEDS-OK:DEP6] Vosk STT engine + Hindi model download via the existing `ModelDownloader` path; Vosk JSON -> `SttSegment`; keep-rules added
  - **Files**: `android/app/build.gradle(.kts)`, `K/SttEngine.kt`, `K/ModelDownloader.kt`, `android/app/proguard-rules.pro`, `KT/core/SttResultParserTest.kt`  **Depends on**: T2.5, T1.15
  - **Done when**: `APP` and `REL` succeed; `KT(SttResultParserTest)` passes `T2_6_parsesVoskJson`
- [ ] T2.7 [sonnet] [UI] Recording screen: pick file (SAF) or share `audio/*` -> decode -> STT -> pipeline; progress, per-statement timeline with verdicts, overall risk, trigger phrases, Report button
  - **Files**: `lib/screens/recording_screen.dart`, `K/RecordingChannel.kt`, `K/MainActivity.kt`, `android/app/src/main/AndroidManifest.xml`  **Depends on**: T2.4, T2.6, T1.7
  - **Done when**: `APP` succeeds; `FT(recording_screen_test.dart)` passes `T2_7_rendersTimelineAndRisk` (fake channel)
- [ ] T2.8 [sonnet] [BLOCKED:device: OnePlus 10T + real or team-scripted Hindi call recording] Run T2.7 on the phone; log verdict, STT quality and latency
  - **Files**: `PROGRESS.md`  **Depends on**: T2.7
  - **Done when**: human logs result with phone model and model id

## Phase 3 — Must-have screens
- [ ] T3.1 [codex] `ReportPack` (pure): targets (money lost: 1930 + cybercrime.gov.in; not yet: Chakshu/Sanchar Saathi + 1930) as `[VERIFY]` constants; evidence checklist pre-filled from recent `VerdictEvent`s (time, scam type, source, triggers; user adds number, amount, UTR, screenshots)
  - **Files**: `K/core/ReportPack.kt`, `KT/core/ReportPackTest.kt`  **Depends on**: T1.3
  - **Done when**: `KT(ReportPackTest)` passes `T3_1_prefillsFromEvents`, `T3_1_lostVsNotYetTargets`
- [ ] T3.2 [sonnet] [UI] Report screen: two paths ("I lost money" / "not yet"), checklist, buttons for 1930 (`ACTION_DIAL`, never auto-call), cybercrime.gov.in, Chakshu; opened by the alert's Report action (`route=report`)
  - **Files**: `lib/screens/report_screen.dart`, `K/HandoffChannel.kt`, `K/MainActivity.kt`  **Depends on**: T3.1, T1.4, T1.7
  - **Done when**: `APP` succeeds; `FT(report_screen_test.dart)` passes `T3_2_prefillsFromEvent`, `T3_2_dialIsDialNotCall`
- [x] T3.3 [codex] Lessons data + Dart model: 8 lessons (OTP, UPI PIN, ATM PIN, QR, digital arrest, KYC, courier, loan app), 3 cards + 3 quiz questions each, `en/hi/hne` JSON in `assets/lessons/` (hne drafts `[VERIFY:hne]`)
  - **Files**: `assets/lessons/en.json`, `hi.json`, `hne.json`, `lib/lessons/lesson_model.dart`, `test/lessons_test.dart`, `pubspec.yaml` (asset entry)  **Depends on**: none
  - **Done when**: `FT(lessons_test.dart)` passes `T3_3_languageKeyParity`, `T3_3_eightLessons`
- [x] T3.4 [codex] Quiz engine + Digital Financial Literacy Score (0-100: mean of per-topic best attempt, untouched topics count 0), persistence behind an injected store interface
  - **Files**: `lib/lessons/quiz_engine.dart`, `test/quiz_engine_test.dart`  **Depends on**: T3.3
  - **Done when**: `FT(quiz_engine_test.dart)` passes `T3_4_scoreBounds`, `T3_4_retryKeepsBest`, `T3_4_perTopic`
- [ ] T3.5 [sonnet] [UI] Lesson cards + quiz screens, offline, Hindi/Chhattisgarhi first; store impl reuses whatever Settings persists with (verify after import; else native SharedPreferences over the existing channel)
  - **Files**: `lib/screens/lessons_screen.dart`, `lib/screens/quiz_screen.dart`, `lib/lessons/prefs_store.dart`  **Depends on**: T3.4
  - **Done when**: `FT(lessons_screen_test.dart)` passes `T3_5_hindiCardsRender`, `T3_5_quizUpdatesScore` (text scale 2.0, no overflow)
- [ ] T3.6 [sonnet] [BLOCKED:native Chhattisgarhi speaker] Sign-off of `hne` lessons and prompts
  - **Files**: `assets/lessons/hne.json`  **Depends on**: T3.3
  - **Done when**: human sign-off logged in `PROGRESS.md`; `[VERIFY:hne]` markers removed
- [x] T3.7 [codex] Dashboard data + aggregation: `dashboard/agg.mjs` (validates exactly `{district, scam_type, date}`, rejects extra keys, counts by district/type/week), `dashboard/validate.mjs <file>`, `data/districts.json` `[VERIFY list]`, labelled-synthetic `data/trends/sample.json`
  - **Files**: `dashboard/agg.mjs`, `dashboard/validate.mjs`, `data/districts.json`, `data/trends/sample.json`, `dashboard/test/agg.test.mjs`  **Depends on**: none
  - **Done when**: `NT(agg.test.mjs)` passes `T3_7_rejectsExtraKeys`, `T3_7_weeklyCounts`; `node dashboard/validate.mjs data/trends/sample.json` exits 0
- [ ] T3.8 [codex] `TrendExport` (pure): verdict events -> `{district, scam_type, date}` rows (SAFE skipped, no text, district chosen by user)
  - **Files**: `K/core/TrendExport.kt`, `KT/core/TrendExportTest.kt`  **Depends on**: T3.7, T1.3
  - **Done when**: `KT(TrendExportTest)` passes `T3_8_threeKeysOnly` and writes `android/app/build/trend_export.json`; `node dashboard/validate.mjs android/app/build/trend_export.json` exits 0
- [x] T3.9 [sonnet] [UI+DATAVIZ] Policy dashboard as a static page (no build step): district ranking, scam-type trend by week, stat tiles; loads `data/trends/sample.json` or a dropped export file; accuracy panel from a copy of `ml/reports/m1.json` ("not measured" if absent)
  - **Files**: `dashboard/index.html`, `dashboard/app.js`, `dashboard/styles.css`, `dashboard/test/page.test.mjs`  **Depends on**: T3.7
  - **Done when**: `NT(page.test.mjs)` passes (every referenced file exists, `agg.mjs` imported, "not measured" path covered)
- [ ] T3.10 [sonnet] [UI] Settings: district picker + "Export anonymised counts" (share-sheet file)
  - **Files**: `lib/screens/settings_screen.dart`, `K/TrendChannel.kt`  **Depends on**: T3.8, T1.4
  - **Done when**: `APP` succeeds; `FT(settings_screen_test.dart)` passes `T3_10_exportCallsChannel`
- [ ] T3.11 [sonnet] [UI] Navigation wiring: entries for Report, Lessons, Recording, Try API/QR; `route=report` deep link
  - **Files**: `lib/main.dart` (or the app's nav file)  **Depends on**: T3.2, T3.5, T2.7, T3.10
  - **Done when**: `APP` succeeds; `flutter test` exits 0

## Phase 4 — Bonus
- [x] T4.1 [codex] `UpiQr` (pure): parse `upi://pay?pa=&pn=&am=`, payee-name vs expected-name mismatch, "You will PAY Rs X to <name>" framing, collect-request wording
  - **Files**: `K/core/UpiQr.kt`, `KT/core/UpiQrTest.kt`  **Depends on**: T0.5
  - **Done when**: `KT(UpiQrTest)` passes `T4_1_parsesPaTn`, `T4_1_nameMismatch`, `T4_1_payFraming`, `T4_1_rejectsMalformed`
- [ ] T4.2 [sonnet] [UI] Fake-QR checker in Try API: `upi://` in pasted/shared text (or manual link) + optional "name I was told" -> card with PAY framing and mismatch warning; also logs a FAKE_QR verdict event
  - **Files**: `lib/screens/try_api_screen.dart`, `K/MainActivity.kt`  **Depends on**: T4.1, T2.1, T3.11
  - **Done when**: `APP` succeeds; `FT(upi_card_test.dart)` passes `T4_2_mismatchWarning`
- [ ] T4.3 [sonnet] [NEEDS-OK:DEP7] [OPTIONAL: if time remains after P3] ML Kit code scanner button feeding T4.2
  - **Files**: `K/QrChannel.kt`, `android/app/build.gradle(.kts)`, `lib/screens/try_api_screen.dart`  **Depends on**: T4.2
  - **Done when**: `APP` and `REL` succeed; the scanner result is passed to the same parser (`KT(UpiQrTest)` still green)
- [ ] T4.4 [codex] [NEEDS-OK:DEP4] [OPTIONAL: only if P0-P3 done and a human asks] New-scam clustering on exported trigger features (HDBSCAN from scikit-learn), cluster summaries JSON for the dashboard
  - **Files**: `ml/scamshield_ml/cluster.py`, `ml/tests/test_cluster.py`  **Depends on**: T1.9
  - **Done when**: `PT(tests/test_cluster.py)` passes `T4_4_newCampaignAlerts` (known types do not alert)

## Phase 5 — Differentiators on the foundation
- [ ] T5.1 [codex] Knowledge graph (pure, new events only): entities sender/brand/event(order, bill, credit, out-for-delivery)/number/UPI ID, `ingest`, lookups, cold-start text "No record since ScamShield was installed"; regex claim parsers (brand, amount, UPI ID, link; use `UnicodeRegex.kt`); claim-vs-context (no bill/order event, non-DLT sender, link not `.bank.in`/`.gov.in`)
  - **Files**: `K/core/graph/KnowledgeGraph.kt`, `ClaimParsers.kt`, `ClaimVsContext.kt`, `KT/core/graph/GraphTest.kt`  **Depends on**: T1.2
  - **Done when**: `KT(GraphTest)` passes `T5_1_ingestThenLookup`, `T5_1_coldStartMessage`, `T5_1_noBillEventFlags`, `T5_1_linkAllowlist`
- [ ] T5.2 [codex] Context rules (pure): mistaken-transfer A/B, bank-call 1600 check, delivery masked-number suppression/flag; wording as `[VERIFY]` constants
  - **Files**: `K/core/graph/ContextRules.kt`, `KT/core/graph/ContextRulesTest.kt`  **Depends on**: T5.1
  - **Done when**: `KT(ContextRulesTest)` passes `T5_2_fakeCreditNoMoneyArrived`, `T5_2_realCreditReturnWarning`, `T5_2_non1600BankCall`, `T5_2_outForDeliverySuppresses`
- [ ] T5.3 [sonnet] SQLite graph persistence fed by `ScamNotificationListener`; claim-vs-context and context-rule hits raise the verdict (rules can only raise) and add reasons shown in the alert
  - **Files**: `K/SqliteKnowledgeGraph.kt`, `K/ScamNotificationListener.kt`, `K/TextApi.kt`  **Depends on**: T5.2, T2.3, T1.15
  - **Done when**: `APP` succeeds; `KT(GraphRowMapperTest)` and `KT(GraphWiringTest)` pass (rule hit never downgrades Gemma's label)
- [ ] T5.4 [codex] `GoldenHour` + `EvidenceZip` (pure): 60-minute timer model, case card pre-filled from the log and graph, ZIP of `card.json` + events + SHA-256 manifest via `java.util.zip`
  - **Files**: `K/core/GoldenHour.kt`, `K/core/EvidenceZip.kt`, `KT/core/GoldenHourTest.kt`  **Depends on**: T3.1
  - **Done when**: `KT(GoldenHourTest)` passes `T5_4_cardPrefilled`, `T5_4_zipManifestVerifies`
- [ ] T5.5 [sonnet] [UI] Golden-hour mode in the Report screen: "I got scammed" -> timer, pre-filled card, 1930 dial, share ZIP via FileProvider
  - **Files**: `lib/screens/report_screen.dart`, `K/HandoffChannel.kt`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/file_paths.xml`  **Depends on**: T5.4, T3.2
  - **Done when**: `APP` succeeds; `FT(report_screen_test.dart)` passes `T5_5_timerAndCard`
- [x] T5.6 [codex] Family code (pure): TOTP RFC 6238 via `javax.crypto`, 30 s step, shared secret as base32 pairing string; offline only (no relay: it would be a new endpoint)
  - **Files**: `K/core/Totp.kt`, `KT/core/TotpTest.kt`  **Depends on**: T0.5
  - **Done when**: `KT(TotpTest)` passes RFC 6238 vectors (`T5_6_rfcVectors`, `T5_6_codesMatchOffline`)
- [ ] T5.7 [sonnet] [UI] Family screen: pair (show/enter secret), rotating 6-digit code with countdown, "does the code match?" prompt; secret in app-private storage (prototype shortcut)
  - **Files**: `lib/screens/family_screen.dart`, `K/FamilyChannel.kt`, `lib/main.dart`  **Depends on**: T5.6, T3.11
  - **Done when**: `APP` succeeds; `FT(family_screen_test.dart)` passes `T5_7_codeScreen`
- [ ] T5.8 [sonnet] APK guard: pure `ApkRisk` permission scoring + `.apk` in a notification/shared file -> `getPackageArchiveInfo` -> heads-up warning with the risky permissions before install
  - **Files**: `K/core/ApkRisk.kt`, `K/ApkGuard.kt`, `K/ScamNotificationListener.kt`, `KT/core/ApkRiskTest.kt`  **Depends on**: T5.3
  - **Done when**: `APP` succeeds; `KT(ApkRiskTest)` passes `T5_8_smsInternetContactsHigh`, `T5_8_plainAppLow`

## Phase 6 — Live-call reach [BLOCKED:device], owned by teammates
- [ ] T6.1 [sonnet] [BLOCKED:device: Pixel with Live Caption] Check Live Caption during real calls on a Pixel; fill device-matrix rows (SCAMSHIELD_HANDOFF §8)
  - **Files**: `SCAMSHIELD_HANDOFF.md` §8  **Depends on**: T0.5
  - **Done when**: human logs per-phone caption results
- [ ] T6.2 [sonnet] [BLOCKED:device: mic-probe results with HAS_AUDIO on some source] Mic path: if a source is HAS_AUDIO, stream mic -> Vosk -> `StatementSegmenter` -> same TextApi/CallRiskTracker (no audio stored)
  - **Files**: `K/MicStreamPipeline.kt`, `K/CaptionAccessibilityService.kt`  **Depends on**: T2.6, T2.4
  - **Done when**: `APP` succeeds; human logs a speaker-phone call run
- [ ] T6.3 [sonnet] [BLOCKED:device: OnePlus 10T, release APK via adb] Release regression: Setup, model download + load (fine-tuned `.task` int4), paste, share, notification listener, recording, Report dial, airplane-mode run; re-run the M1 smoke set on-device and compare with the bf16 report
  - **Files**: `PROGRESS.md`, `SCAMSHIELD_HANDOFF.md` §8  **Depends on**: T1.14, T2.8, T3.11, T5.3
  - **Done when**: human logs pass/fail per flow with the APK name
- [ ] T6.4 [sonnet] [OPTIONAL: only if fine-tuned Gemma 3 1B is below target on real M1] [BLOCKED:device + DEP8] Trial Gemma 3n through a model-path switch; [VERIFY MediaPipe supports 3n at the pinned version]
  - **Files**: `K/GemmaClassifier.kt`, `K/ModelDownloader.kt`  **Depends on**: T1.14
  - **Done when**: latency and M1 on-device logged; adopted only if better

## Phase 7 — Docs, demo, gate
- [ ] T7.1 [sonnet] `ARCHITECTURE.md`: one diagram + sections (pipeline, fusion rule, SLM fine-tune + eval harness, sources, verdict log, privacy), under 120 lines, each claim cites a FINAL_PLAN section
  - **Files**: `ARCHITECTURE.md`  **Depends on**: T1.15, T2.7, T3.11
  - **Done when**: file exists, under 120 lines
- [ ] T7.2 [sonnet] `DEMO.md`: merge handoff §10 with FINAL_PLAN scenarios; mark which steps need the phone; fallbacks (pre-recorded audio, Try API paste); answers for "why not Truecaller/Google" and "how do you hear the call"
  - **Files**: `DEMO.md`  **Depends on**: T3.11, T5.5
  - **Done when**: file exists, every step names its feature task
- [ ] T7.3 [sonnet] Full gate and test summary
  - **Files**: `scripts/check.sh`  **Depends on**: all unblocked tasks
  - **Done when**: `bash scripts/check.sh && bash scripts/trace_report.sh` exits 0 and `REL` succeeds; each ID pass or blocked, none failing

## Traceability
PS must-haves and bonus (handoff §3 rows):
| Item | Tasks |
|---|---|
| ML scam message detector (trained, EN/HI/Hinglish, offline, explains why) | T1.2, T1.8-T1.11, T1.15, T2.1-T2.3 |
| Accuracy on own held-out split (by template) | T1.8, T1.9, T1.12, T1.13, T1.14, T3.9 panel |
| Scam call detector on recorded call | T2.4-T2.8 |
| Official reporting handoff + evidence checklist | T1.3, T1.7, T3.1, T3.2, T5.4, T5.5 |
| Lessons + quiz (Hindi, Chhattisgarhi) -> literacy score | T3.3-T3.6 |
| Scam-trend dashboard | T1.3, T3.7-T3.10 |
| Bonus: live call warning | built (Live Caption, InCallSignals); T6.1-T6.3 device reach |
| Bonus: fake-QR checker | T4.1-T4.3 |
| Bonus: new-scam alerts | T4.4 |
| Deliverables: prototype, accuracy number, architecture overview | T7.3, T1.14, T7.1 |
Differentiators: knowledge graph / claim-vs-context / mistaken transfer / 1600 / delivery T5.1-T5.3 · golden hour T5.4-T5.5 · family code T5.6-T5.7 · APK guard T5.8 · Gemma 3n T6.4.
