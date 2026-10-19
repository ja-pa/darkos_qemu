#!/usr/bin/env bash
source "$(dirname -- "$0")/scripts/workflow-common.sh"
case ${1:-help} in
  source|import)
    action=$1
    if [[ $action == source ]]; then
      archive=${ARCHIVE:-$PROJECT_DIR/images/dArkOS_RG353m_trixie_01312026.img.7z.001}
      [[ -f $archive && -f ${archive%.001}.002 ]] || fail "Download both dArkOS_RG353m_trixie_01312026 archive volumes from https://github.com/christianhaitian/dArkOS/releases#release-v01302026 into $PROJECT_DIR/images, or set ARCHIVE to .001"
    fi
    as_root bash "$PROJECT_DIR/scripts/setup-host.sh"
    mkdir -p "$WORK_DIR/ssh" "$WORK_DIR/images"
    if [[ ! -e $SSH_KEY ]]; then ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY"; fi
    [[ -s $SSH_KEY.pub ]] || fail "Missing public key: $SSH_KEY.pub"
    if [[ $action == source ]]; then
      bash "$PROJECT_DIR/scripts/build-kernel.sh"
      bash "$PROJECT_DIR/scripts/prepare-image.sh"
    else
      [[ $# == 2 ]] || fail 'Usage: setup.sh import <runtime-directory>'
      python3 "$PROJECT_DIR/scripts/workflow-bundle.py" import-runtime "$2"
    fi
    guest_marker=$WORK_DIR/state/guest-prepared-$(printf '%s\n' "$DISK_IMAGE" "$(cat "$SSH_KEY.pub")" | sha256sum | cut -d ' ' -f 1)
    if [[ ! -f $guest_marker ]]; then
      as_root env WORK_DIR="$WORK_DIR" DISK_IMAGE="$DISK_IMAGE" SSH_PUBLIC_KEY="$SSH_KEY.pub" bash "$PROJECT_DIR/scripts/prepare-guest.sh"
      touch "$guest_marker"
    fi
    echo 'Setup complete. Next: bash sdk.sh prepare (source), or bash vm.sh es (runtime import).'
    ;;
  *) echo 'Usage: bash setup.sh source | import <runtime-directory>'; exit 2;;
esac
