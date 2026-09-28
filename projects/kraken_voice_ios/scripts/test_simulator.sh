#!/bin/sh
# Supply a booted Apple Silicon simulator UUID (xcrun simctl list devices).
set -eu
if [ "$#" -ne 1 ]; then
  echo 'Usage: ./scripts/test_simulator.sh SIMULATOR_UUID' >&2
  exit 2
fi
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/stage.sh"
cd "${KRAKEN_IOS_STAGE:-/private/tmp/kraken_voice_ios_build}"
flutter pub get
# Install before granting privacy access: uninstalling a test app resets TCC.
if [ ! -d build/ios/iphonesimulator/Runner.app ]; then
  flutter build ios --simulator --debug --no-pub -t integration_test/ios_recording_test.dart
fi
xcrun simctl install "$1" build/ios/iphonesimulator/Runner.app
xcrun simctl privacy "$1" grant microphone org.krak-en.voice.ios
# Run on the selected simulator and retain its microphone permission afterward.
flutter test --no-pub --no-uninstall integration_test/ios_recording_test.dart -d "$1"
