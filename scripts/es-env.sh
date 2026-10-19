#!/usr/bin/env bash
# Guest-only desktop OpenGL variant of graphics-env.sh.
set -euo pipefail
prefix=${GRAPHICS_PREFIX:-/opt/darkos-graphics}
lib=$prefix/usr/lib/aarch64-linux-gnu
[[ -f $lib/libOpenGL.so.0 ]] || { echo 'Run es.sh prepare first' >&2; exit 1; }
unset LD_PRELOAD LD_LIBRARY_PATH GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE EGL_PLATFORM
export LD_LIBRARY_PATH=$lib
export LIBGL_DRIVERS_PATH=$lib/dri GBM_BACKENDS_PATH=$lib/gbm
export __EGL_VENDOR_LIBRARY_FILENAMES=$prefix/usr/share/glvnd/egl_vendor.d/50_mesa.json
export SDL_VIDEO_EGL_DRIVER=$lib/libEGL.so.1 SDL_VIDEO_GL_DRIVER=$lib/libOpenGL.so.0
export SDL_VIDEODRIVER=kmsdrm SDL_AUDIODRIVER=dummy
export SDL_OPENGL_ES_DRIVER=0
exec "$@"
