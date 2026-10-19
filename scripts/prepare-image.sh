#!/usr/bin/env bash
source "$(dirname -- "$0")/common.sh"
SEVENZIP=$(command -v 7zz || command -v 7z) || fail 'Missing dependency: 7zip'
need qemu-img
ARCHIVE=${ARCHIVE:-$PROJECT_DIR/images/dArkOS_RG353m_trixie_01312026.img.7z.001}
[[ -f "$ARCHIVE" && -f "${ARCHIVE%.001}.002" ]] || fail "Both archive volumes required beside $ARCHIVE"
mkdir -p "$(dirname "$RAW_IMAGE")" "$WORK_DIR/logs"
sha256sum "$ARCHIVE" "${ARCHIVE%.001}.002" > "$WORK_DIR/logs/archive.sha256"
"$SEVENZIP" t "$ARCHIVE" > "$WORK_DIR/logs/archive-test.log"
if [[ ! -e "$RAW_IMAGE" ]]; then
  # Extract into a staging directory: an interrupted extraction cannot become the base image.
  stage=$(mktemp -d "$(dirname "$RAW_IMAGE")/.extract.XXXXXX")
  "$SEVENZIP" x "$ARCHIVE" "-o$stage" > "$WORK_DIR/logs/archive-extract.log"
  extracted="$stage/dArkOS_RG353m_trixie_01312026.img"
  [[ -f "$extracted" ]] || fail "Expected image absent in $stage"
  mv -- "$extracted" "$RAW_IMAGE"
  rmdir "$stage"
fi
[[ $(stat -c %s "$RAW_IMAGE") == 8053063680 ]] || fail 'Unexpected raw image size'
sha256sum "$RAW_IMAGE" > "$WORK_DIR/logs/base-image.sha256"
chmod a-w "$RAW_IMAGE"
DISK_IMAGE=${DISK_IMAGE:-$WORK_DIR/images/darkos.qcow2}
if [[ ! -e "$DISK_IMAGE" ]]; then
  qemu-img create -f qcow2 -F raw -b "$(realpath "$RAW_IMAGE")" "$DISK_IMAGE"
fi
qemu-img info --backing-chain "$DISK_IMAGE"
