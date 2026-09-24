#!/usr/bin/env bash
# Host-side exclusive lock — one probe at a time across ALL devices.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCKFILE="$ROOT/runs/.probe.lock"
mkdir -p "$ROOT/runs"

acquire() {
  local serial=$1 backend=$2
  if [[ -f "$LOCKFILE" ]]; then
    echo "LOCK HELD: $(cat "$LOCKFILE")" >&2
    return 1
  fi
  echo "serial=$serial backend=$backend pid=$$ started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCKFILE"
  echo "Lock acquired for $serial/$backend"
}

release() {
  rm -f "$LOCKFILE"
  echo "Lock released"
}

status() {
  if [[ -f "$LOCKFILE" ]]; then
    echo "LOCKED: $(cat "$LOCKFILE")"
    return 0
  fi
  echo "UNLOCKED"
}

case "${1:-status}" in
  acquire) acquire "${2:?serial}" "${3:?backend}" ;;
  release) release ;;
  status) status ;;
  *) echo "Usage: $0 {acquire|release|status} [serial] [backend]" >&2; exit 1 ;;
esac
