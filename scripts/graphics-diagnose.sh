#!/usr/bin/env bash
# Run inside the guest; deliberately read-only.
set -uo pipefail
echo '=== kernel and space ==='
uname -a
df -h /
echo '=== DRM devices ==='
ls -l /dev/dri /sys/class/drm 2>/dev/null
for device in /sys/class/drm/card[0-9]*/device/driver; do readlink -f "$device"; done
for status in /sys/class/drm/card*-*/status; do
  [[ -f "$status" ]] || continue
  printf '%s: ' "$status"; cat "$status"
  cat "${status%status}modes"
done
echo '=== DRM holders ==='
sudo -n fuser -v /dev/dri/* 2>&1 || true
echo '=== graphics packages ==='
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | grep -Ei 'mesa|libmali|sdl2|libegl|libgles|libgbm|libdrm|kmscube' || true
echo '=== package sources ==='
grep -RhE '^[^#[:space:]]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
echo '=== loader configuration ==='
/sbin/ldconfig -p | grep -E 'lib(EGL|GLES|GLX|GLdispatch|gbm|SDL2|mali)' || true
find /usr/lib/aarch64-linux-gnu /usr/local/lib -maxdepth 2 -iname '*mali*' -ls 2>/dev/null
find /usr/share/glvnd/egl_vendor.d /etc/glvnd/egl_vendor.d -type f -name '*.json' -exec sh -c 'echo "$1"; cat "$1"' sh {} \; 2>/dev/null
echo '=== environment overrides ==='
env | grep -E '^(SDL_|LD_|LIBGL_|MESA_|GALLIUM_|EGL_|GBM_|__EGL_)' || true
echo '=== connector query ==='
if command -v modetest >/dev/null; then sudo -n modetest -M virtio_gpu -c; fi
exit 0
