# Unified Android build 1.0.16+16

One APK/AAB includes LiteRT-LM 0.17.1 GPU and llama.cpp Hexagon runtimes.
The native factory chooses one backend before Flutter starts. Dart validates
that selection and uses only its pinned model filename, size and download URL.
A stale/mismatched profile fails closed. Backend selection cannot change during
the process, and load failure does not fall back to CPU or another model.

| Samsung model | Chipset | Selected backend | Validation |
|---|---|---|---|
| S24 Ultra SM-S928U | SM8650 | LiteRT-LM / Adreno GPU | Unified device tests passed |
| S25 SM-S931U | SM8750 | Hexagon v79 NPU | Upstream support; physical app test pending |
| S25+ SM-S936U | SM8750 | Hexagon v79 NPU | Upstream support; physical app test pending |
| S25 Ultra SM-S938U | SM8750 | Hexagon v79 NPU | Upstream support; physical app test pending |
| S26 Ultra SM-S948U | SM8850 | Hexagon v81 NPU | Unified device tests passed |

Android 12+, Samsung manufacturer and ARM64 are required. Exact models and
matching chipsets are checked together. Other variants, FE/Exynos models, the
A23 and unknown/future chips remain excluded. S25 entries are enabled for this
testing build; do not include them in a public rollout before acceptance testing.
The app gate does not hide a Play listing: configure the Play device catalog
separately, initially excluding unvalidated variants.

## Weights and runtime

The GPU and NPU model revisions, sizes and checksums are unchanged from builds
15 and 14 respectively. Existing matching downloads are reused. The app does
not download both AI models. Settings displays the selected backend.

The NPU package now also contains `libggml-htp-v79.so`, from the same pinned
upstream revision `1bb2044c313769541558f2c27fa67561894d0f26`:
730,248 bytes, SHA-256
`6eb04178e0c2109be42c2c822d7dd2b4283b9c8bf933decb2e89bdb6f2a02a0b`.
The upstream Hexagon backend selects the DSP library for the detected architecture.
All eight pinned libraries are verified before each build. Kotlin 2.4.20 is now
used for the unified LiteRT-LM dependency. CPU host work/unsupported individual
NPU operations remain; there is no CPU-only inference mode.

## Validation — September 24, 2026

- Flutter regression suite: 65 passed, including dynamic profile selection,
  unsupported/stale metadata rejection, and selected model URL/size checks.
- Native hardware routing tests passed, including S25 v79, wrong chipset,
  unsupported manufacturer/ABI/Android version and A23 rejection.
- Identical synthetic integration APK installed with `adb install -r` on S24
  and S26. Three tests passed on each: PDF/DOCX extraction and factual summary,
  backend/model identity, arithmetic correctness, cancellation and reload.
  S24 logged GPU; S26 logged HTP0 NPU. No user vault records were opened by tests.
- S24 harness: 26 seconds; S26 harness: 16 seconds. These are suite durations,
  not model throughput benchmarks.
- Normal unified profile APK built and passed the combined artifact verifier;
  installed on both phones with version 1.0.16/code 16, preserving app data.
  Static analysis: 12 pre-existing informational findings, no new findings.

S25 device testing, sustained long-session tests and the S24 chat-quality issue
recorded in `S24_GPU_TEST_RESULTS.md` remain release acceptance items. This
implementation does not claim those issues have been resolved.

## Build

`sh scripts/build_unified.sh` creates and verifies the normal development profile
APK. Install with `adb install -r` to preserve data; never clear storage or use
the destructive Flutter integration runner on a populated phone.

`sh scripts/build_unified.sh bundle` builds the production release AAB with the
configured upload key. This replaces the former compile-time GPU switch.
The old build/verifier script names forward to the unified workflow.
The artifact verifier checks both runtimes, ARM64, model identities and build 16
in the Dart AOT/native code; it is not a substitute for Play's upload validation.

Target Play track: Closed testing — Alpha. Last user-confirmed Play version:
1.0.9 (code 9). This build uses 1.0.16 (code 16).

## Upload keystore

A keystore is a private file containing the key that signs your app upload.
Google Play checks that signature against the registered upload certificate.
The project currently references the previous Windows path:
`C:\Users\apete\kraken-voice-release.jks`.
That file is not present at the configured location on this Mac. The only key
found in the common local locations was `~/.android/debug.keystore`, which is
for development and must not replace the registered upload key.

Retrieve the existing `kraken-voice-release.jks` from the old computer or its
backup. A suggested destination is `~/.android/kraken-voice-release.jks`; this is
a proposed location, not a file currently found. Configure its absolute Mac
path in ignored `android/key.properties`, preserving the existing alias and
passwords. Do not commit the key or paste passwords into chat. If the upload key
is lost, use Play Console's upload-key reset process where available; simply
generating a different key will not make it valid for existing app updates.

No signed AAB or Play upload has been completed without that key.
