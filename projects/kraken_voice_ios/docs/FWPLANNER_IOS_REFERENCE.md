# Existing FWPlanner iOS Gemma implementation

Located on this Mac at `/Users/zebulon/Code/fwplanner` on 2026-09-27.
The similarly named Google Drive project directory contains only old build output.
No physical iPad was connected when inspected; the installed iPad build has not
been matched to this checkout.

- Native bridge: `ios/Runner/InferencePlugin.swift`
- Registration: `ios/Runner/SceneDelegate.swift`
- Runtime: Gemma4Swift + MLX, Swift package
  `https://github.com/VincentGourbin/gemma-4-swift-mlx`, pinned to
  `c6f8ab5820379898b1d437e8e5c463f376672613`
- Model: `mlx-community/gemma-4-e2b-it-4bit`, a model directory rather than the
  Android LiteRT/GGUF artifact.
- Native downloader: `Gemma4ModelDownloader.download(.e2b4bit)`; bridge estimates
  approximately 3.4 GB. Persistent cache: Documents/models.
- Pipeline: `Gemma4Pipeline.load(from:multimodal:false)` and `pipeline.chat`.
- Memory errors: native MLX work is wrapped in `withError`.
- iOS deployment target: 17.0 in the FWPlanner Podfile.
- Input budget notes: `docs/long-input-summarization-phase1.md` and
  `lib/services/ai/mlx_token_budget.dart`.

Porting still needs Kraken channel mapping, token counting/budget compatibility,
model download UI with progress and cancellation, a readiness check for a full
model directory, and physical-device testing. The existing FWPlanner bridge
returns a complete response on the stream rather than streaming every token.
The newer shared `kraken_gemma_runtime` Flutter dependency in FWPlanner declares
only an Android plugin, so it cannot by itself provide the iOS backend.

FWPlanner source was inspected read-only; no files there were modified.

## Update — 2026-09-28

Kraken's Gemma bridge is now integrated and has passed a synthetic summary on the
physical iPhone 15 Pro Max. The vendored runtime under `ios/Gemma4Swift` includes
fixes for E2B shared K/V layers and the quantized per-layer projection, plus pinned
runtime/model revisions. See `KRAKEN_PATCH.md` there and `IOS_DEVICE_TESTING.md`.
The original FWPlanner checkout was not modified. Gemma is disabled on the
4 GB iPhone 11; bundled Whisper transcription passed there.
