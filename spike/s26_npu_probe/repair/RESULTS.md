# Repaired S26 NPU experiment — 2026-09-23

**Replacement loaded on the S26; all six factual regression checks passed twice,
including after a fresh reload. Kraken's installed app still uses LiteRT GPU.**

## Diagnosis and repair

The original RunAnywhere QHexRT bundle used valid Gemma chat token IDs. Its
compiled 512-token context cannot be enlarged by editing the manifest. Version
0.20.19 remains the latest public QHexRT AAR. Reducing repetition penalty from
1.1 to 1.0 recovered the deadline but still lost the owner in the same short
summary. This did not establish a complete fix or a precise internal cause;
the original bundle remains unsuitable.

Replaced that experimental backend with `h2loop-ai/gemma-4-e2b-hexagon` at
revision `1bb2044c313769541558f2c27fa67561894d0f26`:

- `gemma4-e2b-w4.gguf`, 2,620,370,976 bytes, group-32 Q4_0 weights.
- Matching published llama.cpp ARM64 runtime, build `0ef6e55`, Hexagon v81 kernels.
- Explicit HTP0 selection, 99 requested offload layers, flash attention, 4096
  context, 6 host threads, single slot, no continuous batching.
- **`--reasoning off`**: initial replacement tests wasted most of their 128-token
  output limit on hidden thinking and truncated answers. Disabling thinking
  repaired that configuration error; the same six tests then passed unchanged.
- All 18 downloaded artifacts were size-checked; LFS artifacts also matched
  the publisher's SHA-256 values. `artifacts.json` records every local hash.

Logs assign all 35 transformer layers and the output layer to HTP0. The
runtime's generic log says "offloaded 36/36 layers to GPU" but the selected
device is **HTP0 (Hexagon)**, not OpenCL. CPU buffers and host operations still
exist: this is **NPU-accelerated inference**, not proof of zero CPU computation.

## Results

| Check | First repaired run | After reload | Result |
| --- | ---: | ---: | --- |
| Capital | 0.414 s | 0.5 s | Pass |
| Original meeting | 1.169 s | 1.154 s | Pass |
| Arithmetic | 0.563 s | 0.506 s | Pass |
| Different owner/amount/date | 1.320 s | 1.283 s | Pass |
| Rejected proposal vs final decision | 1.044 s | 1.006 s | Pass |
| Long meeting (1,421 prompt tokens) | 2.270 s | 2.167 s | Pass |

Correct original summary:

> The approved budget is $42,750, owned by Maya, with a deadline of October 16th.

First repaired run reported roughly 26–32 generated tokens/s. The reloaded long
prompt reported 1,718 input tokens/s and 27 generated tokens/s. These are short
single-device checks, not sustained thermal benchmarks. Test requests use greedy
decoding, seed 42, repetition penalty 1.0, and 128 output tokens. The server may
reuse matching prompt prefixes; per-case cache counts are retained in JSONL.

## Reload and scope

Files are staged at `/data/local/tmp/kraken-hexagon-repair` on device
`R3GL40811NP`. `run-server.sh` contains the working configuration. Run it through
ADB; it binds **127.0.0.1:8099 only**. For host testing, forward host port 18099
to device port 8099, then run `test_server.py`. The final test server was left
running. It is an experimental process, not an Android service and not a
persistent installation across reboot. Both Kraken app packages were untouched.

The existing GPU app cannot consume this GGUF using its LiteRT loader. Shipping
this candidate requires a separate app integration, per-chip model routing,
context-aware meeting chunking, app-sandbox verification, full recording flow
checks, and signed-release testing. The 4096-token configuration improves on
512 but does not replace Kraken's configured 32768-token LiteRT context.

SM8750 has not been validated by us. Do not infer release readiness from these
S26 probe passes. Original and replacement artifacts remain on the phone for
comparison; neither was silently selected as Kraken's production model.

Sources:
- https://huggingface.co/h2loop-ai/gemma-4-e2b-hexagon
- https://repo.maven.apache.org/maven2/io/github/sanchitmonga22/runanywhere-qhexrt-android/maven-metadata.xml
