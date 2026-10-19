#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
export WORK_DIR=$(realpath -m "$WORK_DIR")
export DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/work.qcow2}
export KERNEL_IMAGE=${KERNEL_IMAGE:-$BUILD_DIR/arch/arm64/boot/Image}
export ES_SYSROOT=${ES_SYSROOT:-$WORK_DIR/sdk/sysroot}
[[ $(realpath -m "$ES_SYSROOT") == "$WORK_DIR/sdk/sysroot" ]] || fail 'For the four entry points, unset ES_SYSROOT or select WORK_DIR/sdk/sysroot; legacy scripts still support custom sysroots'
export SSH_KEY=${SSH_KEY:-$WORK_DIR/ssh/id_ed25519}
export SSH_PORT=${SSH_PORT:-2222}
export QMP_SOCKET=${QMP_SOCKET:-$WORK_DIR/state/qmp.sock}
umask 077
mkdir -p "$WORK_DIR/logs/workflow" "$WORK_DIR/state"
remote() { bash "$PROJECT_DIR/scripts/graphics-ssh.sh" "$@"; }
vm() { python3 "$PROJECT_DIR/scripts/workflow-vm.py" "$@"; }
owned_vm=false
ensure_vm() {
  if vm status --quiet; then
    vm start gtk-gl
  else
    vm start gtk-gl
    owned_vm=true
  fi
}
finish_vm() { if $owned_vm; then vm stop; fi; }
as_root() { if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi; }
sdk_check() { python3 "$PROJECT_DIR/scripts/workflow-sdk.py" check; }
sdk_match() {
  sdk_check
  if ! remote 'cat /opt/darkos-graphics/runtime-id' > "$WORK_DIR/state/connected-runtime-id"; then
    fail 'Runtime preparation is incomplete: run bash sdk.sh prepare'
  fi
  cmp -s "$WORK_DIR/sdk/runtime-id" "$WORK_DIR/state/connected-runtime-id" || fail 'SDK/runtime mismatch: run bash sdk.sh prepare before deploying'
}
