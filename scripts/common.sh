#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=${WORK_DIR:-$HOME/darkos-qemu-work}
KERNEL_COMMIT=bef65b1793524bc7bd27c4d70d0ce59cbebee032
KERNEL_SRC=${KERNEL_SRC:-$WORK_DIR/kernel}
BUILD_DIR=${BUILD_DIR:-$WORK_DIR/build}
RAW_IMAGE=${RAW_IMAGE:-$WORK_DIR/images/dArkOS_RG353m_trixie_01312026.img}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "Missing dependency: $1 (see README.md)"; }
