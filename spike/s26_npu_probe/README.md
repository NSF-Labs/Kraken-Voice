# S26 Hexagon NPU probe

Isolated native test; does not install, uninstall, or access either Kraken app.
Calls the QHexRT backend test vtable directly, with no CPU/GPU backend registered.
Uses RunAnywhere's version-matched native headers; this is not an app integration.

- Device: SM-S948U / SM8850 / Hexagon v81.
- Model: `runanywhere/gemma4_e2b_HNPU`, revision
  `c3bc94b2d0064ccdc78d993abe2c9fdb038aed3e`, text manifest `v81/gemma4-e2b.json`.
- Model context: 512 tokens, max output for this probe: 48 tokens.
- Runtime and SDK AARs: `io.github.sanchitmonga22:runanywhere-qhexrt-android:0.20.19`
  and `io.github.sanchitmonga22:runanywhere-sdk:0.20.19` from Maven Central.
- Header source: RunanywhereAI/runanywhere-sdks tag `v0.20.19`.
- NDK: 28.2.13676358; arm64 Android API 31; C++20.
- `include/rac/rac_defaults_generated.h` contains only the five defaults needed
  by the test ABI, transcribed from that tag's `idl/llm_options.proto`.

Host artifacts are staged under `/tmp/kraken-npu-model` and
`/tmp/kraken-npu-runtime`. Large model files and vendor binaries are not committed.
All model LFS files were SHA-256 checked against the pinned Hugging Face metadata.

AAR SHA-256:

- QHexRT: `cc98166d0e3db20d04406bdda151f2914fec92cf7334dba45b4ccdb6a4195317`
- SDK: `bb587dfb2aaa68e73c74427c80940bda31964006f38390c6e32ca3459e6bef20`

Build with `aarch64-linux-android31-clang++ -std=c++20 -O2`, including this
probe's `include/`, the SDK `core/include/` and `engines/qhexrt/include/`.
Link against `rac_backend_qhexrt`, `rac_commons`, and `c++_shared` from the AARs.
Stage the resulting executable and arm64 shared libraries into
`/data/local/tmp/kraken-npu-runtime`, along with the v81 skel from the QHexRT AAR's
`assets/runanywhere/qhexrt/skels/arm64-v8a/` directory.
Stage the verified text model files into `/data/local/tmp/kraken-npu-model`.

Run with that runtime directory in `LD_LIBRARY_PATH`, `ADSP_LIBRARY_PATH`, and
`RUNANYWHERE_QHEXRT_SKEL_DIR`; pass the absolute model manifest path to the probe.
The probe has a 300-second process alarm. Use a fresh process for each cold run.
A zero return code requires all three factual assertions to pass, not just model
initialization. Even a pass does not validate long meetings or an app sandbox.
