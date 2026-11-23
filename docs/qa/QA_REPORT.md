# ScamShield QA Report (final)

- Date: 2026-11-23
- Build: HEAD fddef91 (branch main), clean worktree for the final gate. Per-suite counts in the segment table were taken at the commits named there; the Final gate section has the full-suite numbers at fddef91.
- QA commits: Kotlin a5bdf5d, 54e4182, 3b96b18, 21fd870, ea3f96e, 5a12833, b164b60 (and others under android/app/src/test); Flutter 6dd1b1a, 509b9e8, a60c299, 7f3c389, 4ac3d51; ML/dashboard c558864, 42b2fb9, 1adb24c
- Emulator: round 1 at 1adb24c, round 2 at 7f3c389, final pass on the fddef91 debug APK (see Emulator rounds)
- UX audit: docs/qa/UX_AUDIT.md v2 (4b0bf86)

## Summary by segment

| Segment | Suite / file | Tests added | Pass / fail | Bugs (severity, file:line) | Status |
|---|---|---|---|---|---|
| Kotlin core (qa package) | Alerts/Privacy 33, CallPipeline 37, ContextLayer 35 (T5.3), DetectionCore 47, EndToEndPrivacy 9, FixedBugs 7, GraphUpiTotp 47, OtpPrivacyE2E 10, Reports 21, RegressionSplitOtp 5, RegressionDashOtpE2E 1, QASttParserTest 21, QAApkGuardTest 25, QARegressionSttApkTest 5 | 303 (at b164b60) | 303 pass / 0 fail | K1-K9 and 3 LOWs fixed (K1-K7 in 938c6d6, K8 in ea3f96e, K9 + 3 LOWs in fddef91) | fixed, re-tested |
| Flutter | test/qa: family_secret 2, live_feed_layout 2, logic 23, nav 18 (T3.11), report 26, screens 12, try_api_errors 2, upi 27 | 112 (at 4ac3d51); full Flutter suite +209 green at 4ac3d51 | 112 pass / 0 fail | F1, F2, F4, F5, F6 fixed; F3 LOW still open (family_screen.dart:267) | F3 open |
| ML | ml/tests/test_qa_ml.py + short-row regression | 75 | 75 pass / 0 fail | M1 fixed (17d7540) | fixed, re-tested |
| Dashboard | dashboard/test/qa.test.mjs + regression | 31 | 31 pass / 0 fail | D1 fixed (1309997) | fixed, re-tested |
| Emulator (Android 36, arm64, 360dp) | manual rounds r1 (1adb24c), r2 (7f3c389), final (fddef91 APK); no test files | n/a | Demo Lab run-all 12/12; no FATAL or ANR in the kept logcat | E1-E6 fixed on device; L1-L4 open (low) | L1-L4 open |

Detail per segment:

- Kotlin: rules engine (15), scam type mapping (5), Gemma parser (11), prompt builder (6), fusion (13), alert policy/mapper, 1930 ACTION_DIAL source scan + manifest, NotificationMapper, ListenerWiring, VerdictLog privacy, trend export, PcmResampler, StatementSegmenter, CallRiskTracker, RecordingPipeline, GoldenHour, ReportPack, CaseCard, EvidenceZip, claim parsers, KnowledgeGraph, ClaimVsContext, ContextRules, UpiQr, TOTP. Manifest check: no READ_SMS / RECEIVE_SMS / SEND_SMS / READ_CALL_LOG / CALL_PHONE / READ_CONTACTS in any manifest; no ACTION_CALL in product code (OverlayController uses ACTION_DIAL for 1930).
- Kotlin additions since the draft: T5.3 context layer, end-to-end OTP/UPI privacy across rules, log, report, zip and notification, and regressions for the fixed bugs including the split-OTP leak.
- Flutter: screens at 360x740, text scale 2.0, light + dark; Dart-side logic; report screen + golden hour (1930 is sent as channel method `dial` with `{number: '1930'}`; dial/open/share exact channel args, empty evidence, channel throws/missing/false, golden clock expiry/restart); app shell nav, 1930 entry, help hub and route=report deep link (T3.11); UPI QR check, scan button and paste-result advice; try-api friendly-error tests.
- ML: parser, prompt (takeLast(2), 300/150 caps, UTF-16 counting), validate_row/load_rows, heldout leakage, split edges, compute_metrics boundaries, synth determinism, sft_pairs, cluster edges. Kotlin parity checked by reading source only, no JVM run.
- Dashboard: exactly-3-keys privacy, date validation, parseExport garbage/empty/200k rows/deep nesting, isoWeek sweep 1990-2040 vs independent oracle, countBy* with prototype-named districts, typeName, summarize/headline.

## Bugs

| ID | Severity | file:line | Repro | Owner | Status |
|---|---|---|---|---|---|
| K1 | HIGH | core/RuleScorer.kt:~15 (otp_share rule, SHARE list includes "share") | Score genuine bank text "Your OTP is 482913. Do not share it with anyone." -> SCAM at 0.95 (OTP negation not handled). Test: QA_rules_genuineBankOtpSmsMustNotBeScam | APP lead | fixed 938c6d6, re-tested |
| K2 | HIGH (privacy) | core/RuleScorer.kt (trigger capture) | Trigger stored the matched span verbatim, including OTP digits; flowed into SQLite log, ReportPack, evidence ZIP and notification. Test: QA_rules_triggersMustNotContainOtpDigits | APP lead | fixed 938c6d6, re-tested |
| K3 | LOW | GemmaPrompt.kt build (`takeLast(2).filter{isNotBlank}`) | Context [aaa,bbb,""] yielded only bbb. Test: QA_prompt_contextKeepsLastTwoNonBlankEntries | APP lead | fixed 938c6d6, re-tested |
| K4 | LOW | LlmOutputParser.kt bareLabelRe | Prose "This is NOT SAFE. It is a SCAM." parsed SAFE. Test: QA_parser_notSafeProseDoesNotBecomeSafe | APP lead | fixed 938c6d6, re-tested |
| K5 | LOW | core/VerdictLog.kt InMemoryVerdictLog.latest() | Timestamp tie returned first appended; SqliteVerdictLog returns last. Test: QA_log_latestOnTimestampTieReturnsLastAppended | APP lead | fixed 938c6d6, re-tested |
| K6 | LOW | core/UpiQr.kt normalizeName | `filter isLetterOrDigit` dropped Devanagari vowel signs. Test: QA_upi_devanagariNamesDifferingOnlyInVowelSignsMismatch | APP lead | fixed 938c6d6, re-tested |
| K7 | LOW | core/graph/ClaimParsers.kt PHONE lookbehind | "09876543210" yielded no number (expected [9876543210]). Test: QA_claims_zeroPrefixedIndianMobileIsDetected | APP lead | fixed 938c6d6, re-tested |
| K8 | HIGH (privacy) | Kotlin rules/trigger capture (split OTP) | OTP digits split across the text leaked through trigger capture despite the K2 fix. Test: RegressionSplitOtp (5), RegressionDashOtpE2E (1) | APP lead | fixed ea3f96e, re-tested |
| F1 | MEDIUM | live_feed_screen.dart:210 | At 360x740, text scale 2.0, status Card overflowed by 143 px even in empty state. Test: qa_live_feed_layout_test.dart | Flutter | fixed, re-tested |
| F2 | MEDIUM | family_screen.dart:264 | Repeated `Key('family_secret_group')` in a Wrap -> "Duplicate keys found" on "Show my code". Test: qa_family_secret_test.dart | Flutter | fixed, re-tested |
| F3 | LOW | family_screen.dart:267 | Repeated Key left over after F2 fix | Flutter | open |
| F4 | MEDIUM | try_api screen | Raw PlatformException shown to the user | Flutter | fixed by redesign 31fc425, re-tested (try_api_errors) |
| F5 | LOW | try_api screen | Stale error stayed visible | Flutter | fixed by redesign 31fc425, re-tested |
| F6 | HIGH | app shell nav | Report and Lessons unreachable from the UI (found at 99c3662) | Flutter | fixed by T3.11, re-tested (nav 18) and route=report / route=recording deep links verified on emulator |
| M1 | LOW | ml/scamshield_ml/data.py:44 | `load_rows` on a short CSV row -> AttributeError instead of ValueError naming the line | ML | fixed 17d7540, re-tested |
| D1 | LOW | dashboard/app.js:17 | `typeName('constructor')` returned a function; only reachable via hand-edited m1.json | Dashboard | fixed 1309997, re-tested |
| K9 | MEDIUM | Kotlin ApkRisk (APK guard) | Regex hang on long text | APP lead | fixed fddef91, re-tested |
| K10-K12 | LOW | Kotlin ApkRisk / STT parser | Custom permission suffix handling; STT nested-JSON stack overflow; STT huge start value | APP lead | fixed fddef91, re-tested |
| E1 | MED-HIGH | UPI paste card (Flutter) | Paste `upi://pay?pa=refund.helpdesk@oksbi&pn=Priya Stores&am=4999`: card said "You will PAY money to Priya" with no amount, masked id, and a green "safe" card. Root cause: link regex `upi://\S+` cut the paste at the first space | Flutter | fixed 640dad2 (amount, full id, amber, never green), verified on device |
| E2 | LOW-MED | Demo Lab | Scenario mistaken_a (SUSPICIOUS fake-credit) posted no heads-up | APP lead | fixed f2235ad, verified on device |
| E3 | MEDIUM | settings_screen.dart | Developer-only toggles shown to end users in English at the top of Settings | Flutter | fixed 3f1683f (Hindi-first), verified on device |
| E4 | MEDIUM | try_api_screen.dart | Empty Analyse (and empty share) gave no feedback | Flutter | fixed (31fc425 redesign), verified on device |
| E5 | MEDIUM | settings_screen.dart | District bottom sheet extended under the status bar | Flutter | fixed, verified on device |
| E6 | MEDIUM | core/RuleScorer.kt:35 and :130 | Lottery + "processing fee" SMS typed LOAN_APP / SUSPICIOUS | APP lead | fixed 96416af, verified on device; Hindi KYC share now typed KYC. Known false-positive risk: a genuine prize-draw message with "pay" near the prize word scores SCAM |
| L1 | LOW | digital_arrest alert | Alert shows only the trigger 'Kisi ko mat batana', no scam-type label | APP lead | open |
| L2 | LOW | ShareReceiver | SecurityException on an ungranted content URI is caught silently; the user sees nothing | APP lead | open |
| L3 | LOW (UX) | lessons / quiz | Literacy score shows 8/100 after a 2/3 quiz (see UX_AUDIT) | Flutter | open |
| L4 | n/a | emulator coverage | In-call overlay, Live card order, QR camera and the ApkGuard alert on a real APK not verified on the emulator (file:// shares gave no alert; no granted content URI). ApkGuard pure logic has 51 unit tests | QA | not verified, see Untested |

K10-K12 are my labels for the three LOWs named in the fddef91 report; the commit itself may not use those IDs.

Emulator lows from emu.md not individually re-confirmed in the final pass (check UX_AUDIT v2): export "nothing to export" in red error style; setup language chips with no selected state on first run; Try hint truncated at scale 2.0; Live tab shows "no call" twice; golden-hour progress bar semantics value "100" without a percent sign; shared triggers can be a whole short message (the privacy invariant since added masks digits and caps triggers at the source); thin lime frame at screen edges in screenshots (unexplained, possibly an emulator focus ring).

Observation (not a bug, not tested): `upi://collect` links return null (only `pay` accepted), so a collect QR gets no collect warning.

## Emulator rounds

Setup: AVD scamshield_qa (Android 36, arm64, 1080x2400 at 480dpi), rules-only engine (Gemma model not downloaded). Screenshots: /private/tmp/claude-501/-Users-manas-choudhary-orca-projects-hackasol/e64f2eb4-9bd8-469c-aefb-75bfaefd4d3f/scratchpad/shots/emu/

Final pass on the fddef91 debug APK: Demo Lab run-all 12/12; 1930 = ACTION_DIAL only (mCallState 0); AppBar 1930 action opens Report; route=report and route=recording cold and warm OK; export has exactly 3 keys; evidence zip has no raw text; family pair, bad-code and unpair OK; no FATAL or ANR in the kept logcat (window is only about 150 KB).

Verified on device (rounds 1 and 2):
- 1930 uses ACTION_DIAL only (dialer opened, telephony call state 0, no call placed).
- Evidence zip (card.json, events.json, manifest.json) contains triggers, types and timestamps, no raw message text.
- Trend export has exactly 3 keys per row: date, district, scam_type.
- Demo Lab: mistaken_a, debit_scare, genuine_otp and fake_qr pass (no assertion failures).
- Deep links: route=report works warm, cold and from the alert Report action; route=recording works cold, warm and from background.
- Share-sheet receiver handles Hindi, English and Hinglish text; notification listener classifies posted notifications; lessons, quiz, family code, golden hour countdown (59:xx) work.
- logcat: no FATAL EXCEPTION or ANR for the app, no Flutter overflow/RenderFlex lines.
- Environment caveat: heavy host load caused system UI ANRs and an lmkd kill storm during round 1 (emulator, not the app).

## Untested / blocked

- Not testable here: QR camera on the emulator (ML Kit scanner module unavailable; the paste fallback works); the in-call overlay with the 1930 row (needs a live call and a connected accessibility service); Demo Lab digital_arrest scenario not run; Live feed card order (no call to populate it).
- STT parser and APK guard are now built and covered by Kotlin QA (QASttParserTest 21, QAApkGuardTest 25, QARegressionSttApkTest 5). The ApkGuard alert on a real APK was not seen on the emulator.
- Android-only, not unit-testable here: AppSettings export (SharedPreferences), SqliteVerdictLog SQL (row mapping is covered).
- Kotlin side of ML prompt parity: read-only comparison, no JVM run.
- Setup screen showed the accessibility step as pending while dumpsys showed the service bound; probably an artifact of uiautomator dump, not verified.
- Process notes:
  - QA files were swept into other agents' commits (a5bdf5d, 7f3c389, d0e36df) because agents share one checkout.
  - A credential was printed from a local Gradle init script during debugging. It must be rotated. It is not in any repo file and its value is not recorded here.
  - An "atlan-secguard --no-verify bypass detected" warning appeared on a QA commit although QA never passed --no-verify. Not investigated; worth a look by the security owner.

## Final gate

At HEAD fddef91, clean worktree.

| Check | Command | Result |
|---|---|---|
| Aggregate gate | `check.sh` | exit 0 |
| Kotlin unit tests | via check.sh | 402 tests, 0 failures |
| Flutter | via check.sh | 222 tests, 0 failures |
| ML | via check.sh (`pytest tests`) | 75 passed |
| Dashboard | via check.sh (`node --test dashboard/test/`) | 31/31 |
| Traceability | `trace_report.sh` | exit 0: 44 pass, 6 blocked, 10 not-run, 0 fail |
| Release build | `flutter build apk --release --split-per-abi --android-skip-build-dependency-validation` | exit 0 |
| Emulator smoke | manual, fddef91 debug APK | see Emulator rounds |

Release APKs (scratchpad, not in git): /private/tmp/claude-501/-Users-manas-choudhary-orca-projects-hackasol/963dd60f-9fc0-4f23-bbc2-18bf27903757/scratchpad/qa/release/ holds arm64-v8a 51.4M, armeabi-v7a 40.0M, x86_64 54.8M, plus app-debug-final.apk.

Known build issues:
- Gradle 9.1.0 is below Flutter 3.50's minimum, so builds need `--android-skip-build-dependency-validation`.
- A fresh clone lacks the gitignored android/local.properties; Kotlin fails until it is written.

Open at final HEAD: F3 (LOW), L1-L3 (LOW), and the L4 coverage gaps. No open HIGH or MEDIUM bugs.

## How to run

- Kotlin (set `GRADLE_USER_HOME` to a writable cache dir, because ~/.gradle is root-owned here): `cd android && ./gradlew --offline -PskipDependencyChecks=true :app:testDebugUnitTest --tests 'com.hackasol.scamshield.qa.*'`
- Flutter: `flutter test test/qa/qa_logic_test.dart test/qa/qa_screens_test.dart` (subset); `flutter test test/qa` for all 112.
- ML: `pytest tests` (from `ml/`).
- Dashboard: `node --test dashboard/test/`
