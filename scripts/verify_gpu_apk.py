#!/usr/bin/env python3
"""Verify the normal S24 GPU profile/release APK before installing it."""
import re
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    names = apk.namelist()
    abis = {n.split('/')[1] for n in names if n.startswith('lib/')}
    if abis != {'arm64-v8a'}:
        raise SystemExit(f'Unexpected ABIs: {abis}')
    aot = apk.read('lib/arm64-v8a/libapp.so')
    dex = b''.join(apk.read(n) for n in names if re.fullmatch(r'classes\d*\.dex', n))
    for value in ('1.0.15-gpu-sm8650+15', 'gemma4-e2b-gpu.litertlm'):
        if not any(value.encode(enc) in aot for enc in ('utf-8', 'utf-16-le')):
            raise SystemExit(f'Incompatible Flutter AOT: missing {value}. Clean and rebuild.')
        if value.encode() not in dex:
            raise SystemExit(f'Incompatible native backend: missing {value}.')
    if 'lib/arm64-v8a/liblitertlm_jni.so' not in names:
        raise SystemExit('Missing LiteRT-LM runtime')
    if any(re.search(r'/lib(?:ggml[^/]*|llama|kraken_npu)\.so$', n) for n in names):
        raise SystemExit('Unexpected NPU runtime in GPU APK')
print('PASS: ARM64 GPU APK, matching Dart/native build 15 and dedicated GPU model.')
