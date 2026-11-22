# ScamShield — live call scam warnings (offline)

Live Caption text → accessibility service → statement segmenter → **Text API** (rules + on-device Gemma 3 1B)
→ floating bubble: **"This statement is SCAM · 87%"**. No audio is recorded; nothing leaves the phone.

## Run
```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"   # Git Bash on this PC
flutter run                                  # phone connected with USB debugging
flutter build apk --release --split-per-abi  # smaller APKs for sharing (arm64-v8a for most phones)
```

## Load the model (≈550 MB, not bundled in the APK)
1. On Hugging Face, accept the Gemma license and download the Gemma 3 1B IT **int4 `.task`** file (litert-community).
2. Either use **Setup → Import .task file**, or run:
   `adb push gemma3-1b-it-int4.task /sdcard/Android/data/com.hackasol.scamshield/files/models/`, then tap **Reload model**.
Without the model the app runs in **rules-only** mode (the `engine` field shows which one ran).

## First test on a phone
1. Setup → enable **ScamShield call protection** in Accessibility → **Show test bubble**.
2. **Try API** tab → tap the sample chips → check labels and latency.
3. Turn on Live Caption → play a scam-call recording **on the phone** (Live Caption captions media too) → watch the bubble and the **Live** tab.
4. If nothing shows up: Settings → **Discovery mode** → in the Live tab, find the package whose text is the caption → add it under *Caption source packages*. If the caption text never appears there, OCR fallback (on by default) reads it during calls.
5. Real call on speaker: have a teammate read a scam script.

Optional, demo phone only: `adb shell pm grant com.hackasol.scamshield android.permission.WRITE_SECURE_SETTINGS`
lets the app switch Live Caption on directly (`adb shell settings list secure | grep -i caption` to check the key).

## Code map
| Path | What |
|---|---|
| `android/.../core/` | Pure Kotlin: `RuleScorer`, `StatementSegmenter`, `LlmOutputParser`, `CallRiskTracker`, models (unit-tested) |
| `GemmaClassifier.kt` | MediaPipe LLM Inference + few-shot prompt |
| `TextApi.kt` | `classify()` = rules + Gemma fusion; conflated caption queue |
| `CaptionAccessibilityService.kt` | The live pipeline, call detection, OCR fallback, auto-caption |
| `CaptionExtractor.kt` / `CaptionToggler.kt` / `OverlayController.kt` | Node-tree + OCR reading / Live Caption toggle / bubble |
| `MainActivity.kt` | Flutter channels `scamshield/api` + `scamshield/events` |
| `lib/` | Flutter UI: Setup, Try API, Live feed, Settings |

Tests: `cd android && ./gradlew :app:testDebugUnitTest` (18 Kotlin tests) and `flutter test` (3 Dart tests).
