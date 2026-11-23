# ScamShield UX Audit v1

- Build: `a4955aa` (main) plus uncommitted edits to `lib/models/verdict.dart` and `lib/screens/try_api_screen.dart` (scam-type chip). Code was read from the working tree.
- Date: 2026-11-23
- Image source: widget-test renders from `test/design/shots_test.dart` (360x800 at 1.0x and 2.0x, Roboto + macOS Devanagari Sangam MN, real glyphs, not Ahem), taken from the existing shots folder, light theme viewed. Plus three emulator captures of Setup at 1.0x and 2.0x (`shots/emu/setup_pregrant_*`). Dark theme: not viewed, judged from computed ratios only. Round 2 should replace this with emulator shots.
- Not rendered (judged from code only): Report, Golden hour, Try API/paste, Settings, Quiz cards phase, Quiz result, Family choose / show-secret / enter-code, any SAFE or SUSPICIOUS verdict, any dark screen, any screen at 2.0x except Live feed and Setup.
- Caveat on the shots: the "→" and some Material icons show as boxes in widget renders (test font only); the emulator renders them correctly. Not counted as bugs.
- Priorities: P1 = breaks the demo or the user's safety, P2 = real friction, P3 = polish.

## 0. Spec reality check (DESIGN.md)

DESIGN.md is an analysis of apple.com (SF Pro, 17px body, 44px targets, product tiles, "Error and validation states were not surfaced", no dark mode, no semantic colours). It cannot be the spec for this app, and the code already diverges on purpose: 20px body, 56dp targets (`lib/theme/tokens.dart:14`), a sanctioned red/amber/green exception (`lib/theme/app_theme.dart:7`), no letter-spacing for Devanagari (`lib/theme/text_styles.dart:3`), muted text darkened from `#7A7A7A` (3.94:1 on `#F5F5F7`, fails AA) to `#6E6E73` (4.66:1). The real spec is `tokens.dart`, `text_styles.dart`, `app_theme.dart` comments. Fix: add a short "ScamShield addendum" at the top of DESIGN.md listing those overrides, Hindi-first copy, empty/error/loading shape (`StateMessage`) and the 2.0x rule. What the code does follow well: single blue accent for interactive, no shadows, pill buttons, 400/600/700 weights only, icon plus word for every status.

## 1. Contrast (computed, WCAG 2.x)

| Pair | Ratio | Verdict |
|---|---|---|
| Light scam `#C8102E` on its tint over white / over page | 4.95 / 4.56 | pass AA (page case is tight) |
| Light suspicious `#9A4500` on tint over white / page | 5.59 / 5.15 | pass |
| Light safe `#166F2E` on tint over white / page | 5.44 / 5.02 | pass |
| Dark scam `#FF6961` / suspicious `#FFB340` / safe `#30D158` on tint over `#1C1C1E` | 4.93 / 7.11 / 6.51 | pass |
| Ink on every tint | 11.7 to 14.6 | pass |
| Muted `#6E6E73` on page / white; dark `#A1A1A6` on `#1C1C1E` | 4.66 / 5.07; 6.61 | pass, but only barely at 16px caption on the page colour |
| Accent `#0066CC` on white / page; dark `#2997FF` on `#1C1C1E` | 5.57 / 5.11; 5.64 | pass |
| White on accent; black on dark accent | 5.57; 6.96 | pass |
| Disabled filled button text `#6E6E73` on `#E0E0E0` (`app_theme.dart:152-155`) | 3.84 | fail (P3, disabled is exempt but Analyse looks dead) |
| Quiz option after answering, Flutter disabled style (38% ink) on page: light / dark | 2.31 / 3.19 | fail, P1 below |
| Hairline `#E0E0E0` on white as input border (`app_theme.dart:205-207`) | 1.32 | fails 1.4.11 non-text 3:1 for text fields, P2 |

Status colours are fine. The two failures are the quiz disabled options and the hairline input border.

## 2. Per screen

### 2.1 App shell (`lib/main.dart`)

- P1. Report, Lessons, Quiz and the literacy score are not reachable. `HomeShell` has 5 tabs (Setup, Try API, Live, Family, Settings) and nothing constructs `ReportScreen` or `LessonsScreen` outside tests (grep of `lib/`). Two of five must-haves (reporting handoff, lessons + score) do not exist for a demo user. Fix: `main.dart:36-58`. Tabs become 5: सेटअप / Setup, जाँचें / Check, लाइव / Live, सीखें / Learn, मदद / Help. Move Family and Settings into "मदद" (list: शिकायत करें / Report, परिवार का कोड / Family code, सेटिंग / Settings). Add a persistent red-outline action "ठगे गए? 1930" in the AppBar `actions` that opens `ReportScreen` from every tab.
- P1. All shell copy is English and developer-flavoured: titles `'Try the Text API'`, `'Live call feed'` (`main.dart:36`), AppBar `'ScamShield · ${title}'` (`:41`), nav labels `Try API`, `Live` (`:52-58`). "Text API" and "Try API" mean nothing to the user. Fix: Hindi label as the label, English as the tooltip/semantics: `NavigationDestination(label: 'जाँचें', tooltip: 'Check a message')`. AppBar title: Hindi screen name only, no brand prefix.
- P1. At 2.0x the nav label "Settings" breaks to "Setting / s" (emulator capture `setup_pregrant_light_2.0.png`). Fix: wrap the `NavigationBar` in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)` (`main.dart:49`) and use short Hindi labels (max 6 characters). Same clamp on the AppBar.
- P1. No first-run language choice. Language is a per-screen chip (Lessons `:111`, Family `:198`, Report `:310`), defaults to Hindi, is not shared, and Chhattisgarhi does not exist on Setup, Live, Try or Settings at all. Fix: one first-run screen "भाषा चुनें / Choose language" with three large tiles (हिन्दी, छत्तीसगढ़ी, English), saved in prefs, passed down as `initialLang`; the per-screen chips become optional. Until the hne strings exist for Setup/Live, fall back to hi.
- P2. Shell is not safe for 360dp at 2.0x: chrome (AppBar 320px + sticky button 330px + nav 310px of 2400px) leaves 58% for content (Setup emulator capture). Fix: after clamping the nav, drop the in-card duplicate action button of the current step (see 2.2), since the sticky bar already does it.

### 2.2 Setup / onboarding (`lib/screens/setup_screen.dart`)

- P1. Live Caption never completes and is not in the guided sequence. Its step is hard-coded `done: false` (`:292`) and the sticky primary goes service, notifications, message access, mic, test bubble (`:219-233`). Without Live Caption the product does not detect calls (FINAL_PLAN section 2). Fix: add a captions state (native check, or a manual "मैंने चालू कर लिया / I turned it on" toggle if no check exists) and insert it as step 2 of the primary chain. Copy: title `लाइव कैप्शन चालू करें` / `Turn on Live Caption`, body `वॉल्यूम बटन दबाएँ, नीचे कैप्शन का निशान दबाएँ।` / `Press a volume key, tap the captions icon.`
- P1. Progress count is wrong for the user: "3 / 4 ज़रूरी कदम" counts service, notifications, message access and the experimental mic test (`:216`, `:263`). A first-time user cannot finish "ज़रूरी" step 4 (it needs a phone call on speaker). Fix: required = accessibility, captions, notifications, message access (4); the mic test and bubble test are optional ("बाद में / Later"). Copy: `4 में से 3 ज़रूरी कदम पूरे` / `3 of 4 required steps done`.
- P1. Bodies are English, long, and technical, for a Hindi-first user: `:278-279`, `:293-296`, `:309-313` (raw `Status: READY`, file path, "~555 MB"), `:346-348` ("HAS_AUDIO / SILENT"). Fix: Hindi paragraph first (max 2 short lines), English as a smaller second line. Example for step 1: `सेटिंग खुलेगी। "ScamShield" चुनकर चालू करें।` / `Settings opens. Pick "ScamShield" and turn it on.` Model step: `AI मॉडल (555 MB) एक बार डाउनलोड होगा। Wi-Fi पर करें।` / `One-time 555 MB download. Use Wi-Fi.`
- P1. No pre-permission explanation. The sticky button sends the user straight to the Android accessibility screen and its scary system warning (`:220`; Android 13+ "restricted setting" for sideloaded apps per FINAL_PLAN). The privacy promise lives only inside the English body (`:279`). Fix: put one Hindi privacy line at the top of the screen under the header, always visible: `आपकी कॉल रिकॉर्ड नहीं होती। कुछ भी फ़ोन से बाहर नहीं जाता।` / `Calls are not recorded. Nothing leaves your phone.`, and a one-card "अब Android आपसे पूछेगा। यह सामान्य है।" / `Android will now ask you to confirm. This is normal.` before the first system hand-off.
- P2. Developer controls in the first-time path: `.task फ़ाइल जोड़ें`, `मॉडल फिर लोड करें`, `अभी जाँचें (बिना कॉल)`, `कॉल ऑडियो टेस्ट` (`:327-338`, `:341-370`). Fix: collapse under an "उन्नत / Advanced" `ExpansionTile` at the bottom, closed by default.
- P2. Same action twice on the current step: card button `एक्सेसिबिलिटी खोलें` (`:281`) and sticky `कॉल सुरक्षा चालू करें` (`:220`). Two buttons, one result. Fix: keep the sticky one only for the active step; keep in-card buttons only for non-active steps.
- P2. Download state is a raw enum: `'$st ${mb(done)} / ${mb(total)} MB'` (`:110`) and raw `${_dl['message']}` errors (`:99`). Fix: `डाउनलोड हो रहा है: 120 / 555 MB` / `Downloading`; error `डाउनलोड नहीं हो सका। Wi-Fi जाँचें और फिर कोशिश करें।` / `Download failed. Check Wi-Fi and try again.`
- P2. Snackbars are English (`:81`, `:359`): `Import failed`, `Armed: make a call on speaker now`. Fix: Hindi first, English second line.
- P3. Error state repeats itself: title `सेटअप की स्थिति नहीं मिल सकी`, subtitle and button both `फिर कोशिश करें` (`:240-242`). Fix: subtitle `ऐप बंद करके फिर खोलें।` / `Close and reopen the app.`
- Good: done steps collapse to one row with icon + word `हो गया` (`:131-143`), loading and error states exist, one primary action.

### 2.3 Live feed (`lib/screens/live_feed_screen.dart`)

- P1. False reassurance when idle: the status card always shows `StatusChip(_callLevel.hindi · risk%)`, which starts as "सामान्य बातचीत · 0%" with an empty bar even when no call exists and protection may be off (`:225-227`). "Normal conversation" is a claim the app has not earned. Fix: when `!_inCall && _callRisk == 0` hide chip and bar; show `सुरक्षा चालू है / Protection is on` only if the service reports connected, else `सुरक्षा बंद है — सेटअप में चालू करें / Protection is off — turn on in Setup`.
- P1. Raw English developer log in the user feed: `Call started`, `In-call signal: otp (...)`, `Mic Source: HAS_AUDIO -14.2 dBFS, peak ...`, `No captions seen 6 s into the call → trying ...`, `Model: READY ...` (`:81-106`), plus the caption line `"$text  [$via]"` showing a package tag (`:69`). The in-call OTP signal is the most important alert after a verdict and it is a grey bolt row. Fix: show only call start/end, verdicts and signals; gate `discovery`, `mic_probe*`, `captions_*`, `model`, `service` rows behind `discoveryMode`. Signal copy: `कॉल के दौरान OTP आया। किसी को न बताएँ।` / `An OTP arrived during the call. Do not share it.` Render signals with the same tinted-card grammar as SUSPICIOUS, not a `ListTile`.
- P2. Every history item is a full red/amber card (`:151`), a wall of red after a long call. Fix: history rows as one-line chips (icon, Hindi label, first 40 characters of the quote), tap to expand into `VerdictCard`.
- P2. Empty state CTA always opens caption settings (`:196`), even when the user's real problem is that the accessibility service is off. Fix: pick the CTA from setup state: service off, "सेटअप खोलें"; captions off, current CTA.
- P3. The screen has no plain-language title (AppBar says "Live call feed"). Fix with the shell rename (2.1): `कॉल की निगरानी / Call watch`.
- P3. `_Helpline` is a number to read, not a button (`:252-253` comment: "no dialer channel"). A dialer channel already exists: `HandoffApi.dial` (`report_screen.dart:44`). Fix: make the card an `ActionTile` calling `HandoffApi().dial('1930')`; keep copy `1930 पर कॉल करें` / `साइबर ठगी की मुफ़्त हेल्पलाइन`. (Listed again in the top 10 because it is the most important tap in the app.)
- Good: verdict first, calm advice title `घबराएँ नहीं। अभी यह करें:` (`:130`), advice lines are short imperatives, icon + word status.

### 2.4 Verdict card (`lib/widgets/verdict_card.dart`, `lib/models/verdict.dart`)

- P1. Headline is English-only and statistical: `This statement is SCAM · 87%` (`verdict.dart:80`, used at `verdict_card.dart:54`). The Hindi meaning is a smaller second line (`:59`). "87%" and "SCAM" carry no meaning for a low-literacy user and wrap to 4 lines at 2.0x (`ux_live_feed_light_2x.png`). Fix: headline = Hindi label in `titleLarge`, `label.hindi` (`धोखाधड़ी हो सकती है`) with English `Likely a scam` as a caption line under it. Replace the percentage with a 3-step word: `पक्का / शायद / कम` (`Sure / Likely / Low`) or drop it. SAFE stays `सामान्य बातचीत`; add `Normal conversation`.
- P1. The action is the 5th block. Order is headline, label, quote, why, chips, advice, helpline (`:49-96`). Advice and 1930 are what the user must read first. Fix: for non-SAFE verdicts order: icon + Hindi headline, advice lines, 1930 tile, then a collapsed "क्यों? / Why?" (`ExpansionTile`) holding quote, reason and trigger chips. The card then fits one screen at 2.0x.
- P2. Footer is engineering telemetry: `gemma+rules · 1420 ms · caption` (`:98`). Fix: hide unless `discoveryMode`; if wanted, show only the source in Hindi (`फ़ोन कॉल`, `SMS`, `चिपकाया संदेश`; the map already exists as `_hiLabels`, `report_screen.dart:48-67`).
- P2. Trigger chips can be meaningless: a masked value renders as `xxxxxxxxxxxxxxxxxxxxxxxxxxx…` (third chip in `ux_verdict_masked_light_2x.png`, `:71-81`). Fix: drop triggers that are mostly mask characters, or label them `संख्या छिपाई गई / number hidden`.
- P3. `RiskLabel.color` still carries the old hexes `#1B5E20 / #B45309 / #B71C1C` (`verdict.dart:22-26`), contradicting `StatusColors`. Fix: delete it if unused (check callers first), otherwise point it at `StatusColors`.
- Good: tinted surface plus solid icon plus word, so meaning never rests on colour; all three status colours pass AA.

### 2.5 Try API / paste (`lib/screens/try_api_screen.dart`)

- P1. A pasted scam gets a verdict with no next step. The live feed adds advice and 1930 (`live_feed_screen.dart:130-147`); this screen shows a bare `VerdictCard(verdict: v)` (`:84`). The paste/share path is the main real-life entry (SMS, WhatsApp). Fix: extract `_advice`/`_Helpline` from the live feed into a shared widget and use it here, plus a `रिपोर्ट करें / Report` tile once Report is routed.
- P1. Error state prints the raw exception: `_error = '$e'` shown in red (`:39`, `:73-76`). Fix: `जाँच नहीं हो सकी। फिर कोशिश करें।` / `Could not check. Try again.` with the same `StateMessage` used elsewhere.
- P1. Developer naming: tab "Try API", button `Analyse` / `Analysing on device…` (`:71`). Fix: screen name `संदेश जाँचें / Check a message`; button `जाँचें / Check`; busy `जाँच हो रही है…` / `Checking…`; label `संदेश यहाँ चिपकाएँ` / `Paste the message here` (Hindi first, `:53` has both but joined on one line).
- P2. Off-system styling: hard-coded `EdgeInsets.all(16)`, `SizedBox(8/12)`, `Wrap(spacing: 6)`, a local `OutlineInputBorder()` that overrides the themed border (`:47-57`), and the progress spinner is 18dp. Fix: `Sp.l`, `Sp.s`, `Sp.m`; delete the local `border:`; use `kTouch` for the button.
- P2. Sample chips are cut at 20 characters (`:61`), producing `Sir aapke phone pe O…`, which tells the user nothing. Fix: use a short title per sample (`OTP माँगना`, `डिजिटल अरेस्ट`, `पार्सल`, `KYC`, `सामान्य`, `AnyDesk`), full text inserted on tap.
- P2. Empty state is blank under the button. Fix: `StateMessage(icon: Icons.content_paste, title: 'कोई संदेश चिपकाएँ', subtitle: 'SMS या WhatsApp का संदेश कॉपी करके यहाँ डालें।')` and a `पेस्ट करें / Paste` button reading the clipboard.
- P3. History grows without bound and has no clear (`:78-85`); scam-type chip sits outside the card (`:79-83`). Fix: put the scam type inside `VerdictCard` under the headline; cap at 5 results.

### 2.6 Report and golden hour (`lib/screens/report_screen.dart`) (not rendered)

- P1. Not reachable from the app (see 2.1; the class comment says "T3.11 wires navigation").
- P1. On the "I lost money" path the 1930 call is not first. `_detail` builds golden-hour start tile, then dial targets, then evidence, then fields (`:343-360`). The path tile's own subtitle promises `अभी 1930 पर कॉल करें` (`:79`) but tapping it only selects the path (`:339`), and on a 360x640 phone the result appears below the fold with no scroll, so nothing seems to happen. Fix: after `_choose(true)` show the dial tile first, then the clock; call `Scrollable.ensureVisible` on the detail; or replace the two path tiles with the detail view plus a back arrow.
- P1. `f_screenshots`: `स्क्रीनशॉट (फ़ाइल के नाम)` asks a first-time user to type file names (`:99`, `:532-543`). Fix: remove the field in v1, or replace by a file picker button `फ़ोटो चुनें / Choose photos`.
- P2. Selected path is shown only by a 3dp blue outline (`:337`), colour alone. Fix: add a check icon plus the word `चुना गया / Selected` in the tile.
- P2. Jargon: `UTR या लेन-देन नंबर`, `सबूत भेजें (ZIP)`, `चक्षु` (`:98`, `:102`, `:91`). Fix: `बैंक मैसेज वाला लेन-देन नंबर (UTR)`, `सबूत की फ़ाइल बनाकर भेजें / Make and send evidence file`, `चक्षु (संचार साथी): शक वाला नंबर बताएँ`.
- P2. Self-blame in the CTA: `मैं ठगा गया: 60 मिनट शुरू करें` (`:82`). Fix: `मेरे साथ ठगी हुई: 60 मिनट की घड़ी शुरू करें` / `I was scammed: start the 60-minute clock`. Chhattisgarhi: `मोर संग ठगी होइस: 60 मिनट के घड़ी सुरू करव`.
- P2. Expired copy is cold: `समय पूरा हुआ। फिर भी 1930 पर कॉल करें।` (`:86`). Fix: `समय निकल गया, पर मदद मिल सकती है। अभी 1930 पर कॉल करें।` / `Time has passed, but help is still possible. Call 1930 now.`
- P3. Loading is a bare spinner without words (`:324`). Fix: `StateMessage(loading: true, title: 'तैयारी हो रही है…')`.
- P3. Field labels are separate `Text` widgets above `TextField` (`:535-543`), so TalkBack reads an unlabeled field. Fix: `InputDecoration(labelText: s['f_$k'])` or wrap in `Semantics(label:)`.
- Good: clock restored from native (`:243-247`), 1930 fallback when native pack fails (`:196`), 3 languages with identical keys, dial copy `डायल खुलेगा। हरा बटन आप खुद दबाएँ।` is clear.

### 2.7 Lessons (`lib/screens/lessons_screen.dart`) and literacy score

- P1. Not reachable (see 2.1).
- P2. Score label is a mouthful: `आपका डिजिटल वित्तीय साक्षरता स्कोर (/ 100)` under a bare `13` (`:130-135`, image `ux_lessons_light.png`). "Literacy" and `(/ 100)` read as form jargon. Fix: value `13 / 100`, caption `आपकी जानकारी का स्कोर` / `Your knowledge score`, plus `पाठ 1 / 8 पूरे` and a `LinearProgressIndicator`.
- P3. `सर्वश्रेष्ठ` is a hard word for the audience (`quiz_screen.dart:19`). Fix: `सबसे अच्छा`; hne `सबले बढ़िया` is fine.
- P3. Lessons screen has no title or one-line purpose (relies on the AppBar of the shell). Fix: `SectionHeader(title: 'सीखें', subtitle: 'हर पाठ 2 मिनट का है')` above the score.
- Good: icon-first tiles with a 48dp icon and 88dp row, one sticky primary naming the next lesson, `StateMessage` for loading, empty and error.

### 2.8 Quiz (`lib/screens/quiz_screen.dart`)

- P1. After answering, options are disabled with Flutter's 38% style, so the correct answer and the picked answer render grey text on a coloured border (contrast 2.31:1 light, 3.19:1 dark; image `ux_quiz_light.png` shows grey icons and text in both the green and red rows). This is the exact moment the user is supposed to read. Cause: `onPressed: answered ? null` (`:394`), which makes `foregroundColor` ignored. Fix: keep `onPressed: answered ? () {} : ...` (or an `InkWell` in a `Container` with explicit border), so `foregroundColor: color` applies; ink-coloured text on the tinted background.
- P2. Harsh wrong-answer tone: red `cancel` icon plus `गलत` (`:320-325`) for people who may already feel foolish. Fix: heading `ध्यान दें` / `Take note` in `st.suspicious` (amber), same icon-plus-word grammar; keep `सही!` for right. Explanation stays.
- P2. The feedback block sits above the options and repeats the right answer (`:333`) that is highlighted below, pushing options down (at 2.0x the options are off-screen). Fix: options first, feedback under them (sticky `अगला सवाल` stays), drop the `सही उत्तर:` line.
- P3. No progress bar, only text `सवाल 1/3` (`:287`). Fix: `LinearProgressIndicator(value: (_q+1)/n)`.
- P3. All lesson cards show the same shield icon (`:221`). Fix: use the lesson's own icon from `_icons` (`lessons_screen.dart:29`).
- P3. Result view: `इस बार` under `2/3` is ambiguous (`:421`), no per-question review, back from AppBar silently discards a half-done quiz. Fix: `इस बार: 2 में से 2 सही`; confirm dialog on back.
- Good: one question at a time, 56dp options, answer-state icon plus colour plus border width, sticky next.

### 2.9 Family code (`lib/screens/family_screen.dart`)

- P1. One-tap `जोड़ी हटाएँ / Remove pairing` with no confirmation, directly under Yes/No (`:157`, `:374`). A mis-tap silently destroys the pairing the family set up. Fix: confirm dialog `जोड़ी हटाएँ? दोनों फ़ोन को फिर से जोड़ना होगा।` / `Remove pairing? Both phones must pair again.` with outlined `रद्द करें` and filled `हटाएँ`.
- P1. The shared secret is a 16+ character A-Z/2-7 string read aloud or typed by hand (`:261-289`, validation `:30`). For low-literacy users that is the highest-failure step in the app. Fix: add a `भेजें / Share` button (share sheet via existing platform channel, no new endpoint) beside the on-screen groups; QR needs a new dependency, so flag it for approval in BUILD_PLAN.md first.
- P2. The choose screen does not explain the two buttons (`:251-257`). "मेरा कोड दिखाएँ" vs "परिवार का कोड डालें" does not say who does which. Fix: 3-line how-it-works with icons, buttons `पहला फ़ोन: कोड बनाएँ` / `First phone: make a code` and `दूसरा फ़ोन: कोड डालें` / `Second phone: enter code`.
- P2. The code view never tells the user to ask the caller first (`:328`). The question `क्या फ़ोन करने वाले का कोड यही है?` appears after the big code. Fix: line above the ring `फ़ोन करने वाले से उसका कोड पूछें।` / `Ask the caller for their code.`
- P2. Missing safety guidance on the show-secret screen. Fix: line `यह कोड सिर्फ़ परिवार को दें। ग्रुप में न डालें।` / `Give this only to family. Do not post it in a group.`
- P3. After a mismatch the message does not mention 1930 (`noMsg`, `:50`). Fix: append `पैसे माँगे हों तो 1930 पर बताएँ।` / `If they asked for money, tell 1930.`
- Good: best hierarchy in the app (ring, code, question, two answers), tabular numerals, yes/no outlined so they are not two primaries, ring turns red in the last 5 seconds with the number still shown.

### 2.10 Settings (`lib/screens/settings_screen.dart`) (not rendered)

- P1. Every setting is English and engineering-named (`:39-49`): `Use on-device Gemma`, `Screen-reading fallback (OCR)`, `Discovery mode (debug)`, `Caption source packages (comma separated)`. Debug options sit at the same level as `Show warning bubble`. Fix: Hindi-first titles, English subtitle; move `useLlm` (rename `तेज़ मोड / Fast mode (rules only)`), `ocrFallback`, `discoveryMode`, `micProbe`, caption packages into a closed "उन्नत / Advanced" expander.
- P1. Switches render OFF until the native read returns (`_s = {}` at `:12`, `value: _s[key] == true` at `:32`) and there is no loading state, so a safety toggle that is on looks off. Fix: `if (_s.isEmpty) StateMessage(loading: true, title: 'लोड हो रहा है…')`; on read failure show the error `StateMessage` with retry.
- P2. The package field saves only on keyboard submit (`:60`), so typing and leaving loses the value. Fix: save on `onChanged` with a debounce or on focus loss.
- P2. Unstyled: no `SectionHeader`, plain 16dp padding, differs from every other screen (`:51-62`). Fix: use `SectionHeader` and token spacing.
- P3. No home for language, 1930/cybercrime links, or the privacy statement. Fix: a "मदद / About" group with language chooser, 1930 dial tile and the privacy line.

## 3. Cross-cutting findings (where the rules above are broken everywhere)

| Concern | Finding |
|---|---|
| Tap targets (>=48dp) | Pass everywhere I could verify: `kTouch` is 56 (`tokens.dart:14`), ActionTile 72, lesson tile 88, list tiles 56, text/icon buttons 56. Verdict trigger chips are 32dp but not tappable. No fix needed. |
| Empty/error/loading | `StateMessage` is used well on Setup, Live, Lessons, Family. Missing on Try API (no empty, raw error), Settings (no loading, no error), Report (spinner without words). |
| Language | Hindi-first only on Setup headings, Report, Lessons, Quiz, Family. English-only on shell, Try API, Settings, Live feed log lines, verdict headline. Chhattisgarhi: Report, Lessons/Quiz, Family only; hne strings still marked draft (`family_screen.dart:32`, `quiz_screen.dart:10`). |
| Tone | Advice copy is calm and imperative where it exists (`घबराएँ नहीं`, `पैसे न भेजें, कॉल काट दें`, `OTP या PIN किसी को न बताएँ`). It is absent on Try API and on the in-call signal. The headline `SCAM · 87%` in red is the alarming part. |
| Large font 2.0x | Verdict headline 4 lines, nav label broken, Setup content 58% of screen, quiz options pushed off screen by the feedback block. Report, Lessons, Family, Settings at 2.0x not seen. |
| Tokens | Off-token values in Try API (16/8/12/6, own border), Settings, Family ring 280 and font 56, Report clock 180. Acceptable only for the two big timers. |

## 4. Top 10 for the design lead (ordered by user impact on the demo)

1. Make Report, Lessons and the literacy score reachable. They exist only in tests; `HomeShell` has no route to them. Rebuild the shell as Setup / Check / Live / Learn / Help with Hindi labels and a persistent `ठगे गए? 1930` action. (`main.dart:36-58`)
2. Rewrite the verdict card for a first-time reader: Hindi headline (`धोखाधड़ी हो सकती है`), advice and the 1930 tile directly under it, quote/reason/chips behind a "क्यों?" expander, no percentage, no engine/ms footer. (`verdict_card.dart:49-99`, `verdict.dart:80`)
3. Make 1930 a tap-to-dial button on Live and Check screens, and add the same advice block to the paste/Check result. `HandoffApi.dial` already exists. (`live_feed_screen.dart:252`, `try_api_screen.dart:84`)
4. Report screen: for "I lost money", 1930 first, golden-hour clock second, scroll to the result; remove the "file names" screenshot field; remove `ZIP`/`UTR` jargon. (`report_screen.dart:343-360`, `:99`)
5. First-run: one language choice (हिन्दी / छत्तीसगढ़ी / English) applied app-wide, one Hindi privacy line (`कॉल रिकॉर्ड नहीं होती, कुछ फ़ोन से बाहर नहीं जाता`), and a pre-permission card before the Android accessibility screen. (`setup_screen.dart:220`, `main.dart`)
6. Fix the Setup checklist logic: add Live Caption as a real step in the guided chain, count only the 4 truly required steps, and hide `.task` import, model reload and mic tests under "Advanced". (`setup_screen.dart:216`, `:292`, `:327-370`)
7. Live feed honesty and language: stop showing "सामान्य बातचीत · 0%" when idle, show the in-call OTP signal as a Hindi alert card, hide dev log rows. (`live_feed_screen.dart:81-106`, `:225`)
8. Quiz readability and tone: stop using `onPressed: null` for answered options (2.31:1 contrast on the correct answer), replace red `गलत` with amber `ध्यान दें`, put feedback under the options. (`quiz_screen.dart:394`, `:320`)
9. Large-text survival at 2.0x: clamp text scaling on the nav bar and app bar to 1.2, short Hindi nav labels, drop the duplicate in-card button on the active setup step. (`main.dart:49`, `setup_screen.dart:281`)
10. Remove the two silent traps: confirm before `जोड़ी हटाएँ` on Family, and show a loading/error state on Settings so safety toggles never look OFF while loading; move debug toggles under "Advanced". (`family_screen.dart:157`, `settings_screen.dart:12`)

## 5. Not verified

- No emulator renders besides Setup; no dark-theme images viewed; Report/Golden hour/Try/Settings/Quiz cards+result/Family setup stages never rendered, so their layout findings come from code.
- Native behaviour (does `family.code`, `report.pack`, `golden.*` exist and return what Dart expects) not checked.
- Hindi/Chhattisgarhi copy proposed here is drafted by the reviewer and needs a native-speaker read before shipping; the hne lines in particular.
