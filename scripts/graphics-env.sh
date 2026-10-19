#!/usr/bin/env bash
# Execute inside the guest, optionally via sudo. No global library replacement.
set -euo pipefail
prefix=${GRAPHICS_PREFIX:-/opt/darkos-graphics}
lib=$prefix/usr/lib/aarch64-linux-gnu
[[ -d "$lib" ]] || { echo "Missing graphics prefix: $lib" >&2; exit 1; }
unset LD_PRELOAD LD_LIBRARY_PATH LIBGL_DRIVERS_PATH GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE EGL_PLATFORM
export LD_LIBRARY_PATH=$lib
export LIBGL_DRIVERS_PATH=$lib/dri
export GBM_BACKENDS_PATH=$lib/gbm
export __EGL_VENDOR_LIBRARY_FILENAMES=$prefix/usr/share/glvnd/egl_vendor.d/50_mesa.json
export SDL_VIDEO_EGL_DRIVER=$lib/libEGL.so.1
export SDL_VIDEO_GL_DRIVER=$lib/libGLESv2.so.2
export SDL_VIDEODRIVER=kmsdrm
exec "$@"
