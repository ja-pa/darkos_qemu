#!/usr/bin/env bash
# Host-side entry point. Boot graphics.qcow2 with run-qemu.sh gtk-gl first.
source "$(dirname -- "$0")/common.sh"
remote() { bash "$PROJECT_DIR/scripts/graphics-ssh.sh" "$@"; }
guest=/home/ark/darkos-graphics
action=${1:-diagnose}
if [[ $action != diagnose ]]; then
  export WORK_DIR
  python3 "$PROJECT_DIR/scripts/graphics-assert-vm.py"
fi
case "$action" in
  diagnose) remote bash -s < "$PROJECT_DIR/scripts/graphics-diagnose.sh";;
  prepare) remote sudo -n bash -s < "$PROJECT_DIR/scripts/graphics-prepare.sh";;
  deploy)
    tar -C "$PROJECT_DIR" -cf - demos/sdl-kms/hello.c demos/sdl-kms/Makefile \
      scripts/graphics-env.sh scripts/graphics-run.sh |
      remote "mkdir -p $guest && tar -xf - -C $guest"
    ;;
  build)
    bash "$0" deploy
    remote "cd $guest/demos/sdl-kms && make && bash $guest/scripts/graphics-env.sh ./hello --drivers"
    ;;
  kmscube|sdl)
    # Build deploys the common runner; deploy alone suffices for kmscube.
    bash "$0" deploy
    remote "sudo -n bash $guest/scripts/graphics-run.sh $action"
    ;;
  *) fail 'Usage: graphics.sh diagnose|prepare|deploy|build|kmscube|sdl';;
esac
