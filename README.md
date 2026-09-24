# Krak-EN Voice

For internal real-device/emulator testing, see
[Hardware Qualification](HARDWARE_QUALIFICATION.md). Build the separate test app
with `sh scripts/build_qualification.sh`; its ADB runner also works with devices
connected through Android Device Streaming.

Current build: **1.0.16+16**, one Android app with automatic GPU/NPU model selection.
See [unified build and validation](UNIFIED_RELEASE.md) for supported devices,
remaining release checks, build commands and signing-key recovery.

- S24 Ultra SM-S928U / SM8650: Gemma 4 E2B, LiteRT-LM 0.17.1, Adreno GPU.
- S25 SM-S931U, S25+ SM-S936U, S25 Ultra SM-S938U / SM8750: same NPU
  GGUF as S26, Hexagon v79 runtime. **Physical-device validation pending.**
- S26 Ultra SM-S948U / SM8850: Gemma 4 E2B GGUF, Hexagon v81 NPU.

The app downloads only the selected AI model. CPU-only inference fallback is
not enabled. Other model/chipset combinations remain excluded.
Run `sh scripts/build_unified.sh` for the development profile APK, or
`sh scripts/build_unified.sh bundle` with the existing upload key configured
for the production AAB. The model weights download separately.

Summaries preserve interrupted drafts and show estimated progress. Files supports
PDF and Word `.docx` imports; see [document import](DOCUMENT_IMPORT.md).
Historical device findings are in [S24 GPU results](S24_GPU_TEST_RESULTS.md),
[S26 NPU results](S26_RELEASE_TEST_RESULTS.md) and the
[runtime audit](RUNTIME_DEVICE_AUDIT.md).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
