# Mission Brief: Add VoiceInputService to Kraken Kernel

## Objective

Add a new kernel service, `VoiceInputService`, that lets any spoke accept voice input from the user and receive transcribed text. This is an **input-only** service: audio in, text out. No text-to-speech, no AI-speaks-back functionality. Spokes display LLM responses as text on screen; the platform screen reader handles accessibility.

This service composes the existing `AudioService` (microphone capture via platform channel) and Faster-Whisper (on-device STT). It does not touch `LocalInferenceService` — the LLM interaction happens in the spoke, with the transcribed text as input.

## Execution Rules (Read First)

- Follow all rules in `KRAKEN_HUB_IMPLEMENTATION_PLAN.md` §0 Execution Rules and §2.1 Non-Negotiable Coding Rules.
- This work lives entirely in `/lib/kernel/voice_input/`. No changes to spokes, no changes to shell beyond the settings toggle described below.
- Produce a Phase Completion Checklist at the end of this mission per the standing phase-gate rule.
- Do not add any TTS dependency, any cloud ASR dependency, or any network call. Voice input is 100% on-device, consistent with the existing security protocol.
- Stub-first: build against the existing audio stub channel before exercising the real Faster-Whisper integration.

## Phase 1: Service Interface and Kernel Wiring

### 1.1 Create the service interface

Create `/lib/kernel/voice_input/voice_input_service.dart` with this abstract contract:

```dart
abstract class VoiceInputService {
  /// Push-to-talk: capture one utterance, transcribe, return text.
  /// Audio is deleted immediately after transcription completes.
  /// Throws VoiceInputError on mic-permission-denied, hardware-failure,
  /// transcription-failure, or cancellation.
  Future<String> transcribeUtterance({Duration? maxDuration});

  /// Continuous capture with live partial transcriptions.
  /// Emits TranscriptionPartial events as the user speaks,
  /// TranscriptionFinal when silence is detected or stopLiveTranscription is called.
  /// Audio buffer is deleted as soon as final transcription is emitted.
  Stream<TranscriptionEvent> startLiveTranscription();

  /// Stop an in-flight live transcription. Emits a final event and closes the stream.
  Future<void> stopLiveTranscription();

  /// Cancel any in-flight capture or transcription. No event emitted.
  /// Audio buffer is deleted.
  Future<void> cancel();
}

sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

class TranscriptionPartial extends TranscriptionEvent {
  final String text;
  final double confidence;
  const TranscriptionPartial(this.text, this.confidence);
}

class TranscriptionFinal extends TranscriptionEvent {
  final String text;
  final Duration audioDuration;
  const TranscriptionFinal(this.text, this.audioDuration);
}

class TranscriptionErrorEvent extends TranscriptionEvent {
  final VoiceInputError error;
  const TranscriptionErrorEvent(this.error);
}

enum VoiceInputError {
  micPermissionDenied,
  micHardwareUnavailable,
  transcriptionFailed,
  cancelled,
  notImplemented,
}
```

### 1.2 Register in KernelContext

Add `VoiceInputService voiceInput` to `KernelContext` in `/lib/kernel/context/kernel_context.dart`.
Update the kernel initialization sequence to construct and inject the service.
Spokes access voice input via `kernel.voiceInput` exactly like any other kernel service.

### 1.3 Add a BLoC for UI state

Create `VoiceInputBloc` in `/lib/kernel/voice_input/voice_input_bloc.dart`.
States: `Idle`, `Listening`, `Transcribing`, `Error`.
Events: `StartCapture`, `StopCapture`, `Cancel`.
The BLoC is a thin wrapper around the service, designed for spoke UIs to consume via `BlocBuilder`.

## Phase 2: Implementation

### 2.1 Concrete implementation

Create `/lib/kernel/voice_input/faster_whisper_voice_input.dart` implementing `VoiceInputService`.
Internally this class:
- Calls the existing `AudioService.startRecording` / `stopRecording` methods.
- Passes the resulting audio buffer to `AudioService.transcribe` (Faster-Whisper via platform channel).
- Deletes the audio buffer immediately after transcription completes.
- Returns the transcribed text or throws the appropriate `VoiceInputError`.

### 2.2 Live transcription specifics

For `startLiveTranscription`, use chunked capture: small audio windows (~500ms) passed incrementally to the transcription engine. Emit `TranscriptionPartial` as each chunk returns updated interim text. Emit `TranscriptionFinal` on silence detection or explicit `stopLiveTranscription`.

If Faster-Whisper's native bridge does not currently support streaming chunks, implement a simple fallback: buffer the full utterance and return a single `TranscriptionFinal` when capture ends. Document this limitation in a TODO and the Phase Completion Checklist.

### 2.3 Audio retention policy (strict)

Captured audio MUST be deleted as soon as transcription completes — this includes on success, on error, and on cancellation. No persistent audio buffer. No temp file left on disk. No in-memory reference retained after the service method returns.

Add a static analysis check: any code under `/lib/kernel/voice_input/` that writes audio bytes to disk must call the deletion path in a `finally` block. This is enforced, not trusted.

## Phase 3: Security Protocol Updates

### 3.1 Update `KRAKEN_SECURITY_PROTOCOL.md`

Add a new section:

> ### Voice Input
>
> - All voice input processing happens on-device. Audio is captured via the platform microphone, transcribed via Faster-Whisper locally, and then deleted. Audio never leaves the device.
> - No cloud ASR is used under any circumstance.
> - Audio buffers are deleted immediately after transcription completes — on success, on error, and on cancellation. No persistent audio storage.
> - Spokes cannot retain captured audio. Spokes receive only the transcribed text. If a spoke needs to persist audio (e.g. a future Meeting Notes spoke recording full conversations), that is a distinct capability requiring its own explicit user consent flow and a separate kernel service, not a side effect of `VoiceInputService`.
> - Microphone permission is requested on first use, not at app install. Denial gracefully falls back to text input.

### 3.2 Update `APPROVED_DEPENDENCIES.md`

Confirm no new dependencies are added. This service uses existing `AudioService` and existing Faster-Whisper integration. If any new package is required (e.g. a VAD library for silence detection), add it to the approved list with a one-line network-behavior note ("none — pure local processing").

## Phase 4: Mock Spoke Extension

Extend the existing mock spoke (in `/lib/spokes/mock/`) with a fifth button: **"Test voice input."**

Behavior: tapping the button starts a 5-second push-to-talk capture, transcribes the audio, and logs the result. This exercises the `VoiceInputService` end-to-end and gives integration tests something to run against.

Forbidden: no LLM interaction from the voice test button. The mock spoke's job is to verify the contract, not demonstrate a feature. Audio in, text logged. That's it.

## Phase 5: Shell Settings Addition

Add one settings entry in the shell's settings screen:

**Voice Input**
- Toggle: "Enable voice input across Kraken" (default: on)
- Static text: "Audio is transcribed on your device and deleted immediately. It never leaves Kraken."

When the toggle is off, `VoiceInputService` methods return immediately with `VoiceInputError.notImplemented` and spokes are expected to hide their mic buttons. This is a user-facing kill switch for privacy-conscious enterprise deployments.

Do not build a "choose voice / choose language / fine-tune transcription" settings surface in v1. One toggle. Keep it minimal.

## Phase 6: Tests

### 6.1 Unit tests

- `transcribeUtterance` returns expected text when the audio stub returns canned data.
- `transcribeUtterance` throws `micPermissionDenied` when the audio channel reports permission denied.
- `cancel()` during capture deletes the audio buffer and emits no events.
- Audio deletion happens on every code path (success, error, cancellation) — verified by a spy/mock on the audio service.

### 6.2 Integration tests

- Mock spoke's voice test button: full path from button tap → audio capture → transcription → log output succeeds on the stub channel.
- Disabling voice input in settings causes the service to return `notImplemented` and the mock spoke's mic button to hide (or disable).
- Microphone permission denial path: first invocation requests permission; denial produces the expected error; subsequent invocations do not re-prompt within the session.

### 6.3 Static analysis

Add a lint rule (or equivalent) that fails the build if any file under `/lib/kernel/voice_input/` writes to disk without a corresponding deletion in a `finally` block. This enforces the retention policy.

## Phase 7: Exit Criteria

All must pass on iOS simulator and Android emulator before this mission is considered complete:

1. `VoiceInputService` is present in `KernelContext` and consumable from the mock spoke.
2. Push-to-talk capture returns transcribed text end-to-end on stub audio.
3. Live transcription emits at least one `TranscriptionPartial` event followed by a `TranscriptionFinal` event (or documents a fallback to single-shot per §2.2).
4. Audio buffer deletion verified on success, error, and cancel paths.
5. Microphone permission prompt appears on first use; denial is handled gracefully.
6. Settings toggle disables the service cleanly; spokes observe the disabled state.
7. `KRAKEN_SECURITY_PROTOCOL.md` updated with the Voice Input section.
8. `APPROVED_DEPENDENCIES.md` reviewed; any new package added has a network-behavior note.
9. Mock spoke's fifth button works without modification to any other spoke or kernel service.
10. All tests green. Static analysis green. No new warnings.
11. Phase Completion Checklist produced and committed.

## Out of Scope (Do Not Build)

Stop immediately if you find yourself doing any of these:

- Text-to-speech. Not in this mission, not in v1. Spokes display text responses on screen.
- Cloud ASR fallback. Never. 100% on-device.
- Voice profile or voice preference settings. Not applicable to input-only.
- Language selection UI. Faster-Whisper's auto-detect is sufficient for v1.
- Wake-word detection ("Hey Kraken"). Not in v1.
- Noise cancellation settings. Not in v1.
- A "conversational" service that chains voice input → LLM → voice output. That is specifically the design we rejected. Each spoke independently decides what to do with transcribed text.
- Audio retention for any purpose. If a future spoke needs to persist audio, that is a separate kernel service with separate consent flow, not an extension of this one.

## Execution Order

1. Phase 1 (interface + wiring) — get the contract solid before any implementation.
2. Phase 3 (security protocol) — update documentation alongside the contract so the agent and reviewer are working from the same guarantees.
3. Phase 2 (implementation) against the existing stub audio channel.
4. Phase 4 (mock spoke extension) to validate the contract end-to-end.
5. Phase 5 (shell settings) — small and isolated, do last so UI doesn't drift during earlier work.
6. Phase 6 (tests) — written alongside each phase, not at the end.
7. Phase 7 (exit criteria verification) — final gate.

Stop at the end with a Phase Completion Checklist and wait for human review before moving on to the first real spoke that will consume this service.
