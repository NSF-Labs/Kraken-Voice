/// Centralized feature flags for gating incomplete features.
///
/// These are compile-time constants so the Dart compiler tree-shakes all
/// gated code out of release builds, resulting in zero runtime cost.
///
/// To re-enable a feature, simply flip the flag to `true`.
library;

/// Speaker diarization (AV2).
///
/// When `false`, all diarization UI surfaces are hidden:
///  • Settings → "AI Models" hides the diarization model row
///  • Settings → "Diarization" section is removed
///  • Onboarding → model download skips diarization models
///  • Transcript screen → speaker detection panel is hidden
///  • Model readiness → diarization is excluded from `allReady`
///
/// The backend plumbing (NemoDiarizer, DB schema, export alignment) is
/// left intact so we can flip this on without code changes.
const bool kDiarizationEnabled = false;
