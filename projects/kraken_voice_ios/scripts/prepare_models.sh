#!/bin/sh
# Reproducible offline Whisper bundle. Large model bytes stay out of Git.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODEL="$ROOT/assets/models/ggml-base.bin"
HASH=60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe
verify() { printf '%s  %s\n' "$HASH" "$1" | shasum -a 256 -c - >/dev/null 2>&1; }
if [ -f "$MODEL" ] && verify "$MODEL"; then exit 0; fi
mkdir -p "$ROOT/assets/models"
curl -fL --retry 3 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin' -o "$MODEL.part"
verify "$MODEL.part"
mv "$MODEL.part" "$MODEL"
