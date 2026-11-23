# ScamShield UX Audit v2

- Build: `1adb24c` (main). Round 1 audited `a4955aa`; round 1 commit is `e14a3d2`.
- Image source: emulator (Android, real device fonts, 1080x2400), 73 shots in `.../e64f2eb4-9bd8-469c-aefb-75bfaefd4d3f/scratchpad/shots/emu/` (stale_old_ui ignored): light/dark x 1.0/2.0 for 15 screens, plus 13 light-1.0-only flows. Every shot was opened and looked at. Rules-only mode, no live call, so no verdict ever appears in these shots.
- Date: 2026-11-23
- Working tree caveat: other agents are editing `lib/` while I audit (uncommitted changes in main, setup, live feed, report, settings, family, lessons, try_api, section_header, new `lib/demo/`). The shots show committed code. Where the working tree already differs I say "fixed in tree, not on device". `try_api_screen.dart` changed under me mid-audit, so its line numbers are from my last read.
- Capture artefacts, not app bugs: a lime frame around the screen edge on the Learn, Help, quiz, family-code and settings shots from 11:22 on; debug and chat icons in the status bar.
- Pairing secret: `family_code_shown_light_1.0.png` shows the real secret. I did not copy or describe it. Please re-shoot that screen with a throwaway secret before the shots go anywhere shared.
- Priorities: P1 = breaks the demo or the user's safety, P2 = real friction, P3 = polish.

## 1. v1 issues: status

| v1 issue | Status | Evidence |
|---|---|---|
| Report/Lessons/Quiz/score unreachable | FIXED | 5 tabs (सेटअप, जाँच, लाइव, सीखें, मदद), Help hub with Report/Family/Settings/Recording; `main.dart:134-139`, `:145-182`. Seen on device. |
| Shell English-only, "Try API" naming | FIXED | Hindi labels, English tooltips; `main.dart:53`, `:134-138`. Seen. |
| Nav label "Setting/s" breaks at 2.0x | FIXED | Chrome clamped to 1.2x (`main.dart:38`). All 2.0x shots show unbroken labels and the app bar action. |
| No first-run language / privacy / pre-permission | FIXED, with gaps | Language card, lock + Hindi privacy line, "अब Android आपसे पूछेगा। यह सामान्य है।" card (`firstrun_*`, `setup_*`; `setup_screen.dart:417`). Gaps in 2.1. |
| Live Caption never completes, "/4" counts experimental mic | FIXED in code | Required = service, captions, notifications, message access; captions confirmed by the user (`setup_screen.dart:35-37`, `:238`, `:244`); optional steps under "उन्नत" (`:380-389`). Advanced section not shot. |
| Idle "सामान्य बातचीत 0%" chip | FIXED | `live_*` shows only "अभी कोई कॉल नहीं" + empty state. |
| Dev log rows in the feed | PARTLY | captions_*/model gated (`live_feed_screen.dart:42-43`, `:110`). `'Call started'` (`:87`), `'In-call signal: ...'` (`:90`) and mic rows (`:93-98`) are still English. |
| Verdict card Hindi-first, advice first, no %, no telemetry | FIXED in code, not on device | `showDebug:false` layout, `क्यों?` expander (`verdict_card.dart:7-17`, `:60`, `:129-139`); live feed and paste use it. No verdict shot exists. |
| 1930 is a number, not a button | FIXED in code | `_Helpline` dials via `HandoffApi.dial` (`live_feed_screen.dart:307-325`); Report has a pinned 1930 button (seen on device). |
| Report: 1930 first, jargon, screenshots field | MOSTLY FIXED | Pinned `1930 पर कॉल करें` bar, numbered steps ("1 सबसे पहले 1930 पर कॉल करें"), golden-hour card at the top once started (`report_lost_*`, `report_goldenhour_*`). Screenshots field now optional notes (`report_screen.dart:106`). Open items in 2.4. |
| Quiz disabled-option contrast (2.31:1) | FIXED | Right/picked rows show full-colour text and icon (`quiz_q1_answered_*`, `quiz_wrong_feedback_*`). Unpicked options are muted grey, 4.66:1 on page, passes. |
| Harsh red `गलत` | FIXED | Amber `ध्यान दें` with warning icon (`quiz_screen.dart:25`); amber on tint 5.15 to 5.59:1 light, 7.11:1 dark (computed). |
| Family unpair one-tap | FIXED in code | `unpairTitle/unpairBody` strings (`family_screen.dart:51-52`); dialog not shot. |
| Settings loading/error | FIXED in code | `StateMessage` loading/error (`settings_screen.dart:432-444`). |
| Settings English, debug toggles up front | STILL OPEN | `settings_top_*` unchanged: "Use on-device Gemma", "Show warning bubble", OCR, mic test; `Discovery mode (debug)` and package field (`settings_screen.dart:462`, `:497`, `:510`). |
| Try screen English, truncated samples, raw errors, no empty state | STILL OPEN on device, FIXED in tree | `try_*` shots: "Analyse", "संदेश यहाँ चिपकाएँ · Paste a message", chips cut at 20 characters, nothing under the button. Working tree has a pinned `मैसेज जाँचें` bar, `try_empty` state and an example chip (`try_api_screen.dart:300-335`, `:369-392`). |
| Family: how-it-works, ask-the-caller line, secret handling | STILL OPEN | `family_light_1.0` unchanged; code view still asks the question with no instruction line. |
| Learn score caption "डिजिटल वित्तीय साक्षरता स्कोर (/ 100)" | STILL OPEN | `learn_*`, `quiz_result_*`. See 3.3. |
| Quiz feedback repeats the right answer, no progress bar | STILL OPEN | `quiz_wrong_feedback_*`: "सही उत्तर:" line plus the highlighted green row; only text "सवाल 2/3". |
| DESIGN.md is the Apple web analysis | STILL OPEN | No addendum yet. |

## 2. New issues seen only on device

### 2.1 Setup and first run
- P2. Language chips have no selected state and no default (`firstrun_*`, `setup_screen.dart:35`). A person who does nothing sees three identical pills and no sign that Hindi is already in use. Fix: pre-select हिन्दी with the check-circle icon (`:448`) and a caption `अभी: हिन्दी / Current: Hindi`; keep "भाषा चुनें" as a non-blocking card.
- P2. The language choice is not visibly shared: Learn, Report and Family still show their own chips with हिन्दी ticked. I could only shoot Hindi, so propagation is not verified. Fix: read the Setup language in `LessonsScreen`, `ReportScreen`, `FamilyScreen` as `initialLang` and hide their chips (put one chooser in Help).
- P2. Setup wall of text: the "अब Android आपसे पूछेगा" card plus a 6-line Hindi paragraph plus the step card plus a mixed English path `Settings → Accessibility → ...` before the first action is visible (`setup_light_1.0`). At 2.0x the first screen is the privacy paragraph and one line of the next card (`setup_light_2.0`). Fix: collapse the paragraph to two lines (`ScamShield सिर्फ़ स्क्रीन के कैप्शन पढ़ता है। आवाज़ रिकॉर्ड नहीं होती।` / `Reads on-screen captions only. No audio recorded.`) and keep the English path inside the step, not above it.
- P2. At 2.0x the sticky primary wraps to two lines and takes about 330px of 2400px (`setup_*_2.0`); the pending step is mostly hidden behind it. Fix: shorten labels to one word where possible (`चालू करें`) and give the list `bottom` padding equal to the bar height so the last card is never cut.
- P3. `0 / 4 ज़रूरी कदम पूरे` is grey text; no progress bar. Fix: add `LinearProgressIndicator(value: done/4)` under it.

### 2.2 Shell and header action
- P2. `ठगे गए? 1930` sits in the app bar in link-blue like any other text button (`main.dart:116-121`). It is the most important action and looks like a tab title helper. Fix: give it a tinted container with an icon (`Icons.support_agent`) so it reads as an emergency chip; keep the status colours reserved for verdicts by using `cs.primary` fill.
- P3. In dark mode the selected-tab pill is nearly invisible (accent at 12% on black); the selected state rests on label and icon colour (`*_dark_1.0`, `app_theme.dart` navigationBarTheme `indicatorColor`). Fix: use `p.accent.withValues(alpha: 0.24)` in `Pal.dark` only.

### 2.3 Try / paste (HEAD on device)
- P1. At 2.0x the primary `Analyse` is half-hidden under the nav bar and the hint is cut to `संदेश यहाँ चिपकाएँ · Past…` (`try_*_2.0`). Fixed in tree by the pinned action bar (`try_api_screen.dart:369-392`); re-shoot to confirm.
- P2. Empty tap does nothing: `Analyse` with an empty box shows no message (`try_empty_result_light_1.0`; v1 code returns silently). Working tree adds `_inputError` and `try_empty`; verify the error copy: `पहले संदेश चिपकाएँ` / `Paste a message first`.
- P2. Six full-width sample chips push the primary action to the bottom of the first screen. Working tree replaces them with one example chip (`:301-333`), which fixes this.

### 2.4 Report and golden hour
- P1. Choosing a path shows nothing above the fold. `report_top_light_1.0` and `report_lost_light_1.0` look the same except a card appearing under the tiles; at 2.0x `report_top_light_2.0` and `report_lost_light_2.0` are identical. Fix: after `_choose` call `Scrollable.ensureVisible` on the detail, or replace the two path tiles by the detail with a back arrow.
- P2. The selected path has no visible mark in the shots (no outline on `मेरे पैसे कट गए` in `report_lost_*`), although the code draws a 3dp outline (`report_screen.dart:378`). Fix: add a check icon plus the word `चुना गया` inside the tile; do not rely on colour.
- P2. When the clock is running the screen shows the golden card, then the title `शिकायत दर्ज करें` and the two path tiles again with nothing selected (`report_goldenhour_*`, `notif_action_report_light_1.0`). It reads like a fresh form. Fix: when the clock is active hide the path tiles and show `आप "पैसे कट गए" में हैं · बदलें`.
- P2. Self-blame copy is unchanged: `मैं ठगा गया: 60 मिनट शुरू करें` (`report_lost_*`). Fix: `मेरे साथ ठगी हुई: 60 मिनट की घड़ी शुरू करें` / `I was scammed: start the 60-minute clock`.
- P3. The golden-hour card is red tinted with a red 59:53 and a full red bar (`report_goldenhour_*`). The Hindi hint under it is calm, but red plus a countdown is the one alarming element in the flow. Fix: keep red for the last 10 minutes only, blue before.
- Good: pinned `1930 पर कॉल करें`, numbered steps, `घबराएँ नहीं। ये कदम अभी उठाएँ।` subtitle, golden hint with no self-blame, dark mode reads well (`report_*_dark_*`).

### 2.5 Learn, quiz, score
- P2. Copy spelling is inconsistent: lesson card `बताएं`, `मांगे`, `जो कॉल` (`lesson_card_*`) versus UI `बताएँ`, `चिपकाएँ`, `माँग`. Pick one house style (chandrabindu `ँ`) and normalise the lesson JSON.
- P2. Answered state: the right answer is stated three times (amber card line, green row, explanation) (`quiz_wrong_feedback_*`). Fix: drop the `सही उत्तर:` line (`quiz_screen.dart:333`), keep the green row and the explanation.
- P3. The same shield icon on every lesson card (`lesson_card_*`) and the unselected options in the wrong-answer state are grey with 1.5dp outline; still readable. Fix: lesson icon from `_icons`.

### 2.6 Family
- P1. The shared secret is still shown as 4-letter groups to read or type by hand (`family_code_shown_light_1.0`), and there is still no share button. Note: `family_enter_light_1.0` and `family_enter_bad_light_1.0` both show the rotating-code screen, not the code-entry field or its error, so entry and the bad-code error were never captured. Fix: add `भेजें / Share` using the existing platform channel (no new endpoint); QR needs a new dependency and BUILD_PLAN approval.
- P2. The alphabet is A-Z and 2-7 (`family_screen.dart:30`), which includes visually ambiguous letters (I/O). Fix: show a one-line hint `I और O अक्षर हैं, अंक नहीं` or exclude I and O from generation and validation.
- P2. Choose screen unchanged: no how-it-works, and `मेरा कोड दिखाएँ` vs `परिवार का कोड डालें` do not say who does what (`family_light_1.0`). Fix: `पहला फ़ोन: कोड बनाएँ` / `दूसरा फ़ोन: कोड डालें`.
- P2. Code screen: the question `क्या फ़ोन करने वाले का कोड यही है?` appears with no prior instruction to ask the caller (code view: `family_enter_light_1.0`, `family_enter_bad_light_1.0`). Fix: line above the ring `फ़ोन करने वाले से उसका कोड पूछें।` / `Ask the caller for their code.`
- Good: the code view is still the strongest screen: ring, tabular code, 56dp outlined yes/no, `जोड़ी हटाएँ` as a quiet link at 2.0x as well (`family_*_2.0`).

### 2.7 Settings, district picker, export
- P1. District sheet opens with the first row under the status bar clock (`district_picker_light_1.0`: "Balod" overlaps "11:23"), English-only names, no title, no close, 28 rows. The code sets `useSafeArea: true` and a `SafeArea` (`settings_screen.dart:119-123`) so the overlap suggests the insets are lost on this device; verify on a second phone. Fix: add a header (`ज़िला चुनें` / `Choose district`), a drag handle, Hindi names (`रायपुर (Raipur)`).
- P2. The empty-export message `अभी भेजने के लिए कुछ नहीं है` renders in red with an alert icon at the very bottom, partly under the gesture bar (`export_result_light_1.0`). The code passes `info: true` (`settings_screen.dart:183`), so either the shot predates the style or `info` is not used. Fix: neutral grey/blue info style, scroll it into view, copy `अभी कोई ठगी दर्ज नहीं हुई, इसलिए भेजने को कुछ नहीं` / `No scams recorded yet, so nothing to send`.
- P2. The Android share sheet offers Quick Share, Gmail, Drive for `trend_export.json` (`export_chooser_light_1.0`). A first-time user does not know where to send it. Fix: pre-explain in the card: `यह फ़ाइल आप किसी को भेजते हैं तभी जाती है। कुछ अपने आप नहीं जाता।` / `Nothing is sent unless you send this file.`
- P1 (carried). The top half of Settings is still English developer text (`settings_top_*`), at 2.0x one setting per screen. Fix as in v1: Hindi-first titles; `useLlm`, OCR, mic test, discovery mode and caption packages under a closed `उन्नत` expander.
- Good: the trust-framed export card (lock, `सिर्फ़ 3 चीज़ें फ़ोन से बाहर जाती हैं: ज़िला, ठगी का प्रकार, तारीख़`, English line) is the best privacy copy in the app.

### 2.8 Contrast, dark mode, fonts (device)
- Dark mode: all 15 screens read well; status colours pass (computed in v1: 4.93, 7.11, 6.51:1). One weak point: switch off-state track is light grey with a white thumb, about 2.6:1 thumb to track (`settings_top_dark_*`). Fix: dark off-track `#48484A`.
- Devanagari: conjuncts, matras and mixed Latin/Devanagari lines (`अब Android आपसे पूछेगा`) render cleanly at 1.0x and 2.0x; no clipped matras seen. Latin digits are used for 1930 and codes, which is right.
- 2.0x clipping seen: Try (HEAD) action under nav; Report path result off-screen; Setup first screen. Not seen: any clipped text on Learn, Help, Family, quiz, report golden hour.
- Edge-to-edge: Report's pinned button clears the gesture bar; Settings content scrolls under it (normal) but the export message ends under it (2.7).

## 3. Answers to the questions from the walk

### 3.1 Header `ठगे गए? 1930` navigates, bottom `1930 पर कॉल करें` dials. Confusing?
Yes, mildly. Evidence: `report_top_light_1.0` and `deeplink_report_cold_light_1.0`: the header says "1930" in a button, which a panicked user reads as "call 1930", but it opens a screen where the call needs a second tap on a second 1930 button. My read: keep navigation (a dial from a persistent header would misfire constantly), but make the promise match. Fix: header copy `ठगे गए? मदद` with a phone-shaped icon and 1930 only on the button that dials; land on Report with the dial button already pinned (it is). If the lead wants one tap to dial, put dial on the pinned button and keep the header for the route, both labelled with the same verb: `मदद लें` for navigation, `1930 पर कॉल करें` for dialing.

### 3.2 Empty Analyse and empty share
Both are missing proper empty states at HEAD. Analyse with an empty box does nothing (`try_empty_result_light_1.0`: same screen, no message). The export with no data shows a red alert at the screen bottom under the gesture bar (`export_result_light_1.0`). Fixes in 2.3 and 2.7. A user who gets no response taps again, then assumes the app is broken.

### 3.3 Literacy score 8/100 after a 2/3 quiz: demotivating?
Yes. Evidence: `quiz_result_light_1.0` shows `2/3` then `8`; `quiz_engine.dart:74` defines the score as the mean of best percents over all 8 lessons, so a good first lesson (67%) averages to 8. A first-time learner reads "8 out of 100" as failing. My read: show progress, not an average. Fix: lead with `पाठ 1 / 8 पूरे` and a progress bar; show the score as `+8 अंक` with `हर पाठ से स्कोर बढ़ेगा`; keep `/100` in English as a second line. Copy: `बहुत बढ़िया! आपने 1 पाठ पूरा किया। आपका ज्ञान-स्कोर: 8 / 100` / `Well done! 1 lesson complete. Your knowledge score: 8 / 100`. Do not change the formula; change what is shown first.

## 4. Top 10 for the design lead (ordered by user impact on the demo)

1. Re-shoot with a call in progress and show a real SCAM/SUSPICIOUS verdict, a safe one, and the heads-up notification. The new verdict card, the 1930 dial row and the in-call OTP alert are the product and none is visible in the 73 shots.
2. Report: make the path choice visible. After tapping `मेरे पैसे कट गए` nothing changes above the fold (identical at 2.0x), no selected mark, and the running-clock view repeats the title and tiles. Scroll to the result or replace the tiles by the detail plus a back arrow. (`report_screen.dart:378`, `_choose`)
3. Finish the Hindi-first rewrite: Settings (all English, debug toggles up front), Try (HEAD: `Analyse`, truncated English chips), and the Live feed rows that are still English (`Call started`, `In-call signal`). (`settings_screen.dart:462-510`, `live_feed_screen.dart:87-98`)
4. The header action: make it look like an emergency control and make the label match what it does (navigate), not `1930`. (`main.dart:116-121`)
5. Family secret handling: add a Share button, remove I/O ambiguity, add the how-it-works and ask-the-caller lines. Re-shoot with a throwaway secret. (`family_screen.dart:30`, choose screen)
6. Score framing: lead with `पाठ 1/8 पूरे`, show the average as `+8 अंक`; fix the long `डिजिटल वित्तीय साक्षरता` caption. (`quiz_engine.dart:74`, `lessons_screen.dart`, `quiz_screen.dart`)
7. Empty and error states for Try and export: empty Analyse must say what to do; the empty export must not be a red alert under the gesture bar. (`try_api_screen.dart`, `settings_screen.dart:183`)
8. District sheet: title, handle, Hindi names, and check the status-bar overlap on a second phone. (`settings_screen.dart:119-145`)
9. Setup at 2.0x: shorten the privacy and Android-warning text, shorten the sticky label, pad the list by the bar height, add a progress bar. (`setup_screen.dart:238-290`, `:460`)
10. Normalise Hindi spelling (`ँ` everywhere), pre-select हिन्दी on first run, and carry the chosen language into Learn, Report and Family. (`setup_screen.dart:35`, lesson JSON)

## 5. Not verified

- No shot of: any verdict (SAFE, SUSPICIOUS, SCAM), the heads-up notification itself, the family unpair dialog, the Setup "उन्नत" section, the recording screen, the QR/UPI check, Demo Lab, the paste result, or any Chhattisgarhi or English state.
- The family code-entry field and its bad-code error (the two `family_enter*` shots show the code view instead).
- `setup_postgrant_light_1.0.png` looks the same as the pre-grant shot (primary still `कॉल सुरक्षा चालू करें`), so the post-grant state was not captured.
- Dark 2.0x looked at for all 15 screens; nothing new beyond the light findings except the switch contrast.
- Hindi and Chhattisgarhi copy proposed here is my draft and needs a native-speaker read.
- Contrast ratios for amber and the switch track are computed from the hexes in `app_theme.dart`, not sampled from pixels.
