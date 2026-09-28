# Broader hardware qualification — September 24, 2026

## Model policy — September 25, 2026

Gemma 4 E2B is the only supported model family for device qualification and
release. Gemma 3 testing is cancelled. Devices that cannot run Gemma 4 are
excluded; there is no smaller-model fallback. Untested devices and download-only
failures remain unqualified, not proven incompatible. A short inference pass
does not replace quality, memory and sustained thermal acceptance.

## Actual execution status

Latest September 25 remediation: **all retests passed**. The original Pixel 10
GPU-specific Gemma 4 artifact selected GpuArtisan and timed out during decoding.
The publisher's standard Gemma 4 E2B export, pinned as
`gemma4-e2b-portable-gpu`, passed on Pixel 10 Pro and S26 in
`matrix-2ateexz85mszl`. Pixel native logs show the OpenCL delegate. This is an
explicit alternative profile, not an automatic fallback after an error.

Pixel 10 Pro: 35,550 ms load; median first text 1,584 ms; median decode 1.9 tokens/s.
S26 GPU comparison: 8,595 ms load; median first text 137 ms; median decode 38.3 tokens/s.
S26 NPU regression also passed (`matrix-35v3mjriaw9f1`). All nine summaries retained
the required facts, with thermal status 0. The context remains 4,096 tokens and
the per-summary timeout remains 90 seconds.

The Pixel workaround stays in the qualification catalog. Its slow throughput,
long-summary quality and sustained behavior require acceptance before public
support; production eligibility and profiles are unchanged. The OpenCL sampler
was unavailable on Pixel and the runtime used its statically linked sampler;
per-operator CPU usage is not measured. No CPU-only model backend was selected.
See `spike/hardware_probe/firebase/PIXEL10_REMEDIATION.md` for reproduction.

The earlier attempts below are retained as historical evidence.

September 25 update: the corrected pre-staged Gemma 4 retries are complete.
S26 SM-S942U1 passed GPU (median 39.8 decode tokens/sec; 171 ms first text)
and NPU (HTP0 initialized; median 84 ms first text). All six S26 responses
preserved the required facts, with thermal status 0. These remain short smoke
passes, not sustained thermal or long-summary acceptance.

Pixel 10 Pro initialized Gemma 4 GPU in 8.165 seconds, but generation exceeded
90 seconds without a completed response. It remains excluded with the current
model/runtime; do not fall back to Gemma 3. This is now an inference failure,
not an inconclusive model download.

Corrected matrices: `matrix-28jvwti7jl190` (GPU) and `matrix-1fcoetigmd91s` (NPU).
Initial staged matrices `matrix-r4d3w3e1o1c1a` and `matrix-32xe25j987o54` failed
before inference with EACCES under Android/data. The test-only fix imports
weights from `/data/local/tmp` into app-owned internal storage using the
instrumentation shell; exact size and SHA-256 verification are retained.
Details: `spike/hardware_probe/firebase/staged-retry-2026-09-25.json`.
Production device eligibility remains unchanged.

The completed September 24 batch is described below.

Discovery matrix `matrix-3p3vsy2l0san4` completed successfully on three physical phones.
[Firebase results](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.bc4a4cad7633ea33/matrices/7801636253553125808).
Raw reports: `spike/hardware_probe/firebase/{m1q,pa3q,e3q}.json`.

The six-device follow-up `matrix-32j6pkfaersjm` was rejected with
`TEST_QUOTA_EXCEEDED`. A reduced A16 5G/A16 matrix `matrix-1vnmbfc0lk678` completed discovery on both phones.
[Firebase A16 results](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.bc4a4cad7633ea33/matrices/6272641299832361335).
The user resolved the quota limit. No project billing settings were changed by the agent.
The resumed four-phone discovery matrix `matrix-1kv1y8qv8ygkm` passed.
All submitted comparisons have finished. Six devices passed GPU smoke tests;
S25 also passed NPU. S26 and Pixel 10 cloud inference remained inconclusive due
to failed model delivery. See
`spike/hardware_probe/firebase/RESULTS.md` for final outcomes.

## Hardware and model hypotheses

These are candidates, not automatic release approvals or measured model rankings.
E2B-GPU means the existing pinned Gemma 4 E2B LiteRT-LM model; E2B-NPU means the
existing Gemma 4 E2B W4 GGUF + ggml-hexagon runtime, not LiteRT-LM's NPU backend.

| Priority/device | Silicon | First candidate | Evidence / limits |
|---|---|---|---|
| S26 Ultra (local) | SM8850 / Adreno 840 | Compare E2B-NPU v81 with E2B-GPU | Local NPU quick test passed previously; 10-minute soak stopped for severe thermal status. No Firebase Ultra inventory. |
| S26 `m1q` | **SM8850 / Adreno 840** | Compare E2B-NPU v81 and E2B-GPU | Confirmed Firebase SM-S942U1, API36, OpenCL 3.0, ~10.86 GiB OS-visible RAM. Not Exynos in this inventory sample. |
| S25 Ultra `pa3q` | **SM8750 / Adreno 830** | Compare E2B-NPU v79 and E2B-GPU | Confirmed Firebase SM-S938U1, API36, OpenCL 3.0, ~10.85 GiB RAM. |
| S24 Ultra `e3q` | **SM8650 / Adreno 750** | E2B-GPU | Confirmed Firebase SM-S928U1, API36, OpenCL 3.0, ~10.83 GiB RAM; GPU smoke test passed locally. |
| A17 5G | Exynos 1330 / Mali-G68 | E2B-GPU qualification only | Manufacturer specs; not in current Firebase inventory. No performance claim. |
| A16 5G `a16x` | **s5e8535 (Exynos 1330 family) / Mali-G68** | E2B-GPU unqualified; likely memory-constrained | Confirmed SM-S166V, API36, ~3.37 GiB RAM, only ~0.86 GiB available at probe time. Do not enable E2B based on OpenCL alone. |
| A16 LTE `a16` | **MT6789V/CD / Mali-G57 MC2** (Helio G99 family) | E2B-GPU qualification only | Confirmed SM-A165M, API35, ~5.50 GiB RAM, ~2.74 GiB available; E2B-GPU smoke passed at ~6 tokens/sec; full qualification pending. |
| S23 Ultra `dm3q` | **SM8550 / Adreno 740** | E2B-GPU only | Confirmed Firebase API34, 6.89 GiB OS-visible RAM. Current Hexagon v79/v81 libraries do not establish support for this generation. |
| Pixel 10 Pro `blazer` | **Tensor G5 / PowerVR DXT-48-1536** | E2B-GPU experiment; evaluate Tensor-specific artifact separately | Confirmed Firebase API36, 15.18 GiB RAM and OpenCL device enumeration. Qualcomm GGUF/NPU route does not apply. |
| Pixel 9 Pro `caiman` | **Tensor G4 / Mali-G715** | E2B-GPU only | Confirmed Firebase API35, 15.19 GiB RAM and OpenCL enumeration. No Qualcomm NPU route. |
| Xiaomi 14 `houji` | **SM8650 / Adreno 750** | E2B-GPU | Confirmed Firebase API35, 10.91 GiB RAM. Same SoC family as S24, different vendor drivers/thermal behavior. |

Firebase also has S26+ `m2q`; omit the duplicate generation initially. Xiaomi 14
is available but is not a current-generation 2026 flagship; it is the available
cross-vendor Snapdragon comparison. A newer Xiaomi/OnePlus must be sourced
separately if that specific generation is required.

Gemma 4 E2B is the only model candidate on all phones. Devices must pass
latency, memory, thermal and summary-quality qualification to become eligible;
phones unable to run it are excluded instead of receiving a smaller model.

Sources:
- https://www.samsung.com/us/business/mobile/phones/galaxy-s26/
- https://www.samsung.com/ie/smartphones/galaxy-s26/ (regional Exynos variant)
- https://www.qualcomm.com/news/releases/2025/01/qualcomm-and-samsung-redefine-premium-performance-by-bringing-th
- https://news.samsung.com/ca/samsung-canada-introduces-the-galaxy-a17-5g-with-everyday-ai-and-essential-performance
- https://www.mediatek.com/products/smartphones/mediatek-dimensity-6300
- https://www.qualcomm.com/news/releases/2023/02/qualcomm-and-samsung-partner-to-bring-the-fastest-snapdragon-eve
- https://support.google.com/pixelphone/answer/7158570?hl=en
- https://www.mi.com/global/product/xiaomi-14/
- https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm

## Expanded APKs and inference harness

Build with `scripts/build_hardware_probe.sh`. Both debug app and instrumentation
APKs are required. The new instrumentation test bypasses the *public allowlist*
only within the test harness to probe GPU execution on other physical ARM64 phones;
it does not widen release eligibility or choose models for production users.

`android/app/src/androidTestQualification/assets/inference_candidates.json` pins
Gemma 4 E2B GPU (~2.01 GB) by immutable URL, byte size and SHA256.
Models are not embedded in APKs. No credentials are embedded or sent to Firebase phones.

`InferenceProbeTest` requires `runInference=true` and a named `modelCandidate`.
It verifies the model, explicitly initializes `Backend.GPU`, performs three short
synthetic summaries, checks required facts, and records first-text latency, total
latency, decode tokens/sec, PSS samples and thermal status. Native logs provide
additional backend evidence. These samples are not peak-memory or sustained
thermal tests. First-text callback is a TTFT approximation. No CPU fallback is
created; per-operator CPU use is not measured. This is not an appointment-summary
quality evaluation. The existing qualification screen remains the long-run tool.

Local S24 inference validation passed (three responses); report:
`spike/hardware_probe/s24-gpu-inference.json`. Gemma 3 has been removed from the candidate catalog. `NpuProbeTest` now exercises the existing Hexagon bridge with the same three synthetic
summaries; it passed locally on S26. It requires HTP0, retains SHA verification,
and reports first-text/total latency, PSS and thermal status. It does not report
a decode-token rate because that bridge does not expose a comparable benchmark.

Review/submit remaining batches after quota is available:

```sh
python3 scripts/run_firebase_probe.py --gcloud /Users/zebulon/Downloads/google-cloud-sdk/bin/gcloud --project kraken-voice --group coverage
# Add --submit to execute the printed, inventory-checked discovery command.
# Use --group priority --phase gpu --submit for the first GPU inference comparison.
```

GPU runs allow 12 minutes/device including up to 8 minutes for downloading.
Use only `--test-targets 'class org.krak_en.voice.HardwareProbeTest'` for discovery;
do not run every instrumentation test indiscriminately. Only Gemma 4 is selectable
for cloud inference submission.

The A16 5G snapshot had only ~0.86 GiB free memory. Gemma 4 inference remains
untested on this device, which remains unqualified.
Both A16 JSON reports are saved beside the flagship reports.

For Gemma 4 GPU model staging, place the pinned file at
`/data/local/tmp/gemma4-e2b-gpu.litertlm` and pass `useStagedModel=true`.
The instrumentation runner imports it into app-owned internal storage. NPU uses
`/data/local/tmp/gemma4-e2b-w4.gguf`. Do not stage directly under Android/data: the
September 25 Firebase attempt created a directory inaccessible to the app.
Only the separate `inference-probe` report folder is collected by Firebase.

To run the bounded NPU comparison: use `--group npu --phase npu --submit`.
Use `--app-uri gs://.../app-qualification-debug.apk` to reuse the identical uploaded
app instead of uploading 126 MB again. `scripts/collect_firebase_probe.py` retrieves
status and JSON reports; add `--collect --logs` for native logs.

For repeatable future batches, `--model-source /path/to/pinned-model` or
`--model-source gs://PRIVATE_BUCKET/pinned-model` uses Firebase `--other-files`
to stage the model before the timed test. The test still verifies its size and SHA.
Only pinned Gemma 4 weights are eligible for these tests.
The initial staging attempt failed with EACCES before model initialization;
the corrected test harness uses shell-assisted import from `/data/local/tmp`.
The current runs downloaded directly from Hugging Face; several hit transfer
limits before inference. Retry APKs allow `downloadMinutes=15` and save download
byte/time checkpoints every 32 MiB. No arbitrary model download URLs are accepted.

## Completed inference observations

| Device | Gemma 4 E2B GPU decode tokens/sec | Result |
|---|---:|---|
| S25 Ultra | 47–48 | Passed |
| S24 Ultra | 35–37 | Passed after download retry |
| Xiaomi 14 | 30–33 | Passed |
| S23 Ultra | 28–29 | Passed |
| Pixel 9 Pro | 17–22 | Passed |
| A16 LTE, 6 GB | ~6 | Passed, substantially slower; retain release exclusion pending Gemma 4 real-workload tests |

S25 NPU also passed: first text 76–85 ms, full short response 855–1043 ms.
Its GPU response times were 541–623 ms. This is a short-prompt observation, not
a general GPU-vs-NPU ranking; regional variants and export formats differed.
The September 24 S26 GPU/NPU and Pixel 10 GPU cloud tests never reached model
initialization because transfers failed. September 25 pre-staged retries resolved
model delivery: S26 passed both backends; Pixel 10 timed out during generation.
Local S26 Ultra NPU smoke test passed. A16 5G (4 GB) inference remains untested.

All public eligibility restrictions remain unchanged. Passing three synthetic
summaries does not cover long appointments, sustained thermal behavior or summary
quality. The previous S26 sustained NPU thermal concern is still open.
