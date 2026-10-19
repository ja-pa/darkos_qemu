#!/usr/bin/env bash
# Source this file; all SDK paths are resolved at its current location.
export DARKOS_SDK=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export ES_SYSROOT=$DARKOS_SDK/sysroot
export PKG_CONFIG_SYSROOT_DIR=$ES_SYSROOT
export PKG_CONFIG_LIBDIR=$ES_SYSROOT/opt/darkos-graphics/usr/lib/aarch64-linux-gnu/pkgconfig:$ES_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$ES_SYSROOT/usr/share/pkgconfig
unset PKG_CONFIG_PATH
export CC=aarch64-linux-gnu-gcc-12 CXX=aarch64-linux-gnu-g++-12
export DARKOS_TOOLCHAIN=$DARKOS_SDK/toolchain.cmake
