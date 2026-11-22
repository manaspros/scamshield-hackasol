# ScamShield — Progress

Branch: `main`. Orchestrator-only file (with BUILD_PLAN.md).

## Done
- T0.1 [sonnet] imported AB527/scamshield @ 55f2343 into repo root — 2026-11-23 — ls of RuleScorer.kt, try_api_screen.dart, proguard-rules.pro
- T0.2 [sonnet+human] JDK 17 (user ran the brew cask install) — 2026-11-23 — `/usr/libexec/java_home -v 17 && java -version`
- T1.9 [codex] synthetic EN/HI/Hinglish generator (44 templates per lang) — 2026-11-23 — `cd ml && uv run pytest -q tests/test_synth.py` (SFT target format is a placeholder until T1.10)
- T3.7 [codex] dashboard agg + validate + districts + synthetic sample — 2026-11-23 — `node --test dashboard/test/agg.test.mjs && node dashboard/validate.mjs data/trends/sample.json` — commit 1f7248f
- T3.9 [sonnet] policy dashboard static page — 2026-11-23 — `node --test dashboard/test/page.test.mjs` (serve over http from repo root; m1.json shape to recheck after T1.13; week gaps skipped not zero)
- T1.8 [codex] ml uv project + schema + template split — 2026-11-23 — `cd ml && uv run pytest -q tests/test_data.py` (pins: numpy 2.4.6, pyyaml 6.0.3, pytest 9.2.0)

## Blocked
- Not supplied by user (2026-11-23): real messages, hne reviewer. (RTX box dropped by user.)
- T1.14 — needs RTX 5090 box + real messages in `data/eval/real/` + human upload of `.task`.
- T2.8, T6.1, T6.2, T6.3, T6.4 — device (OnePlus 10T / Pixel) owned by teammates.
- T3.6 — native Chhattisgarhi speaker sign-off.

## Decisions
- 2026-11-23: DEP1-DEP8 marked `yes` on the user's blanket approval ("u can download anything dont worry about it"). Versions still pinned to newest public >=7 days. DEP5 installs only on the RTX box; DEP8 is a human download.
- 2026-11-23: Flutter-dependent tasks with no Depends (T3.3, T3.4) wait for T0.4 since their Done-when needs `flutter test`.

- 2026-11-23: ScamShield source = https://github.com/AB527/scamshield (user message); T0.1 unblocked.
- 2026-11-23: User direction: proactive approach, the on-device LLM does all message screening and context by itself. Consistent with SLM-first fusion (Gemma decides, rules only raise); no change to task list.

- 2026-11-23: The `rtk` shell wrapper rewrites `uv run pytest` output to "No tests collected". Verifiers call `/Users/manas.choudhary/.local/bin/uv` (and `/usr/bin/wc`, `/usr/bin/grep`) by absolute path.
- T1.8 committed 9a527f6.
- 2026-11-23: GitHub account switched to manaspros at user request; AB527/scamshield still 404 for it.

- 2026-11-23: T0.3 runs before T0.1 (user asked to parallelise): install cmdline-tools, platform-tools and latest stable platform + build-tools now; add the imported project's exact compileSdk after T0.1. T0.4 Flutter install likewise.

- 2026-11-23: JDK Temurin 17.0.21.1 is dated 2026-11-17 (6 days, under the 7-day cooldown); user-installed, flagged for review. T0.2 committed fab4460.

- 2026-11-23: User: no RTX 5090; use the existing base Gemma 3 1B (GitHub release model) for now; fine-tune deferred. T1.14 rewritten to run base eval on this Mac. T1.15 keeps the current model URL. T1.11 scripts still built (dry-run only).

- 2026-11-23: Source AB527/scamshield (private, read via gh account manaspros) @ 55f2343. Kotlin tests: android/app/src/test/kotlin/com/hackasol/scamshield/core/CoreTest.kt (24 @Test by grep). minSdk 26; compileSdk/targetSdk from flutter.*; AGP 9.0.1, Kotlin 2.3.20, JVM 17; Dart ^3.12.2. Source HANDOFF.md kept beside SCAMSHIELD_HANDOFF.md.

## Failures log

## Model ids
- Implementers: sonnet (Agent tool), codex `gpt-6-luna` (Orca). Verifier: haiku.
