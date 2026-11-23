# ScamShield Demo Script

Merges `SCAMSHIELD_HANDOFF.md` §10 with the `FINAL_PLAN.md` §5 scenarios. The Demo Lab (T8.1) is the backbone: it runs the scenarios through the real pipeline with no phone, notifications or captions. Each step lists its feature task IDs from `BUILD_PLAN.md`.

- `[phone]` = needs the real phone (OnePlus 10T, release APK installed with adb). `[any]` = works on any device or the emulator (Demo Lab, Try API, Report, Lessons, Family, dashboard).
- **3-minute cut:** steps 1, 2, 3, 4, 8, 11, 13, 14.
- Drafting-time status: all feature tasks are installed except device runs (T2.8, T6.x) and the Chhattisgarhi sign-off (T3.6), which are blocked on people and phones.

## Pre-flight

0. Install the build. [any] Debug builds have Demo mode on. [phone] Release APK: Help -> Settings -> tap the version row 7 times, or flip the Demo mode switch; the "Demo Lab" tile then appears in Help. (T8.1, T3.11)
   - [phone] Setup: accessibility on (allow restricted settings), battery Unrestricted, notification permission, notification access, model download to READY, "Show test bubble". (T1.7, T2.3, T1.15; handoff §6)
   - Pre-load on the phone: a Hindi digital-arrest recording file, and 2 test messages.
   - Without the model (emulator), the lab runs rules-only: say so; Gemma lines show as not available.

## Run the Demo Lab (T8.1)

Help -> Demo Lab. Each of the 11 scenarios is synthetic and runs through the REAL pipeline (`Pipeline.kt` shared with `TextApi`: RuleScorer, Gemma or rules-only, Fusion including `raiseForContext`, call-side context rules) on an isolated graph and log, so the real history is untouched. A 6-stage timeline per step shows the event, the Known context lines sent to Gemma, masked rule hits, the Gemma output, fusion with `raisedBy`, and the [DEMO] alert, with PASS or FAIL against the scripted expectation.

1. Open Demo Lab, pick a scenario, press run, read the timeline top to bottom. (T8.1)
2. Toggle cold start vs warm graph where offered to show "No record since ScamShield was installed". (T8.1, T5.1)
3. Run all scenarios once before the demo and confirm every stage is PASS; any FAIL means do not demo that scenario. (T8.1)

Scenarios and what each proves:

| # | Scenario | Shows | Tasks |
|---|---|---|---|
| a | Mistaken transfer A, fake credit SMS | No real credit alert, so the "send it back" call is flagged | T5.2, T5.3, T8.1 |
| b | Mistaken transfer B, real credit | Return-via-bank warning, not a direct refund | T5.2, T5.3, T8.1 |
| c | Debit scare, then a "bank" call | Debit claim with no matching event, then a non-1600 caller asking for the OTP | T5.3, T8.1 |
| d | Bank call, 10-digit vs 1600 | Banks call from 1600 series | T5.2, T8.1 |
| e | Delivery, genuine vs customs | Out-for-delivery event suppresses; "parcel held, pay" flags | T5.2, T8.1 |
| f | Digital arrest | Recording pipeline, rising call risk | T2.4, T8.1 |
| g | KYC link | Claim-vs-context: non-DLT sender, link not `.bank.in` | T5.1, T8.1 |
| h | Genuine OTP | Stays SAFE (no false alarm, triggers masked) | T1.5, T8.1 |
| i | Fake QR | PAY framing and name mismatch | T4.1, T4.2, T8.1 |
| j | Family code | Same rotating code on both phones | T5.6, T5.7, T8.1 |

## Script

1. **Problem (20 s)** [any]. First-time users lose money through calls, SMS, WhatsApp, QR and fake apps. Chhattisgarh lost 107 cr in 18 months and recovered 3.69 cr. Truecaller and spam labels judge the number; we judge what is said (FINAL_PLAN §1). (Setup steps: T1.7 notification permission, T2.3 notification access)

2. **Demo Lab opener: mistaken transfer A then B (60 s)** [any]. Run scenarios a and b and read the timeline. A: "No money arrived. This SMS is not from your bank." B: "This money may be stolen. Returning it yourself can get your account frozen..." Wording is `[VERIFY]` RBI/NPCI. (T5.2, T5.3, T8.1; FINAL_PLAN §5)

3. **Paste a Hinglish OTP scam, in airplane mode (30 s)** [any]. Airplane mode on, paste into Try API. Expect SCAM, scam-type chip, reason "asks you to share OTP", masked triggers (no digits), engine `gemma+rules`. Gemma decided, rules only raised, 0.7/0.3 (FINAL_PLAN §2). Then paste a genuine bank OTP notice: SAFE (Demo Lab scenario h). (T1.2, T1.5, T1.15, T2.1)

4. **Live Caption on a digital-arrest call (60 s)** [phone]. Play the call recording with Live Caption on: bubble goes yellow then red with the Hindi line and a 1930 button; a heads-up notification carries a Report action. Call-side bank and delivery rules also run on captions now. (existing CaptionAccessibilityService; T1.6, T1.7, T8.1)
   - Fallback [any]: Demo Lab scenario f (digital arrest), or paste the script statement by statement into Try API. OnePlus 10T Live Caption covers media only, not calls (FINAL_PLAN §2).

5. **In-call signal (30 s)** [phone]. During a call open PhonePe or AnyDesk: yellow "Is the caller asking you to pay?". (built-in InCallSignals, alert via T1.7)
   - Fallback: narrate, or show the unit-tested rule.

6. **Message guard: SMS and WhatsApp (30 s)** [phone]. Send a scam SMS or WhatsApp text: heads-up notification without opening the app. No `READ_SMS`. (T2.2, T2.3, T1.6, T1.7)
   - Fallback [any]: Try API paste, or Demo Lab scenario g (KYC link).

7. **Bank call, delivery, claim-vs-context on the phone (30 s)** [phone]. Real notification and caption events build the one shared graph. Bank call from a 10-digit number is flagged; "out for delivery" then an unknown caller is quiet; unmatched bill claims flag. (T5.1, T5.2, T5.3; FINAL_PLAN §5)
   - Fallback [any]: Demo Lab scenarios d, e, g. Not device-verified.

8. **Recorded call (45 s)** [phone]. Help -> Recording, pick the pre-recorded Hindi audio: progress, per-statement timeline, overall risk, trigger phrases, Report button; offline Vosk, nothing stored. (T2.4, T2.5, T2.6, T2.7)
   - Fallback: Demo Lab scenario f runs the same `RecordingPipeline` with scripted statements [any]. The audio file is the intended input, not a live call. If STT fails, paste the transcript into Try API. Device run T2.8 is blocked on the phone.

9. **Fake QR (30 s)** [any]. Try API: paste `upi://pay?pa=a@bank&pn=Priya Stores` and the name you were told: "You will PAY Rs X to <name>", "Name does not match this UPI ID", FAKE_QR event logged without link or VPA. [phone] "Scan QR" button (ML Kit, no camera permission). (T4.1, T4.2, T4.3; Demo Lab i)

10. **APK guard (20 s)** [phone]. Share or receive a risky `.apk`: heads-up warning listing risky permissions (SMS + internet + contacts is HIGH). A chat message naming an `.apk` gets "don't install apps sent in chats". (T5.8)
    - Fallback: narrate with `ApkRiskTest`; cut if no phone.

11. **Report and golden hour (45 s)** [any]. Alert's Report action or the persistent "1930" entry: "I lost money" (1930 + cybercrime.gov.in) and "not yet" (Chakshu + 1930); checklist pre-filled from the verdict log. "I got scammed": 60-minute timer, case card, evidence ZIP via the share sheet. 1930 opens the dialer, never auto-calls. (T3.1, T3.2, T3.11, T5.4, T5.5)

12. **Lessons, quiz, literacy score (30 s)** [any]. Learn tab, Hindi, switch to Chhattisgarhi, take a quiz, watch the score move. Chhattisgarhi text is unsigned drafts: say so. (T3.3, T3.4, T3.5, T3.11; sign-off T3.6 blocked)

13. **Family code (20 s)** [any]. Help -> Family, pair with the base32 secret; both phones show the same rotating 6-digit code; a voice clone cannot know it. Offline, no relay. (T5.6, T5.7; Demo Lab j)

14. **Dashboard and export (30 s)** [any]. Serve the repo root over http, open `dashboard/index.html`: district ranking, weekly scam-type trend, accuracy panel, labelled synthetic sample. In Settings pick a district and "Export anonymised counts"; drop the file in; only `{district, scam_type, date}` is accepted. (T3.7, T3.8, T3.9, T3.10)

15. **Accuracy slide (20 s)** [any]. Quote the block below exactly; the fine-tune is future work. (T1.9, T1.10, T1.13, T1.14, T3.9 panel)

16. **Privacy close (10 s)** [any]. "We never record your call. We read captions Android already shows you, on the device. Nothing leaves the phone except a counts file you choose to export." (T1.4, T3.8, T3.10; FINAL_PLAN §2, §6)

## Accuracy line (verbatim from `docs/accuracy.md`, re-read at drafting)

> Data: synthetic held-out by template (0 real, 26 synthetic rows). Headline: synthetic.
> Positive class: SCAM or SUSPICIOUS; UNPARSED counts as negative.
>
> | System | Slice | Precision | Recall | FPR | Type macro-F1 | n | Unparsed |
> |---|---|---|---|---|---|---|---|
> | rules | overall | 100.0% | 47.8% | 0.0% | 0.31 | 26 | 0 |
> | base_gemma | overall | 100.0% | 91.3% | 0.0% | 0.39 | 26 | 0 |
> | finetuned_gemma | - | future work (not planned for this prototype): no --finetuned path given | | | | | |

Say plainly: synthetic data, 0 real rows, not real-world accuracy; only 3 of the 26 rows are negatives. The Demo Lab PASS/FAIL checks scripted scenarios and is not an accuracy number. Re-copy this block if `docs/accuracy.md` changes.

## Likely questions

**Why not Truecaller or Google?** They rate the number, so a rotated or unknown number slips through, they do not speak Chhattisgarhi, and they stop once the money is gone. ScamShield judges what is being said, warns during the call or message, then hands you to 1930, cybercrime.gov.in and Chakshu with the evidence ready, all offline on the phone. (FINAL_PLAN §1; T1.15, T3.2, T5.5)

**How do you hear the call?** Live: Android Live Caption already turns speech into text on screen and our accessibility service reads that text; we do not record. Recorded call: you pick a file and on-device Vosk converts it to text; no audio is stored or uploaded. Limit: on OnePlus 10T Live Caption covers media only, and Pixel call captions are `[verify]` (FINAL_PLAN §2). (T2.4-T2.7)

**Is the model trained by you?** Not yet. The prototype ships base Gemma 3 1B plus rules. The LoRA scripts exist but were never run (no GPU box). (FINAL_PLAN §3A; T1.11, T1.14)

**What if the model is missing?** Rules-only mode keeps working with a rule-derived scam type; the Demo Lab runs this way on the emulator. (FINAL_PLAN §2; T1.5, T8.1)

**Is the Demo Lab real or faked?** The inputs are scripted and synthetic; every decision step is the production `Pipeline` on an isolated graph and log. (T8.1)
