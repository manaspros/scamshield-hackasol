# ScamShield QA Report (near-final)

- Date: 2026-11-23
- Build: HEAD 257d210 when this update was written (branch main). Suite counts below were taken at the commits named in each row; the Final gate section is still TBD.
- QA commits: Kotlin a5bdf5d, 54e4182, 3b96b18, 21fd870, ea3f96e (and others under android/app/src/test); Flutter 6dd1b1a, 509b9e8, a60c299, 7f3c389, 4ac3d51; ML/dashboard c558864, 42b2fb9, 1adb24c
- Emulator: round 1 at 1adb24c, round 2 at 7f3c389 (see Emulator rounds)

## Summary by segment

| Segment | Suite / file | Tests added | Pass / fail | Bugs (severity, file:line) | Status |
|---|---|---|---|---|---|
| Kotlin core (qa package) | Alerts/Privacy 33, CallPipeline 37, ContextLayer 35 (T5.3), DetectionCore 47, EndToEndPrivacy 9, FixedBugs 7, GraphUpiTotp 47, OtpPrivacyE2E 10, Reports 21, RegressionSplitOtp 5, RegressionDashOtpE2E 1 | 252 | 252 pass / 0 fail | K1-K8 all fixed (K1/K2/K3-K7 in 938c6d6, K8 in ea3f96e) | fixed, re-tested |
| Flutter | test/qa: family_secret 2, live_feed_layout 2, logic 23, nav 18 (T3.11), report 26, screens 12, try_api_errors 2, upi 27 | 112 (at 4ac3d51); full Flutter suite +209 green at 4ac3d51 | 112 pass / 0 fail | F1, F2, F4, F5 fixed; F3 LOW still open (family_screen.dart:267) | F3 open |
| ML | ml/tests/test_qa_ml.py + short-row regression | 75 | 75 pass / 0 fail | M1 fixed (17d7540) | fixed, re-tested |
| Dashboard | dashboard/test/qa.test.mjs + regression | 31 | 31 pass / 0 fail | D1 fixed (1309997) | fixed, re-tested |
| Emulator (Android 36, arm64, 360dp) | manual rounds r1 (1adb24c) and r2 (7f3c389), no test files | n/a | no app FATAL or ANR in logcat | E1-E3 and 4 re-check items (see Emulator rounds) | open, fixer in progress |

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
| E1 | MED-HIGH | UPI paste card (Flutter) | Paste `upi://pay?pa=refund.helpdesk@oksbi&pn=Priya Stores&am=4999`: card says "You will PAY money to Priya" with no amount, masked id, and a separate green "safe / normal conversation" card. Shot qr_paste_result_light_1.0.png (r2) | coordinator's fixer | open, fix in progress |
| E2 | LOW-MED | Demo Lab | Scenario mistaken_a (SUSPICIOUS fake-credit) posts no heads-up | coordinator's fixer | open, fix in progress |
| E3 | MEDIUM | settings_screen.dart | Developer-only toggles (Gemma, OCR, mic source test, caption source packages, discovery mode) shown to end users in English at the top of Settings | coordinator's fixer | open, fix in progress |
| E4 | MEDIUM | try_api_screen.dart | Empty Analyse (and empty share) gives no feedback; still present at 7f3c389 | Flutter | open, re-check at final HEAD |
| E5 | MEDIUM | settings_screen.dart | District bottom sheet extends under the status bar ("Balod" over the clock); suggested fix `useSafeArea` | Flutter | open, re-check at final HEAD |
| E6 | MEDIUM | core/RuleScorer.kt:35 and :130 | Lottery + "processing fee" SMS typed LOAN_APP / SUSPICIOUS; prize rule has no scam type. Commit 96416af (prize-fee scams score SCAM) may cover this | APP lead | open, re-check at final HEAD |

Lows from the emulator notes (emu.md, all open unless the redesign fixed them, to be re-checked): export "nothing to export" shown in red error style and the last message hidden behind the gesture bar; setup language chips show no selected state on first run; Try hint truncated at scale 2.0 and English Analyse label; Live tab shows "no call" twice; golden-hour progress bar semantics value "100" has no percent sign; shared triggers can be a whole short message and are stored in the log and zip (notification caps at 40 chars); thin lime frame at screen edges in screenshots from about 11:22 (unexplained, possibly an emulator focus ring). Info: bottom nav "Setting/s" wrap at font 2.0 was fixed in the new UI.

Observation (not a bug, not tested): `upi://collect` links return null (only `pay` accepted), so a collect QR gets no collect warning.

## Emulator rounds

Setup: AVD scamshield_qa (Android 36, arm64, 1080x2400 at 480dpi), rules-only engine (Gemma model not downloaded). Screenshots: /private/tmp/claude-501/-Users-manas-choudhary-orca-projects-hackasol/e64f2eb4-9bd8-469c-aefb-75bfaefd4d3f/scratchpad/shots/emu/

Verified on device:
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
- Not built, so untested: STT parser, APK guard (as of the Kotlin QA pass; commits f4aa9f0 and 5125e16 have since landed and are not covered by the counts above).
- Android-only, not unit-testable here: AppSettings export (SharedPreferences), SqliteVerdictLog SQL (row mapping is covered).
- Kotlin side of ML prompt parity: read-only comparison, no JVM run.
- Setup screen showed the accessibility step as pending while dumpsys showed the service bound; probably an artifact of uiautomator dump, not verified.
- Process notes:
  - QA files were swept into other agents' commits (a5bdf5d, 7f3c389, d0e36df) because agents share one checkout.
  - A credential was printed from a local Gradle init script during debugging. It must be rotated. It is not in any repo file and its value is not recorded here.
  - An "atlan-secguard --no-verify bypass detected" warning appeared on a QA commit although QA never passed --no-verify. Not investigated; worth a look by the security owner.

## Final gate

To be filled in at the final HEAD.

| Check | Command | Result |
|---|---|---|
| Final HEAD | `git rev-parse --short HEAD` | TBD |
| Kotlin qa package | see How to run | TBD |
| Full Kotlin unit tests | `:app:testDebugUnitTest` | TBD |
| Flutter test/qa and full suite | `flutter test test/qa`, `flutter test` | TBD |
| ML | `pytest tests` | TBD |
| Dashboard | `node --test dashboard/test/` | TBD |
| Open bugs at final HEAD (E1-E6, F3) | re-check | TBD |
| Emulator smoke at final HEAD | manual | TBD |

## How to run

- Kotlin (set `GRADLE_USER_HOME` to a writable cache dir, because ~/.gradle is root-owned here): `cd android && ./gradlew --offline -PskipDependencyChecks=true :app:testDebugUnitTest --tests 'com.hackasol.scamshield.qa.*'`
- Flutter: `flutter test test/qa/qa_logic_test.dart test/qa/qa_screens_test.dart` (subset); `flutter test test/qa` for all 112.
- ML: `pytest tests` (from `ml/`).
- Dashboard: `node --test dashboard/test/`
