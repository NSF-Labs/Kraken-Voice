#!/usr/bin/env python3
"""Reject stale AOT that lacks internal automation or measurement controls."""
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as apk:
    aot = apk.read('lib/arm64-v8a/libapp.so')
    for value in ('launchOptions', 'Measured responses', 'qualification-status'):
        if not any(value.encode(enc) in aot for enc in ('utf-8', 'utf-16-le')):
            raise SystemExit(f'Stale qualification AOT: missing {value}. Run flutter clean.')
print('PASS: qualification automation and measurement UI present in AOT')
