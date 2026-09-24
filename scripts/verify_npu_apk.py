#!/usr/bin/env python3
"""Verify the normal profile/release APK before installation or distribution.

Catches stale Flutter AOT code paired with the newer native NPU backend.
Usage: python3 scripts/verify_npu_apk.py path/to/app.apk
"""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
profile = (root / 'lib/kernel/inference/model_profile.dart').read_text()
expected = [re.search(rf"static const {key} = '([^']+)'", profile)[1]
            for key in ('npuFilename', 'npuBuild')]
with zipfile.ZipFile(sys.argv[1]) as apk:
    names = apk.namelist()
    abis = {name.split('/')[1] for name in names if name.startswith('lib/')}
    if abis != {'arm64-v8a'}:
        raise SystemExit(f'Unexpected ABIs: {abis}')
    aot = apk.read('lib/arm64-v8a/libapp.so')
    dex = b''.join(apk.read(n) for n in names if re.fullmatch(r'classes\d*\.dex', n))
    for value in expected:
        if not any(value.encode(enc) in aot for enc in ('utf-8', 'utf-16-le')):
            raise SystemExit(f'Stale/incompatible Flutter AOT: missing {value}. Run flutter clean and rebuild.')
        if value.encode() not in dex:
            raise SystemExit(f'Stale/incompatible Android backend: missing {value}.')
    for lib in ('kraken_npu', 'llama', 'ggml-hexagon', 'ggml-htp-v81'):
        if f'lib/arm64-v8a/lib{lib}.so' not in names:
            raise SystemExit(f'Missing NPU runtime: {lib}')
print(f'PASS: ARM64 APK, matching Dart/native {expected[1]}, model {expected[0]}.')
