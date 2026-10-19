# EmulationStation on SDL2 KMSDRM / Mesa

This workflow cross-compiles ARM64 EmulationStation in x86-64 WSL and runs it
inside QEMU. Native guest compilation is not required. It uses the fork's SDL
desktop OpenGL 2.1 renderer: its GLES 1 renderer still uses libgo2. This is
separate from the GLES2 triangle validated in milestone 2.

## Isolated guest

Shut down the graphics VM before copying its disk. Run these commands in WSL,
from this repository. `graphics.qcow2` and the raw image remain unchanged.

```bash
export WORK_DIR=${WORK_DIR:-$HOME/darkos-qemu-work}
export DISK_IMAGE=$WORK_DIR/images/emulationstation.qcow2
test ! -e "$DISK_IMAGE"
qemu-img convert -p -f qcow2 -O qcow2 "$WORK_DIR/images/graphics.qcow2" "$DISK_IMAGE"
bash scripts/run-qemu.sh gtk-gl
```

The GTK launcher includes an xHCI controller and USB keyboard. The saved kernel
has xHCI PCI, USB HID, generic HID and evdev built in; no kernel rebuild is needed.
Once SSH is ready, use a second WSL shell with the same environment:

```bash
sudo apt-get install --no-install-recommends g++-12-aarch64-linux-gnu cmake ninja-build pkg-config
bash scripts/es.sh prepare
bash scripts/es.sh sysroot
bash scripts/es.sh probe
bash scripts/es.sh build
bash scripts/es.sh deploy
bash scripts/es.sh run
```

`prepare` prints the Debian sources, free space and simulated installation,
refuses package removals, and installs missing development dependencies without
a distribution upgrade. Dependency updates can also update existing packages,
including their installed ARMHF counterparts. Desktop GLVND libraries are
extracted into `/opt/darkos-graphics`, preserving system vendor libraries.

## Cross build and deployment

The source is pinned to `ja-pa/EmulationStation-fcamod` commit
`db23162142f2d01c4c08216895fd793da243d19b`, with pugixml submodule
`96aebcb8ae2062ad020186e32fd301db7c3a0c88`. The checkout defaults to
`$WORK_DIR/repos/EmulationStation-fcamod` on the WSL filesystem. A different HEAD
is rejected; the pinned checkout and repository patches must match.

The toolchain uses GCC/G++ 12, Ninja, `SDL_KMSDRM=ON`, `GL=ON`, `GLES=OFF`,
`CEC=OFF`, `RPI=OFF`, and `RelWithDebInfo`. `JOBS` defaults to 4. Override paths
with `ES_SRC`, `ES_SYSROOT`, and `ES_BUILD_DIR`; defaults are under `WORK_DIR`.
The copied `ES_SYSROOT` must remain inside `WORK_DIR`.
`DISK_IMAGE` defaults to the isolated ES disk, and the existing SSH variables
(`SSH_PORT`, default 2222, and `SSH_KEY`) are supported.

`sysroot` copies the guest headers, ARM64 libraries and private graphics prefix.
Absolute symlinks are made relative only in that copy. CMake library/header
search and pkg-config are restricted to this sysroot. Guest startup objects,
libc and C++ runtime are preferred over the Ubuntu cross runtime. Compiler
intrinsics and GCC 12's C++ headers still come from the host cross toolchain.

The patch enables current CMake compatibility and out-of-source output, rejects
the incompatible GLES/go2 configuration, and logs/checks the actual SDL backend.
For this SDL build it also reads keyboard configuration from `--home`, replacing
the fork's hardcoded `/etc/emulationstation/es_input.cfg` lookup. Other builds
keep their existing input path.
Builds do not install either bundled Mali package from the fork.

Deployment puts the executable and resources in `/opt/darkos-es`, with an
isolated `--home /opt/darkos-es/home`. Two `.demo` files contain no ROM data;
their launch command is `/bin/true`. No system EmulationStation service is enabled.
Tests run as root for DRM/input access, with SDL dummy audio.

The ES wrapper selects desktop OpenGL through `libOpenGL.so.0`, EGL, GBM and
Gallium from the private prefix. The existing GLES wrapper is unchanged. SDL is
forced to KMSDRM; desktop fallback is an error.

## Validation

The desktop GL probe renders a rotating triangle for 30 seconds before the ES
build. In ES, use arrows to navigate, Enter to accept, Escape to go back, Space
to open the menu, and Tab as Select. Verify a visible UI for at least 60 seconds,
a changed list selection, menu navigation, and quitting through the UI.

While ES is running, capture and check its runtime libraries from another shell:

```bash
bash scripts/graphics-ssh.sh sudo -n bash /opt/darkos-es/scripts/es-audit.sh
```

Record SDL backend and GL vendor/renderer/version, `/proc/PID/maps`, ELF
dependencies and required GLIBC/GLIBCXX versions. Neither libMali nor libgo2 may
appear in loaded libraries. Logs and package manifests live in
`$WORK_DIR/logs/es` and guest `/opt/darkos-es/logs`; large artifacts stay outside Git.
Re-run ES and the original SDL GLES2 demo, check SSH, then cleanly shut down:

```bash
DISK_IMAGE="$WORK_DIR/images/emulationstation.qcow2" bash scripts/graphics.sh sdl
bash scripts/graphics-ssh.sh sudo -n systemctl poweroff
```

Performance, emulator launching, audio output and gamepads are outside this
milestone. A VirGL guest renderer backed by host LLVMpipe is recorded as such;
it is not evidence of host hardware acceleration.

## Recorded results (2026-10-19)

The ARM64 cross build completed with GCC 12.5.0, CMake 4.2.3, Ninja 1.13.2 and
pkg-config 2.5.1. Ninja recorded about 59.4 seconds for the full compilation/link
with four jobs (excluding configure and sysroot preparation).
Required ABI versions top out at GLIBC 2.38 and GLIBCXX 3.4.30;
the guest supplies glibc 2.41 and libstdc++.so.6.0.33. No libgo2 symbols or
dependency are present. Debug information stays in the host build; deployment
strips only debug information from a separate staging copy.

Both applications reported SDL **KMSDRM**, Mesa **25.0.7-2+deb13u1**, and
**OpenGL 4.3 Compatibility Profile**, with renderer
`virgl (LLVMPIPE (LLVM 21.1.8, 256 bits))`. The requested GL 2.1 compatibility
context therefore works without a GLES renderer port. The desktop probe ran
for 30.001 seconds and rendered 9,569 frames; its visible triangle is captured
in [gl21.png](evidence/es/gl21.png).

EmulationStation displayed the two-item test system and list. USB keyboard
Enter opened the list, Down changed the selection, Space opened the main menu,
and the Quit submenu confirmed a clean exit with status 0. This run lasted
approximately 117 seconds, exceeding the 60-second requirement. A subsequent
launch also exercised Enter, Down, Escape and F4, and exited cleanly. Screenshots
show the [list](evidence/es/ui.png), [changed selection](evidence/es/second.png)
and [menu](evidence/es/menu.png).

The runtime audit passed after opening the menu: SDL2, EGL, OpenGL, GBM and
Gallium came from the private prefix, with no libMali or libgo2 in either
`ldd` or process maps. See [runtime maps](evidence/es/es.maps),
[dependencies](evidence/es/es.ldd), [ELF ABI](evidence/es/elf.log), and
[validated run](evidence/es/run.log). Distribution SDL2 also loads some X11 and
Wayland support libraries; the active backend remains KMSDRM and no desktop
server is used.

The first dependency installation added 44 packages and updated 47 dependencies
(37.4 MB downloaded), with no removals. Repeating preparation succeeded with no
new installs or upgrades. The original transaction is in
[apt-plan.log](evidence/es/apt-plan.log); package versions and desktop GL package
hashes are alongside it. [Build provenance](evidence/es/build-manifest.log) and
[Ninja compilation records](evidence/es/ninja-build.log) identify the source,
patch and artifacts. The small `build.log` records the incremental input-path fix.

Invalid GLES/go2 configuration and missing sysroot checks both failed with the
intended explanatory error. Existing launcher checks passed (6 tests).

The original GLES2 SDL demo also passed after the ES tests: 9,560 frames in
30.004 seconds, KMSDRM, GLES 3.2 Mesa, exit status 0. Its runtime audit continued
to pass. SSH remained active after both applications exited; the guest was then
shut down through systemd. QEMU exited with status 0 after the root filesystem
was remounted read-only and unmounted; `qemu-img check` found no image errors.
The [shutdown log](evidence/es/shutdown.log) and
[image check](evidence/es/image-check.log) record these final checks.
