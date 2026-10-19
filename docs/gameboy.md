# Game Boy launch / return test

Milestone 4 uses the SDL2 frontend of Peanut-GB, pinned to
`d0bcca771c83a2638c93a9ae61f3d51f226dc905` (version 1.3.0 plus upstream commits),
cross-compiled in WSL against the milestone 3 sysroot. The target contains two C
translation units: the frontend/core and miniGB APU. No SDL rebuild is needed.

## Prepare and build in WSL

```bash
export WORK_DIR=${WORK_DIR:-$HOME/darkos-qemu-work}
bash scripts/gb.sh prepare
bash scripts/gb.sh build
```

The defaults are `$WORK_DIR/repos/Peanut-GB`, `$WORK_DIR/gb/build`, and the existing
`$WORK_DIR/es/sysroot`. Override these with `GB_SRC`, `GB_BUILD_DIR`, and
`ES_SYSROOT`. `JOBS` defaults to 4. The build uses GCC 12, upstream CMake, Ninja,
Release mode and explicitly links the private ARM64 SDL2 library. The included
APU is compiled; audible output is disabled by `SDL_AUDIODRIVER=dummy`.

The small patch adds fullscreen, Escape to quit, required KMSDRM/OpenGL checks,
renderer logging and a presented-frame count. It also destroys textures before
their renderer during cleanup and latches short input presses for one emulated
frame. Upstream can otherwise consume both key-down and key-up in one event
batch before the emulated CPU sees the button. `SDL_RENDER_DRIVER=opengl` selects SDL's desktop
OpenGL renderer; its name is checked at runtime to prohibit a silent fallback.
Guest VirGL can still use LLVMpipe on the host, as in the preceding milestones.

## Test ROM and licenses

The test is the original monochrome **Tobu Tobu Girl** by Tangram Games, with
music by potato-tan. It is downloaded from the author's
[itch.io page](https://tangramgames.itch.io/tobutobugirl), upload ID `678889`.
The original archive and extracted ROM are kept under `$WORK_DIR/gb/roms` and
are not committed. The downloader pins and verifies both hashes:

| Artifact | SHA-256 |
| --- | --- |
| Original ZIP | `c5ec138071079b9cad227d6fb875ad4e58a77f173ed3cd8758c04c0ab166d6e7` |
| `tobutobugirl/tobu.gb` (262,144 bytes) | `5d3871cae77db2287807e8914fd21f76203e73aa3fec20955489d45cb4571d8f` |

Game source is MIT; graphics, text, sound and music are CC BY 4.0, as stated in
the [author's repository](https://github.com/SimonLarsen/tobutobugirl).
Peanut-GB and its SDL example are MIT; their copyright/license notices stay in
the pinned source. The patch does not require a Game Boy boot ROM.

## Isolated guest and deployment

Shut down the milestone 3 VM before copying. Never convert a running disk, and
do not overwrite an existing emulator test image.

```bash
export DISK_IMAGE=$WORK_DIR/images/emulator.qcow2
test ! -e "$DISK_IMAGE"
qemu-img convert -p -f qcow2 -O qcow2 "$WORK_DIR/images/emulationstation.qcow2" "$DISK_IMAGE"
bash scripts/run-qemu.sh gtk-gl
```

In a second WSL shell, with the same variables, once SSH is ready:

```bash
bash scripts/gb.sh deploy
bash scripts/gb.sh run       # standalone diagnosis; Escape exits
bash scripts/es.sh run      # select Game Boy, then Tobu Tobu Girl
```

The guest helpers default to `emulator.qcow2` and reuse the existing SSH options.
For `es.sh`, export `DISK_IMAGE` explicitly as shown above. Deployment rejects
the milestone 2/3 reference images and the primary/raw images. It installs under
`/opt/darkos-emulators/peanut-gb`, with separate `roms`, `saves`, and `logs`.
It adds/replaces only the `gb` system in the isolated ES profile and explicitly
sets `HideWindow=true` and `StartupSystem=gb`. The original `.demo` test remains.
ES passes its escaped `%ROM%` argument to the same wrapper as the standalone run.
The wrapper preserves the emulator exit code and reports a missing ROM as exit 2.

Keyboard: arrows = D-pad, Z/X = A/B, Enter = Start, Backspace = Select,
Escape = quit the emulator and return to ES. In ES, Enter accepts, Escape goes
back, and Space opens the menu. Run both applications as root for DRM/input
access. Audio and gamepads are outside this milestone.
SDL's KMS keyboard mapping uses US key positions: on the tested Czech QWERTZ
host, pressing Y delivered SDL Z (A), while pressing Z delivered SDL Y.

While the emulator runs, use a third shell:

```bash
bash scripts/gb.sh audit
```

The audit checks live process maps and `ldd`, requiring private SDL2, EGL,
OpenGL, GBM and Gallium and rejecting libMali/libgo2 or unresolved dependencies.
Logs are under `$WORK_DIR/logs/gb` and guest
`/opt/darkos-emulators/peanut-gb/logs`. A new per-launch log is retained for every
game session. Saves remain separate from the read-only test ROM.

## Acceptance

Validate at least 60 seconds of standalone operation, enter actual gameplay,
and check keyboard response. Then perform three ES → game → Escape → ES cycles,
confirming that ES regains graphics and keyboard control each time. Its normal
launch code tears down the SDL window/context before the child starts and
reinitializes them afterwards; no background emulator may remain.

For the missing-ROM case, first let ES enumerate the game, temporarily rename
the guest ROM over SSH, and launch its cached list entry. Check the wrapper's
nonzero status and ES recovery, then restore the ROM. Finally check SSH, quit ES,
power off through systemd and run `qemu-img check` while the image is offline.

## Recorded results (2026-10-19)

The first compile/link took **1.122 seconds**; a fresh build of the final patch
took **1.185 seconds**, plus about three seconds of CMake configuration. The
fresh build and deployed executable have identical SHA-256
`b01f4c0aaccde3e26d4f331c9ff6d4bbad646fb1f4e39e23d110d1e44b6aa416`.
The only direct runtime dependencies are SDL2, glibc and the ARM64 loader; the
ELF requires at most GLIBC 2.34. GCC 12.5.0, CMake 4.2.3 and Ninja 1.13.2 were used.

The frontend reported `SDL backend=KMSDRM renderer=opengl`, Mesa
`25.0.7-2+deb13u1`, desktop OpenGL **4.3 Compatibility Profile**, and
`virgl (LLVMPIPE (LLVM 21.1.8, 256 bits))`. The private SDL runtime is 2.32.4.
Both emulator and restored ES passed live library checks with no libMali/libgo2.
No ES source changes were needed for DRM handoff.

The final executable completed these three UI-driven ES launch/return cycles:

| Cycle | Guest PID | Presented frames | Elapsed | Result |
| --- | --- | --- | --- | --- |
| 1 | 2226 | 3,688 | 66.344 s | Entered Plains, Right, Escape, ES menu usable |
| 2 | 2610 | 4,071 | 74.242 s | Entered Plains, Escape, ES system/list navigation usable |
| 3 | 2952 | 3,692 | 66.369 s | Entered Plains, Left, Escape, ES usable |

The final standalone run (PID 3687) rendered **6,476 frames in 121.154 seconds**,
with Start, A, B and Escape recorded in the input log; it exited with status 0.
An earlier standalone run also passed (7,627 frames in 138.858 seconds).
Diagnostic runs before the short-input fix remain in the evidence and are not
counted among the three final cycles.

The missing-ROM test returned wrapper exit 2. ES logs the raw `system()` wait
status **512**, then successfully recreated its KMSDRM/OpenGL window; its menu
and keyboard still worked. The original ROM was restored. The 8 KiB save and
local gamelist persisted. The first creation of `gamelist.xml` produces the
fork's missing-old-backup warning; the resulting XML was created successfully.
ALSA mixer warnings refer to the absent hardware card; SDL audio uses dummy.

Reference-image mutation and deployment over a running emulator were both
rejected. Shell/Python syntax checks and patch validation passed. SSH remained
active with guest address `10.0.2.15` after all processes exited.
All six existing launcher tests passed. The guest cleanly powered off, QEMU
exited with status 0, and the offline image check found no errors. See
[shutdown](evidence/gb/shutdown.log) and [image check](evidence/gb/image-check.log).

Evidence is under [evidence/gb](evidence/gb):
[build log](evidence/gb/build.log), [provenance](evidence/gb/build-manifest.log),
[ES launch/return log](evidence/gb/es-launch-return.log),
[standalone log](evidence/gb/standalone-final.log),
[live audit](evidence/gb/audit.log), [process maps](evidence/gb/emulator.maps),
and [ROM provenance](evidence/gb/rom-manifest.json).
The screenshots show [gameplay](evidence/gb/final.png),
[cycle 2](evidence/gb/cycle2.png), [cycle 3](evidence/gb/cycle3.png), and
[ES recovery after a missing ROM](evidence/gb/recovered.png).
