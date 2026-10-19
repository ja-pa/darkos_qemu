#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
mode=serial
dry_run=false
for arg in "$@"; do
  case "$arg" in
    serial|gtk-gl) mode=$arg;;
    --dry-run) dry_run=true;;
    *) fail "Unknown argument: $arg (use serial|gtk-gl and/or --dry-run)";;
  esac
done
need qemu-system-aarch64
need qemu-img
need python3
KERNEL_IMAGE=${KERNEL_IMAGE:-$BUILD_DIR/arch/arm64/boot/Image}
DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/darkos.qcow2}
SSH_PORT=${SSH_PORT:-2222}
[[ $SSH_PORT =~ ^[0-9]+$ && ${#SSH_PORT} -le 5 ]] || fail 'SSH_PORT must be an integer from 1 to 65535'
(( 10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535 )) || fail 'SSH_PORT must be from 1 to 65535'
[[ -s "$KERNEL_IMAGE" ]] || fail "Missing kernel: $KERNEL_IMAGE (run build-kernel.sh)"
[[ -s "$DISK_IMAGE" ]] || fail "Missing overlay: $DISK_IMAGE (run prepare-image.sh)"
format=$(qemu-img info --output=json "$DISK_IMAGE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')
[[ $format == qcow2 ]] || fail 'DISK_IMAGE must be a qcow2 overlay; never boot the raw base writable'
[[ $DISK_IMAGE != *,* ]] || fail 'DISK_IMAGE path cannot contain commas'
cmdline='console=ttyAMA0,115200 root=PARTUUID=a4b2b6f5-84cc-4a7d-9864-3a05d70567ba rootfstype=btrfs rw rootwait'
[[ -z ${ROOT_FLAGS:-} ]] || cmdline+=" rootflags=$ROOT_FLAGS"
[[ -z ${EXTRA_APPEND:-} ]] || cmdline+=" $EXTRA_APPEND"
cmd=(qemu-system-aarch64 -M "${QEMU_MACHINE:-virt}" -accel tcg -cpu cortex-a53 -m 1024
  -serial mon:stdio -kernel "$KERNEL_IMAGE"
  -drive "file=$DISK_IMAGE,format=qcow2,if=none,id=hd0"
  -device virtio-blk-pci,drive=hd0
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -device virtio-net-pci,netdev=net0 -append "$cmdline")
if [[ $mode == serial ]]; then
  cmd+=(-display none)
else
  qemu-system-aarch64 -device help | grep -q 'virtio-gpu-gl-pci' || fail 'QEMU lacks virtio-gpu-gl-pci'
  cmd+=(-device virtio-gpu-gl-pci,hostmem=512M -display gtk,gl=on
    -device qemu-xhci,id=usb -device usb-kbd,bus=usb.0)
fi
if $dry_run; then printf '%q ' "${cmd[@]}"; printf '\n'; else exec "${cmd[@]}"; fi
