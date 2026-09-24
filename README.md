# Krak-EN Voice

Default Android build: **1.0.14-npu-sm8850+14** — Gemma 4 E2B on Hexagon NPU.
The separate S24 GPU build is **1.0.15-gpu-sm8650+15**; see
[S24 GPU setup and validation](S24_GPU_TEST_RESULTS.md). Build it with
`sh scripts/build_s24_gpu.sh` (no Hexagon runtime preparation required).
Summaries now allow 2,048 output tokens, continue within the available model context,
and preserve incomplete drafts if interrupted.
Summary generation shows estimated progress, section counts, live output activity and elapsed time.
See the [attached-device runtime audit](RUNTIME_DEVICE_AUDIT.md) for S24/S26 backend verification.
PDF and Word `.docx` imports are available in Files; see [document import](DOCUMENT_IMPORT.md).
Read [release eligibility and build instructions](RELEASE_DEVICE_POLICY.md)
and [S26 validation results](S26_RELEASE_TEST_RESULTS.md) before distribution.

Before building Android, run `python3 scripts/prepare_hexagon_runtime.py` to
fetch the checksum-pinned runtime libraries. Model weights download separately
inside the app. Only validated SM8850 phones are enabled in this build.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
