#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'Usage: ./scripts/install_device.sh DEVICE_UDID' >&2
  exit 2
fi
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/stage.sh"
cd "${KRAKEN_IOS_STAGE:-/private/tmp/kraken_voice_ios_build}"
flutter pub get
flutter build ios --release --no-pub --no-codesign --config-only -t lib/main.dart
(cd ios && pod install)
# Provision for this device, rather than reusing an unrelated cached profile.
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -clonedSourcePackagesDirPath build/ios/SourcePackages \
  -configuration Release -destination "id=$1" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=ZVCZM72MN3 "BUILD_DIR=$PWD/build/ios"
xcrun devicectl device install app --device "$1" build/ios/Release-iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing --device "$1" org.krak-en.voice.ios
