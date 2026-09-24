#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/prepare_hexagon_runtime.py
flutter clean
flutter build apk --profile --flavor qualification --target-platform android-arm64 -t lib/main_qualification.dart
python3 scripts/verify_unified_artifact.py build/app/outputs/flutter-apk/app-qualification-profile.apk
python3 scripts/verify_qualification_apk.py build/app/outputs/flutter-apk/app-qualification-profile.apk
