# ScamShield — Progress

Branch: `main`. Orchestrator-only file (with BUILD_PLAN.md).

## Done
- T3.7 [codex] dashboard agg + validate + districts + synthetic sample — 2026-11-23 — `node --test dashboard/test/agg.test.mjs && node dashboard/validate.mjs data/trends/sample.json`

## Blocked
- T0.1 — awaiting ScamShield source (git URL or zip path); code lives on a teammate's Windows machine (`D:\HackASol26\scamshield`). Blocks every Kotlin/Flutter task. User answered "Not available yet" (2026-11-23); not asked again. Also not supplied: RTX box, real messages, hne reviewer.
- T1.14 — needs RTX 5090 box + real messages in `data/eval/real/` + human upload of `.task`.
- T2.8, T6.1, T6.2, T6.3, T6.4 — device (OnePlus 10T / Pixel) owned by teammates.
- T3.6 — native Chhattisgarhi speaker sign-off.

## Decisions
- 2026-11-23: DEP1-DEP8 marked `yes` on the user's blanket approval ("u can download anything dont worry about it"). Versions still pinned to newest public >=7 days. DEP5 installs only on the RTX box; DEP8 is a human download.
- 2026-11-23: Flutter-dependent tasks with no Depends (T3.3, T3.4) wait for T0.4 since their Done-when needs `flutter test`.

## Failures log

## Model ids
- Implementers: sonnet (Agent tool), codex `gpt-6-luna` (Orca). Verifier: haiku.
