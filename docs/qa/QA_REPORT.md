# ScamShield QA Report (draft)

- Date: 2026-11-23
- Build: HEAD 2b8ce43 (branch main)
- QA commits: a5bdf5d (6 Kotlin QA files, swept into the design lead's commit), 6dd1b1a and 509b9e8 (Flutter), c558864 (ML + dashboard)
- Emulator walkthrough: in progress, not reported here

## Summary by segment

| Segment | Suite / file | Tests added | Pass / fail | Bugs (severity, file:line) | Status |
|---|---|---|---|---|---|
| Kotlin core | QADetectionCoreTest, QAAlertsPrivacyTest, QACallPipelineTest, QAReportsTest, QAGraphUpiTotpTest (committed) + QAPending*Test.kt (uncommitted) | 192 (185 committed, 7 pending) | 185 pass / 7 fail | 2 HIGH, 5 LOW (see Bugs K1-K7) | 7 open, routed to APP lead |
| Flutter | test/qa (qa_logic_test, qa_screens_test, qa_report_test, qa_live_feed_layout_test, qa_family_secret_test) | 65 | 65 pass / 0 fail | 2 MEDIUM fixed (live_feed_screen.dart:210, family_screen.dart:264), 1 LOW leftover (family_screen.dart:267) | MEDIUMs re-tested, LOW open |
| ML | ml/tests/test_qa_ml.py | 59 | 59 pass / 0 fail | 1 LOW (ml/scamshield_ml/data.py:44) | open (pending test uncommitted) |
| Dashboard | dashboard/test/qa.test.mjs | 21 | 21 pass / 0 fail | 1 LOW (dashboard/app.js:17) | open (pending test uncommitted) |

Detail per segment:

- Kotlin: rules engine (15), scam type mapping (5), Gemma parser (11), prompt builder (6), fusion (13), alert policy/mapper, 1930 ACTION_DIAL source scan + manifest, NotificationMapper, ListenerWiring, VerdictLog privacy, trend export, PcmResampler, StatementSegmenter, CallRiskTracker, RecordingPipeline, GoldenHour, ReportPack, CaseCard, EvidenceZip, claim parsers, KnowledgeGraph, ClaimVsContext, ContextRules, UpiQr, TOTP. Manifest check: no READ_SMS / RECEIVE_SMS / SEND_SMS / READ_CALL_LOG / CALL_PHONE / READ_CONTACTS in any manifest; no ACTION_CALL in product code (OverlayController uses ACTION_DIAL for 1930).
- Flutter: screens at 360x740, text scale 2.0, light + dark (14 tests); Dart-side logic (21); report screen + golden hour (22; 1930 is sent as channel method `dial` with `{number: '1930'}`; dial/open/share exact channel args, empty evidence, channel throws/missing/false, golden clock expiry/restart); layout and family-secret regressions promoted from pending (4).
- ML: parser, prompt (takeLast(2), 300/150 caps, UTF-16 counting), validate_row/load_rows, heldout leakage, split edges, compute_metrics boundaries, synth determinism, sft_pairs, cluster edges. Kotlin parity checked by reading source only, no JVM run.
- Dashboard: exactly-3-keys privacy, date validation, parseExport garbage/empty/200k rows/deep nesting, isoWeek sweep 1990-2040 vs independent oracle, countBy* with prototype-named districts, typeName, summarize/headline.

## Bugs

| ID | Severity | file:line | Repro | Owner | Status |
|---|---|---|---|---|---|
| K1 | HIGH | core/RuleScorer.kt:~15 (otp_share rule, SHARE list includes "share") | Score genuine bank text "Your OTP is 482913. Do not share it with anyone." -> SCAM at 0.95; Fusion raises any model label to SCAM at >=0.85. Test: QA_rules_genuineBankOtpSmsMustNotBeScam | APP lead | open |
| K2 | HIGH (privacy) | core/RuleScorer.kt (trigger capture) | Trigger stores the matched span verbatim, including OTP digits, and length is unbounded. Digits flow into SQLite log, ReportPack, evidence ZIP and notification. Test: QA_rules_triggersMustNotContainOtpDigits | APP lead | open |
| K3 | LOW | GemmaPrompt.kt build (`takeLast(2).filter{isNotBlank}`) | Context [aaa,bbb,""] yields only bbb; doc says last 2 non-blank. Test: QA_prompt_contextKeepsLastTwoNonBlankEntries | APP lead | open |
| K4 | LOW | LlmOutputParser.kt bareLabelRe | Prose "This is NOT SAFE. It is a SCAM." parses SAFE (first bare token). Test: QA_parser_notSafeProseDoesNotBecomeSafe | APP lead | open |
| K5 | LOW | core/VerdictLog.kt InMemoryVerdictLog.latest() | Timestamp tie returns first appended; SqliteVerdictLog returns last (ts DESC, id DESC). Test: QA_log_latestOnTimestampTieReturnsLastAppended (expected 2, got 1) | APP lead | open |
| K6 | LOW | core/UpiQr.kt normalizeName | `filter isLetterOrDigit` drops Devanagari vowel signs; names differing only in matras do not mismatch. Test: QA_upi_devanagariNamesDifferingOnlyInVowelSignsMismatch | APP lead | open |
| K7 | LOW | core/graph/ClaimParsers.kt PHONE lookbehind | "09876543210" yields no number though ContextRules.bankCall handles 0-prefix (expected [9876543210], got []). Test: QA_claims_zeroPrefixedIndianMobileIsDetected | APP lead | open |
| F1 | MEDIUM | live_feed_screen.dart:210 | At 360x740, text scale 2.0, status Card overflows by 143 px even in empty state. Test now in qa_live_feed_layout_test.dart | Flutter | fixed, re-tested |
| F2 | MEDIUM | family_screen.dart:264 | Repeated `Key('family_secret_group')` in a Wrap -> "Duplicate keys found" on "Show my code". Test now in qa_family_secret_test.dart | Flutter | fixed, re-tested |
| F3 | LOW | family_screen.dart:267 | Repeated Key left over after F2 fix | Flutter | open |
| M1 | LOW | ml/scamshield_ml/data.py:44 | `load_rows` on a short CSV row (header + line `only text`) -> AttributeError ('NoneType' has no 'strip'); expected ValueError naming the line. DictReader fills missing cells with None. Pending test: ml/tests/test_qa_pending_ml.py | ML | open |
| D1 | LOW | dashboard/app.js:17 | `typeName('constructor')` returns a function (`TYPE_NAMES[t] ?? label(t)`); same shape in accuracyRows SYSTEM_NAMES. Reachable only via a hand-edited m1.json. Pending test: dashboard/test/qa_pending.test.mjs | Dashboard | open |

Observation (not a bug, not tested): `upi://collect` links return null (only `pay` accepted), so a collect QR gets no collect warning.

## Untested / blocked

- Not built yet, so untested: STT result parser, APK guard, `route=report` deep link, settings export (T3.10), UPI card UI (T4.2).
- Android-only, not unit-testable here: paste/share entry (MainActivity), AppSettings export (SharedPreferences), SqliteVerdictLog SQL (row mapping is covered).
- Emulator walkthrough: in progress.
- Kotlin side of ML prompt parity: read-only comparison, no JVM run.
- Gate note: uncommitted pending test files (QAPending*Test.kt, test_qa_pending_ml.py, qa_pending.test.mjs) make the full pytest, node and gradle runs red in this checkout until K1-K7, M1, D1 are fixed. A clean checkout stays green.
- Security note: a credential was printed from a local Gradle init script during debugging. It must be rotated. It is not in any repo file and its value is not recorded here.

## How to run

- Kotlin (set `GRADLE_USER_HOME` to a writable cache dir, because ~/.gradle is root-owned here): `cd android && ./gradlew --offline -PskipDependencyChecks=true :app:testDebugUnitTest --tests 'com.hackasol.scamshield.qa.*'`
- Flutter: `flutter test test/qa/qa_logic_test.dart test/qa/qa_screens_test.dart` (35 tests); `flutter test test/qa` for all 65.
- ML: `pytest tests` (from `ml/`).
- Dashboard: `node --test dashboard/test/`
