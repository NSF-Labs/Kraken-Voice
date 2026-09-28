# Pixel 10 Pro Gemma 4 GPU remediation — September 25, 2026

## Outcome

The alternative Gemma 4 E2B export passed the unchanged three-summary smoke test
on Pixel 10 Pro and S26. S26 NPU regression also passed. No production allowlist
or default model profile was changed.

| Device / backend | Result | Load | Median first text | Median decode |
|---|---|---:|---:|---:|
| Pixel 10 Pro / GPU | 3 correct summaries | 35.55 s | 1.584 s | 1.9 tokens/s |
| S26 SM-S942U1 / GPU | 3 correct summaries | 8.595 s | 0.137 s | 38.3 tokens/s |
| S26 SM-S942U1 / NPU | 3 correct summaries | 5.209 s | 0.058 s | Not exposed |

All responses reported thermal status 0. These are short synthetic smoke tests,
not sustained thermal, realistic workload or release acceptance tests.

## Failure and change

The original `gemma4-e2b-gpu` export loaded successfully, but Pixel decoding
exceeded 90 seconds. Its native log identifies `GPU_ARTISAN`. The new
`gemma4-e2b-portable-gpu` candidate uses the publisher's standard export with
explicit `Backend.GPU()`; Pixel logs confirm OpenCL initialization. This provides
a tested compatibility alternative; it does not establish the specific underlying
driver defect in the Artisan path.

The runtime remains LiteRT-LM 0.17.1, context 4096, output cap 256, three identical
factual prompts, greedy sampling, thinking off, speculative decoding off, and
90-second response timeout. The alternative artifact is larger and changes the
model export, so throughput differences are not a pure hardware comparison.

- Publisher repository: `litert-community/gemma-4-E2B-it-litert-lm`.
- Revision: `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1`.
- Publisher filename: `gemma-4-E2B-it.litertlm`.
- Test filename: `gemma4-e2b-portable-gpu.litertlm`.
- Bytes: `2588147712`.
- SHA-256: `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c`.

The OpenCL sampler was unavailable on Pixel and the runtime reported a fallback
to its statically linked sampler. This is not CPU-only model execution; individual
CPU operations are not measured. Pixel remains excluded from production pending
performance, long-summary quality and sustained acceptance. Do not generalize this
pass to every Tensor/PowerVR phone, or replace the faster existing S26 profile.
For Quotes/FW Planner reuse, carry this as a separate, pinned Gemma 4 profile with
its own device validation, rather than using one export for every GPU.

## Reproduce

Build the qualification test APK with the current `inference_candidates.json` and
`ProbeModelStaging`. Stage the verified weights at `/data/local/tmp/` through
Firebase `--other-files`; `useStagedModel=true` imports them into app-owned storage
and retains size/hash checks. The prior direct Android/data staging caused EACCES
and is not supported.

```sh
python3 scripts/run_firebase_probe.py \
  --gcloud /Users/zebulon/Downloads/google-cloud-sdk/bin/gcloud \
  --project kraken-voice --group gpu-retry --phase gpu \
  --model gemma4-e2b-portable-gpu \
  --results-bucket test-lab-hj0k59sbdp2xk-htf793v23x37a \
  --app-uri gs://test-lab-hj0k59sbdp2xk-htf793v23x37a/2026-09-24_17:35:25.627728_HyiM/app-qualification-debug.apk \
  --model-source gs://test-lab-hj0k59sbdp2xk-htf793v23x37a/gemma4-staged-2026-09-25/gemma4-e2b-portable-gpu.litertlm
# Review the inventory-checked command; add --submit to run it.
```

## Evidence

- Original Pixel failure: `matrix-28jvwti7jl190`.
- Passing GPU comparison: `matrix-2ateexz85mszl`.
- Passing S26 NPU regression: `matrix-35v3mjriaw9f1`.
- `portable-retry-2026-09-25.json`: artifact identity, metrics and console URLs.
- `pixel10-portable-gpu-evidence.txt`: selected native backend log lines.
- `RESULTS.md`: full comparison including historical failures.

The instrumentation APK built successfully. Local dry-run checks verified both
GPU/NPU staging destinations and rejected Gemma 3. Timeout reports now retain
partial output, elapsed time, PSS and thermal status for future diagnosis.
