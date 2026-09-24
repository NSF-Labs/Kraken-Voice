# Attached-device runtime audit — September 24, 2026

| Device/package | Installed build at audit | Model/runtime/backend | Evidence |
|---|---|---|---|
| S24 Ultra SM-S928U / development | 1.0.9 (9) | Gemma 4 E2B / LiteRT-LM **0.15.0** / **CPU** | APK Dart model URL; native GNU build ID matches cached official 0.15.0 AAR; app DEX constructs Backend.CPU |
| S24 Ultra / production | 1.0.9 (9) | Gemma 4 E2B / legacy LiteRT-LM / **CPU** | APK AOT model URL; app DEX constructs Backend.CPU; exact runtime version not established |
| S26 Ultra SM-S948U / development | 1.0.13 (13), updated to 1.0.14 (14) | Gemma 4 E2B Q4_0 GGUF / llama.cpp 0ef6e55 / Hexagon HTP0 v81 | Current profile, pinned runtime, JNI initialization and previous physical checks |

The S26 also retains an older production-package build 1.0.9. Its presence and
old `.litertlm` files do not describe the active development NPU build. The S24
packages were inspected read-only; neither was replaced or launched for this audit.

S24 development native GNU build ID: `830e4de3389c7d7cf9d59007b309456e`, matching
`litertlm-android-0.15.0.aar`; 0.17.1 has ID `f0a0ae939564ad3aca8e13c7ff440ecc`.
S24 production ID: `c2c27170ba409dbd0bc01820fa738580` (unmatched in local cache).
Both installed APKs select the Gemma 4 E2B LiteRT model URL, not Gemma 3.

Hardware queried directly from `ro.soc.model` and the KGSL `gpu_model` sysfs node:
S24 = **SM8650 / Adreno750v2**; S26 = **SM8850 / Adreno840v2**. The Adreno 750
part of the proposed stack applies to the S24, not the attached S26.

## Proposed GPU path (before S24 migration)

Google's [v0.17.1 release](https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.17.1)
is marked latest and dated September 16. Its listed fix concerns tool-call integer
types; that release note alone is not evidence that a particular Samsung GPU issue
has been fixed. [v0.17.0](https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.17.0)
lists local-attention memory/context improvements.

Google's [Android guide](https://developers.google.com/edge/litert-lm/android) supports
`Backend.GPU()` and explicitly requires OpenCL native-library declarations. Thus
Gemma 4 E2B → LiteRT-LM 0.17.1 → Adreno GPU is a reasonable separate evaluation
configuration, not the currently installed runtime or an already qualified
production configuration. It requires a `.litertlm` model rather than the current
NPU GGUF, backend verification, correctness tests, sustained timings and memory tests
on each target phone. The current SM8850 NPU release gate remains unchanged.

Update: the S24 development package has now been migrated to the isolated GPU
build 15. The earlier installed-runtime findings above describe the baseline.
See [S24 GPU validation](S24_GPU_TEST_RESULTS.md) for the new runtime and evidence.
