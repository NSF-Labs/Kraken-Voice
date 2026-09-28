# Trial build 1.0.17+17

S24 follow-up: [controlled quality diagnosis](S24_QUALITY_DIAGNOSIS_2026-09-26.md)
reproduces corruption in the current GPU-specific Gemma 4 export with ample
available RAM. The portable Gemma 4 GPU export passed the comparison, but has
not yet been integrated into this trial APK.

The trial records for up to 20 minutes per recording. Custom export branding and export content controls require the existing non-consumable `krak_en_voice_full_unlock` product. The intended US price is $4.95 once, without a subscription. The app displays the localized Play product price when available and $4.95 otherwise. Development/profile builds no longer automatically receive paid access; the development override requires explicit `--dart-define=KRAKEN_DEV=true` in a non-release build.

Full access removes the recording-duration cap (including the former five-hour cap), unlocks branding/content customization, and bypasses the historical trial audio storage cap. User-selected audio retention policies still apply. Speaker diarization remains disabled for all tiers; its export speaker-name toggle was removed. Trial exports ignore previously saved paid customization. Paid PDF/DOCX exports apply section and timestamp settings.

## Background processing

- `KrakenProcessingService` runs a visible local-file-processing notification and partial wake lock for queued transcription/summary work. The process retains its Flutter engine and inference bridge independently of the activity.
- A shared queue prevents transcription, automatic tags, recording summaries, and document summaries from loading competing model workloads. Each summary request is committed to the encrypted vault before processing; completed results are saved independently of the screen.
- After process death, opening the vault recovers interrupted summary requests and existing transcription jobs. Summary crash recovery is bounded to three attempts; explicit retry resets the request. Partial final-summary drafts remain separate from completed summaries.
- Recording duration is enforced in the native microphone service using monotonic elapsed time, including when the dashboard is absent. Paused time does not count. Native stop events save the recording through an app-owned callback.
- An explicit Android force-stop ends execution; requests recover when the user opens the app again. OS restrictions still apply, including the [Android dataSync foreground-service time budget](https://developer.android.com/develop/background-work/services/fgs/timeout). Local file processing is a documented [dataSync use case](https://developer.android.com/develop/background-work/services/fgs/service-types#data-sync).

## Device-driven fixes

The S24 completed the 133-second audio fixture's transcription in the background in approximately 39 seconds, with the same app PID. Its summary initially hit a GPU context/output limit. Summary prompts now use explicit word budgets, and oversized intermediate sections are split and retried without dropping source material. Duplicate normalized topic tags are deduplicated before insertion.

A subsequent S24 run completed and persisted output but produced mixed-script, unreliable text. The final S24 restart-recovery run reproduced the corruption on all three attempts. A new quality guard rejected it and repetitive phrase loops; recording summary generation reloads the model and retries up to three times, then shows a recoverable failure instead of publishing a new invalid summary. This is an independent model-quality limitation, not evidence that Home navigation stopped the worker. The runtime and Gemma 4 model routing have not been changed.

## Verification

- 77 Flutter tests passed, including background serialization/foreground failure, summary checkpointing, section-limit recovery, mixed-script/repetition rejection, actual trial/paid DOCX output, paid storage-cap bypass, and recording preservation.
- Clean profile APK build and ARM64 GPU/NPU packaging/identity verifier passed.
- S24: background transcription completed; background summary request/draft persistence exercised; deliberate process stop during an active summary followed by reopening automatically resumed the saved request under a new PID, without tapping Generate again.
- S26: native recording stopped automatically with the app in the background and the display asleep; reopening showed the saved test recording at exactly **20:00**. The recording-service code was unchanged between that test APK and the final quality-guard build. On the final APK, the NPU generated the synthetic DOCX summary entirely after pressing Home; reopening showed the saved summary with the correct $42,750 amount, Maya as owner, and October 16 deadline. A subsequent force-stop/reopen still listed the document as “Summary saved.”

An incremental build produced stale Flutter AOT content during this work. Use `scripts/build_unified.sh` (clean build); the artifact verifier now checks trial/background code markers in addition to the shared Dart/native build identity.

## Distribution and billing

This APK uses `org.krak_en.voice.dev` so it upgrades the attached development installations without clearing data. It is a sideload testing artifact, not a Play publication. Google Play controls the actual charge: configure the matching product's US base price as $4.95 in Play Console, distribute the production package through a Play test track, and verify purchase/restore with a license tester before public release. No real payment or Play product-price change was performed in this session.

Final trial APK SHA-256: `c6450a326bb6e0d8132d059f0a81372e2e903a01261957c6929931d725c30e22`.

Both attached devices were verified byte-for-byte against the final APK SHA-256 above. Static analysis reported no errors or warnings (24 informational lint findings). The final S24 model-quality failure remains unresolved; this APK should be treated as a trial/testing build, not a broadly qualified production release.
