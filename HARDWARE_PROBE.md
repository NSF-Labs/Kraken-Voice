# Discovery-only Firebase instrumentation probe

Status: discovery tests submitted with user authorization on September 24, 2026. See FIREBASE_DEVICE_MATRIX.md for current results and quota limitations.

This test runs inside the internal `org.krak_en.voice.qualification` app without
starting an Activity. It does not download models, construct inference engines,
perform inference, or change production device eligibility. The test source is
restricted to `androidTestQualification`; its JNI helper is built only into the
qualification flavor. Do not launch the qualification UI during this test.

## Build

With the Android SDK, Flutter, and Java 17+ configured:

```sh
scripts/build_hardware_probe.sh
```

Artifacts:

- `build/app/outputs/flutter-apk/app-qualification-debug.apk`
- `build/app/outputs/apk/androidTest/qualification/debug/app-qualification-debug-androidTest.apk`

These are debug-signed ARM64 test artifacts, not Play Store release bundles.
The app APK includes the existing runtime libraries but no Gemma model weights.

## Evidence and limits

- Build manufacturer, model, device, hardware, board, SoC manufacturer/model,
  Android release/API and ABIs; total and currently available RAM.
- OpenGL ES vendor, renderer, version and extensions from a temporary ES2 pbuffer
  context, destroyed afterward. This reports the created context, not a benchmark.
- Vulkan Android feature declarations plus loader/instance status and enumerated
  physical devices, IDs, API and driver versions. No logical device or work submitted.
- OpenCL loader status and actual platform/device enumeration, including device
  name, vendor, driver and OpenCL version. No context, kernel or inference created.
- Qualcomm `libcdsprpc.so` and `libQnnHtp.so` loader visibility; packaged Hexagon
  library names. No QNN backend or DSP session is initialized. Missing vendor
  libraries may reflect Android linker restrictions rather than absent silicon.
- Bundled LiteRT-LM 0.17.1 has CPU/GPU/NPU backend options but its inspected Engine
  API exposes no model-free availability enumeration. `availableAccelerators` is
  explicitly null, not a fabricated list. The app uses LiteRT-LM for GPU and a
  separate llama.cpp/ggml-hexagon runtime for NPU.

A passing discovery test means the report was written, not that inference works.
Capability errors are recorded in JSON. Inspect those errors before drawing any
conclusions. A native driver crash can still fail the instrumentation run.
No device serials, recordings or user documents are collected.

## Local execution

Install the two APKs with `adb -s SERIAL install -r APK`, then:

```sh
adb -s SERIAL shell am instrument -w \
  -e class org.krak_en.voice.HardwareProbeTest \
  org.krak_en.voice.qualification.test/androidx.test.runner.AndroidJUnitRunner
adb -s SERIAL pull \
  /sdcard/Android/data/org.krak_en.voice.qualification/files/hardware-probe/hardware.json
```

The report is also logged under `HARDWARE_PROBE`. Numbered chunks share a run UUID;
join their payloads in order to reconstruct JSON. Each new run overwrites the file.
Instrumentation does not require microphone or storage permissions.

## Proposed Firebase matrix — review before submitting

Start with physical `e3q`, `pa3q`, `m1q`, `m2q`. Recheck inventory and supported
Android versions immediately before submission; inventory names alone do not
establish the SoC. Prefer Android 16 across all four for comparison when available.
Use an instrumentation run selecting `org.krak_en.voice.HardwareProbeTest`, a
2-minute timeout, and pull directory:
`/sdcard/Android/data/org.krak_en.voice.qualification/files/hardware-probe`.
The timeout bounds a hung vendor query. No cloud-submit script is included.

Firebase accepts the app APK and its separate instrumentation APK:
https://firebase.google.com/docs/test-lab/android/command-line

Phase 2 remains separate: model initialization, actual accelerator execution,
fallback detection, TTFT/prefill/decode and sustained thermal behavior. Discovery
alone must not expand the public supported-device list.

## Local verification — September 24, 2026

Both connected physical phones passed the final instrumentation APK (`OK (1 test)`):

| Phone | Reported SoC | Actual GLES/OpenCL/Vulkan GPU | Android |
|---|---|---|---|
| S24 Ultra SM-S928U | SM8650 | Adreno 750 | 16 / API 36 |
| S26 Ultra SM-S948U | SM8850 | Adreno 840 | 16 / API 36 |

Both enumerate OpenCL 3.0 devices and Vulkan physical devices. Both load
`libcdsprpc.so`; neither exposes `libQnnHtp.so` to this app. This does not invalidate
the separate ggml-hexagon NPU runtime. Raw reports are in
`spike/hardware_probe/s24-ultra.json` and `spike/hardware_probe/s26-ultra.json`.
No inference was performed. S25 and Firebase S26/S26+ discovery remain pending review
and cloud execution. Prior S26 sustained-inference thermal limits remain unresolved.
