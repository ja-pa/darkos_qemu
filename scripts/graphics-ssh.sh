#!/usr/bin/env bash
# Run a guest command using this project's dedicated development identity.
source "$(dirname -- "$0")/common.sh"
need ssh
exec ssh -i "${SSH_KEY:-$WORK_DIR/ssh/id_ed25519}" -p "${SSH_PORT:-2222}" \
  -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  -o "UserKnownHostsFile=$WORK_DIR/ssh/graphics_known_hosts" \
  "${SSH_USER:-ark}@${SSH_HOST:-127.0.0.1}" "$@"
