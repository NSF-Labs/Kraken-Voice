#!/usr/bin/env python3
"""Fetch the pinned Android runtime (not the model), checking every SHA-256.
Run before Flutter builds. --verify performs an offline build-time check.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'android/app/src/main/cpp/runtime-artifacts.json'
TARGET = ROOT / 'android/app/src/main/jniLibs/arm64-v8a'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--cache', type=Path, help='Optional existing llama.cpp/lib directory')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    TARGET.mkdir(parents=True, exist_ok=True)
    for artifact in manifest['files']:
        target = TARGET / Path(artifact['path']).name
        def valid():
            return (target.exists() and target.stat().st_size == artifact['size']
                    and hashlib.sha256(target.read_bytes()).hexdigest() == artifact['sha256'])
        if valid():
            continue
        if args.verify:
            raise SystemExit(f'{target.name} missing or corrupt. Run python3 scripts/prepare_hexagon_runtime.py')
        cached = args.cache / target.name if args.cache else None
        partial = target.with_suffix('.part')
        try:
            if cached and cached.exists():
                partial.write_bytes(cached.read_bytes())
            else:
                url = f"https://huggingface.co/{manifest['repo']}/resolve/{manifest['revision']}/{artifact['path']}"
                with urllib.request.urlopen(url, timeout=60) as response:
                    partial.write_bytes(response.read())
            if partial.stat().st_size != artifact['size'] or hashlib.sha256(partial.read_bytes()).hexdigest() != artifact['sha256']:
                raise RuntimeError(f'Checksum mismatch for {target.name}')
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
    print(f"Verified pinned Hexagon runtime ({len(manifest['files'])} libraries).")

if __name__ == '__main__':
    main()
