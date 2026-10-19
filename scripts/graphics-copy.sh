#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
need qemu-img
source_image=${BASE_DISK_IMAGE:-$WORK_DIR/images/darkos.qcow2}
target=${DISK_IMAGE:-$WORK_DIR/images/graphics.qcow2}
[[ -f "$source_image" ]] || fail "Missing source disk: $source_image"
[[ ! -e "$target" && ! -e "$target.partial" ]] || fail "Destination already exists: $target (or .partial)"
mkdir -p "$(dirname "$target")"
# QEMU's image lock rejects an active source. The copy has no backing dependency.
qemu-img convert -p -f qcow2 -O qcow2 "$source_image" "$target.partial"
mv -- "$target.partial" "$target"
qemu-img info "$target"
