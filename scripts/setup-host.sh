#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )); then
  echo 'Run as root: sudo bash scripts/setup-host.sh' >&2
  exit 1
fi
apt-get -o Acquire::Retries=3 update
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y build-essential gcc-12 \
  gcc-12-aarch64-linux-gnu binutils-aarch64-linux-gnu bc bison flex \
  libssl-dev libelf-dev 7zip qemu-system-arm qemu-system-gui qemu-utils \
  btrfs-progs fdisk dosfstools rsync git python3 openssh-client kmod udev util-linux
