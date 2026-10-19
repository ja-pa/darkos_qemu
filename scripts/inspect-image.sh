#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
(( EUID == 0 )) || fail 'Run as root, passing WORK_DIR explicitly (see README.md)'
for tool in losetup mount umount blkid sfdisk btrfs; do need "$tool"; done
[[ -f "$RAW_IMAGE" ]] || fail "Missing raw image: $RAW_IMAGE"
mount_dir=$(mktemp -d)
loop=''
cleanup() {
  if mountpoint -q "$mount_dir"; then umount "$mount_dir"; fi
  [[ -z "$loop" ]] || losetup -d "$loop"
  rmdir "$mount_dir"
}
trap cleanup EXIT
loop=$(losetup --find --show --read-only --partscan "$RAW_IMAGE")
for attempt in {1..100}; do
  [[ ! -b "${loop}p4" ]] || break
  sleep 0.1
done
[[ -b "${loop}p4" ]] || fail 'Root partition node did not appear'
sfdisk --dump "$loop"
blkid "${loop}"p* || true
mount -t btrfs -o ro,rescue=nologreplay "${loop}p4" "$mount_dir"
btrfs subvolume get-default "$mount_dir"
btrfs subvolume list "$mount_dir"
for file in etc/os-release etc/fstab etc/inittab etc/network/interfaces etc/systemd/network/eth0.network etc/ssh/sshd_config; do
  if [[ -f "$mount_dir/$file" ]]; then
    printf '\n--- %s ---\n' "$file"
    cat "$mount_dir/$file"
  fi
done
printf '\n--- init ---\n'
ls -l "$mount_dir/sbin/init"
printf '\n--- enabled services ---\n'
find "$mount_dir/etc/systemd/system" -type l -printf '%P -> %l\n' | sort
