#!/usr/bin/env bash
# Root guest diagnostic archive; stdout is exclusively a tar stream.
set -euo pipefail
logs=/opt/darkos-workflow/logs
mkdir -p "$logs"
status=0
if pidof peanut-sdl >/dev/null; then
  bash /opt/darkos-emulators/peanut-gb/scripts/gb-audit.sh > "$logs/live-audit.log" 2>&1 || status=$?
elif pidof emulationstation >/dev/null; then
  bash /opt/darkos-es/scripts/es-audit.sh > "$logs/live-audit.log" 2>&1 || status=$?
fi
{
  uname -a
  findmnt /
  lsblk -f
  ip -br address
  ip route
  ls -l /dev/dri || echo 'No DRM device (serial mode)'
  test ! -f /opt/darkos-graphics/runtime-id || cat /opt/darkos-graphics/runtime-id
} > "$logs/runtime.log" 2>&1
paths=()
for path in opt/darkos-workflow/logs opt/darkos-es/logs opt/darkos-graphics/logs \
  opt/darkos-emulators/peanut-gb/logs opt/darkos-es/home/.emulationstation/es_log.txt; do
  [[ ! -e /$path ]] || paths+=("$path")
done
tar -C / -cf - "${paths[@]}"
exit "$status"
