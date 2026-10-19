#!/usr/bin/env bash
source "$(dirname -- "$0")/scripts/workflow-common.sh"
case ${1:-help} in
  prepare)
    [[ $# == 1 || ( $# == 2 && ${2:-} == --refresh ) ]] || fail 'Usage: sdk.sh prepare [--refresh]'
    ensure_vm
    trap finish_vm EXIT
    remote 'if pidof emulationstation peanut-sdl sdl-demo kmscube hello gl21-probe >/dev/null; then echo "Quit graphical applications before preparing SDK" >&2; exit 1; fi'
    if [[ ${2:-} != --refresh && -f $WORK_DIR/sdk/manifest.json ]] && sdk_check >/dev/null 2>&1; then
      remote sudo -n bash -s < "$PROJECT_DIR/scripts/workflow-runtime-id.sh" > "$WORK_DIR/state/probed-runtime-id"
      if cmp -s "$WORK_DIR/sdk/runtime-id" "$WORK_DIR/state/probed-runtime-id"; then
        # Complete copyright metadata when upgrading an earlier local SDK.
        if [[ ! -d $ES_SYSROOT/usr/share/common-licenses ]]; then
          remote 'tar -C / -cf - usr/share/common-licenses' | tar -C "$ES_SYSROOT" -xf -
          python3 "$PROJECT_DIR/scripts/workflow-sdk.py" record
        fi
        echo 'SDK already matches runtime; no packages or sysroot need rebuilding. Use --refresh to check repository updates.'
        exit 0
      fi
    fi
    remote 'sudo -n rm -f /opt/darkos-graphics/runtime-id'
    remote sudo -n bash -s < "$PROJECT_DIR/scripts/graphics-prepare.sh" |& tee "$WORK_DIR/logs/workflow/graphics-prepare.log"
    bash "$PROJECT_DIR/scripts/es.sh" prepare
    remote sudo -n bash -s < "$PROJECT_DIR/scripts/workflow-runtime-id.sh" > "$WORK_DIR/state/runtime-id"
    # Build a new sysroot before replacing the last complete one.
    destination=$ES_SYSROOT
    export ES_SYSROOT=$WORK_DIR/sdk/sysroot.partial
    if [[ -e $ES_SYSROOT ]]; then mv "$ES_SYSROOT" "$ES_SYSROOT.interrupted.$(date +%s)"; fi
    bash "$PROJECT_DIR/scripts/es.sh" sysroot
    mkdir -p "$WORK_DIR/sdk"
    if [[ -e $destination ]]; then mv "$destination" "$destination.previous.$(date +%s)"; fi
    mv "$ES_SYSROOT" "$destination"
    export ES_SYSROOT=$destination
    cp "$WORK_DIR/state/runtime-id" "$WORK_DIR/sdk/runtime-id"
    cp "$PROJECT_DIR/scripts/es-toolchain.cmake" "$WORK_DIR/sdk/toolchain.cmake"
    cp "$PROJECT_DIR/scripts/sdk-environment.sh" "$WORK_DIR/sdk/environment.sh"
    cp "$WORK_DIR/logs/es/sysroot-packages.tsv" "$WORK_DIR/sdk/packages.tsv"
    python3 "$PROJECT_DIR/scripts/workflow-sdk.py" record
    sdk_check
    ;;
  check) sdk_check;;
  export) [[ $# == 2 ]] || fail 'Usage: sdk.sh export <new-directory>'; python3 "$PROJECT_DIR/scripts/workflow-bundle.py" export-sdk "$2";;
  import) [[ $# == 2 ]] || fail 'Usage: sdk.sh import <sdk-directory>'; python3 "$PROJECT_DIR/scripts/workflow-bundle.py" import-sdk "$2"; sdk_check;;
  *) echo 'Usage: bash sdk.sh prepare [--refresh]|check|export <directory>|import <directory>'; exit 2;;
esac
