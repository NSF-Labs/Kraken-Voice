#!/usr/bin/env bash
# Throwaway probe orchestration — STRICTLY sequential, one device at a time.
# Requires probe_lock.sh — do not run probes in parallel across devices.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCK="$ROOT/probe_lock.sh"
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
PKG=org.krak_en.spike.accel
ACTIVITY=org.krak_en.spike.AccelProbeActivity
MODEL="/storage/emulated/0/Documents/KrakenModels/gemma4.litertlm"
LOG_DIR="$ROOT/runs/$(date +%Y%m%d_%H%M%S)"
COOL_SEC="${COOL_SEC:-720}"

S26=R3GL40811NP
S24=R5CX104QTAM

mkdir -p "$LOG_DIR"
chmod +x "$LOCK"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/orchestrator.log"; }

if "$LOCK" status | grep -q LOCKED; then
  log "ABORT: probe lock held. Run: $LOCK release"
  exit 1
fi

run_probe() {
  local serial=$1 device_name=$2 backend=$3 short_prompt=${4:-false}
  local tag="${device_name}_${backend}"
  [[ "$short_prompt" == "true" ]] && tag="${tag}_short"

  log "Cooling ${COOL_SEC}s before $tag..."
  sleep "$COOL_SEC"

  "$LOCK" acquire "$serial" "$backend"
  trap '"$LOCK" release' EXIT

  adb -s "$serial" shell dumpsys battery > "$LOG_DIR/${tag}_battery.txt"
  adb -s "$serial" shell am force-stop "$PKG"
  adb -s "$serial" logcat -c
  adb -s "$serial" shell am start -n "$PKG/$ACTIVITY" \
    --es backend "$backend" \
    --es modelPath "$MODEL" \
    --es shortPrompt "$short_prompt"

  log "Started $tag on $serial"
  for ((i=0; i<720; i++)); do
    if adb -s "$serial" logcat -d 2>/dev/null | rg -q '"event":"(probe_complete|init_failure|probe_result)"'; then
      break
    fi
    sleep 5
  done

  adb -s "$serial" logcat -d 2>/dev/null | rg "KRAKEN_ACCEL_PROBE" > "$LOG_DIR/${tag}.logcat"
  "$LOCK" release
  trap - EXIT
  log "Done $tag"
}

log "Building probe APK..."
(cd "$ROOT" && ./gradlew :app:assembleDebug -q)
for S in "$S26" "$S24"; do
  adb -s "$S" install -r "$APK" >/dev/null
  adb -s "$S" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow
done

# One at a time — no parallelism
run_probe "$S26" S26 qnn false
run_probe "$S26" S26 npu false
run_probe "$S26" S26 gpu false
run_probe "$S24" S24 qnn false
run_probe "$S24" S24 npu false
run_probe "$S24" S24 cpu false
run_probe "$S26" S26 cpu false

log "Sequence complete. Logs: $LOG_DIR"
