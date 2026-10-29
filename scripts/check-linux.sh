#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift_bin="${SWIFT_BIN:-swift}"
if ! command -v "$swift_bin" >/dev/null 2>&1; then
  swift_bin="$PWD/.toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swift"
fi
if [[ ! -x "$swift_bin" ]] && ! command -v "$swift_bin" >/dev/null 2>&1; then
  echo 'Сначала установите Swift: bash scripts/setup-linux.sh' >&2; exit 1
fi
# Explicit caches make the script usable in restricted Linux workspaces.
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" .build/cache .build/config .build/security
flags=(--cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
"$swift_bin" --version
"$swift_bin" build "${flags[@]}"
"$swift_bin" test "${flags[@]}"
python3 scripts/validate-project.py
python3 scripts/validate-exercise-library.py
swiftc_bin="$(dirname "$(command -v "$swift_bin")")/swiftc"
python3 scripts/parse-apple.py "$swiftc_bin"
if "$swift_bin" format --help >/dev/null 2>&1; then
  "$swift_bin" format lint --strict --recursive Sources Tests Apple Package.swift
else
  echo 'swift format отсутствует; требуется Swift 6.2+ для проверки форматирования.' >&2; exit 1
fi
bash -n scripts/setup-linux.sh scripts/setup-macos.sh scripts/check-linux.sh
printf '\nLinux checks passed. Apple SDK type checking, rendering and runtime remain unverified.\n'
