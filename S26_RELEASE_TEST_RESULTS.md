# Current build: 1.0.14-npu-sm8850+14 — visible summary progress

Document summaries, manually generated recording summaries and refinements now
show an estimated progress bar, current preparation pass/section, live output
character counts and elapsed time. A separate activity spinner remains visible
while waiting for output. Document updates are throttled to avoid excessive
redraws; the active job stores its start time and progress across navigation.
The previous timer-based recording ETA has been removed: output length and
additional condensation passes are not known in advance.

- 62 Flutter tests pass, including failed-section progress, continuation,
  accessibility semantics, panel updates and timer disposal.
- Analyzer: 12 pre-existing informational diagnostics, no errors or warnings.
- Clean explicit main-entrypoint profile build; APK profile/ABI verification passes.
- Installed on S26 with `adb install -r`; S24 packages left unchanged.
- On-device normal-app validation with the existing 75,026-character document:
  section 3/8 at 20% and 0:58; reopened at section 4/8, 24%, elapsed 1:26;
  section 7/8 at 36%, elapsed 2:43; final writing at 87%, elapsed 3:59,
  1,495 characters written. Counters visibly update, and navigation preserves
  the job's progress/start time. On completion the panel disappeared and the
  saved summary was displayed with Regenerate enabled and no error. The original
  sleep setting was restored. Source content omitted from this report.
- Model, native context and acceleration backend unchanged.

See [attached-device runtime audit](RUNTIME_DEVICE_AUDIT.md) for the verified
S24 CPU / S26 NPU distinction and the separate LiteRT-LM GPU proposal.

---

# Build 1.0.13-npu-sm8850+13 — summary continuation

Final summaries reserve 2,048 output tokens (previously 1,024), with automatic
continuation in the same KV state up to the validated 4,096-token total context.
Encrypted draft checkpoints retain partial final responses without replacing
completed summaries. Audio, refinement and document summaries use this path. A hard
context limit still requires regeneration; drafts do not restore native KV state.

Validation on S26 Ultra SM-S948U / SM8850, September 24:
- 58 Flutter regression tests pass; analyzer reports 12 existing info diagnostics.
- Synthetic native continuation test passes: a 1-token soft cutoff produces
  exactly the same complete answer as the ordinary 128-token request.
- A longer response crosses the old 1,024-token cutoff and completes normally
  (1,891 output characters); native logs confirm same-KV continuation at token 1,024.
- Deliberately filling the context raises the expected error; all 529 emitted
  characters survive encrypted database close/reopen. Repeated checkpoints
  replace one draft row, and successful cleanup removes it.
- A subsequent normal request succeeds after the hard context limit.
- Synthetic harness uses an isolated temporary database, not the user vault.
- The first normal-app retry of the 75,026-character document continued past
  multiple 768-token section cutoffs, but exposed a separate condensation failure
  after roughly 29 minutes. The final implementation restores the previous
  3,072-token section capacity independently of the final response allowance,
  asks later passes to merge/prioritize rather than repeat detailed notes, and
  checks the result of the sixth pass before rejecting it.
- The corrected normal app then summarized that same 75,026-character document
  successfully in under five minutes (started around 12:05:32, success observed
  before 12:10). Force-stop/reopen confirmed the document card reports
  **Summary saved** and the summary remains visible without an error or draft.
- Original USB stay-awake setting restored after testing; existing files preserved.
- Version 13 installed with `adb install -r`; normal Files screen shows both existing files.
- Normal profile APK rebuilt after `flutter clean`, explicit `lib/main.dart`;
  `scripts/verify_npu_apk.py` passes Dart/native build and model identity checks.

Device harness: `integration_test/summary_continuation_test.dart`.
Earlier build reports below remain historical.

---

# Build 1.0.12-npu-sm8850+12 — PDF and Word imports

See [document import validation](DOCUMENT_IMPORT.md) for the new feature.
54 regression tests pass; PDF/DOCX native extraction and NPU checks pass on S26.
Both import paths and saved summaries were verified in the normal app. Existing
appointment data is preserved. Earlier build reports below remain historical.

---

# September 24 repair — normal app build 1.0.11-npu-sm8850+11

The September 23 standalone and debug-harness NPU checks passed, but the normal
profile APK shipped stale Flutter AOT code paired with the new native backend.
On September 24, the 14,887-character imported recording reached the native
model-size guard with the wrong model selected. Logs rejected the model before
NPU initialization; this was **not an out-of-memory exception**. The old UI
incorrectly described it as insufficient free memory.

The correct 2,620,370,976-byte GGUF was already present with app ownership.
A clean, explicit `lib/main.dart` profile rebuild now embeds the matching GGUF
filename and build identity in both Flutter AOT and Android DEX; the new
`scripts/verify_npu_apk.py` checks this before installation. Dart also checks the
native profile at load time. Missing/unreadable/incomplete model errors now
identify the actual file problem instead of suggesting other apps be closed.

Installed by `adb install -r`, preserving recordings, transcripts, model files,
and settings. All **50 Flutter tests passed**, including mismatch rejection.

Normal-app verification on the user's existing imported recording:
- Input: 14,887 characters; no transcript content copied into this report.
- NPU: Hexagon v81, HTP0 ready at 10:28:00 local.
- Summary: 433 streamed pieces, 2,287 characters, 55.394 seconds total,
  no output-cap error, parsed on attempt 1 and saved at 10:28:51.
- UI: generated summary visible; Generate AI Summary action replaced by summary.
- Original recording and transcript preserved.

The prior report below is retained as historical evidence; its debug-harness
results must not be treated as proof that the old normal profile APK worked.

---

# S26 NPU app validation — 2026-09-23

Current build: **1.0.10-npu-sm8850+10**, development package `org.krak_en.voice.dev`.
Device: Samsung Galaxy S26 Ultra SM-S948U, Qualcomm SM8850, Android API 36,
12 GB nominal RAM. See [release policy](RELEASE_DEVICE_POLICY.md) for exact pins
and store restrictions. Earlier GPU results below are historical.

## Verified inside the Android app sandbox

The integrated JNI backend opened the vendor Hexagon **v81** FastRPC session,
selected **HTP0**, assigned 36/36 model layers for acceleration, and generated
correct text. This is NPU-accelerated inference with CPU host/individual-op work,
not a claim of exclusively NPU execution. No local HTTP test server is used by
the app. Model SHA-256 was verified before native loading.

Expanded non-destructive device harness passed all assertions:

| Check | Result |
| --- | --- |
| Load, including SHA-256 | 5.401 s |
| Paris | 0.113 s first text; 0.530 s total |
| Long meeting: $42,750 / Maya / October 16 | 0.796 s first text; 3.121 s total |
| Repeated request: 17 + 25 = 42 | 0.107 s first text; 0.790 s total |
| Oversized prompt rejection and recovery | Pass |
| Output cap rejection and recovery | Pass; incomplete output errors |
| Cancel after first token, then new request | Pass |
| Corrected facts: rejected proposal vs $28,500 / Omar / March 22 | Pass |
| French output without broken UTF-8 | Pass |
| Transcript exceeding context: condense two sections, retain final facts | Pass |
| Unload, fresh checksum/load, generate again | Pass |

Measurements are single-run **debug harness** observations, not sustained or
production-signed benchmarks. The harness only reads model files; it never
opens or deletes the user's vault. Installation used `adb install -r`.

48 Flutter regression tests and 2 Android hardware-policy tests passed.
Analyzer: no errors or warnings; 12 pre-existing informational notices.
Evidence: `spike/s26_npu_probe/repair/app-integration-evidence.log`.

## Installed artifact

The normal optimized **profile** app (not the test harness) was reinstalled with
`adb install -r` and launched successfully. Version name
`1.0.10-npu-sm8850`, version code **10**; model retained at its exact expected
size with app ownership. Final APK contains **ARM64 only** (73.5 MB).

Artifact: `build/app/outputs/flutter-apk/kraken-voice-1.0.10-npu-sm8850-dev-profile.apk`

SHA-256: `094e7249b49e89c1193f868c13d75e148c4aae381fc21c94fac408451369c9f7`

## Remaining public-release requirements

- Supply the valid production signing key; current signing settings reference
  an unavailable Windows path. Development/profile validation is not a signed
  production acceptance test. Release builds no longer fall back to debug signing.
- Apply Play Console device exclusions. The initial catalog should include only
  tested SM-S948U/SM8850 variants; the app's SM8850 gate does not hide listings.
- SM8750 and newer unvalidated SoCs remain disabled pending their own validation.
- Verify real recording → transcription → summary, offline startup after model
  download, interruptions/recovery, sharing/exports, sustained heat/memory/battery,
  and representative long meeting accuracy on the signed production build.
- Retain runtime notices and complete model/DSP redistribution checks described
  in the release policy before distribution.

## Historical GPU build and earlier test incident

### Build 1.0.9+9 (superseded)

Device: Samsung SM-S948U, Qualcomm SM8850, Android API 36.
Installed and launched the normal `org.krak_en.voice.dev` app, version 1.0.9,
using an optimized profile build at 12:19 local time. `adb install -r` succeeded;
the restored model remained present. This is not the production-signed build.
Runtime: LiteRT-LM 0.15.0, GPU, 32768-token configured context, no CPU fallback.
Model: existing Gemma 4 E2B `gemma4.litertlm`, 2,588,147,712 bytes.
The model revision was not independently hash-verified against upstream.

## Passing checks

The actual app native inference channel passed the non-destructive inference
test after replacing LiteRT's crashing Flow wrapper with its callback API.
Text extraction now uses typed Content.Text fields; maxTokens is passed through
to the runtime rather than ignored.

| Check | First text | Total |
| --- | ---: | ---: |
| GPU model load | — | 5.916 s |
| Capital of France, correct answer | 0.446 s | 0.648 s |
| 6,462-character meeting prompt, correct $42,750 / Maya / October 16 | 1.806 s | 2.706 s |
| Repeated request, 17 + 25 = 42 | 0.194 s | 0.531 s |

These are single-run debug harness measurements, not sustained throughput or
signed-release benchmarks. The long prompt does not exercise the full 32K window.
Evidence: `/tmp/kraken-s26-gpu-pass.log` on the development Mac.

All 45 Flutter unit/regression tests passed. Two native hardware-policy tests
passed. Flutter analyze reported 12 existing informational notices, no errors
or warnings. The voice-input retention tests now use real temporary files and
an injected transcriber to verify cleanup on success and failure.

## Test incident

The initial `flutter test` device runner uninstalled the development package
during cleanup, resetting its app-scoped data. Production was not uninstalled
or updated. The shared model survived and was copied back into development
storage with app ownership. Subsequent testing used manual `adb install -r`
and launch to preserve data. Do not run the automatic runner on a populated app.

## Release blockers / remaining verification

- Production signing configuration references a Windows keystore path; a valid
  Mac keystore path is still needed for a signed production install/update.
- Play Console device restrictions have not been applied. Follow
  RELEASE_DEVICE_POLICY.md; an app-side guard does not restrict store visibility.
- SM8750, the proposed minimum, has not been tested in this session.
- Verify real recording → transcription → summary, airplane-mode operation,
  background/call interruptions, recovery, retention, sharing, and exports.
- Test sustained generation, thermal behavior, and representative maximum-length
  meetings on the production-signed build before rollout.
- GPU is verified here. NPU inference has not been configured or tested.
