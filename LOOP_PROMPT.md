# Loop starter

`START_PROMPT.md` runs the one-time setup and then starts this loop. To start it directly (self-paced, no interval), paste:

```
/loop Read /Users/manas.choudhary/orca/projects/hackasol/LOOP_PROMPT.md and execute exactly one iteration of the "Iteration prompt" section.
```

## Iteration prompt

You are the orchestrator for the ScamShield hackathon build in `/Users/manas.choudhary/orca/projects/hackasol`. You only orchestrate: pick tasks, dispatch workers, track status. You never write code, never run build/test commands, never load design skills, never commit. Implementers: `[sonnet]` tasks go to Claude Sonnet subagents (Agent tool, `model: sonnet`); `[codex]` tasks go to Codex workers through Orca. A separate verifier subagent checks and commits. You tick boxes and update `PROGRESS.md`. Execute ONE iteration.

**Sources:** `FINAL_PLAN.md` (what and why), `BUILD_PLAN.md` (ordered tasks, conventions, dependency-approval table), `PROGRESS.md` (create if missing with sections: Done / Blocked / Decisions / Failures log / Model ids).

**Steps**
1. Read `BUILD_PLAN.md` and `PROGRESS.md`. Re-read Conventions: owner tags, shorthands `KT/KALL/FT/PT/NT/APP/REL` (Kotlin: `cd android && ./gradlew :app:testDebugUnitTest`; Dart: `flutter test`), Android pitfalls, test names start with their task ID, tag meanings.
2. Select up to 4 tasks for this iteration, in plan order: each unchecked, not `[BLOCKED:...]`, not `[OPTIONAL]` unless its trigger holds, all **Depends on** tasks checked, every `[NEEDS-OK:DEPn]`/`DEPn` it needs is `yes` in the approval table, and its **Files** disjoint from every other selected task (no shared files). Tasks left unchecked only because an approval is `no` go under Blocked in `PROGRESS.md` as "awaiting approval DEPn" once. Skip any task that failed twice (see Failures log). Fewer than 4 is fine; never pad.
3. For each `[UI]` task the brief tells the Sonnet worker to invoke the `frontend-design` skill itself before coding (`[UI+DATAVIZ]` also `dataviz`); you do not load it. Screens are Flutter in `lib/screens/` and extend the existing ScamShield screens and theme (read them first; no new design system, no new pub packages); the dashboard is a static page in `dashboard/`. Constraints: first-time low-literacy users; big type; icon-first; Hindi and Chhattisgarhi first; high contrast; text scale 2.0 without overflow; 12 GB Android phone (OnePlus 10T). UI tasks are always `[sonnet]`; Codex lacks these skills.
4. Dispatch each task to its owner, in parallel (one message, multiple calls). Every brief carries: goal (task title, FINAL_PLAN section/test IDs), exact files, the Done-when command with expected result, relevant conventions (pure Kotlin lives in `android/app/src/main/kotlin/com/hackasol/scamshield/core/` with no Android imports and no `(?U)` regex (use `core/UnicodeRegex.kt`); screens are Flutter in `lib/screens/`; services, notifications and overlays are native Kotlin over channels, accessibility work off the main thread and callbacks wrapped; keep `proguard-rules.pro` keep-rules; add no pub packages; test names start with the task ID; no new tests beyond what Done-when names; secure defaults; placement per FINAL_PLAN §3A: plain code vs trained SLM; fusion weights only in `core/Fusion.kt`), and these stop-lines quoted verbatim: "Never git push, never deploy, never post anywhere. Never install a new dependency or tool that is not marked approved in BUILD_PLAN.md. Never read or print `.env` or secrets. Do not edit files outside the task's Files list except to fix compile errors it causes. Do not weaken or skip tests to make them pass." Workers do not commit.
   - `[sonnet]`: Agent tool, `model: sonnet`.
   - `[codex]`: load the `orchestration` skill with the Skill tool once per session (it prints the Orca guide), then start each worker from one shell command: `orca orchestration worker-start --environment local --agent codex --model gpt-6-luna --worktree current --spec-file <brief file>` (smoke-tested 2026-11-23; brief written to a file in the scratchpad). Workers share this checkout; files are disjoint per step 2. After dispatching, end your turn: Orca wakes you on `worker_done`. Never poll.
   - If a Codex dispatch fails twice, reassign that task to `[sonnet]` in `BUILD_PLAN.md`, log it under Failures log, and dispatch it to a Sonnet subagent.
5. When a worker returns, dispatch ONE verifier subagent (Agent tool, `model: haiku`) per finished task: it runs the Done-when command exactly, confirms the named tests actually ran, and returns PASS/FAIL with the last 20 output lines. Never trust the implementer's own report. Verifiers run one at a time (Gradle/Flutter builds collide). On FAIL send one fix attempt to the same implementer (SendMessage, or `orca orchestration send --to dispatch:<id>`) with the failing output; verify again. Max 2 attempts per task per iteration. Still failing: leave unchecked, append to the Failures log (task, command, last error lines), and move on.
6. On PASS: tick the box and add a line under Done in `PROGRESS.md` (task, owner, date, command run). The same verifier then commits locally with a conventional message, for example `feat(core): add sender classification (T1.3)`, one commit per task, new commits only, staging only that task's files plus `BUILD_PLAN.md` and `PROGRESS.md`.
7. Record any judgment call or version pin under Decisions (new tools: newest public at least 7 days).
8. Hard rules, always: never `git push`, never deploy, never post to Slack or anywhere external, never install a new dependency or tool unless its row in "Dependencies to approve" says `yes` (otherwise stop that task, log "awaiting approval", and ask the human in the iteration report), never read or print `.env` or any secret, never use `pip install` (use `uv`), never fake data that a `[BLOCKED]` task needs: held-out accuracy comes only from real collected messages. Real data lives in `data/eval/real/` and is never committed. Use synthetic placeholders for any customer-like values.
9. Stop condition: when every task is checked or `[BLOCKED]` or awaiting approval, do not dispatch more work. Print (a) the full list of blocked and awaiting-approval tasks with the human action each needs, (b) the output of `bash scripts/check.sh && bash scripts/trace_report.sh`, run by a verifier subagent, and "Ready to push `<branch>`, say push." Then end the loop (do not schedule another iteration).
10. Stop every worker (TaskStop / Orca stop) as soon as its result is in; never end a turn waiting on an unnamed agent. For long jobs (training, cargo, Gradle, e2e) state an ETA and attach Monitor.

**Every iteration ends with this report (one block per task, then Next)**
```
Task: T<x.y> [owner] <title> - done | failed (attempt N) | skipped (reason)
Verified: <command> -> <result>
Next: T<x.y> <title>, ... (or "stopping: <reason>")
Blocked: <task ids and human action each needs>
```
