#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
export WORK_DIR=$(realpath -m -- "$WORK_DIR")
export DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/emulationstation.qcow2}
export ES_SYSROOT=$(realpath -m -- "${ES_SYSROOT:-$WORK_DIR/es/sysroot}")
ES_SRC=${ES_SRC:-$WORK_DIR/repos/EmulationStation-fcamod}
ES_BUILD_DIR=${ES_BUILD_DIR:-$WORK_DIR/es/build}
ES_COMMIT=db23162142f2d01c4c08216895fd793da243d19b
logs=$WORK_DIR/logs/es
mkdir -p "$logs"
remote() { bash "$PROJECT_DIR/scripts/graphics-ssh.sh" "$@"; }
assert_vm() {
  [[ $(realpath -m "$DISK_IMAGE") != "$(realpath -m "$WORK_DIR/images/graphics.qcow2")" ]] || fail 'Copy graphics.qcow2 to a separate ES disk first'
  python3 "$PROJECT_DIR/scripts/graphics-assert-vm.py"
}
case ${1:-help} in
  prepare)
    assert_vm
    remote sudo -n bash -s < "$PROJECT_DIR/scripts/es-prepare.sh" | tee "$logs/prepare.log"
    ;;
  sysroot)
    assert_vm
    [[ $WORK_DIR != / && $ES_SYSROOT == "$WORK_DIR"/* ]] || fail 'ES_SYSROOT must be inside WORK_DIR'
    mkdir -p "$ES_SYSROOT"
    # Tar preserves all target symlinks. Only the copied sysroot is normalized.
    remote 'sudo -n tar -C / -cf - usr/include usr/lib/aarch64-linux-gnu usr/lib/gcc usr/lib/pkgconfig lib opt/darkos-graphics/usr usr/share/pkgconfig usr/share/doc usr/share/common-licenses' |
      tar -C "$ES_SYSROOT" -xf -
    python3 "$PROJECT_DIR/scripts/es-sysroot.py" "$ES_SYSROOT"
    remote 'dpkg-query -W' > "$logs/sysroot-packages.tsv"
    ;;
  build)
    need aarch64-linux-gnu-g++-12; need cmake; need ninja
    if [[ ! -d $ES_SRC/.git ]]; then
      mkdir -p "$(dirname -- "$ES_SRC")"
      git clone --no-checkout https://github.com/ja-pa/EmulationStation-fcamod.git "$ES_SRC"
      git -C "$ES_SRC" checkout --detach "$ES_COMMIT"
    fi
    [[ $(git -C "$ES_SRC" rev-parse HEAD) == "$ES_COMMIT" ]] || fail "ES_SRC must be at $ES_COMMIT"
    git -C "$ES_SRC" submodule update --init --recursive
    for patch in "$PROJECT_DIR"/patches/emulationstation/*.patch; do
      if git -C "$ES_SRC" apply --reverse --check "$patch" 2>/dev/null; then continue; fi
      git -C "$ES_SRC" apply --check "$patch"
      git -C "$ES_SRC" apply "$patch"
    done
    [[ -f $ES_SYSROOT/usr/include/stdio.h ]] || fail 'Run es.sh sysroot first'
    export PKG_CONFIG_SYSROOT_DIR=$ES_SYSROOT
    export PKG_CONFIG_LIBDIR=$ES_SYSROOT/opt/darkos-graphics/usr/lib/aarch64-linux-gnu/pkgconfig:$ES_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$ES_SYSROOT/usr/share/pkgconfig
    unset PKG_CONFIG_PATH
    cmake -S "$ES_SRC" -B "$ES_BUILD_DIR" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$PROJECT_DIR/scripts/es-toolchain.cmake" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DSDL_KMSDRM=ON -DGL=ON -DGLES=OFF -DCEC=OFF -DRPI=OFF \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON |& tee "$logs/configure.log"
    cmake --build "$ES_BUILD_DIR" -j "${JOBS:-4}" |& tee -a "$logs/build.log"
    aarch64-linux-gnu-readelf -h -d -V "$ES_BUILD_DIR/emulationstation" > "$logs/elf.log"
    ! aarch64-linux-gnu-nm -u "$ES_BUILD_DIR/emulationstation" | grep -Ei 'go2_|mali' || fail 'Forbidden GPU dependency'
    {
      aarch64-linux-gnu-g++-12 --version
      cmake --version
      ninja --version
      pkg-config --version
      git -C "$ES_SRC" rev-parse HEAD
      git -C "$ES_SRC" submodule status
      sha256sum "$PROJECT_DIR"/patches/emulationstation/*.patch "$ES_BUILD_DIR/emulationstation"
    } > "$logs/build-manifest.log"
    ;;
  probe)
    assert_vm
    mkdir -p "$WORK_DIR/es"
    lib=$ES_SYSROOT/opt/darkos-graphics/usr/lib/aarch64-linux-gnu
    aarch64-linux-gnu-gcc-12 --sysroot="$ES_SYSROOT" \
      -I"$ES_SYSROOT/opt/darkos-graphics/usr/include/SDL2" \
      "$PROJECT_DIR/demos/sdl-gl21/probe.c" -L"$lib" \
      -Wl,-rpath-link,"$ES_SYSROOT/usr/lib/aarch64-linux-gnu" \
      -Wl,-rpath-link,"$lib" -lSDL2 -lOpenGL -o "$WORK_DIR/es/gl21-probe"
    tar -C "$PROJECT_DIR" -cf - scripts/es-env.sh | remote 'sudo -n tar -C /opt/darkos-es -xf -'
    tar -C "$WORK_DIR/es" -cf - gl21-probe | remote 'sudo -n tar -C /opt/darkos-es -xf -'
    remote 'sudo -n bash /opt/darkos-es/scripts/es-env.sh /opt/darkos-es/gl21-probe' |& tee "$logs/probe.log"
    ;;
  deploy)
    assert_vm
    remote 'if pidof emulationstation >/dev/null; then echo "Quit ES before deployment" >&2; exit 1; fi'
    [[ -s $ES_BUILD_DIR/emulationstation ]] || fail 'Run es.sh build first'
    mkdir -p "$WORK_DIR/es/stage"
    aarch64-linux-gnu-strip --strip-debug -o "$WORK_DIR/es/stage/emulationstation" "$ES_BUILD_DIR/emulationstation"
    sha256sum "$WORK_DIR/es/stage/emulationstation" > "$logs/deployed.sha256"
    tar -C "$WORK_DIR/es/stage" -cf - emulationstation | remote 'sudo -n tar -C /opt/darkos-es -xf -'
    tar -C "$ES_SRC" -cf - resources | remote 'sudo -n tar -C /opt/darkos-es -xf -'
    tar -C "$PROJECT_DIR" -cf - scripts/es-env.sh scripts/es-audit.sh demos/sdl-gl21/probe.c fixtures/es |
      remote 'sudo -n tar -C /opt/darkos-es -xf -'
    remote 'sudo -n mkdir -p /opt/darkos-es/home; sudo -n cp -an /opt/darkos-es/fixtures/es/. /opt/darkos-es/home/'
    ;;
  run)
    assert_vm
    remote 'if pidof emulationstation >/dev/null; then echo "ES is already running" >&2; exit 1; fi'
    remote 'cd /opt/darkos-es && sudo -n bash scripts/es-env.sh ./emulationstation --home /opt/darkos-es/home --debug --no-splash' |& tee "$logs/run.log"
    ;;
  *) fail 'Usage: es.sh prepare|sysroot|probe|build|deploy|run';;
esac
