# ScamShield — Progress

Branch: `main`. Orchestrator-only file (with BUILD_PLAN.md).

## Done
- T3.1 [sonnet] Report pack with official targets (pure) — 2026-11-23 — cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --tests '*ReportPackTest*'
- T3.5 [sonnet] lessons + quiz screens (hi default, hne/en toggle, scale 2.0) — 2026-11-23 — flutter test test/lessons_screen_test.dart
- T1.3 [sonnet] Verdict event log (pure) — 2026-11-23 — cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --tests '*VerdictLogTest*'
- T1.10 [sonnet] Python prompt/parser port, parity with data/golden/prompt_golden.json (APP T1.2 7c09a0e); synth.py SFT pairs now use the on-device format — 2026-11-23 — cd ml && uv run pytest -q tests/test_prompt_parity.py
- T1.12 [sonnet] rules-only predictions exporter (RULES_EVAL_CSV override, default data/golden/eval_smoke.csv) — 2026-11-23 — ./gradlew ... --tests '*RulesEvalExportTest*'
- T1.2 [sonnet] ScamType + GemmaPrompt + parser + rule type + golden — 2026-11-23 — cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest (ScamTypeTest 3/3; also fixes Source.parse("signal") -> SIGNAL)
- T3.4 [sonnet] quiz engine + literacy score — 2026-11-23 — flutter test test/quiz_engine_test.dart
- T5.6 [codex] Totp pure RFC 6238 (SHA1, 30 s step, base32 secret, offline verify); verified by haiku — 2026-11-23 — `cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --tests '*TotpTest*' --rerun` (T5_6_rfcVectors, T5_6_codesMatchOffline passed)
- T4.1 [codex] UpiQr pure parser (pa/pn/am, name mismatch, PAY framing, collect-request, malformed rejects); verified by haiku — 2026-11-23 — `cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --tests '*UpiQrTest*' --rerun` (4/4 passed)
- T1.1 [codex] Source enum (CAPTION, PASTE, SHARE, SMS, WHATSAPP, NOTIFICATION, RECORDING, +SIGNAL kept from HEAD) with legacy string parse; verified by haiku — 2026-11-23 — `cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --tests '*SourceTest*' --rerun` (T1_1_parsesLegacyStrings passed)
- T0.5 [sonnet] Baseline green: Kotlin 24 CoreTest tests (31 total incl. SourceTest/TotpTest/UpiQrTest), Dart 5 tests, debug APK built, Gradle wrapper added — 2026-11-23 — `cd android && ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest --rerun`; `flutter test`; `flutter build apk --debug --android-skip-build-dependency-validation`
- T1.11 [sonnet] LoRA fine-tune + .task convert scripts, dry-run only (no GPU) — 2026-11-23 — cd ml && uv run pytest -q tests/test_finetune_dry.py
- T1.13 [sonnet] eval harness (stub + hf backends, rules JSONL join, m1.json/accuracy.md/heldout.csv) — 2026-11-23 — cd ml && uv run pytest -q tests/test_eval.py (held-out = 26 synthetic rows; rules row waits on T1.12 JSONL; T1.10 provisional port committed separately)
- T3.3 [codex] lessons data en/hi/hne (8 lessons) + Dart model — 2026-11-23 — flutter test test/lessons_test.dart (hne drafts await T3.6; flutter pub get under Flutter 3.50.1 updated pubspec.lock and analysis_options.yaml)
- T0.3/T0.4 [sonnet] Android SDK (platform-tools, android-36, build-tools 36.0.0, + cmdline-tools;latest) at ~/Library/Android/sdk; Flutter 3.50.1 / Dart 3.14.0 — 2026-11-23 — sdkmanager --list_installed, adb version, flutter doctor -v
- T0.1 [sonnet] imported AB527/scamshield @ 55f2343 into repo root — 2026-11-23 — ls of RuleScorer.kt, try_api_screen.dart, proguard-rules.pro
- T0.2 [sonnet+human] JDK 17 (user ran the brew cask install) — 2026-11-23 — `/usr/libexec/java_home -v 17 && java -version`
- T1.9 [codex] synthetic EN/HI/Hinglish generator (44 templates per lang) — 2026-11-23 — `cd ml && uv run pytest -q tests/test_synth.py` (SFT target format is a placeholder until T1.10)
- T3.7 [codex] dashboard agg + validate + districts + synthetic sample — 2026-11-23 — `node --test dashboard/test/agg.test.mjs && node dashboard/validate.mjs data/trends/sample.json` — commit 1f7248f
- T3.9 [sonnet] policy dashboard static page — 2026-11-23 — `node --test dashboard/test/page.test.mjs` (serve over http from repo root; m1.json shape to recheck after T1.13; week gaps skipped not zero)
- T1.8 [codex] ml uv project + schema + template split — 2026-11-23 — `cd ml && uv run pytest -q tests/test_data.py` (pins: numpy 2.4.6, pyyaml 6.0.3, pytest 9.2.0)

## Blocked
- Not supplied by user (2026-11-23): real messages, hne reviewer. (RTX box dropped by user.)
- T1.14 — base Gemma: HF returns 403 "not in the authorized list" for google/gemma-3-1b-it (user must accept the licence on the account that 'hf auth whoami' shows). Rules-only row: waits on android/app/build/rules_preds.jsonl from APP T1.12 over ml/reports/heldout.csv. Fine-tuned row: not run (no GPU box).
- T2.8, T6.1, T6.2, T6.3, T6.4 — device (OnePlus 10T / Pixel) owned by teammates.
- T3.6 — native Chhattisgarhi speaker sign-off.

## Decisions
- 2026-11-23: T3.5 lesson scores persist via new MethodChannel scamshield/prefs (getString/setString, key lesson_best_v1), because AppSettings only accepts fixed keys; falls back to in-memory until the native handler lands with the next MainActivity task (T1.4/T3.2). Language choice not persisted.
- 2026-11-23: T1.12 reads its CSV from env RULES_EVAL_CSV (relative to repo root, default data/golden/eval_smoke.csv) at the ML session's request; env var instead of a system property so build.gradle stays unchanged. JSONL lines carry "text" because ml eval_heldout.load_rules_preds joins on text (build output, gitignored).
- 2026-11-23: DEP1-DEP8 marked `yes` on the user's blanket approval ("u can download anything dont worry about it"). Versions still pinned to newest public >=7 days. DEP5 installs only on the RTX box; DEP8 is a human download.
- 2026-11-23: Flutter-dependent tasks with no Depends (T3.3, T3.4) wait for T0.4 since their Done-when needs `flutter test`.
- 2026-11-23: T0.5 baseline green. android/gradlew, gradlew.bat, gradle/wrapper/gradle-wrapper.jar generated by `flutter build apk --debug` (wrapper 9.1.0, AGP 9.0.1; installed Flutter demands Gradle 9.3.1 / AGP 9.1.1, so every Flutter/Gradle build needs `--android-skip-build-dependency-validation` for flutter, `-PskipDependencyChecks=true` for gradlew). Gradle needs a writable GRADLE_USER_HOME (~/.gradle was read-only in the agent sandbox). No NDK needed. Kotlin test source path: android/app/src/test/kotlin/com/hackasol/scamshield/core/ (CoreTest.kt holds 24 = CallRiskTrackerTest 3, InCallSignalsTest 6, LlmOutputParserTest 5, RuleScorerTest 5, StatementSegmenterTest 5; plus SourceTest 1, TotpTest 2, UpiQrTest 4 = 31 total, 0 failures); JUnit XML lands in build/app/test-results/testDebugUnitTest/ (repo-root build/, not android/app/build). Dart: 5 tests pass. APK: build/app/outputs/flutter-apk/app-debug.apk (206 MB).

- 2026-11-23: ScamShield source = https://github.com/AB527/scamshield (user message); T0.1 unblocked.
- 2026-11-23: User direction: proactive approach, the on-device LLM does all message screening and context by itself. Consistent with SLM-first fusion (Gemma decides, rules only raise); no change to task list.

- 2026-11-23: The `rtk` shell wrapper rewrites `uv run pytest` output to "No tests collected". Verifiers call `/Users/manas.choudhary/.local/bin/uv` (and `/usr/bin/wc`, `/usr/bin/grep`) by absolute path.
- T1.8 committed 9a527f6.
- 2026-11-23: GitHub account switched to manaspros at user request; AB527/scamshield still 404 for it.

- 2026-11-23: T0.3 runs before T0.1 (user asked to parallelise): install cmdline-tools, platform-tools and latest stable platform + build-tools now; add the imported project's exact compileSdk after T0.1. T0.4 Flutter install likewise.

- 2026-11-23: JDK Temurin 17.0.21.1 is dated 2026-11-17 (6 days, under the 7-day cooldown); user-installed, flagged for review. T0.2 committed fab4460.

- 2026-11-23: User: no RTX 5090; use the existing base Gemma 3 1B (GitHub release model) for now; fine-tune deferred. T1.14 rewritten to run base eval on this Mac. T1.15 keeps the current model URL. T1.11 scripts still built (dry-run only).

- 2026-11-23: Source AB527/scamshield (private, read via gh account manaspros) @ 55f2343. Kotlin tests: android/app/src/test/kotlin/com/hackasol/scamshield/core/CoreTest.kt (24 @Test by grep). minSdk 26; compileSdk/targetSdk from flutter.*; AGP 9.0.1, Kotlin 2.3.20, JVM 17; Dart ^3.12.2. Source HANDOFF.md kept beside SCAMSHIELD_HANDOFF.md.
- 2026-11-23: Flutter 3.50.1 (framework 2026-11-18) is under the 7-day cooldown; brew offers only latest; kept under the user's blanket approval, flagged for review. android-36/build-tools 36.0.0 chosen over 37.x for cooldown and compatibility. ANDROID_HOME set per command, no rc edits.
- 2026-11-23 (ML): training uses raw build_prompt text, no chat turns, matching GemmaClassifier.kt:127 addQueryChunk. convert_task.py has --dry-run but no --limit (nothing to limit). [VERIFY] gemma3 example script ships in the litert-torch 0.10.0 wheel; mediapipe 1.2.3 bundler import path; peft vs litert-torch torch<2.15 pin.
- 2026-11-23 (ML): held-out split is 26 synthetic rows (one row per template, 20% of templates) so numbers are noisy; more slot-fills per template would need a synth.py change outside ML scope. Binary positive = SCAM or SUSPICIOUS; UNPARSED counts negative. Provisional T1.10 port committed before T1.13 because the harness imports it.
- 2026-11-23 (ML): T1.10 Parsed.reason -> reasons: list[str] to match the golden output. SFT target = one-line JSON {label, scam_type (NONE for SAFE), confidence fixed per label, reason}. T1_9_sftPairsWellFormed now asserts every target parses with the on-device parser (the old LABEL:/TYPE: text assertion could not hold after the format swap). Unparseable output -> label UNPARSED in Python (Kotlin returns null).
- 2026-11-23 (ML): torch 2.15.0 (2026-10-28) + transformers 5.23.0 (2026-11-13) in uv group 'hf' (DEP5); [tool.uv] exclude-newer 2026-11-16 keeps the 7-day cooldown on re-resolve; pytest pythonpath=["."] added because package=false left scamshield_ml unimportable after uv sync. Dashboard m1.json not written while Gemma is blocked: stub numbers must never reach the panel.

## Failures log

## Model ids
- Implementers: sonnet (Agent tool), codex `gpt-6-luna` (Orca). Verifier: haiku.
- Base model: google/gemma-3-1b-it (HF, gated). Converter: litert-torch==0.10.0 (PyPI 2026-10-20, renamed ai-edge-torch; Gemma 3 1B via litert_torch/generative/examples/gemma3, quant dynamic_int4_block32) + mediapipe==1.2.3 genai bundler (2026-11-11) -> .task. Not installed (dry-run only).
