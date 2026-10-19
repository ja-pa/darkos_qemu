#!/usr/bin/env bash
source "$(dirname -- "$0")/scripts/workflow-common.sh"
action=${1:-help}
target=${2:-}
build_demo() {
  source "$WORK_DIR/sdk/environment.sh"
  local name=${1:-sdl-demo} src=${2:-$PROJECT_DIR/demos/sdk-app}
  cmake -S "$src" -B "$WORK_DIR/apps/$name" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$DARKOS_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  TIMEFORMAT='Compile/link wall time: %3R seconds'
  { time cmake --build "$WORK_DIR/apps/$name" -j "${JOBS:-4}"; } |& tee "$WORK_DIR/logs/workflow/$name-build.log"
  while IFS= read -r -d '' bin; do
    aarch64-linux-gnu-readelf -h -d -V "$bin" > "$WORK_DIR/logs/workflow/$name-$(basename "$bin").elf.log"
    ! aarch64-linux-gnu-nm -u "$bin" | grep -Ei 'go2_|mali' || fail 'Forbidden GPU dependency'
  done < <(find "$WORK_DIR/apps/$name" -maxdepth 1 -type f -executable -print0)
}
deploy_demo() {
  local bin=$1 name
  name=$(basename "$bin")
  [[ $name =~ ^[a-zA-Z0-9_-]{1,15}$ && -s $bin ]] || fail 'Executable name must contain 1-15 letters, digits, underscores or hyphens'
  aarch64-linux-gnu-readelf -h "$bin" | grep -q AArch64 || fail 'Expected ARM64 ELF'
  remote "if pgrep -x '$name' >/dev/null; then echo 'Quit $name before deployment' >&2; exit 1; fi"
  remote "sudo -n mkdir -p /opt/darkos-apps/$name"
  tar -C "$(dirname "$bin")" -cf - "$name" | remote "sudo -n tar -C /opt/darkos-apps/$name -xf -"
  tar -C "$PROJECT_DIR/scripts" -cf - es-env.sh | remote "sudo -n tar -C /opt/darkos-apps/$name -xf -"
}
case $action in
  build|deploy)
    [[ $target == es || $target == peanut-gb || $target == sdl-demo || $target == all ]] || fail 'Target must be es|peanut-gb|sdl-demo|all'
    sdk_check
    if [[ $action == deploy ]]; then
      ensure_vm; trap finish_vm EXIT; sdk_match
      remote 'if pidof emulationstation peanut-sdl sdl-demo >/dev/null; then echo "Quit graphical applications before deployment" >&2; exit 1; fi'
    fi
    targets=("$target"); [[ $target != all ]] || targets=(es peanut-gb sdl-demo)
    for item in "${targets[@]}"; do
      case $item:$action in
        es:build) bash "$PROJECT_DIR/scripts/es.sh" build;;
        peanut-gb:build) bash "$PROJECT_DIR/scripts/gb.sh" prepare; bash "$PROJECT_DIR/scripts/gb.sh" build;;
        sdl-demo:build) build_demo;;
        es:deploy)
          if [[ ${3:-} == --reset-profile ]]; then
            remote 'if pidof emulationstation >/dev/null; then exit 1; fi; if test -d /opt/darkos-es/home/.emulationstation; then sudo -n mv /opt/darkos-es/home/.emulationstation /opt/darkos-es/home/.emulationstation.backup.$(date +%s); fi'
          elif [[ -n ${3:-} ]]; then fail 'Unknown deployment option'; fi
          bash "$PROJECT_DIR/scripts/es.sh" deploy
          remote 'if test -s /opt/darkos-emulators/peanut-gb/peanut-sdl; then sudo -n python3 /opt/darkos-emulators/peanut-gb/scripts/gb-configure.py; fi'
          remote sudo -n python3 - < "$PROJECT_DIR/scripts/workflow-profile.py"
          ;;
        peanut-gb:deploy) bash "$PROJECT_DIR/scripts/gb.sh" deploy; remote sudo -n python3 - < "$PROJECT_DIR/scripts/workflow-profile.py";;
        sdl-demo:deploy)
          deploy_demo "$WORK_DIR/apps/sdl-demo/sdl-demo"
          remote sudo -n python3 - < "$PROJECT_DIR/scripts/workflow-profile.py"
          ;;
      esac
    done
    ;;
  app)
    [[ $# == 2 && -f $target/CMakeLists.txt ]] || fail 'Usage: build.sh app <CMake-source-directory>'
    sdk_check
    name=$(basename "$(realpath "$target")")
    [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || fail 'Use a simple project directory name'
    build_demo "$name" "$(realpath "$target")"
    ;;
  deploy-app)
    [[ $# == 2 ]] || fail 'Usage: build.sh deploy-app <ARM64-binary>'
    ensure_vm; trap finish_vm EXIT; sdk_match; deploy_demo "$target"
    ;;
  *) echo 'Usage: bash build.sh build|deploy es|peanut-gb|sdl-demo|all [--reset-profile] | app <source> | deploy-app <binary>'; exit 2;;
esac
