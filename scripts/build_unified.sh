#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/prepare_hexagon_runtime.py
flutter clean
if [ "${1:-profile}" = "bundle" ]; then
  flutter build appbundle --release --flavor prod --target-platform android-arm64 -t lib/main.dart
  python3 scripts/verify_unified_artifact.py build/app/outputs/bundle/prodRelease/app-prod-release.aab
else
  flutter build apk --profile --flavor dev --target-platform android-arm64 -t lib/main.dart
  python3 scripts/verify_unified_artifact.py build/app/outputs/flutter-apk/app-dev-profile.apk
fi
