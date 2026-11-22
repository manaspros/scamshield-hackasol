# ScamShield — Progress

Branch: `main`. Orchestrator-only file (with BUILD_PLAN.md).

## Done
- T3.7 [codex] dashboard agg + validate + districts + synthetic sample — 2026-11-23 — `node --test dashboard/test/agg.test.mjs && node dashboard/validate.mjs data/trends/sample.json` — commit 1f7248f
- T1.8 [codex] ml uv project + schema + template split — 2026-11-23 — `cd ml && uv run pytest -q tests/test_data.py` (pins: numpy 2.4.6, pyyaml 6.0.3, pytest 9.2.0)

## Blocked
- T0.1 — https://github.com/AB527/scamshield returns 404 (`git clone`: Repository not found; `gh api` as manas-atlan: 404). Either private or a different name; no AB527 public repo matches. Human action: make it public, add manas-atlan as collaborator, or give the correct URL / a zip path.
- Not supplied by user (2026-11-23): RTX box, real messages, hne reviewer.
- T0.2 — human step: run `! /opt/homebrew/bin/brew install --cask temurin@17` (installer needs sudo password; Temurin 17.0.21.1+2 downloaded fine). Then verifier checks `/usr/libexec/java_home -v 17`.
- T1.14 — needs RTX 5090 box + real messages in `data/eval/real/` + human upload of `.task`.
- T2.8, T6.1, T6.2, T6.3, T6.4 — device (OnePlus 10T / Pixel) owned by teammates.
- T3.6 — native Chhattisgarhi speaker sign-off.

## Decisions
- 2026-11-23: DEP1-DEP8 marked `yes` on the user's blanket approval ("u can download anything dont worry about it"). Versions still pinned to newest public >=7 days. DEP5 installs only on the RTX box; DEP8 is a human download.
- 2026-11-23: Flutter-dependent tasks with no Depends (T3.3, T3.4) wait for T0.4 since their Done-when needs `flutter test`.

- 2026-11-23: ScamShield source = https://github.com/AB527/scamshield (user message); T0.1 unblocked.
- 2026-11-23: User direction: proactive approach, the on-device LLM does all message screening and context by itself. Consistent with SLM-first fusion (Gemma decides, rules only raise); no change to task list.

## Failures log

## Model ids
- Implementers: sonnet (Agent tool), codex `gpt-6-luna` (Orca). Verifier: haiku.
