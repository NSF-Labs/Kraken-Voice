# S24 GPU evaluation — September 24, 2026

Build **1.0.15-gpu-sm8650+15**, launcher **Krak-EN Voice GPU**,
development package `org.krak_en.voice.dev`. This is a separate SM8650 GPU
configuration; the default SM8850 S26 NPU configuration remains build 14.
There is no CPU inference fallback or automatic backend selection.
The source now restricts GPU eligibility to Samsung **SM-S928U + SM8650**,
Android 12+ and ARM64; other S24 variants require separate validation.
This tightened gate requires a new APK build; the earlier installed build 15
used a chipset-only gate.

## Runtime and model

- Attached Galaxy S24 Ultra SM-S928U: SM8650, Adreno750v2.
- LiteRT-LM Android **0.17.1**, explicit `Backend.GPU()`, OpenCL.
- Gemma 4 E2B dedicated `gemma-4-E2B-it-gpu.litertlm`, stored as
  `gemma4-e2b-gpu.litertlm`; 2,008,432,640 bytes.
- Source revision `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1` in
  `litert-community/gemma-4-E2B-it-litert-lm`.
- SHA-256 `a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5`;
  verified before native model initialization.
- 4,096 context budget; thinking and speculative decoding disabled for baseline.
- GPU builds use Kotlin 2.4.20 for runtime compatibility; NPU builds retain 2.2.20.

## Device evidence

The non-destructive integration harness exercised synthetic content only.
Native logs identify `LlmGpuArtisanExecutor::Create`, `backend: GPU_ARTISAN`
and `READY runtime=LiteRT-LM-0.17.1 backend=GPU soc=SM8650 ... no_cpu_fallback`.
Process mappings confirmed `libOpenCL.so` and `libOpenCL_adreno.so` from the
vendor driver. This establishes inference GPU use independently of UI rendering.

| Check | Result |
|---|---|
| PDF/DOCX extraction and factual summaries | Pass |
| Corrected facts, approved budget/date/owner | Pass, 960 ms |
| Continue beyond a one-token soft output limit | Pass |
| Explicit output cap reports truncation | Pass |
| Cancel streaming and generate next response | Pass |
| Unload, reload, generate | Pass |
| Flutter regression suite, default and GPU profiles | 62 passed each |
| Normal profile APK startup and native GPU generation | Pass, installed version 15 |
| Separate normal GPU and default NPU APK builds | Pass, both verified; NPU not installed |

The normal chat UI smoke test completed on GPU at 36.7 tokens/second, but
declined an unrelated arithmetic question under the existing recording-grounded
prompt and emitted stray non-English characters. Direct arithmetic and document
fixtures passed in the harness. This chat-quality discrepancy remains open;
the GPU migration is not a claim of release-ready answer quality. Static analysis
reports the same 12 pre-existing informational findings, with no new findings.

Short-response decode measured approximately **34–38 tokens/second**. This is
not a sustained long-recording benchmark or broad release qualification.
Long documents, thermal behavior and repeated long sessions still need a release
soak test on this GPU profile. Existing S26 NPU results do not qualify the S24.

The Kotlin API exposes no tokenizer. This build conservatively budgets UTF-8
bytes plus chat-template allowance, which can cause more document condensation
than exact token counting. Automatic continuation uses the remaining context
within the same generation; it does not provide unlimited output. Existing draft
preservation handles failures or exhausted context.

## Build and install

Run `sh scripts/build_s24_gpu.sh`. It cleans stale Flutter outputs, builds the
normal app target with `KRAKEN_S24_GPU=true` and explicit version 15, then checks
the APK's Dart/native profile, ARM64 ABI and runtime packaging. Do not omit the
define or version flags when building manually. GPU APKs exclude the Hexagon
runtime; default NPU APKs do not depend on LiteRT-LM.

Install `build/app/outputs/flutter-apk/app-dev-profile.apk` using `adb install -r`
on the S24. Never uninstall or clear storage to switch this development package.
The model download is separate from the APK; the previous model file may remain
on disk but is not selected by build 15. The older production package is separate.
The installed GPU artifact is also retained locally as
`build/app/outputs/flutter-apk/app-s24-gpu-profile.apk` after the separate NPU
build check. Build output directories are disposable and removed by `flutter clean`.
