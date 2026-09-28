# S24 summary quality diagnosis — September 26, 2026

Follow-up: [build 1.0.18](TRIAL_RELEASE_1.0.18.md) integrates the portable export
and passes the previously failing recording's full-app background-summary and
restart-persistence checks on the S24. The observations below describe the
earlier diagnostic comparison and build 1.0.17.

The current Gemma 4 E2B GPU-specific export reproducibly corrupts longer English
notes on the attached SM-S928U (SM8650 / Adreno 750). The alternate portable
Gemma 4 E2B export produces coherent, factually correct output on the same GPU.
Evidence points to the export/GPU implementation combination, not a false
rejection by the app's quality checker or exhausted RAM. The precise defect
within conversion, GPU kernels, or driver execution is not yet isolated.

## Controlled native comparison

LiteRT-LM 0.17.1, explicit `Backend.GPU`, context 4096, thinking off,
topK 1, topP 1, temperature 0. Both pinned files passed SHA-256 verification.
Each run used a new instrumentation process, one 53-token factual prompt,
then the same 445-token synthetic meeting-notes prompt twice in separate
conversations. Output limits were 256 and 768 tokens respectively.
Tests bypassed Flutter and the production quality checker. No user recording
was read or modified. The idle development app was stopped to release its model.

| Export / decoding setting | Short prompt | Longer notes, two repeats | Available RAM minimum | Largest sampled app PSS | Longer-response speed |
|---|---|---|---|---|---|
| GPU-specific / speculation off | Pass | Both corrupted | 2.93 GiB | 2.32 GiB | 34–36 tokens/s |
| GPU-specific / speculation requested on | Pass | Both corrupted | 3.85 GiB | 2.32 GiB | 35–36 tokens/s |
| Portable / speculation off | Pass | Both passed | 3.48 GiB | 2.15 GiB | 26–34 tokens/s |
| Portable / fresh-process repeat | Pass | Both passed | 3.69 GiB | 2.10 GiB | 31–33 tokens/s |

Every recorded Android low-memory flag was false; thermal status was 0.
Memory values are samples before/after responses, not instrumented peak
allocations. System swap was in use, so this is not a claim of zero memory
pressure. The failing output repeated identically with substantially more
available RAM. No generation hit its output limit or timed out.

The failing export changed the deadline to `*$16`, lost the month, mixed
Chinese/Devanagari/Tamil fragments into English, and ended with an incomplete
bullet. The portable export preserved Maya, $42,750, October 16, rejected
proposals, task owners, and unresolved questions without that corruption.
Its notes exceeded the requested 120 words: these passes establish factual
and text-quality improvement, not complete instruction-following acceptance.

Native logs identify **GpuArtisan** for the GPU-specific export and
**OpenCL-based** execution for the portable export. Unsupported profiling
summary warnings are not themselves proof of the underlying quality defect.
Enabling the speculative-decoding flag did not change the failing output;
the report records the requested flag, not verified use of a draft model.

## Answers and release implications

- **Internet bandwidth:** no role in generation after local staging. Both
  files passed their pinned checksums before inference; a corrupt download
  is not the explanation for these runs.
- **RAM capacity:** not supported as the cause of the reproduced corruption.
  The failure persisted with nearly 4 GiB available and no low-memory signal.
- **Memory bandwidth:** not directly profiled. Both paths generated tens of
  tokens per second; throughput alone cannot identify a hardware bottleneck.
- **Quality checker:** correctly rejects this observed corrupted output.
  Its three existing unit tests pass. The native reproduction proves the
  checker does not introduce the corruption; it is not an exhaustive audit
  of every possible false positive.
- **Remedy candidate:** use `gemma-4-E2B-it.litertlm` on the S24 GPU instead
  of `gemma-4-E2B-it-gpu.litertlm`, then validate the full app's condensation,
  structured final summary, background recovery, model migration, and long
  recordings before release. These results cover two unique synthetic prompts
  with repeated generations, not broad device/content qualification.

The installed trial APK and production model selector were not changed by
this diagnostic task. S24 summary quality in build 1.0.17 remains a release
blocker until the candidate is integrated and passes full-app testing.
Gemma 3 and CPU-only fallbacks remain excluded.

## Artifacts and reproduction

Reports, raw synthetic answers/prompts, instrumentation results, memory samples,
and selected native logs are in
[`spike/hardware_probe/s24_quality_20260926`](../spike/hardware_probe/s24_quality_20260926/).
`comparison.json` summarizes all four runs. Both model identities and pinned
hashes are in `android/app/src/androidTestQualification/assets/inference_candidates.json`.

Build `:app:assembleQualificationDebugAndroidTest` with target
`lib/main_qualification.dart` and ARM64, then install the qualification app/test
APKs. Stage the pinned files as `/data/local/tmp/gemma4-e2b-gpu.litertlm` and
`/data/local/tmp/gemma4-e2b-portable-gpu.litertlm`. Run sequentially:

```sh
adb -s SERIAL shell am instrument -w -r \
  -e class org.krak_en.voice.InferenceProbeTest \
  -e runInference true -e useStagedModel true \
  -e modelCandidate gemma4-e2b-gpu -e qualitySuite true \
  org.krak_en.voice.qualification.test/androidx.test.runner.AndroidJUnitRunner
```

Repeat with `modelCandidate=gemma4-e2b-portable-gpu`. Add `-e speculative true`
for the decoding experiment. Omit staging on repeat runs after import.
Pull each report before reusing the candidate: the test overwrites
`/sdcard/Android/data/org.krak_en.voice.qualification/files/inference-probe/CANDIDATE.json`.
The optional quality suite records all responses before failing; the original
default short-prompt smoke test still fails immediately on a bad response.

## Related upstream evidence

[LiteRT-LM issue #3012](https://github.com/google-ai-edge/LiteRT-LM/issues/3012)
reports longer-prompt GPU corruption on the same Adreno 750/SM8650 family.
It concerns Gemma 4 **E4B**, German text, and another device, so it is supporting
context rather than confirmation of the precise E2B defect found here.
