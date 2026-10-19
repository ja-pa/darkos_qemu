#!/usr/bin/env bash
# Guest-only evidence capture, while ES is running.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run via sudo' >&2; exit 1; }
pid=
for exe in /proc/[0-9]*/exe; do
  if [[ $(readlink "$exe" 2>/dev/null || true) == /opt/darkos-es/emulationstation ]]; then
    [[ -z $pid ]] || { echo 'Multiple ES processes' >&2; exit 1; }
    pid=${exe#/proc/}; pid=${pid%/exe}
  fi
done
[[ -n $pid ]] || { echo 'EmulationStation is not running' >&2; exit 1; }
log=/opt/darkos-es/logs
mkdir -p "$log"
cat "/proc/$pid/maps" > "$log/es.maps"
bash /opt/darkos-es/scripts/es-env.sh ldd /opt/darkos-es/emulationstation > "$log/es.ldd"
if grep -Ei 'libmali|libgo2|not found' "$log/es.maps" "$log/es.ldd"; then
  echo 'Unexpected vendor or missing library' >&2; exit 1
fi
for library in libSDL2 libEGL libOpenGL libgbm libgallium; do
  grep "/opt/darkos-graphics/usr/lib/aarch64-linux-gnu/.*$library" "$log/es.maps" >/dev/null || {
    echo "Missing private library: $library" >&2; exit 1;
  }
done
grep -E 'SDL video backend|OpenGL (version|renderer|vendor)' /opt/darkos-es/home/.emulationstation/es_log.txt
echo "PID=$pid; runtime libraries verified without libMali/libgo2"
