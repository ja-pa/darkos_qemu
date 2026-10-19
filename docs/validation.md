# Milestone 1 validation

Validation date: 2026-10-19. The host is Ubuntu 26.04 on x86-64 WSL2,
kernel 6.18.33.1-microsoft-standard-WSL2. QEMU is 10.2.1; both host and ARM64
compilers are GCC 12.5.0, with AArch64 binutils 2.46. Full package versions are
recorded in [host-versions.txt](evidence/host-versions.txt).

**Milestone 1 passed:** two kernel builds and two full guest validations,
including a fresh overlay for the repeat run.

## Source and image findings

- Kernel source: `ja-pa/kernel_5_10_226`, commit
  `bef65b1793524bc7bd27c4d70d0ce59cbebee032`, Linux 5.10.226.
- Existing `darkos-tools` checkout: `2edeba378ee819a01c0a471151cdc85f2df00ae5`.
- The Windows source checkout has broken symlinks and case-handling problems.
  Build sources were cloned from its Git objects onto WSL ext4, without copying
  working-tree files. No kernel source patches were made.
- No ARM64 QEMU-specific defconfig or saved `.config` was found. The generic
  ARM64 defconfig plus the project fragment is used instead.
- The two-volume archive passed `7z t` and extracted a raw 8,053,063,680-byte image.
- Read-only loop inspection confirmed GPT and the root Btrfs filesystem. Its
  default subvolume is ID 5 (top-level); there are no separate root subvolumes.
  Btrfs feature flags are `compat_ro=0x3`, `incompat=0x371`, supported by this tree.
- Partition 3 is FAT32 `dArkOS_Fat`; partition 4 is Btrfs `ROOTFS`; partition 5
  is VFAT `ROMS`. The root filesystem contains Debian 13.3 (trixie), systemd,
  NetworkManager, OpenSSH, and the existing `ark` account with passwordless sudo.

The unmodified guest successfully mounted its root and started systemd, then
entered emergency mode because fstab waits for nonexistent `/dev/mmcblk1p3`.
Its root account is locked, so sulogin also cannot open that emergency console.
This independently confirms the need for the overlay profile; it is not a
kernel root-mount failure. The diagnostic run was stopped by a 120-second timeout.

The QEMU profile changes only the overlay: two fstab device paths, six service
masks, serial autologin, and key-only SSH configuration. Its exact operations
are in `scripts/prepare-guest.sh`. Reapplying the profile to a stopped VM was
also tested successfully. The base image is read-only.

## Build and boot results

The first attempt exposed unrelated Allwinner clock code calling the absent
`clk_hw_can_set_rate_parent` function. Disabling `ARCH_SUNXI` in the project
fragment resolved it without a source patch. OpenSSL 3 deprecation warnings in
the kernel's host certificate tool did not prevent the build.

The resulting kernel release is `5.10.226-darkos-qemu`. The primary Image is
31 MiB and was built with four jobs in an out-of-tree directory. Required boot
drivers, Btrfs, GPT, DRM/KMS and VirtIO GPU were verified as built in.

The primary integration run passed all checks, using normal systemd startup and
SSH public-key authentication rather than `init=/bin/sh`:

| Check | Observed result |
| --- | --- |
| PID 1 | `systemd` |
| Multi-user target, NetworkManager, SSH | All active |
| Serial console | Automatic `ark` login and interactive shell prompt |
| Root | `/dev/vda4`, Btrfs, read/write, subvolume ID 5 |
| Boot filesystem | `/dev/vda3`, VFAT |
| Block device | `vda`, 7.5 GiB, all five partitions detected |
| Virtual network | `enp0s2`, DHCP `10.0.2.15/24` |
| Default route | `10.0.2.2` |
| Gateway ping | Successful, zero packet loss |
| DNS | `deb.debian.org` resolved successfully |
| Host access | Key-authenticated SSH through `127.0.0.1:2222` |
| Shutdown | Guest poweroff, filesystems detached, QEMU exit status 0 |

The complete guest check output is in [primary-guest.txt](evidence/primary-guest.txt).
The first boot and shutdown took approximately 84 seconds of guest uptime.

A second Image was compiled in a separate, initially empty `build-repeat/`
directory. Its resolved configuration is byte-identical to the primary build
and the saved project configuration. The final build script was also rerun
successfully after an edit to the running wrapper caused a post-build shell
parse error; the kernel make and Image generation had already succeeded.
The repeat validation used that second Image and a separately created,
freshly provisioned overlay. All the same checks passed, including serial
autologin, SSH, root and boot mounts, DHCP, gateway and DNS. It powered off
with QEMU exit status 0 at approximately 66 seconds of guest uptime.
See [repeat-guest.txt](evidence/repeat-guest.txt).

Kernel and configuration hashes are recorded in
[kernel-artifacts.sha256](evidence/kernel-artifacts.sha256). The Image hashes
differ because their embedded build timestamps differ; the configuration hashes
match. Input archive and raw image hashes are in [images.sha256](evidence/images.sha256).
The base raw image checksum was verified unchanged after preparation and boot.

Six launcher contract tests passed, covering space-containing paths, serial and
graphics commands, missing artifacts, invalid ports/arguments, and refusal to
boot a raw base writable. All shell and Python files passed syntax checks.

## Artifacts and limitations

Working artifacts are under `/home/japa1/darkos-qemu-work` in the Ubuntu distro:
`kernel/`, `build/`, `build-repeat/`, `images/`, `ssh/`, and `logs/`. Private keys
remain there and are not part of this repository. The full reviewed kernel
configuration is in `configs/qemu-arm64.config`.

Serial, build, archive, inspection and guest-profile logs are retained in the
work directory. The original Windows kernel checkout and archive were preserved.

Known limitations:

- ARM64 runs through TCG on this x86-64 host; performance is not representative
  of physical hardware.
- GTK/OpenGL boot and guest graphics have not been validated. QEMU advertises
  the original GPU device, and its command is covered by the launcher tests.
- The old kernel/vendor userspace combination emits a nonfatal
  `systemd-gpt-auto-generator` error. Explicit kernel root selection and fstab
  mounts work. An early `/tmp` unmount warning and unused flash suspend warnings
  were seen on shutdown; final filesystem detachment and poweroff succeeded.
- Board kernel modules in the image do not match the rebuilt kernel. Boot and
  network drivers are built in; arbitrary module-dependent applications are
  outside this milestone.
- Archive checksums identify the supplied local files; they are not an upstream
  authenticity claim. Builds reproduce the tested procedure, not identical
  timestamps or binary hashes.
