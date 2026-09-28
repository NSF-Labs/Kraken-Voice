# Trial build 1.0.18+18 — S24 summary fix

Replaces the S24's GPU-specific Gemma 4 E2B export, which produced corrupted
summary text, with the pinned portable Gemma 4 E2B export on LiteRT-LM 0.17.1
GPU/OpenCL. The quality guard remains enabled. S26 Hexagon NPU selection and
the 1.0.17 trial/background-processing features remain unchanged.

- Profile: `gemma4-litert171-opencl-adreno750`.
- Local model: `gemma4-e2b-portable-gpu.litertlm`, 2,588,147,712 bytes.
- Source: `litert-community/gemma-4-E2B-it-litert-lm`, revision
  `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1`, `gemma-4-E2B-it.litertlm`.
- Model SHA-256: `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c`.
- Distinct filename and compilation cache prevent reusing the failed export.
  The old model remains on disk but is not selected. Other installations must
  download the new model through the existing model-download flow.
- Native load checks the pinned size and checksum. Dart rejects the old native
  GPU profile, and artifact verification checks matching profile/build identities.

## Installed and verified

Installed with `adb install -r` on the attached S24 Ultra SM-S928U, preserving
recordings and app data. The new model was staged and checksum-verified in the
app's existing model directory. No S26 installation was performed in this task.

APK: `build/app/outputs/flutter-apk/krak-en-voice-1.0.18-trial.apk`

APK SHA-256: `3e762274807037a8a122d34591ccd1713cd3653ff0d191e22e252d41bd3a0ef6`.
The installed APK matches this hash; Android reports version 1.0.18 / code 18.

## Validation

- 38 targeted model-selection, summary, background-recovery, trial-export and
  recording-safety regression tests passed.
- Static analysis: zero errors/warnings; 24 informational lint findings.
- Artifact verifier passed for both model profiles and ARM64 runtime packaging.
- Regenerated the previously failing 2:13 test recording in the actual app.
  Native logs confirm the new file and OpenCL initialization. Condensation
  completed with 686 input / 137 output tokens; final generation used
  273 input / 222 output tokens and passed the app's quality checks.
- App activity stopped at 16:27:23; final summary completed and was saved at
  16:27:31 on September 26, 2026 (America/New_York).
- Reopened and inspected the readable result, then stopped the app process and
  reopened it. The corrected summary remained available in the new process.

Technical evidence and result flags:
[`spike/hardware_probe/s24_fix_20260926`](../spike/hardware_probe/s24_fix_20260926/).
Recording-derived summary text was inspected on-device and not exported into
the repository. Earlier controlled comparison:
[S24 diagnosis](S24_QUALITY_DIAGNOSIS_2026-09-26.md).

This fixes the reproduced S24 corruption. Broad long-recording, multilingual,
and additional-device acceptance remain separate from this targeted regression.
