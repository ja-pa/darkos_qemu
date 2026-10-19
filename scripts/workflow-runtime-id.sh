#!/usr/bin/env bash
set -euo pipefail
cd /opt/darkos-graphics
{
  find usr -type f -print0 | sort -z | xargs -0 sha256sum
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort
} | sha256sum | cut -d ' ' -f 1 > runtime-id.new
mv runtime-id.new runtime-id
cat runtime-id
