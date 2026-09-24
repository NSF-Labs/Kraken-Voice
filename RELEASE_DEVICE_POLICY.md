# NPU release policy — 1.0.14-npu-sm8850+14

This build replaces LiteRT-LM/GPU with **Gemma 4 E2B Q4_0 GGUF on llama.cpp Hexagon HTP0**, in-process through JNI. The NPU executes accelerated operations; CPU host work and unsupported individual operations remain. It is not an exclusively NPU execution claim.

- Model: `h2loop-ai/gemma-4-e2b-hexagon`, revision `1bb2044c313769541558f2c27fa67561894d0f26`, `gemma4-e2b-w4.gguf`, 2,620,370,976 bytes.
- SHA-256: `e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889` (checked before each fresh model load).
- Runtime: upstream llama.cpp `0ef6e55`, publisher's pinned ARM64 binaries. Header API matches that commit. `runtime-artifacts.json` pins each packaged library; build verifies hashes.
- Profile: `gemma4-hexagon-v81`, HTP0 required, 36 layers requested for acceleration, 4,096-token context, f16 KV, flash attention, thinking disabled. Missing NPU produces an error, never CPU-only fallback.
- Build identity: `1.0.14-npu-sm8850`, Android version code **14**, visible in Settings. Development package `org.krak_en.voice.dev`; production `org.krak_en.voice`.

## Eligibility

The native runtime uses an explicit model-and-chipset allowlist, with Samsung
manufacturer, Android 12+ and ARM64 required:

| AI build | Only enabled phone model | Required chipset |
|---|---|---|
| Default Gemma 4 Hexagon NPU | Galaxy S26 Ultra **SM-S948U** | SM8850 |
| Separate Gemma 4 LiteRT GPU evaluation | Galaxy S24 Ultra **SM-S928U** | SM8650 |

Chipset suffix variants are accepted only with the exact phone model above.
Other models, including SM-A236V (Galaxy A23), regional/carrier variants,
unknown devices and future chipsets, are explicitly excluded. A matching chipset
alone is insufficient. Add a model only after validating its matching runtime
and model weights. The startup guard runs before vault/model initialization;
native load and generation calls also enforce eligibility. No CPU fallback is
enabled. Existing installed APKs require rebuilding/updating to receive this
stricter model gate. The GPU build remains an evaluation build with the quality
limitations recorded in `S24_GPU_TEST_RESULTS.md`.

Before publishing, use **Google Play Console → Device catalog** to exclude every unvalidated device/variant and inspect the resulting supported-device list. The app guard does **not** hide the store listing. Manifest features cannot express this exact SoC/firmware allowlist. No Play Console changes have been made by this code update.

Official catalog guidance: https://support.google.com/googleplay/android-developer/answer/7353455

## Model selection strategy

A single app can detect SoC, RAM and available backends and select a model from an explicitly validated profile registry. A phone cannot infer that an arbitrary compiled model will work from an NPU label or a higher chip number. This release deliberately has one enabled profile. To support SM8750 or another NPU/GPU/CPU profile, first validate its runtime, model, correctness, memory and sustained performance, then add that profile and its eligible Play devices. CPU-only fallback remains disabled per the release performance requirement.

## Reproduce

1. `python3 scripts/prepare_hexagon_runtime.py` (downloads only the seven pinned runtime libraries, about 10 MB).
2. `flutter build apk --profile --flavor dev --target-platform android-arm64` for development installation; production builds require the release signing key.
3. Run `python3 scripts/verify_npu_apk.py build/app/outputs/flutter-apk/app-dev-profile.apk` before installing. It rejects stale Flutter/native profile mismatches and unsupported ABIs.
4. Download the pinned GGUF through the app, or stage an app-owned copy for testing. Previous `.litertlm` files are preserved but no longer selected.

Native initialization and decoding are serialized; unload waits for cancellation. Each request clears its KV state. Prompts are counted with the actual tokenizer. Final summaries reserve 2,048 output tokens and automatically continue in the same KV state beyond that soft limit while space remains in the 4,096-token total context. At the hard context limit, generation reports an error and retains the final-response draft separately in the encrypted vault; completed summaries are never replaced by truncated responses. This does not resume generation across an app restart or extend the validated context window. Long meeting summaries are condensed in ordered sections before the final summary, with no silent input truncation. This needs longer meeting accuracy/thermal acceptance testing before public release.

Redistribution notices: `android/app/src/main/cpp/LLAMA-LICENSE.txt` includes the publisher's MIT and Qualcomm DSP runtime notice. Model retains Gemma terms. Retain notices when packaging; confirm redistribution requirements for the model/DSP binaries as part of release preparation.
