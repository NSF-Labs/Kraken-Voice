#!/bin/sh
# Compatibility entry point. The unified APK chooses GPU on supported S24 phones.
set -eu
exec sh "$(dirname "$0")/build_unified.sh" "$@"
