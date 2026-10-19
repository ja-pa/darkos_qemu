#!/usr/bin/env bash
# Inside guest while Peanut-SDL owns the screen.
set -euo pipefail
root=/opt/darkos-emulators/peanut-gb
pid=$(cat "$root/logs/emulator.pid")
[[ $(readlink "/proc/$pid/exe") == "$root/peanut-sdl" ]] || { echo 'Emulator is not running'; exit 1; }
cat "/proc/$pid/maps" > "$root/logs/emulator.maps"
bash "$root/scripts/es-env.sh" ldd "$root/peanut-sdl" > "$root/logs/emulator.ldd"
if grep -Ei 'libmali|libgo2|not found' "$root/logs/emulator.maps" "$root/logs/emulator.ldd"; then
  echo 'Forbidden or missing library'; exit 1
fi
for library in libSDL2 libEGL libOpenGL libgbm libgallium; do
  grep "/opt/darkos-graphics/usr/lib/aarch64-linux-gnu/.*$library" "$root/logs/emulator.maps" >/dev/null || {
    echo "Missing private graphics library: $library"; exit 1;
  }
done
ps -p "$pid" -o pid,etimes,args
echo 'Runtime library audit passed: private SDL2/Mesa, no libMali/libgo2'
