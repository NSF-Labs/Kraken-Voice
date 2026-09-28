#!/bin/sh
# Google Drive attaches metadata that Apple codesign rejects. Build a clean,
# disposable copy outside cloud storage; edit source in the project directory.
set -eu
SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAGE="${KRAKEN_IOS_STAGE:-/private/tmp/kraken_voice_ios_build}"
if [ "$STAGE" = "$SOURCE" ]; then
  echo 'Staging directory must differ from source.' >&2
  exit 1
fi
"$SOURCE/scripts/prepare_models.sh"
mkdir -p "$STAGE"
rsync -rlt --exclude '.git' --exclude '.dart_tool' --exclude 'build' \
  --exclude 'Pods' --exclude '.symlinks' --exclude 'ephemeral' \
  --exclude '.flutter-plugins*' --exclude 'Generated.xcconfig' \
  --exclude 'flutter_export_environment.sh' --exclude 'xcuserdata' \
  "$SOURCE/" "$STAGE/"
# rsync omits extended attributes; leave cached build dependencies alone.
printf 'Build directory: %s\n' "$STAGE"
