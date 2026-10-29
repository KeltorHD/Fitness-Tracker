#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Этот скрипт запускается только на macOS. Xcode на Linux не запускается.' >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'Установите полный Xcode 26+ и выберите его: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer' >&2
  exit 1
fi
xcode_major="$(xcodebuild -version | awk '/^Xcode / {split($2, v, "."); print v[1]}')"
if [[ "$xcode_major" -lt 26 ]]; then echo 'Нужен Xcode 26 или новее с iOS/watchOS 26 SDK.' >&2; exit 1; fi
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Установите Homebrew с https://brew.sh, затем повторите скрипт.' >&2; exit 1
  fi
  brew install xcodegen
fi
if [[ ! -f Config/Local.xcconfig ]]; then
  cp Config/Local.xcconfig.example Config/Local.xcconfig
  echo 'Создан Config/Local.xcconfig: укажите Team ID и свой Bundle ID перед запуском на устройстве.'
fi
xcodebuild -version
xcodegen --version
swift build
swift test
# XcodeGen validates the real spec on the platform where generation is supported.
xcodegen generate
printf '\nГотово: откройте FitSession.xcodeproj. Следуйте MAC_BUILD_GUIDE.md для signing, сборки и интеграций.\n'
