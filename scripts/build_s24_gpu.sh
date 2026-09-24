#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
flutter clean
flutter build apk --profile --flavor dev --target-platform android-arm64 \
  --dart-define=KRAKEN_S24_GPU=true \
  --build-name=1.0.15-gpu-sm8650 --build-number=15 -t lib/main.dart
python3 scripts/verify_gpu_apk.py build/app/outputs/flutter-apk/app-dev-profile.apk
