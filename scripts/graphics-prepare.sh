#!/usr/bin/env bash
# Run as root INSIDE the isolated graphics guest.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run via sudo inside the graphics VM' >&2; exit 1; }
prefix=${GRAPHICS_PREFIX:-/opt/darkos-graphics}
mkdir -p "$prefix/packages" "$prefix/logs"
[[ $(dpkg --print-architecture) == arm64 ]] || { echo 'ARM64 guest required' >&2; exit 1; }
apt-get -o Acquire::Retries=3 update
packages=(kmscube libdrm-tests gcc make pkg-config)
apt-cache policy "${packages[@]}" libsdl2-2.0-0:arm64 libgbm1:arm64 libegl-mesa0:arm64 | tee "$prefix/logs/package-policy.log"
df -h / | tee "$prefix/logs/space-before.log"
apt-get -s --no-install-recommends install "${packages[@]}" | tee "$prefix/logs/apt-plan.log"
if grep -q '^Remv ' "$prefix/logs/apt-plan.log"; then
  echo 'Unexpected package removals; inspect apt-plan.log before proceeding' >&2
  exit 1
fi
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y --no-install-recommends "${packages[@]}"
# Vendor symlinks override files owned by already-installed Debian packages.
# Extract matching official runtime/development packages to a private prefix.
download_dir=$(mktemp -d "$prefix/packages/run.XXXXXX")
cd "$download_dir"
graphics=(libsdl2-2.0-0 libsdl2-dev libgbm1 libgbm-dev libegl1 libegl-dev
          libgles2 libgles-dev libegl-mesa0 libgl1-mesa-dri mesa-libgallium)
for package in "${graphics[@]}"; do
  version=$(apt-cache policy "$package:arm64" | awk '/Candidate:/ {print $2}')
  [[ -n "$version" && "$version" != '(none)' ]] || { echo "No candidate: $package" >&2; exit 1; }
  apt-get download "$package:arm64=$version"
done
sha256sum "$download_dir"/*.deb > "$prefix/logs/packages.sha256"
for package in ./*.deb; do dpkg-deb -x "$package" "$prefix"; done
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > "$prefix/logs/installed-packages.txt"
echo "Official graphics packages extracted to $prefix; system vendor libraries preserved."
