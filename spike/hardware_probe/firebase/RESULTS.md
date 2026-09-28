# Firebase qualification results

Discovery is hardware evidence; short synthetic inference passes are not release certification.

## Test matrices

| Matrix | State | Outcome | Results |
|---|---|---|---|
| matrix-1fcoetigmd91s | FINISHED | SUCCESS | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.9be9137b2ee2a6b4/matrices/6518523641879792753) |
| matrix-1kv1y8qv8ygkm | FINISHED | SUCCESS | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.5e07d20b87be7774/matrices/8039190514071463178) |
| matrix-1w3afptyvyrp3 | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.9be9137b2ee2a6b4/matrices/7055091359072756451) |
| matrix-27nulnndb2bdv | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/7156399563536065339) |
| matrix-28jvwti7jl190 | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/5602907906240795118) |
| matrix-2ateexz85mszl | FINISHED | SUCCESS | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/8679824764687551509) |
| matrix-2xfg3wrckabr6 | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/6141206234472505278) |
| matrix-32xe25j987o54 | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.9be9137b2ee2a6b4/matrices/5873343354677394934) |
| matrix-35v3mjriaw9f1 | FINISHED | SUCCESS | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.9be9137b2ee2a6b4/matrices/5541451948783581995) |
| matrix-398hlmqp1ap4c | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/7891022316726041833) |
| matrix-3jk50wrl2fi7d | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/6151786945863950032) |
| matrix-3m3hshjdl92cg | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.9be9137b2ee2a6b4/matrices/8009411612962717672) |
| matrix-452emtavhlr9a | FINISHED | SUCCESS | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/5662968265246320436) |
| matrix-r4d3w3e1o1c1a | FINISHED | FAILURE | [Console](https://console.firebase.google.com/project/kraken-voice/testlab/histories/bh.81b3818b1d32cae9/matrices/7202547094223753459) |

## Inference observations

| Matrix / Firebase device | Actual phone | Model candidate | Backend | Outcome | Load ms | First text ms (median) | Decode tokens/sec (median) | Details |
|---|---|---|---|---|---:|---:|---:|---|
| matrix-1fcoetigmd91s / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-npu | NPU | passed | 6076 | 84 | — | 3 short synthetic summaries; peak memory not measured |
| matrix-1w3afptyvyrp3 / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-npu | NPU | Inconclusive: model delivery | — | — | — | java.lang.IllegalStateException: Download timeout |
| matrix-1w3afptyvyrp3 / pa3q-36-en-portrait | SM-S938U | gemma4-e2b-npu | NPU | Inconclusive: model delivery | — | — | — | java.lang.IllegalStateException: Download timeout |
| matrix-27nulnndb2bdv / e3q-36-en-portrait | SM-S928U1 | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | IllegalStateException: Download exceeded eight minutes |
| matrix-27nulnndb2bdv / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | IllegalStateException: Download exceeded eight minutes |
| matrix-27nulnndb2bdv / pa3q-36-en-portrait | SM-S938B | gemma4-e2b-gpu | GPU | passed | 6347 | 144 | 47.2 | 3 short synthetic summaries; peak memory not measured |
| matrix-28jvwti7jl190 / blazer-36-en-portrait | Pixel 10 Pro | gemma4-e2b-gpu | GPU | failed | 8165 | — | — | IllegalStateException: Generation exceeded 90 seconds |
| matrix-28jvwti7jl190 / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-gpu | GPU | passed | 9123 | 171 | 39.8 | 3 short synthetic summaries; peak memory not measured |
| matrix-2ateexz85mszl / blazer-36-en-portrait | Pixel 10 Pro | gemma4-e2b-portable-gpu | GPU | passed | 35550 | 1584 | 1.9 | 3 short synthetic summaries; peak memory not measured |
| matrix-2ateexz85mszl / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-portable-gpu | GPU | passed | 8595 | 137 | 38.3 | 3 short synthetic summaries; peak memory not measured |
| matrix-2xfg3wrckabr6 / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | IllegalStateException: Download exceeded 15 minutes after 1561894788 bytes |
| matrix-32xe25j987o54 / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-npu | NPU | Inconclusive: model delivery | — | — | — | java.io.FileNotFoundException: /storage/emulated/0/Android/data/org.krak_en.voice.qualification/files/inference-models/gemma4-e2b-w4.partial: open failed: EACCES (Permission denied) |
| matrix-35v3mjriaw9f1 / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-npu | NPU | passed | 5209 | 58 | — | 3 short synthetic summaries; peak memory not measured |
| matrix-398hlmqp1ap4c / blazer-36-en-portrait | Pixel 10 Pro | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | SocketTimeoutException: timeout |
| matrix-3jk50wrl2fi7d / blazer-36-en-portrait | Pixel 10 Pro | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | IllegalStateException: Download exceeded eight minutes |
| matrix-3jk50wrl2fi7d / caiman-35-en-portrait | Pixel 9 Pro | gemma4-e2b-gpu | GPU | passed | 6175 | 297 | 20.6 | 3 short synthetic summaries; peak memory not measured |
| matrix-3jk50wrl2fi7d / dm3q-34-en-portrait | SM-S918B | gemma4-e2b-gpu | GPU | passed | 8846 | 238 | 28.3 | 3 short synthetic summaries; peak memory not measured |
| matrix-3jk50wrl2fi7d / houji-35-en-portrait | 23127PN0CG | gemma4-e2b-gpu | GPU | passed | 7884 | 222 | 31.9 | 3 short synthetic summaries; peak memory not measured |
| matrix-3m3hshjdl92cg / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-npu | NPU | Inconclusive: model delivery | — | — | — | java.net.ProtocolException: unexpected end of stream |
| matrix-3m3hshjdl92cg / pa3q-36-en-portrait | SM-S938U | gemma4-e2b-npu | NPU | passed | 3681 | 81 | — | 3 short synthetic summaries; peak memory not measured |
| matrix-452emtavhlr9a / a16-35-en-portrait | SM-A165M | gemma4-e2b-gpu | GPU | passed | 12286 | 1274 | 6.0 | 3 short synthetic summaries; peak memory not measured |
| matrix-452emtavhlr9a / e3q-36-en-portrait | SM-S928B | gemma4-e2b-gpu | GPU | passed | 7356 | 207 | 35.1 | 3 short synthetic summaries; peak memory not measured |
| matrix-r4d3w3e1o1c1a / blazer-36-en-portrait | Pixel 10 Pro | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | FileNotFoundException: /storage/emulated/0/Android/data/org.krak_en.voice.qualification/files/inference-models/gemma4-e2b-gpu.partial: open failed: EACCES (Permission denied) |
| matrix-r4d3w3e1o1c1a / m1q-36-en-portrait | SM-S942U1 | gemma4-e2b-gpu | GPU | Inconclusive: model delivery | — | — | — | FileNotFoundException: /storage/emulated/0/Android/data/org.krak_en.voice.qualification/files/inference-models/gemma4-e2b-gpu.partial: open failed: EACCES (Permission denied) |

## Interpretation limits

- Download failures are inconclusive for inference support. Retries remain separate rows.
- Firebase can allocate different regional variants under the same device ID. Actual model is recorded per run.
- GPU tests explicitly request Backend.GPU; per-operator CPU work is not measured. Native logs provide additional evidence.
- NPU tests use the app Hexagon bridge, which requires HTP0 and rejects CPU-only execution. CPU host/unsupported operations remain.
- Three short summaries do not qualify long appointments, sustained thermals, cancellation or summary quality across real workloads.
- GPU load timing excludes checksum verification; NPU load timing includes the bridge checksum. Do not treat those timings as an identical initialization benchmark.
- Gemma 4 E2B is the only qualification model. Gemma 3 tests are cancelled; devices unable to run Gemma 4 are excluded, with no smaller-model fallback.
- Production device eligibility is unchanged. Existing S26 sustained NPU thermal concerns are not cleared by a smoke test.
