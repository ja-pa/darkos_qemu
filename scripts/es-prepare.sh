#!/usr/bin/env bash
# Run as root in the isolated ES guest.
set -euo pipefail
[[ $EUID == 0 && $(dpkg --print-architecture) == arm64 ]]
prefix=/opt/darkos-graphics
mkdir -p /opt/darkos-es/logs "$prefix/packages/es"
log=/opt/darkos-es/logs
cat /etc/apt/sources.list | tee "$log/apt-sources.log"
df -h / | tee "$log/space-before.log"
[[ $(df --output=avail -k / | tail -1) -gt 600000 ]] || { echo 'Need at least 600 MB free' >&2; exit 1; }
apt-get update
deps=(libfreetype-dev libfreeimage-dev libsdl2-mixer-dev libcurl4-openssl-dev libvlc-dev rapidjson-dev libasound2-dev rsync)
apt-get -s --no-install-recommends install "${deps[@]}" | tee "$log/apt-plan.log"
! grep -q '^Remv ' "$log/apt-plan.log" || { echo 'Unexpected removals' >&2; exit 1; }
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${deps[@]}"
cd "$prefix/packages/es"
for package in libopengl0 libopengl-dev libgl1 libgl-dev libglx0 libglx-dev libglvnd0; do
  version=$(apt-cache policy "$package:arm64" | awk '/Candidate:/ {print $2}')
  [[ -n $version && $version != '(none)' ]]
  apt-get download "$package:arm64=$version"
done
sha256sum ./*.deb > "$log/desktop-gl.sha256"
for package in ./*.deb; do dpkg-deb -x "$package" "$prefix"; done
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > "$log/packages.tsv"
