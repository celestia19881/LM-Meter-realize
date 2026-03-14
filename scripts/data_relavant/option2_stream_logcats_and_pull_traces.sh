#!/usr/bin/env bash
# =============================================================================
# option2_stream_logcats_and_pull_traces.sh
#
# Collects both phase-level and kernel-level latency data from a connected
# Android device running LM-Meter (MLC LLM runtime).
#
# This script:
#   1. Removes stale trace_*.json files from the device.
#   2. Clears logcat buffers for a clean run.
#   3. Streams runtime logs (TVM_RUNTIME, MLC_Profile, MLC_EVENT tags) and
#      saves them as tvm_mlc.log on the host machine.
#   4. Waits for the user to run the LLM inference on the device.
#   5. Pulls all trace_*.json files from the device.
#   6. Organises every artefact under a timestamped output directory.
#
# Usage:
#   chmod +x scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh
#   bash scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh [OPTIONS]
#
# Options:
#   -o DIR   Output base directory  (default: ./output)
#   -d DEV   ADB device serial      (default: first device returned by adb devices)
#   -t DIR   On-device trace path   (default: /data/local/tmp)
#   -h       Show this help message
# =============================================================================

set -euo pipefail

# ─────────────────────────── defaults ──────────────────────────────────────
OUTPUT_BASE="./output"
DEVICE_SERIAL=""
DEVICE_TRACE_DIR="/data/local/tmp"
LOG_TAGS="TVM_RUNTIME:V MLC_Profile:V MLC_EVENT:V *:S"

# ─────────────────────────── helpers ───────────────────────────────────────
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,2\}//' | sed '/^!/d'
  exit 0
}

# ADB wrapper that forwards the device serial when specified.
adb_cmd() {
  if [[ -n "$DEVICE_SERIAL" ]]; then
    adb -s "$DEVICE_SERIAL" "$@"
  else
    adb "$@"
  fi
}

# ─────────────────────────── argument parsing ───────────────────────────────
while getopts ":o:d:t:h" opt; do
  case $opt in
    o) OUTPUT_BASE="$OPTARG" ;;
    d) DEVICE_SERIAL="$OPTARG" ;;
    t) DEVICE_TRACE_DIR="$OPTARG" ;;
    h) usage ;;
    *) err "Unknown option: -$OPTARG. Use -h for help." ;;
  esac
done

# ─────────────────────────── pre-flight checks ──────────────────────────────
command -v adb &>/dev/null || err "'adb' not found. Install Android platform-tools."

log "Checking ADB connection …"
DEVICES=$(adb devices 2>/dev/null | tail -n +2 | grep -v '^$' || true)
if [[ -z "$DEVICES" ]]; then
  err "No Android device detected. Connect a device and enable USB Debugging."
fi
log "Connected devices:\n$DEVICES"

if [[ -n "$DEVICE_SERIAL" ]]; then
  log "Using device: $DEVICE_SERIAL"
fi

# ─────────────────────────── set up output directory ───────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXPERIMENT_DIR="$OUTPUT_BASE/option2_${TIMESTAMP}"
TRACES_DIR="$EXPERIMENT_DIR/traces"
mkdir -p "$TRACES_DIR"
log "Output directory: $EXPERIMENT_DIR"

LOG_FILE="$EXPERIMENT_DIR/tvm_mlc.log"

# ─────────────────────────── 1. clean old traces on device ─────────────────
log "Removing old trace files on device …"
adb_cmd shell "rm -f $DEVICE_TRACE_DIR/trace_*.json" 2>/dev/null || true
ok "Old traces removed."

# ─────────────────────────── 2. clear logcat buffers ───────────────────────
log "Clearing logcat buffers …"
adb_cmd logcat -c
ok "Logcat buffers cleared."

# ─────────────────────────── 3. start streaming logcat ─────────────────────
log "Streaming runtime logs → $LOG_FILE"
log "(Start the LLM inference on your Android device now.)"
log "(Press Ctrl-C when inference is complete.)"

# Stream logcat in background, save to file
adb_cmd logcat $LOG_TAGS > "$LOG_FILE" &
LOGCAT_PID=$!

# Trap Ctrl-C to gracefully stop logcat streaming
cleanup() {
  log ""
  log "Stopping logcat stream (PID $LOGCAT_PID) …"
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
  ok "Logcat stream stopped. Log saved to $LOG_FILE"
  pull_traces
  print_summary
}
trap cleanup INT TERM

# Wait for user to trigger inference and press Ctrl-C
wait "$LOGCAT_PID" || true

# ─────────────────────────── 4. pull trace files ───────────────────────────
pull_traces() {
  log "Pulling trace_*.json from device ($DEVICE_TRACE_DIR) …"
  TRACE_COUNT=0
  while IFS= read -r remote_path; do
    [[ -z "$remote_path" ]] && continue
    filename=$(basename "$remote_path")
    adb_cmd pull "$remote_path" "$TRACES_DIR/$filename" 2>/dev/null && \
      TRACE_COUNT=$((TRACE_COUNT + 1)) || \
      warn "Could not pull $remote_path"
  done < <(adb_cmd shell "ls $DEVICE_TRACE_DIR/trace_*.json 2>/dev/null" || true)

  if [[ $TRACE_COUNT -eq 0 ]]; then
    warn "No trace files found on device. Make sure kernel-level profiling is enabled in the app."
  else
    ok "Pulled $TRACE_COUNT trace file(s) to $TRACES_DIR"
  fi
}

# ─────────────────────────── 5. print summary ──────────────────────────────
print_summary() {
  echo ""
  log "=== Collection complete ==="
  log "Experiment directory : $EXPERIMENT_DIR"
  log "Log file             : $LOG_FILE"
  log "Trace files          : $TRACES_DIR/"
  log ""
  log "Next steps:"
  log "  Analyse results with:  jupyter lab test/quick_start.ipynb"
  log "  See post-processing guide: docs/logcat-post-processing.md"
}
