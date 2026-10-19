#!/usr/bin/env bash
# Called only on a detached export copy, never on the working disk.
set -euo pipefail
[[ $EUID == 0 && $# == 1 && -f $1 ]] || exit 2
image=$(realpath "$1")
[[ $image == *.partial/runtime.qcow2 ]] || { echo 'Expected export staging copy' >&2; exit 1; }
device=${NBD_DEVICE:-/dev/nbd0}
[[ $device =~ ^/dev/nbd[0-9]+$ ]] || exit 2
[[ ! -e /sys/class/block/${device##*/}/pid ]] || { echo 'NBD device busy' >&2; exit 1; }
modprobe nbd max_part=16
root=$(mktemp -d)
connected=false
cleanup() {
  if mountpoint -q "$root"; then umount "$root"; fi
  if $connected; then qemu-nbd -d "$device"; fi
  rmdir "$root"
}
trap cleanup EXIT
qemu-nbd --discard=unmap -f qcow2 -c "$device" "$image"
connected=true
for i in {1..100}; do [[ ! -b ${device}p4 ]] || break; sleep 0.1; done
mount -t btrfs "${device}p4" "$root"
[[ -d $root/opt/darkos-es && -f $root/etc/darkos-qemu-profile ]] || exit 1
find "$root/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -delete
find "$root/home" "$root/root" -type f \( -name authorized_keys -o -name known_hosts -o -name '.bash_history' \) -delete
find "$root/home" "$root/root" -type d -name .ssh -exec rm -rf -- {} +
rm -rf -- "$root/var/log/journal" "$root/var/lib/systemd/random-seed"
find "$root/var/log" -type f -exec truncate -s 0 -- {} +
truncate -s 0 "$root/etc/machine-id"
rm -f -- "$root/var/lib/dbus/machine-id"
ln -s /etc/machine-id "$root/var/lib/dbus/machine-id"
for app in "$root/opt/darkos-es/logs" "$root/opt/darkos-emulators/peanut-gb/logs" "$root/opt/darkos-emulators/peanut-gb/saves" "$root/opt/darkos-workflow/logs" "$root/opt/darkos-graphics/logs"; do
  if [[ -d $app ]]; then find "$app" -mindepth 1 -delete; fi
done
# Rebuild the entire custom home, including any profile backups, from fixtures.
rm -rf -- "$root/opt/darkos-es/home"
mkdir -p "$root/opt/darkos-es/home"
cp -a "$root/opt/darkos-es/fixtures/es/." "$root/opt/darkos-es/home/"
roms=$root/opt/darkos-emulators/peanut-gb/roms
if [[ -d $roms ]]; then
  find "$roms" -mindepth 1 -maxdepth 1 ! -name 'Tobu Tobu Girl.gb' ! -name rom-manifest.json -exec rm -rf -- {} +
  if [[ -f $roms/Tobu\ Tobu\ Girl.gb ]]; then
    echo "5d3871cae77db2287807e8914fd21f76203e73aa3fec20955489d45cb4571d8f  $roms/Tobu Tobu Girl.gb" | sha256sum -c -
  fi
fi
# Configure the sanitized copy using its ARM64 Python on next boot, not the host.
mkdir -p "$root/opt/darkos-workflow"
cp "$(dirname "$0")/workflow-profile.py" "$(dirname "$0")/gb-configure.py" "$root/opt/darkos-workflow/"
sync
fstrim -v "$root"
