#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
export WORK_DIR=$(realpath -m -- "$WORK_DIR")
export DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/emulator.qcow2}
export ES_SYSROOT=${ES_SYSROOT:-$WORK_DIR/es/sysroot}
GB_SRC=${GB_SRC:-$WORK_DIR/repos/Peanut-GB}
GB_BUILD_DIR=${GB_BUILD_DIR:-$WORK_DIR/gb/build}
commit=d0bcca771c83a2638c93a9ae61f3d51f226dc905
root=/opt/darkos-emulators/peanut-gb
logs=$WORK_DIR/logs/gb
mkdir -p "$logs"
remote() { bash "$PROJECT_DIR/scripts/graphics-ssh.sh" "$@"; }
assert_vm() {
  for reference in graphics emulationstation; do
    [[ $(realpath -m "$DISK_IMAGE") != "$(realpath -m "$WORK_DIR/images/$reference.qcow2")" ]] || fail 'Use a separate emulator.qcow2 copy'
  done
  python3 "$PROJECT_DIR/scripts/graphics-assert-vm.py"
}
case ${1:-help} in
  prepare)
    if [[ ! -d $GB_SRC/.git ]]; then
      mkdir -p "$(dirname -- "$GB_SRC")"
      git clone --no-checkout https://github.com/deltabeard/Peanut-GB.git "$GB_SRC"
      git -C "$GB_SRC" checkout --detach "$commit"
    fi
    [[ $(git -C "$GB_SRC" rev-parse HEAD) == "$commit" ]] || fail "GB_SRC must be at $commit"
    python3 "$PROJECT_DIR/scripts/gb-rom.py" "$WORK_DIR/gb/roms" | tee "$logs/prepare.log"
    ;;
  build)
    [[ $(git -C "$GB_SRC" rev-parse HEAD) == "$commit" ]] || fail 'Run gb.sh prepare first'
    [[ -f $ES_SYSROOT/usr/include/stdio.h ]] || fail 'Missing ES sysroot'
    for patch in "$PROJECT_DIR"/patches/peanut-gb/*.patch; do
      if git -C "$GB_SRC" apply --reverse --check "$patch" 2>/dev/null; then continue; fi
      git -C "$GB_SRC" apply --check "$patch"
      git -C "$GB_SRC" apply "$patch"
    done
    export PKG_CONFIG_SYSROOT_DIR=$ES_SYSROOT
    export PKG_CONFIG_LIBDIR=$ES_SYSROOT/opt/darkos-graphics/usr/lib/aarch64-linux-gnu/pkgconfig
    unset PKG_CONFIG_PATH
    cmake -S "$GB_SRC/examples/sdl2" -B "$GB_BUILD_DIR" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$PROJECT_DIR/scripts/es-toolchain.cmake" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DLIBRARY_DISCOVER_METHOD=PKG_CONFIG -DENABLE_SOUND=ON \
      -DDARKOS_SDL_PREFIX="$ES_SYSROOT/opt/darkos-graphics/usr" |& tee "$logs/configure.log"
    TIMEFORMAT='Compile/link wall time: %3R seconds'
    { time cmake --build "$GB_BUILD_DIR" --target peanut-sdl -j "${JOBS:-4}"; } |& tee "$logs/build.log"
    aarch64-linux-gnu-readelf -h -d -V "$GB_BUILD_DIR/peanut-sdl" > "$logs/elf.log"
    ! aarch64-linux-gnu-nm -u "$GB_BUILD_DIR/peanut-sdl" | grep -Ei 'go2_|mali' || fail 'Forbidden GPU dependency'
    {
      aarch64-linux-gnu-gcc-12 --version
      cmake --version
      ninja --version
      git -C "$GB_SRC" rev-parse HEAD
      sha256sum "$PROJECT_DIR"/patches/peanut-gb/*.patch "$GB_BUILD_DIR/peanut-sdl"
    } > "$logs/build-manifest.log"
    ;;
  deploy)
    assert_vm
    [[ -s $GB_BUILD_DIR/peanut-sdl ]] || fail 'Run gb.sh build first'
    remote 'if pgrep -x peanut-sdl >/dev/null; then echo "Quit Peanut-SDL before deployment" >&2; exit 1; fi'
    remote "sudo -n mkdir -p $root/scripts $root/roms $root/saves $root/logs"
    tar -C "$GB_BUILD_DIR" -cf - peanut-sdl | remote "sudo -n tar -C $root -xf -"
    tar -C "$PROJECT_DIR/scripts" -cf - es-env.sh gb-run.sh gb-audit.sh gb-configure.py |
      remote "sudo -n tar -C $root/scripts -xf -"
    tar -C "$WORK_DIR/gb/roms" -cf - 'Tobu Tobu Girl.gb' rom-manifest.json |
      remote "sudo -n tar -C $root/roms -xf -"
    remote "sudo -n python3 $root/scripts/gb-configure.py"
    ;;
  run)
    assert_vm
    remote "sudo -n bash $root/scripts/gb-run.sh '$root/roms/Tobu Tobu Girl.gb'" |& tee "$logs/standalone.log"
    ;;
  audit)
    assert_vm
    remote "sudo -n bash $root/scripts/gb-audit.sh" |& tee -a "$logs/audit.log"
    ;;
  *) fail 'Usage: gb.sh prepare|build|deploy|run|audit';;
esac
