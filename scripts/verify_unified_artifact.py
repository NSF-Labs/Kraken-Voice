#!/usr/bin/env python3
"""Check runtime packaging and matching Dart/native identity in an APK or AAB."""
import re
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = archive.namelist()
    prefix = 'base/' if 'base/manifest/AndroidManifest.xml' in names else ''
    libs = prefix + 'lib/'
    abis = {n[len(libs):].split('/')[0] for n in names if n.startswith(libs)}
    if abis != {'arm64-v8a'}:
        raise SystemExit(f'Unexpected ABIs: {abis}')
    aot = archive.read(libs + 'arm64-v8a/libapp.so')
    dex = b''.join(archive.read(n) for n in names
                   if re.fullmatch(prefix + r'(?:dex/)?classes\d*\.dex', n))
    for value in ('1.0.19+19', 'gemma4-e2b-w4.gguf', 'gemma4-e2b-portable-gpu.litertlm',
                  'gemma4-litert171-opencl-adreno750'):
        if not any(value.encode(enc) in aot for enc in ('utf-8', 'utf-16-le')):
            raise SystemExit(f'Stale Flutter AOT: missing {value}; clean and rebuild')
        if value.encode() not in dex:
            raise SystemExit(f'Native profile mismatch: missing {value}')
    if b'181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c' not in dex:
        raise SystemExit('Missing pinned portable Gemma 4 GPU model checksum')
    for value in ('_applyTranscriptOptions', 'background_summary_jobs', 'No app storage cap'):
        if not any(value.encode(enc) in aot for enc in ('utf-8', 'utf-16-le')):
            raise SystemExit(f'Stale trial AOT: missing {value}; clean and rebuild')
    if b'KrakenProcessingService' not in dex:
        raise SystemExit('Missing Android processing foreground service')
    for name in ('litertlm_jni', 'kraken_npu', 'llama', 'ggml-hexagon',
                 'ggml-htp-v79', 'ggml-htp-v81'):
        if libs + f'arm64-v8a/lib{name}.so' not in names:
            raise SystemExit(f'Missing runtime: {name}')
print('PASS: unified build 19, both model profiles, GPU and v79/v81 NPU, ARM64 only')
