#!/usr/bin/env bash
source "$(dirname -- "$0")/scripts/workflow-common.sh"
controls() { python3 "$PROJECT_DIR/scripts/controls-window.py" "$1" "$WORK_DIR" || true; }
# Strip the optional flag only for commands that open a graphical VM.
show_controls=true
if [[ ${1:-} == start || ${1:-} == es ]]; then
  args=()
  for arg in "$@"; do
    if [[ $arg == --no-controls ]]; then show_controls=false; else args+=("$arg"); fi
  done
  set -- "${args[@]}"
fi
case ${1:-help} in
  start)
    [[ $# -le 2 ]] || fail 'Usage: vm.sh start [gtk-gl|serial] [--no-controls]'
    vm start "${2:-gtk-gl}"
    if [[ ${2:-gtk-gl} == gtk-gl ]] && $show_controls; then controls start; fi
    ;;
  stop) vm stop; controls stop;;
  status|check) vm "$@";;
  controls) [[ $# == 1 ]] || fail 'Usage: vm.sh controls'; controls start;;
  ssh) vm verify; shift; remote "$@";;
  logs)
    if vm status --quiet; then
      vm verify
      remote sudo -n bash -s < "$PROJECT_DIR/scripts/workflow-guest-logs.sh" > "$WORK_DIR/logs/workflow/guest-logs.tar"
      echo "Guest diagnostics: $WORK_DIR/logs/workflow/guest-logs.tar"
    fi
    tail -n 100 "$WORK_DIR/logs/workflow/serial.log"
    ;;
  es)
    [[ $# == 1 ]] || fail 'Usage: vm.sh es [--no-controls]'
    vm start gtk-gl
    if $show_controls; then controls start; fi
    if [[ -f $WORK_DIR/state/import-profile ]]; then
      remote 'sudo -n python3 /opt/darkos-workflow/gb-configure.py; sudo -n python3 /opt/darkos-workflow/workflow-profile.py'
      rm "$WORK_DIR/state/import-profile"
    fi
    remote 'test -s /opt/darkos-es/emulationstation' || fail 'ES not installed: run bash build.sh build all and bash build.sh deploy all'
    bash "$PROJECT_DIR/scripts/es.sh" run
    ;;
  export) [[ $# == 2 ]] || fail 'Usage: vm.sh export <new-directory>'; vm check; python3 "$PROJECT_DIR/scripts/workflow-bundle.py" export-runtime "$2";;
  *) echo 'Usage: bash vm.sh start [gtk-gl|serial] [--no-controls] | es [--no-controls] | controls | stop | status | ssh [command] | logs | check | export <directory>'; exit 2;;
esac
