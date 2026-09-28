#!/bin/sh
# Build only. Never books or submits a Firebase test.
set -eu
cd "$(dirname "$0")/.."
python3 scripts/prepare_hexagon_runtime.py --verify
flutter clean
flutter build apk --debug --flavor qualification --target-platform android-arm64 -t lib/main_qualification.dart
cd android
./gradlew :app:assembleQualificationDebugAndroidTest -Ptarget=lib/main_qualification.dart -Ptarget-platform=android-arm64
