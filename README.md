# dArkOS on ARM64 QEMU

Milestone 1 builds Linux 5.10.226 for QEMU `virt` and boots the existing dArkOS
userspace on an x86-64 Ubuntu WSL2 host. EmulationStation and accelerated graphics
are later milestones. See [validation.md](docs/validation.md) for measured results.

Milestone 2 now validates kmscube and a native SDL2 KMSDRM/GLES demo using a
private Mesa stack. See [graphics.md](docs/graphics.md) for setup and measured results.

## Host and source

Run these commands **inside Ubuntu**, from this project directory. On Windows the
directory is available as `/mnt/c/Users/japa1/Documents/ChatGPT/darkos_qemu`.

```bash
sudo bash scripts/setup-host.sh
export WORK_DIR="$HOME/darkos-qemu-work"
bash scripts/build-kernel.sh
```

The build script imports Git objects from `repos/kernel_5_10_226` when present,
otherwise clones `https://github.com/ja-pa/kernel_5_10_226`. It checks out commit
`bef65b1793524bc7bd27c4d70d0ce59cbebee032` on the native Linux filesystem.
The existing Windows checkout is preserved: it has broken symlinks and cannot
reliably represent case-sensitive Linux paths. Never copy its working files into
the build source. A pre-existing source must have the exact commit and be clean.

The default toolchain is GCC 12 for both ARM64 and host tools. The build uses
`ARCH=arm64`, `CROSS_COMPILE=aarch64-linux-gnu-`, and four jobs. Override
`SOURCE_REPO`, `KERNEL_SRC`, `BUILD_DIR`, or `JOBS` through environment variables.
Use native Linux paths for source and output; building on `/mnt/c` is slow and
can break symlinks and case-sensitive names.

Configuration starts with ARM64 `defconfig`, merges
`configs/qemu-arm64.fragment`, then runs `olddefconfig`. Boot-critical drivers,
Btrfs, GPT, DRM/KMS, and VirtIO GPU are built in; no initramfs is needed.
The output is `$WORK_DIR/build/arch/arm64/boot/Image` and the resolved configuration
is `$WORK_DIR/build/.config`. Build logs are under `$WORK_DIR/logs`.
The reviewed complete configuration is stored as `configs/qemu-arm64.config`.

## Existing image

The image used for this project was downloaded from
[christianhaitian/dArkOS release v01302026](https://github.com/christianhaitian/dArkOS/releases#release-v01302026).
The tested variant is `dArkOS_RG353m_trixie_01312026.img`, distributed as the two
archive volumes listed below.

Keep both original files together under `images/`:

```text
dArkOS_RG353m_trixie_01312026.img.7z.001
dArkOS_RG353m_trixie_01312026.img.7z.002
```

```bash
bash scripts/prepare-image.sh
sudo env WORK_DIR="$WORK_DIR" bash scripts/inspect-image.sh
```

Preparation hashes and tests both archive volumes, extracts to staging, and moves
the completed 7.5 GiB raw image into `$WORK_DIR/images`. It makes the raw file
read-only and creates `darkos.qcow2`, a writable overlay with an explicit raw
backing format. Extraction needs approximately 8 GiB plus overlay/build space.
An existing image or overlay is never silently overwritten.

Inspection uses a read-only loop device and Btrfs `ro,rescue=nologreplay`, then detaches
it on exit. It reports partition information, subvolumes, fstab and enabled
services. WSL's Btrfs module must be available. Never run filesystem repair,
resize, or writable mounts on the base image. Archive and base-image checksums
are saved under `$WORK_DIR/logs`.

The image uses GPT: partitions 1 and 2 contain board boot resources, partition 3
is FAT32, partition 4 is Btrfs `ROOTFS`, and partition 5 is an additional small
partition. QEMU direct kernel boot bypasses the board bootloader. The root
PARTUUID is `a4b2b6f5-84cc-4a7d-9864-3a05d70567ba`.

## Boot

The physical-device image's fstab refers to `/dev/mmcblk1p3` and `mmcblk1p4`.
Apply the QEMU development profile to the **offline overlay** before the regular
boot. Generate a dedicated host keypair as your normal WSL user:

```bash
mkdir -p "$WORK_DIR/ssh"
ssh-keygen -t ed25519 -N '' -f "$WORK_DIR/ssh/id_ed25519"
sudo env WORK_DIR="$WORK_DIR" bash scripts/prepare-guest.sh
```

The profile replaces those two fstab paths with their verified PARTUUIDs. It masks
`firstboot`, `emulationstation`, `ogage`, `audiostate`, `shutdowntasks`, and
`welcome-message` services, which resize physical storage or require board/UI
devices. It does not edit EmulationStation or library sources. It configures
serial autologin as `ark`, enables SSH, adds only your public key, generates a
per-overlay SSH host key, and disables password/root SSH login. Guest passwords
are unchanged. Serial autologin is intended for this local development VM.
Stop QEMU before running this script; its image lock prevents editing an active
overlay. The default `/dev/nbd0` must be free; choose another `NBD_DEVICE` if needed.
The base image remains read-only. A fresh overlay needs the profile applied again.

```bash
bash scripts/run-qemu.sh --dry-run
bash scripts/run-qemu.sh serial
```

The default command uses `virt`, TCG, Cortex-A53, 1 GiB RAM, VirtIO PCI block and
network devices, and PL011 serial console. Root is selected by PARTUUID with
`rootfstype=btrfs rw rootwait`. Serial access is independent of WSLg.
Use QEMU's `Ctrl-a c` to switch between the console and monitor; `quit` exits QEMU.
Shut down the guest cleanly with `poweroff` whenever possible.

SSH, when enabled in the guest, is forwarded to `127.0.0.1:2222`:

```bash
ssh -i "$WORK_DIR/ssh/id_ed25519" -p 2222 ark@127.0.0.1
```

The forward binds only to localhost. A second VM needs a different
`SSH_PORT` and its own overlay. Do not attach the same overlay to multiple VMs.

Optional environment variables:

| Variable | Default / purpose |
| --- | --- |
| `WORK_DIR` | `$HOME/darkos-qemu-work` |
| `BUILD_DIR` | `$WORK_DIR/build` |
| `KERNEL_IMAGE` | `$BUILD_DIR/arch/arm64/boot/Image` |
| `RAW_IMAGE` | `$WORK_DIR/images/dArkOS_RG353m_trixie_01312026.img` |
| `DISK_IMAGE` | `$WORK_DIR/images/darkos.qcow2`; must be qcow2 |
| `ARCHIVE` | Project `images/...img.7z.001` |
| `SSH_PORT` | `2222` |
| `QEMU_MACHINE` | `virt`; use a recorded versioned machine for a fixed device model |
| `ROOT_FLAGS` | Optional Btrfs mount flags, if required by the image's subvolume layout |
| `EXTRA_APPEND` | Diagnostic kernel parameters; passed as one command-line argument |

For a new isolated run, create a fresh overlay without deleting the previous one:

```bash
qemu-img create -f qcow2 -F raw \
  -b "$WORK_DIR/images/dArkOS_RG353m_trixie_01312026.img" \
  "$WORK_DIR/images/fresh.qcow2"
sudo env WORK_DIR="$WORK_DIR" DISK_IMAGE="$WORK_DIR/images/fresh.qcow2" \
  bash scripts/prepare-guest.sh
DISK_IMAGE="$WORK_DIR/images/fresh.qcow2" bash scripts/run-qemu.sh
```

The overlay stores its backing path. Keep the base at that location; moving it
requires an explicit backing-path update. Moving the overlay alone is insufficient.

## Graphics and diagnostics

```bash
bash scripts/run-qemu.sh gtk-gl
```

This preserves the original `virtio-gpu-gl-pci,hostmem=512M` and
`-display gtk,gl=on` configuration from
[darkos-tools](https://github.com/ja-pa/darkos-tools/blob/main/run_in_qemu.sh).
The launcher checks GPU device availability; GTK/OpenGL also requires working
WSLg/host EGL. A graphical backend failure does not imply a kernel boot failure.
Return to serial mode to isolate it. Mesa, EGL and EmulationStation validation
are outside Milestone 1.

For boot diagnosis use `EXTRA_APPEND='loglevel=7'`. An emergency
`EXTRA_APPEND='init=/bin/sh'` can inspect the guest, but does not validate normal
userspace startup. Hardware-specific startup fixes belong only in the overlay
and must be documented. Never install the board's modules for this rebuilt
kernel; essential virtual devices already have built-in drivers.

To verify repeatability, build into a second empty output directory and boot
using that Image plus a fresh overlay. Record `uname -a`, `findmnt /`, `lsblk`,
`ip address`, `ip route`, connectivity results, and serial output. Compiler
timestamps can change Image hashes; repeatability here means the same source,
configuration and procedure produce a working boot, not bit-identical binaries.

The fragment disables `ARCH_SUNXI`: this vendor tree's Allwinner clock driver
references the missing `clk_hw_can_set_rate_parent` function. QEMU needs none of
that platform's drivers, so this avoids changing kernel source code.

```bash
python3 tests/test_launcher.py
bash scripts/record-host.sh
python3 scripts/validate-boot.py --name primary
BUILD_DIR="$WORK_DIR/build-repeat" bash scripts/build-kernel.sh
# Create and provision a fresh overlay as above, then:
BUILD_DIR="$WORK_DIR/build-repeat" DISK_IMAGE="$WORK_DIR/images/fresh.qcow2" \
  python3 scripts/validate-boot.py --name repeat
sha256sum -c "$WORK_DIR/logs/base-image.sha256"
```

For the cross-compiled EmulationStation frontend using SDL2 KMSDRM and Mesa,
see [the EmulationStation workflow](docs/emulationstation.md).
For launching a small Game Boy emulator and returning to ES, see
[the Peanut-GB workflow](docs/gameboy.md).

The integration validator starts QEMU, waits for SSH, checks normal systemd
multi-user startup, root and boot mounts, VirtIO disk, DHCP/default route, gateway
connectivity and DNS, then requests clean poweroff. It records serial and guest
logs. It uses a dedicated known-hosts file per validation name; use a new name
for a newly provisioned overlay because its SSH host key is different.
