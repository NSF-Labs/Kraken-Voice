#!/bin/sh
# Build locally; publishing is an explicit separate command.
set -eu
cd "$(dirname "$0")/.."
flutter test test/inference test/processing test/data/trial_export_test.dart test/data/recording_safety_test.dart
# Avoid reusing Flutter AOT from a previous flavor/build identity.
flutter clean
flutter build appbundle --release --flavor prod --target-platform android-arm64
python3 scripts/verify_unified_artifact.py build/app/outputs/bundle/prodRelease/app-prod-release.aab
