#!/usr/bin/env bash
# Guest-side bounded test with loader and live-process evidence.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
action=${1:?Use kmscube or sdl}
logs=${GRAPHICS_LOG_DIR:-/opt/darkos-graphics/logs}
mkdir -p "$logs"
card=''
for driver in /sys/class/drm/card[0-9]*/device/driver; do
  [[ $(basename "$(readlink -f "$driver")") == virtio_gpu ]] || continue
  candidate=${driver%/device/driver}; candidate=${candidate##*/}
  for status in /sys/class/drm/"$candidate"-*/status; do
    if [[ -f "$status" && $(cat "$status") == connected ]]; then card=/dev/dri/$candidate; break; fi
  done
  [[ -z "$card" ]] || break
done
[[ -n "$card" ]] || { echo 'No connected VirtIO GPU card found' >&2; exit 1; }
echo "DRM device: $card"
case "$action" in
  kmscube) command=(kmscube -D "$card");;
  sdl)
    export SDL_KMSDRM_DEVICE_INDEX=${card##*card}
    command=("$root/demos/sdl-kms/hello" --seconds 30)
    ;;
  *) echo 'Use kmscube or sdl' >&2; exit 2;;
esac
bash "$here/graphics-env.sh" ldd "$(command -v "${command[0]}")" > "$logs/$action.ldd.log"
# kmscube treats readable stdin (including SSH's EOF) as a request to exit.
# Keep a private FIFO open in both directions until the bounded test finishes.
input_dir=$(mktemp -d)
mkfifo "$input_dir/input"
exec 3<> "$input_dir/input"
bash "$here/graphics-env.sh" stdbuf -oL -eL "${command[@]}" <&3 > "$logs/$action.log" 2>&1 &
pid=$!
close_input() { exec 3>&-; rm -f "$input_dir/input"; rmdir "$input_dir"; }
cleanup() { kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; close_input; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sleep 3
if [[ -r /proc/$pid/maps ]]; then
  cat "/proc/$pid/maps" > "$logs/$action.maps"
  if grep -Ei '/[^ ]*libmali[^ ]*' "$logs/$action.maps"; then
    echo 'FAIL: proprietary Mali library loaded' >&2; exit 1
  fi
  if awk '$6 ~ "^/(usr/)?lib/aarch64-linux-gnu/(lib(EGL|GLES|gbm|SDL2|gallium)|gbm/|dri/)" {print; found=1} END {exit !found}' "$logs/$action.maps"; then
    echo 'FAIL: graphics libraries escaped the private prefix' >&2; exit 1
  fi
else
  cat "$logs/$action.log"
  echo 'Application exited before live library inspection' >&2
  wait "$pid" || true
  exit 1
fi
if [[ $action == kmscube ]]; then
  # Debian kmscube polls stdin. A newline invokes its normal DRM cleanup.
  for second in {1..37}; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  printf '\n' >&3
  for second in {1..5}; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    echo 'Application did not exit after its stdin quit request' >&2
  fi
fi
set +e
wait "$pid"
status=$?
set -e
trap - EXIT INT TERM
close_input
cat "$logs/$action.log"
echo "Application exit status: $status"
exit "$status"
