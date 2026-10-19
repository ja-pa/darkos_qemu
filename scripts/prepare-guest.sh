#!/usr/bin/env bash
# Apply the documented QEMU development profile to an OFFLINE qcow2 overlay only.
source "$(dirname -- "$0")/common.sh"
(( EUID == 0 )) || fail 'Run as root, passing WORK_DIR and SSH_PUBLIC_KEY explicitly'
for tool in qemu-img qemu-nbd modprobe mount umount python3 udevadm blkid ssh-keygen; do need "$tool"; done
DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/darkos.qcow2}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-$WORK_DIR/ssh/id_ed25519.pub}
[[ -f "$DISK_IMAGE" ]] || fail "Missing overlay: $DISK_IMAGE"
[[ -s "$SSH_PUBLIC_KEY" ]] || fail "Missing public key: $SSH_PUBLIC_KEY (generate it as your normal host user; see README)"
[[ $(qemu-img info --output=json "$DISK_IMAGE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])') == qcow2 ]] || fail 'Only qcow2 overlays may be customized'
modprobe nbd max_part=16
NBD_DEVICE=${NBD_DEVICE:-/dev/nbd0}
[[ $NBD_DEVICE =~ ^/dev/nbd[0-9]+$ ]] || fail 'NBD_DEVICE must be /dev/nbdN'
[[ ! -e /sys/class/block/"${NBD_DEVICE##*/}"/pid ]] || fail "$NBD_DEVICE is already in use"
mount_dir=$(mktemp -d)
connected=false
cleanup() {
  if mountpoint -q "$mount_dir"; then umount "$mount_dir"; fi
  if $connected; then qemu-nbd --disconnect "$NBD_DEVICE"; fi
  rmdir "$mount_dir"
}
trap cleanup EXIT
qemu-nbd --format=qcow2 --connect="$NBD_DEVICE" "$DISK_IMAGE"
connected=true
# The kernel's NBD partition scan can finish after qemu-nbd returns and after
# udev's currently queued events drain. Wait for the actual partition node.
for attempt in {1..100}; do
  [[ ! -b "${NBD_DEVICE}p4" ]] || break
  sleep 0.1
done
udevadm settle
[[ -b "${NBD_DEVICE}p4" ]] || fail 'Partition 4 not found on overlay'
[[ $(blkid -s PARTUUID -o value "${NBD_DEVICE}p4") == a4b2b6f5-84cc-4a7d-9864-3a05d70567ba ]] || fail 'Unexpected image partition identity'
mount -t btrfs "${NBD_DEVICE}p4" "$mount_dir"
[[ -f "$mount_dir/etc/fstab" && -d "$mount_dir/home/ark" ]] || fail 'Expected dArkOS guest layout absent'
[[ -e "$mount_dir/etc/fstab.before-qemu" ]] || cp "$mount_dir/etc/fstab" "$mount_dir/etc/fstab.before-qemu"
sed -i 's|/dev/mmcblk1p4|PARTUUID=a4b2b6f5-84cc-4a7d-9864-3a05d70567ba|g; s|/dev/mmcblk1p3|PARTUUID=670cf923-abc6-4cfb-ad8c-0302d886d82a|g' "$mount_dir/etc/fstab"
# Board firstboot resizes physical MMC partitions; the other units require board devices/UI.
for unit in firstboot emulationstation ogage audiostate shutdowntasks welcome-message; do
  ln -sfn /dev/null "$mount_dir/etc/systemd/system/$unit.service"
done
install -d "$mount_dir/etc/systemd/system/serial-getty@ttyAMA0.service.d"
cat > "$mount_dir/etc/systemd/system/serial-getty@ttyAMA0.service.d/qemu.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ark --noclear %I 115200 vt100
EOF
install -d "$mount_dir/etc/systemd/system/getty.target.wants"
ln -sfn /usr/lib/systemd/system/serial-getty@.service "$mount_dir/etc/systemd/system/getty.target.wants/serial-getty@ttyAMA0.service"
install -d "$mount_dir/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/ssh.service "$mount_dir/etc/systemd/system/multi-user.target.wants/ssh.service"
# Host tools cannot execute ARM64 binaries; generate per-overlay host keys offline.
if [[ ! -f "$mount_dir/etc/ssh/ssh_host_ed25519_key.qemu-created" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$mount_dir/etc/ssh/ssh_host_ed25519_key.qemu-new"
  mv "$mount_dir/etc/ssh/ssh_host_ed25519_key.qemu-new" "$mount_dir/etc/ssh/ssh_host_ed25519_key"
  mv "$mount_dir/etc/ssh/ssh_host_ed25519_key.qemu-new.pub" "$mount_dir/etc/ssh/ssh_host_ed25519_key.pub"
  touch "$mount_dir/etc/ssh/ssh_host_ed25519_key.qemu-created"
fi
install -d "$mount_dir/etc/ssh/sshd_config.d"
cat > "$mount_dir/etc/ssh/sshd_config.d/00-qemu.conf" <<'EOF'
HostKey /etc/ssh/ssh_host_ed25519_key
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
install -d -m 700 -o 1000 -g 1000 "$mount_dir/home/ark/.ssh"
authorized="$mount_dir/home/ark/.ssh/authorized_keys"
touch "$authorized"
key=$(cat "$SSH_PUBLIC_KEY")
grep -qxF -- "$key" "$authorized" || printf '%s\n' "$key" >> "$authorized"
chown 1000:1000 "$authorized"
chmod 600 "$authorized"
printf '%s\n' 'QEMU development profile: portable fstab, board units masked, serial autologin ark, key-only SSH.' > "$mount_dir/etc/darkos-qemu-profile"
sync
echo 'QEMU guest profile applied to overlay. Base image was not modified.'
