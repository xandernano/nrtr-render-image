#!/usr/bin/env bash
# One-command GPU render for the NRTR world engine. Run on the POD.
#
#   ./run.sh                  setup (if needed) + benchmark + render all 4 scenes
#   ./run.sh s1 s10           render only those scenes
#   BENCH_ONLY=1 ./run.sh     benchmark only — get the cost number, render nothing
#   SKIP_BENCH=1 ./run.sh     skip the benchmark, render immediately
#   RATE_PER_HR=0.34 ./run.sh pod $/hr used in the benchmark cost extrapolation
#                             (default 0.74 ≈ RunPod Secure 4090; Community ≈ 0.34)
#
# Pass-through flags for build_worlds.py work too: --test, --audit, --force.
# Rendering is resumable: frames already on disk are skipped, so re-running
# after an interruption continues where it stopped.
set -euo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_BIN="${BLENDER_BIN:-$HOME/blender-4.2.3-linux-x64/blender}"
ROOT="$HOME/workspace/video-creation"
OUT="$ROOT/build/world3d"
RATE_PER_HR="${RATE_PER_HR:-0.74}"

ARGS=("$@")
if [ "${#ARGS[@]}" -eq 0 ]; then
  ARGS=(s1 s2 s10 s11)
fi

count_frames() {
  (ls "$1"/f*.png 2>/dev/null || true) | wc -l
}

# ---- 1. setup, if Blender is not installed yet -------------------------
if [ ! -x "$BLENDER_BIN" ]; then
  "$PACK_DIR/setup.sh"
fi

# ---- tree sanity --------------------------------------------------------
if [ ! -f "$ROOT/build/blender/build_worlds.py" ]; then
  echo "NOTE: canonical build tree not found at $ROOT/build/blender/."
  echo "      The wrapper will run the pack's snapshot copy of build_worlds.py."
  echo "      Outputs still land in $OUT — build_worlds.py hardcodes"
  echo "      ROOT=~/workspace/video-creation regardless of where it runs from."
  mkdir -p "$OUT"
fi

render() {
  "$BLENDER_BIN" -b -P "$PACK_DIR/render_gpu.py" -- "$@"
}

# ---- 2. benchmark: time the first BENCH_N new frames of one scene -------
if [ "${SKIP_BENCH:-0}" != "1" ]; then
  BENCH_SCENE="${BENCH_SCENE:-s2}"
  BENCH_N="${BENCH_N:-10}"
  BDIR="$OUT/$BENCH_SCENE"
  mkdir -p "$BDIR"
  before="$(count_frames "$BDIR")"
  echo "== BENCHMARK: timing $BENCH_N new frames of $BENCH_SCENE =="
  echo "   (benchmark frames are real production frames and are kept;"
  echo "    the audit stills render first, so treat this as an upper bound)"
  start="$(date +%s)"
  # setsid puts Blender in its own process group so the kill below takes
  # the whole group. Killing only the wrapper shell orphans Blender,
  # which keeps rendering (caught live on the 2026-11-02 benchmark run).
  setsid "$BLENDER_BIN" -b -P "$PACK_DIR/render_gpu.py" -- "$BENCH_SCENE" > "$PACK_DIR/benchmark.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    now="$(count_frames "$BDIR")"
    if [ $((now - before)) -ge "$BENCH_N" ]; then
      break
    fi
    sleep 2
  done
  end="$(date +%s)"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  # The newest frame may be half-written; delete it so the full run
  # re-renders it cleanly instead of skipping it.
  newest="$( (ls -t "$BDIR"/f*.png 2>/dev/null || true) | head -1 )"
  if [ -n "$newest" ]; then
    rm -f "$newest"
  fi
  got=$(( $(count_frames "$BDIR") - before ))
  elapsed=$(( end - start ))
  if [ "$elapsed" -lt 1 ]; then elapsed=1; fi
  if [ "$got" -gt 0 ]; then
    python3 - "$got" "$elapsed" "$RATE_PER_HR" <<'PY'
import sys
frames, elapsed, rate = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
spf = elapsed / frames
print(f"BENCHMARK RESULT: {frames} frames in {elapsed}s -> {spf:.2f} s/frame")
for total in (450, 500, 550):
    secs = spf * total
    print(f"  full 4-scene batch at {total} frames: {secs / 60:.1f} min, "
          f"~${secs / 3600 * rate:.2f} at ${rate}/hr")
print(f"  throughput: {3600 / spf:.0f} frames/hour")
print("  shorts/hour = 3600 / (frames in the short x s/frame)")
PY
  else
    echo "BENCHMARK produced no new frames — see $PACK_DIR/benchmark.log" >&2
    if [ "${BENCH_ONLY:-0}" = "1" ]; then exit 1; fi
  fi
  if [ "${BENCH_ONLY:-0}" = "1" ]; then
    echo "BENCH_ONLY=1 — stopping before the full render. No further billing risk from this script."
    exit 0
  fi
fi

# ---- 3. full render -------------------------------------------------------
echo "== FULL RENDER: ${ARGS[*]} =="
render "${ARGS[@]}" 2>&1 | tee "$PACK_DIR/render.log"
echo "DONE. Frames + WORLD_AUDIT reports are in $OUT"
echo "Download that folder back home, verify it, then TERMINATE the pod to stop billing."
