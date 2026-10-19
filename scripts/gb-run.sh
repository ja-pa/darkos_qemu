#!/usr/bin/env bash
# Guest launcher used both directly and by ES. Keep its true child exit status.
set -euo pipefail
root=/opt/darkos-emulators/peanut-gb
mkdir -p "$root/logs" "$root/saves"
log=$(mktemp "$root/logs/run.XXXXXXXX.log")
exec > >(tee "$log") 2>&1
echo "Started $(date -u +%FT%TZ); ROM=${1:-<missing>}"
[[ $# == 1 && -s $1 ]] || { echo 'Missing or empty ROM'; exit 2; }
rom=$(realpath -- "$1")
name=$(basename -- "$rom" .gb)
export SDL_RENDER_DRIVER=opengl
export SDL_AUDIODRIVER=dummy
cd "$root"
set +e
bash scripts/es-env.sh ./peanut-sdl "$rom" "$root/saves/$name.sav" &
pid=$!
echo "Emulator PID=$pid"
printf '%s\n' "$pid" > "$root/logs/emulator.pid"
wait "$pid"
status=$?
set -e
echo "Emulator exit status: $status"
exit "$status"
