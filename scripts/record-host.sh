#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
mkdir -p "$WORK_DIR/logs"
{
  date -u '+Recorded: %Y-%m-%dT%H:%M:%SZ'
  cat /etc/os-release
  uname -a
  printf '\nKernel commit: %s\n' "$KERNEL_COMMIT"
  git -C "$KERNEL_SRC" status --short
  aarch64-linux-gnu-gcc-12 --version | head -1
  gcc-12 --version | head -1
  aarch64-linux-gnu-ld --version | head -1
  qemu-system-aarch64 --version | head -1
  dpkg-query -W -f='${Package}\t${Version}\n' build-essential gcc-12 \
    gcc-12-aarch64-linux-gnu binutils-aarch64-linux-gnu bc bison flex \
    libssl-dev libelf-dev 7zip qemu-system-arm qemu-system-gui qemu-utils \
    btrfs-progs fdisk dosfstools rsync git python3 openssh-client kmod udev util-linux
} > "$WORK_DIR/logs/host-versions.txt"
cat "$WORK_DIR/logs/host-versions.txt"
