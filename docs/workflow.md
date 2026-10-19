# QEMU development environment and SDK

The four root-level entry points replace the manual milestone sequence. Run them
as your normal WSL user; host installation and offline disk preparation use sudo.
The supported test host is Ubuntu 26.04 x86-64 WSL2 with WSLg. Other Linux hosts
have not been validated. Building applications uses GCC/G++ 12 on the host,
Debian ARM64 headers/runtime from the guest, and the private SDL2/Mesa prefix.

## Commands and state

| Entry point | Commands |
| --- | --- |
| `setup.sh` | `source`, `import <runtime-directory>` |
| `sdk.sh` | `prepare [--refresh]`, `check`, `export <new-directory>`, `import <sdk-directory>` |
| `build.sh` | `build\|deploy es\|peanut-gb\|sdl-demo\|all`, `app <CMake-source>`, `deploy-app <ARM64-binary>` |
| `vm.sh` | `start [gtk-gl\|serial] [--no-controls]`, `es [--no-controls]`, `controls`, `stop`, `status`, `ssh [command]`, `logs`, `check`, `export <new-directory>` |

Defaults: `WORK_DIR=$HOME/darkos-qemu-work`, `DISK_IMAGE=$WORK_DIR/images/work.qcow2`,
`SSH_PORT=2222`, `SSH_KEY=$WORK_DIR/ssh/id_ed25519`, `JOBS=4`. Export WORK_DIR once
in the shell before using the commands. Each independent environment needs its
own work directory, working disk and SSH port. Source builds, SDK and outputs
belong on the native Linux filesystem. The original raw image is read-only.
Keep WORK_DIR and export destinations outside the repository. Allow roughly
40 GiB free when retaining source/build outputs, both exports and an imported
copy together; routine use of a prepared runtime needs substantially less.

`setup.sh source` uses the original two-volume archive from the dArkOS release
linked in the README. `ARCHIVE` can select another location for the first volume.
Kernel source, configuration and compiler choices remain pinned as documented
in the original workflow. Repeating source setup preserves its disk and key.
All host build dependencies, including G++/CMake/Ninja/pkg-config, are installed
by setup; no separate host package commands are needed.

`sdk.sh prepare` provisions missing guest dependencies, then records the runtime
identity and copies a new sysroot. An interrupted partial sysroot is moved aside
on retry; the last complete SDK is preserved until the new copy is complete.
Package preparation simulates installations and rejects removals; it does not
perform a distribution upgrade. Package versions reflect the repositories at
preparation time and are recorded, rather than guaranteed to remain available
forever. Runtime identity covers the private library contents and installed
package versions. SDK checks validate the sysroot contents and ARM64 libraries;
deployment also compares the connected runtime identity. Refresh SDK after
changing guest dependencies.
When a verified SDK already matches a freshly measured guest runtime, `prepare`
skips package installation and the sysroot copy. Use `prepare --refresh` to check
for repository updates even when the current SDK/runtime match. The four entry
points keep the SDK at `WORK_DIR/sdk`; custom `ES_SYSROOT` paths remain supported
by the historical low-level scripts.
Use `prepare --refresh` after manually editing system libraries outside the
package manager, so those files are recopied even if package versions match.

Build targets retain the pinned ES/Peanut-GB sources and project patches. The
Peanut-GB prepare step downloads the official, checksum-pinned test game; its
provenance and licenses are in [gameboy.md](gameboy.md). `all` builds/deploys ES,
Peanut-GB and the triangle. Source and binaries remain outside Git.

`deploy` preserves the ES home, user settings, ROMs and saves, and refuses to
replace a running application. To explicitly reset the custom ES configuration,
use `bash build.sh deploy es --reset-profile`; the previous configuration is
retained as a timestamped backup. The original dArkOS profile is preserved.
The custom profile copies NES Box from the original image, carries over selected
presentation settings, and exposes only verified systems. Audio uses SDL dummy.
In ES: arrows navigate, Enter accepts, Escape goes back, Space opens the menu.
In Game Boy: arrows, Z/X, Enter, Backspace and Escape; see the QWERTZ caveat in
the game guide. The triangle exits after 30 seconds or Escape.

VM management verifies the actual local QEMU disk and forwarded port using
`/proc`, rather than trusting only a saved PID. An occupied port or disk belonging
to another VM is an error. SSH readiness has a 240-second limit, overridable with
`VM_TIMEOUT`. Failure leaves the VM available for diagnosis and prints the serial
log path. `vm.sh logs` captures guest diagnostics and available application logs
as `WORK_DIR/logs/workflow/guest-logs.tar`, runs the applicable ES/emulator live
library audit when one is active, and prints the last 100 serial lines. With the
VM stopped it prints the existing serial log. Serial mode runs in the
background with output in that log; use `vm.sh ssh` for commands.
`vm.sh es` opens the GUI and runs ES in the foreground; quitting ES leaves QEMU
running. `stop` requests systemd poweroff, waits up to 120 seconds, and never
silently kills the process. `check` requires an offline disk.

### Host keyboard legend

`vm.sh es` and `vm.sh start gtk-gl` open a resizable Tkinter help window by
default. It runs on the WSL host and never sends input to the guest. Choose the
EmulationStation or Game Boy / Peanut-GB profile from its dropdown. Click QEMU
to play; the helper does not periodically raise itself or request keyboard focus.
Its initial position is a window-manager hint; WSLg may place it elsewhere.

```bash
bash vm.sh es --no-controls             # suppress automatic opening
bash vm.sh start gtk-gl --no-controls
bash vm.sh controls                     # open/reopen independently
```

Closing the legend leaves the VM running. Repeating a graphical start reuses
the existing legend for this WORK_DIR without raising it. `--no-controls` skips
opening a window; it does not close one that is already open. Serial launches
never open the legend. A successful `vm.sh stop` also closes it, including when
the VM has already stopped. Closing QEMU directly can leave the legend open.

Setup installs `python3-tk`. On an existing host, install it with
`sudo apt-get install python3-tk`. Missing Tk or a display failure produces a
warning and `WORK_DIR/logs/workflow/controls.log`; it never blocks QEMU startup.
Window PID/state and a singleton lock live under `WORK_DIR/state/controls.*`.
Process command line and start time are checked before stopping the helper.

Edit [config/controls.json](../config/controls.json) to change the displayed
profiles, then close/reopen the window. This changes the legend only, not input
bindings. Defaults follow `fixtures/es/.emulationstation/es_input.cfg`, ES's F4
quit action, and the pinned patched `examples/sdl2/peanut_sdl.c`. Custom guest
bindings require a corresponding manual legend update. The helper does not
automatically detect the active application.

Validation on 20 October 2026: 25 host tests passed, including real Tk profile
switching/resizing/cleanup, stale-PID rejection and missing-display recovery.
The default legend was visually inspected under WSLg with Tk 8.6.
Live tests against the prepared `darkos-qemu-m5` runtime confirmed that
`--no-controls` and serial starts do not open the legend, repeated graphical
starts retain the same helper PID, and closing/reopening it leaves ES running.
QMP keyboard input still reached ES (including clean F4 exit). Managed stop
closed both VM and helper; the subsequent `qemu-img check` reported no errors.

## Build another application

`demos/sdk-app` is a standalone CMake example using SDL2 and desktop OpenGL.
Copy it to a new source directory, modify it, then run:

```bash
bash build.sh app /path/to/my-app
bash build.sh deploy-app "$WORK_DIR/apps/my-app/sdl-demo"
bash vm.sh ssh 'sudo -n bash /opt/darkos-apps/sdl-demo/es-env.sh /opt/darkos-apps/sdl-demo/sdl-demo'
```

Stop ES before running a separate graphical process. Executable basenames must
contain at most 15 letters, digits, underscores or hyphens. Deployment installs
the binary and graphics environment under `/opt/darkos-apps/<name>`; arbitrary
applications are not automatically added to the ES menu. Supply assets separately
when your application needs them. The SDK environment can also be used directly:

```bash
source "$WORK_DIR/sdk/environment.sh"
cmake -S /path/to/source -B "$WORK_DIR/apps/custom" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$DARKOS_TOOLCHAIN"
cmake --build "$WORK_DIR/apps/custom" -j4
```

## Local export and relocation

Export is explicit and does not upload anything. Stop the VM first:

```bash
bash vm.sh stop
bash vm.sh export "$HOME/darkos-runtime-export"
bash sdk.sh export "$HOME/darkos-sdk-export"
```

Runtime export contains a standalone qcow2, kernel, provenance, license notes,
runtime identifier and checksums. Export modifies a detached copy, removes SSH
identities and authorized keys, resets machine identity, clears standard guest
and application logs, custom ES profiles/backups, emulator saves and additional
ROMs in the Peanut-GB test directory. It retains only the hash-verified official
test game. Files users put in other locations are not automatically classified
or removed. Review an export before sharing it. A public distribution would also
require reviewing the upstream image's components and licensing/source duties;
this workflow performs no publication.

The separate SDK contains the normalized sysroot, package versions and copyright
notices, toolchain, environment and manifest. It contains no host GCC binaries;
setup installs those. Both exports are directories, avoiding an additional huge
archive copy. Neither destination nor an interrupted `.partial` is overwritten.

To relocate without any dependency on the old paths:

```bash
export WORK_DIR="$HOME/darkos-import-test"
bash setup.sh import "$HOME/darkos-runtime-export"
bash sdk.sh import "$HOME/darkos-sdk-export"
bash build.sh app demos/sdk-app  # works with VM stopped
bash vm.sh es
```

Import validates checksums and standalone disk format. It copies the runtime,
creates fresh SSH credentials/host keys and restores the custom QEMU profile on
the first ES start. New known-hosts state is private to the new work directory.
SDK symlinks are validated and all environment paths resolve at the new location.
For interruption recovery, rerun setup/SDK preparation; export/import report
partial copies explicitly instead of treating an incomplete copy as usable.

## Recorded validation: 19–20 October 2026

A new `/home/japa1/darkos-qemu-m5` directory was prepared from the original
two-volume archive and clean Git objects at the pinned kernel commit. It used
neither a previously built kernel nor a previously provisioned milestone disk.
Preparation was resumed and rerun successfully; the repeat kept the same kernel
and configuration hashes. Privileged host phases used WSL root in the test
harness; ordinary SDK/build/run phases ran as `japa1`.

| Operation | Measured wall time |
| --- | --- |
| Repeat source setup, including archive/base verification | 186.28 s |
| Initial SDK preparation, including guest provisioning and copy | 710.72 s |
| Matching SDK preparation with VM already running | 16.89 s |
| Build all, including sources/configure/ES/Peanut-GB/demo | 110.68 s |
| Peanut-GB compile/link | 1.088 s |
| SDL template compile/link | 0.405 s |
| SDK export / import | 8.40 s / 7.50 s |
| Runtime export / import, including verification/provisioning | 54.66 s / 46.24 s |

The host used GCC/G++ 12.5.0, CMake 4.2.3, Ninja 1.13.2 and QEMU 10.2.1.
Source and imported ES used SDL2 2.32.4, KMSDRM, private Mesa
25.0.7-2+deb13u1, and OpenGL 4.3 Compatibility Profile. The renderer was
`virgl (LLVMPIPE (LLVM 21.1.8, 256 bits))`; this does not claim host hardware
acceleration. ES displayed the original NES Box theme for over a minute;
keyboard navigation, menus and clean F4 exit worked.

Three accepted ES → gameplay in Plains → Escape → usable ES/menu cycles passed:

| Cycle | PID | Presented frames | Elapsed | Exit |
| --- | --- | --- | --- | --- |
| 1 | 1952 | 5,516 | 94.685 s | 0 |
| 2 | 2616 | 5,069 | 86.940 s | 0 |
| 3 | 2960 | 6,304 | 108.506 s | 0 |

Each running emulator passed the private-library audit, and restored ES passed
its audit. An additional title-screen launch while checking system navigation
is retained in the log but is not counted among these three cycles. The NES Box
system carousel uses Up/Down; Enter opens the selected list. The SDL OpenGL
example launched from the Ports/test-applications system and returned normally
after 8,609 frames in 30.001 s. The original GLES2 demo also passed: 9,554 frames
in 30.001 s, KMSDRM, GLES 3.2 Mesa, exit 0.

Redeployment preserved a changed preference plus ROM/save markers. Explicit
profile reset restored defaults, retained Game Boy, kept a configuration backup
and preserved saves. A simulated interrupted sysroot was moved aside and
preparation completed. Active deployment, foreign VM identity, active image
checking, SDK mismatch and graphical ES on a serial VM were rejected.
The stdin readiness regression found during integration was fixed and covered
by a test; multiline Python scripts sent through `vm.sh ssh` then performed the
actual state assertions successfully.

| Local export | Physical bytes | GiB |
| --- | --- | --- |
| Runtime directory, including kernel and metadata | 5,580,087,296 | 5.20 |
| SDK directory | 1,506,959,360 | 1.40 |

The runtime has a 7.5 GiB virtual disk and **no backing file**. Exports are not
compressed or uploaded. SDK import and a fresh example build succeeded while
the original SDK directory was hidden; compile/link took 0.529 s. The imported
runtime in `/home/japa1/darkos-qemu-m5-import` used SSH port 2233, displayed the
same theme, passed the ES library audit and supported repeated ES starts.
Only the newly generated user key was authorized; the server host key differed
from the source. The extra ROM, saves and profile backups were absent, while
the official test game and matching SDK/runtime identity remained. Reimporting
the same SDK succeeded without replacing it.

The source also passed serial boot/SSH while the imported graphical VM ran on
its separate port. Test-only source markers were subsequently removed and real
game saves retained. Both VMs were cleanly powered off, both working qcow2 images
passed offline checking, and the imported SDK passed verification with its VM
stopped. Six launcher tests and sixteen workflow tests passed, as did shell and
Python syntax checks.

See [machine-readable results](evidence/workflow/results.json),
[checks](evidence/workflow/checks.log), [ES launch log](evidence/workflow/es-run.log),
[profile preservation](evidence/workflow/profile-validation.log),
[import validation](evidence/workflow/import-import-validation.log),
[source image check](evidence/workflow/image-check.log) and
[imported image check](evidence/workflow/import-image-check.log).
The [source theme](evidence/workflow/es-theme.png),
[gameplay](evidence/workflow/cycle3.png), [restored menu](evidence/workflow/es-return.png),
[SDL example](evidence/workflow/sdl-demo.png) and
[imported UI](evidence/workflow/imported.png) were captured from the QEMU window
and cropped to the guest display. QMP supplied virtual keyboard inputs; native
window keyboard navigation was also checked. Historical evidence remains in
the earlier milestone directories.
