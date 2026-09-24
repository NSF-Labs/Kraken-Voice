# Internal hardware qualification

## Validation on September 24, 2026

- 66 Flutter tests passed; native routing tests passed. Static analysis has the
  same 12 existing informational findings.
- S24 GPU quick test passed (18.3 s overall; 7.6 s load including checksum).
- S24 GPU ten-minute soak passed: 618.8 s including setup, 335 measured responses,
  maximum reported thermal status 0, sampled peak PSS 3,117 MiB. Native decode
  measurements ranged approximately 19.0–37.8 tokens/s across this synthetic run;
  these are not a long-document throughput guarantee.
- S26 NPU quick test passed (9.4 s overall; 3.9 s load including checksum).
- On-screen Cancel saved a cancelled report; a subsequent S24 quick test in the
  same process passed. The final internal APK is installed on both physical phones.
- API 36 ARM64 emulator: document compatibility passed; an explicit GPU AI
  request was rejected with AI marked not tested. Interrupted-checkpoint recovery
  passed. The ordinary production flavor still rejects this emulator.
- **S26 NPU sustained test did not pass:** stopped at Android severe thermal
  status 3 after approximately 360.7 seconds overall (about 350 seconds into the
  repeated-inference phase). 275 measured responses completed before stopping;
  battery temperature last sampled at 42.4 °C. This is not SoC temperature.
  It started plugged in, at thermal status 0 and battery temperature 32.3 °C.
  The report was saved and the model unloaded. Realistic long-summary thermal
  acceptance remains open; do not treat this phone/runtime as soak-qualified.

The separate production-profile APK built and passed the unified artifact
verifier; it was tested on the emulator without replacing either user's normal
phone app. No remote lab sessions or Play uploads were performed.

## Usage

Build with `sh scripts/build_qualification.sh`. The separate ARM64 app is
**Krak-EN Hardware Test**, package `org.krak_en.voice.qualification`.
It does not open the normal app's vault or replace its installation. The
qualification entry point is not referenced by the production entry point, and
the native diagnostics/switching channel is registered only for this flavor.
Normal production model/chipset eligibility remains unchanged.

## Screen

- **App Compatibility Test**: synthetic PDF/DOCX extraction and sandbox I/O.
  Available on physical devices and ARM64 emulators, without downloading weights.
  This does not yet automate the normal app's permissions, navigation, background
  download or lifecycle test matrix; use the existing app integration tests too.
- **Quick AI Test**: checksum-verified model loading, summary fact checks,
  cancellation followed by a new request, unload/reload and another fact check.
- **10-Minute Stress Test**: quick checks followed by at least ten minutes of
  repeated synthetic summaries; each response is checked. It stops on failed
  output or severe Android thermal status. This is a repeated short-prompt soak,
  not a ten-minute transcript or long-context accuracy benchmark.
- **Cancel** waits for native work to finish safely. A model load cannot be
  forcibly interrupted; cancellation is observed after it returns. Generation
  has a 90-second no-event timeout. A native hang can still require stopping the
  internal app via ADB; it must not be recorded as a pass.
- **Export JSON Report** shares the saved local report. No automatic uploads.
  Reports contain synthetic outputs and hardware/firmware metadata, not recordings,
  account data or device serials.

GPU candidates: SM8650, SM8750 and SM8850. NPU candidates: SM8750/v79 and
SM8850/v81. Only the qualification flavor may bypass exact model/manufacturer
restrictions within these chipset families. Other chipsets get compatibility-only
tests. Qualification does not automatically modify the public allowlist.
Selecting a different backend unloads the old engine and selects its pinned model.
Emulator detection uses standard build-property heuristics, not attestation; an
emulator report is never sufficient evidence to qualify physical hardware.

## Measurements and limits

Reports identify app build, test-suite version, model URL/checksum, runtime,
device model, firmware, requested backend and initialization evidence. GPU
reports include native decode token metrics where supplied by LiteRT-LM. NPU
token throughput is **unavailable** in this first version; measured character
throughput is labeled separately and never presented as tokens/second.

Native GPU initialization requires explicit `Backend.GPU`; NPU initialization
requires HTP0. Driver mappings supplement this evidence. Neither proves every
operation is accelerated: CPU-only fallback is disabled, while host work and
individual CPU operations can remain. There is no claim of zero CPU usage.

Memory samples are process PSS once per second, not a precise peak or full GPU
allocation. Thermal status and battery temperature are recorded; battery
temperature is not SoC temperature. Plugged-in state is included because remote
lab power/cooling can differ from normal handheld use. Short-run correctness
assertions check expected facts but do not replace a broader quality evaluation.

Checkpoints are written atomically before phases and repeated inference. A process
ending mid-test leaves a `running` checkpoint; reopening marks it `interrupted`,
without claiming whether the cause was a crash, force-stop or system termination.
Reports are labeled test passed/failed/cancelled/interrupted; never certified.
The latest report is overwritten by the next run, so export or collect each run.

## Agent-driven execution

Install the APK with `adb -s SERIAL install -r .../app-qualification-profile.apk`.
Open it once. Download the selected model in the screen, or stage the matching
checksum-pinned file under:

`/sdcard/Android/data/org.krak_en.voice.qualification/files/models/`

GPU filename: `gemma4-e2b-gpu.litertlm`; NPU filename: `gemma4-e2b-w4.gguf`.
Model downloads are separate from the APK and can take a substantial part of a
short remote-device session. Existing normal-app models are not copied automatically.

```sh
python3 scripts/run_qualification.py --serial SERIAL --mode compatibility --output /tmp/compatibility.json
python3 scripts/run_qualification.py --serial SERIAL --mode quick --backend GPU --output /tmp/gpu-quick.json
python3 scripts/run_qualification.py --serial SERIAL --mode stress --backend NPU --output /tmp/npu-stress.json
```

The runner restarts **only the internal app**, waits for the new report, prints
phase progress and exits nonzero for failures or timeouts. It reads the phone's
clock to avoid confusing a previous report with this run. It works with ADB
serials for USB, emulators and streamed devices. It does not reserve cloud devices
or spend cloud credits on its own. Exported reports should be reviewed before
adding a device to the production allowlist.

## Android Device Streaming

Android Studio is installed on this Mac. Google requires Android Studio for
interactive reservation/authentication; after reservation, agents can use the
ADB connection with ordinary command-line tools.

1. In Android Studio, open this project's `android` folder.
2. Open **Device Manager**, select its Firebase option, sign in, and select a
   Firebase project with the required access.
3. Use **+ → Select Remote Devices**, choose an available S25 first and connect.
   Enable the Samsung partner lab for that project if prompted. Check the quota
   and any billing before reserving; catalog and firmware availability vary.
4. Once it appears in `adb devices -l`, give the agent its serial and test scope.
   The agent can install, stage weights, run the script and collect reports.
5. Return and erase the remote lab device through Android Studio after collecting
   results. Do not apply that lab cleanup procedure to your own USB phones.

Official workflow: https://developer.android.com/studio/run/android-device-streaming

Start with one remote S25 quick test, then the ten-minute soak. Reuse the session
to compare GPU/NPU before testing additional firmware/model variants. Keep cloud
usage within the session/budget you reserve. Broader automated matrices can be
added through Firebase Test Lab after interactive tests establish compatibility.
