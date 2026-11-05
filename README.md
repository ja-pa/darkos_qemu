# dArkOS on ARM64 QEMU

Run the dArkOS G350 v08272026 system in QEMU on Ubuntu Linux or Windows **WSL2 with WSLg**. The standalone download includes the disk, kernel and launchers; no SDK or source checkout is needed. Native Windows QEMU is not supported.

## Download and run

Get **all archive parts and SHA256SUMS** from the [latest QEMU release](https://github.com/ja-pa/darkos_qemu/releases/latest). Use a writable Linux directory (inside Ubuntu on Windows).

```bash
sudo apt-get update
sudo apt-get install qemu-system-arm qemu-system-gui qemu-utils python3 python3-tk python3-pil python3-pil.imagetk libpulse0 libpulse-mainloop-glib0

# In the folder containing the downloaded parts:
sha256sum -c SHA256SUMS
cat darkos-qemu-g350-trixie-09022026-gdac27c86d54c.tar.gz.[0-9][0-9][0-9] | tar -xz
cd darkos-qemu-g350-trixie-09022026-gdac27c86d54c
sha256sum -c SHA256SUMS
bash start.sh
```

EmulationStation opens automatically; the first boot can take several minutes. Use arrow keys, Enter to select and Escape to return. Send keys to the QEMU window; the separate controls window shows game and application mappings.

```bash
bash controls.sh  # reopen the keyboard guide
bash stop.sh      # shut down cleanly
```

A Linux desktop needs working GTK/OpenGL and PulseAudio (or compatible PipeWire); WSLg normally supplies these. For a silent start, use `QEMU_AUDIO=none bash start.sh` while the VM is stopped. Settings and saves persist in `darkos.qcow2`; its published checksum applies only before first boot. Back it up while stopped. ARM64 software emulation on x86 is not representative of handheld performance.

## Sources and documentation

- [QEMU source and documentation](https://github.com/ja-pa/dArkOS/tree/codex/qemu-arm64-v08272026/qemu)
- [Usage and keyboard controls](https://github.com/ja-pa/dArkOS/blob/codex/qemu-arm64-v08272026/qemu/docs/USAGE.md)
- [Build from the official image](https://github.com/ja-pa/dArkOS/blob/codex/qemu-arm64-v08272026/qemu/docs/BUILD.md)
- [Troubleshooting](https://github.com/ja-pa/dArkOS/blob/codex/qemu-arm64-v08272026/qemu/docs/TROUBLESHOOTING.md)
- [Original development repository archive](https://github.com/ja-pa/darkos_qemu/tree/archive/pre-qemu-landing-2026-11-05)

Component licenses, source identities and image provenance are included in the release. This repository is the download and quick-start entry point; active development lives in the linked dArkOS branch.
