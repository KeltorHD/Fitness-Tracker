#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Этот скрипт предназначен для Linux. На Mac используйте setup-macos.sh.' >&2
  exit 1
fi
if command -v swift >/dev/null 2>&1; then
  swift --version
  exit 0
fi
# Official Swift 6 toolchain; install inside the repository, without sudo.
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 24.04 || "$(uname -m)" != x86_64 ]]; then
  echo 'Автоустановка настроена для Ubuntu 24.04 x86_64. Выберите toolchain на https://www.swift.org/install/linux/ .' >&2
  exit 1
fi
version=6.2.1
install_dir="$PWD/.toolchains"
archive="$install_dir/swift-$version.tar.gz"
toolchain="$install_dir/swift-$version-RELEASE-ubuntu24.04"
mkdir -p "$install_dir"
if [[ ! -x "$toolchain/usr/bin/swift" ]]; then
  curl --fail --location --retry 3 "https://download.swift.org/swift-$version-release/ubuntu2404/swift-$version-RELEASE/swift-$version-RELEASE-ubuntu24.04.tar.gz" -o "$archive"
  tar -xzf "$archive" -C "$install_dir"
fi
"$toolchain/usr/bin/swift" --version
printf '\nДобавьте toolchain в PATH:\nexport PATH="%s/usr/bin:$PATH"\n' "$toolchain"
echo 'Далее: bash scripts/check-linux.sh'
