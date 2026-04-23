# Kraken Security Protocol

> **Note on terminology:** The code refers to data containers as "Workspaces" (developer term). Users see them as "Libraries" (user-facing term). Both terms refer to the same underlying system. The security rules for "Workspaces" and "Libraries" are identical. This document may use both terms interchangeably.

Kraken Hub enforces strict privacy and security guarantees for all hosted spokes and kernel services. 

## Core Tenets
1.  **Zero-Cloud Execution:** All features, including AI inference and voice transcription, must operate entirely on-device. No data leaves the device.
2.  **Strict Boundary Separation:** Spokes operate in isolated sandboxes and cannot access external APIs or the device filesystem directly. They must use the `SpokeContext` to read/write specific data or invoke kernel services.
3.  **Encrypted Persistence:** All saved data via the VaultService is encrypted at rest using SQLCipher.

## Voice Input Service Security Policy
The `VoiceInputService` is a kernel-level module that provides audio-to-text transcription to spokes. To ensure audio privacy:
*   **Input Only:** The service is strictly for converting audio to text. There is no Text-to-Speech (TTS) capability to prevent the system from mimicking user voices.
*   **Zero Retention Guarantee:** Any audio recorded to the device filesystem for transcription MUST be deleted immediately upon transcription completion, failure, or user cancellation. This is enforced programmatically via strict `try/finally` blocks within the `FasterWhisperVoiceInput` implementation.
*   **No Background Listening:** The microphone is only active when a Spoke explicitly invokes a capture event (e.g., Push-to-Talk).
*   **Global Kill Switch:** The user has ultimate control over the microphone via a global "Voice Input" toggle in the Shell Settings. When disabled, the `VoiceInputService` instantly rejects any transcription requests with a `notImplemented` or `permissionDenied` error.
