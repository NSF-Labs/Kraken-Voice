> Current app: **1.0.14-npu-sm8850+14**, Gemma 4 E2B GGUF on llama.cpp Hexagon
> HTP0. This file records the earlier **QHexRT experiment**, not the current
> working app backend. See [device/runtime audit](../../RUNTIME_DEVICE_AUDIT.md)
> and [current validation](../../S26_RELEASE_TEST_RESULTS.md).

> September 24 app repair: normal build **1.0.11-npu-sm8850+11** fixes stale
> Flutter AOT paired with the NPU backend. The user's 14,887-character recording
> successfully generated and saved its summary in 55.4 seconds on the S26.
> See [current app validation](../../S26_RELEASE_TEST_RESULTS.md).

# S26 Gemma 4 E2B NPU test — 2026-09-23

**NPU execution confirmed; this model/runtime combination fails release qualification.**

Hardware: attached Samsung SM-S948U, SM8850. QNN reported Hexagon v81,
SoC 87, 8 MB VTCM. Runtime: QHexRT from RunAnywhere 0.20.19, bundled QAIRT
2.47.0.260601114230. Both decoder and LM-head context graphs instantiated on
HTP; the probe called only the QHexRT backend. This confirms NPU graph execution,
not an assertion that tokenization or every host operation runs on the NPU.

The pinned 8,251,288,552-byte text bundle was downloaded, its LFS files verified
against published SHA-256 hashes, and all ten files transferred to the phone.
See README.md for revision, runtime hashes, and reproduction details.

| Check | Run 1 | Run 2 | Result |
| --- | ---: | ---: | --- |
| Model load | 2.695 s | 2.312 s | Pass |
| Capital of France | 2.258 s | 2.248 s | Correct: Paris |
| Short meeting facts | 6.397 s | 6.507 s | Failed identically both runs |
| 17 + 25 | 3.623 s | 3.212 s | Correct: 42 |

Meeting input explicitly gave $42,750, Maya, and October 16. Both runs returned:

> The approved budget is for \$42,750, with the deadline for completion being the submission of an audit by [Insert Date].

The owner and actual deadline were lost. All inference calls returned success,
but the factual assertions failed, so both test processes exited with code 5.
Greedy decoding, seed 42, maximum 48 output tokens. The failed response was
29 tokens; it was not truncated at the output cap. The input was 47 tokens.

Runtime-reported decode throughput was 9.3–10.4 tokens/s. End-to-end throughput
was lower because prefill was slow. Its TTFT field returned zero and should not
be interpreted as a measured zero-latency first token. Compared with the earlier
GPU test, the identical capital prompt took ~2.25 s here versus ~0.65 s on GPU.
This is evidence about these two tested implementations, not all NPU software.

The compiled model has only a 512-token context. The 6,462-character prompt from
the earlier GPU test was therefore not attempted; the NPU cannot satisfy that
meeting-summary workload with this bundle.

The initial load was safely refused with 2,723 MB available: the runtime required
2,564 MB for graphs plus 512 MB headroom. After Android's `am kill-all` reclaimed
safe-to-kill background processes, the retry reported 4,551 MB available and
loaded successfully. No memory guard was bypassed. Background apps may reload.

Kraken production and development packages were not installed, uninstalled,
updated, or accessed in this session. Their existing GPU configuration remains.
The model and probe remain in `/data/local/tmp/kraken-npu-model` and
`/data/local/tmp/kraken-npu-runtime` for further testing (about 8.5 GB total).
No probe process is intended to remain running after the tests.

Do not promote this bundle to release: factual accuracy, context capacity, and
performance all require a better model/runtime combination and revalidation.

## Follow-up repair

A replacement Hexagon model/runtime passed six checks twice, including a fresh
reload. See [repair/RESULTS.md](repair/RESULTS.md). The original QHexRT bundle
still fails; the replacement is an isolated probe, not yet the Kraken app backend.
