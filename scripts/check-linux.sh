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
python3 scripts/validate-localizations.py
python3 scripts/validate-branding.py
swiftc_bin="$(dirname "$(command -v "$swift_bin")")/swiftc"
bin_path="$("$swift_bin" build "${flags[@]}" --show-bin-path)"
# These presentation/data types use only Foundation/Observation. This is a real Swift 6
# type check of this explicit subset; it does not compile SwiftUI or Apple integrations.
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -typecheck -I "$bin_path/Modules" \
  Apple/Features/ProgressViewModel.swift Apple/Features/ExerciseProgressViewModel.swift \
  Apple/Features/BodyWeightViewModel.swift \
  Apple/Features/WorkoutExercisePresentation.swift Apple/Features/WorkoutNumberPadModel.swift \
  Apple/Features/HistoryViewModel.swift \
  Apple/Features/ExerciseLibraryViewModel.swift Apple/Services/ExerciseImageLoader.swift \
  Apple/Services/CloudAccountChecking.swift Apple/Shared/WidgetSnapshot.swift \
  Apple/Services/AppCapabilities.swift Apple/Shared/L10n.swift \
  Apple/Design/WorkoutFormatting.swift Apple/Services/LocalHeartRateRepository.swift \
  Apple/Services/HeartRateBluetooth.swift Apple/Services/LiveHeartRate.swift Apple/Services/ServiceError.swift \
  Apple/Features/TrackerViewModel.swift Apple/Features/WorkoutHeartRateViewModel.swift \
  Apple/Features/TrackerDeviceProfile.swift Apple/Shared/AppCompatibility.swift
echo 'Portable presentation/data subset: Swift 6 type check passed (no Apple SDK).'
# Exercise chart presentation with real Core data, without SwiftUI/Charts SDK stand-ins.
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o \
  Apple/Features/ExerciseProgressViewModel.swift Apple/Features/ProgressViewModel.swift \
  Apple/Features/BodyWeightViewModel.swift \
  Tests/PortableProgressChecks/main.swift -o "$bin_path/portable-progress-checks"
"$bin_path/portable-progress-checks"
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o Apple/Features/BodyWeightViewModel.swift \
  Tests/PortableWeightChecks/main.swift -o "$bin_path/portable-weight-checks"
"$bin_path/portable-weight-checks"
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o Apple/Design/WorkoutFormatting.swift Apple/Shared/L10n.swift \
  Tests/PortableCSVChecks/main.swift \
  -o "$bin_path/portable-csv-checks"
"$bin_path/portable-csv-checks"
# Exercise the real tracker presentation/storage subset with fakes, without radio/HealthKit calls.
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o \
  Apple/Services/LocalHeartRateRepository.swift Apple/Services/HeartRateBluetooth.swift Apple/Services/LiveHeartRate.swift \
  Apple/Services/ServiceError.swift Apple/Features/TrackerViewModel.swift \
  Apple/Features/WorkoutHeartRateViewModel.swift Apple/Features/TrackerDeviceProfile.swift \
  Apple/Shared/AppCompatibility.swift \
  Tests/PortableTrackerChecks/main.swift \
  -o "$bin_path/portable-tracker-checks"
"$bin_path/portable-tracker-checks"
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o \
  Apple/Services/LocalHeartRateRepository.swift Apple/Services/HeartRateBluetooth.swift Apple/Services/LiveHeartRate.swift \
  Apple/Services/ServiceError.swift Apple/Features/TrackerViewModel.swift \
  Apple/Features/TrackerDeviceProfile.swift Apple/Shared/AppCompatibility.swift \
  Tests/PortableAirPodsChecks/main.swift -o "$bin_path/portable-airpods-checks"
"$bin_path/portable-airpods-checks"
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o Apple/Shared/L10n.swift \
  Apple/Features/WorkoutExercisePresentation.swift \
  Tests/PortableWorkoutExerciseChecks/main.swift -o "$bin_path/portable-workout-exercise-checks"
"$bin_path/portable-workout-exercise-checks"
"$swiftc_bin" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -I "$bin_path/Modules" \
  "$bin_path"/FitnessTrackerCore.build/*.swift.o Apple/Shared/L10n.swift \
  Apple/Features/WorkoutExercisePresentation.swift Apple/Features/WorkoutNumberPadModel.swift \
  Tests/PortableNumberPadChecks/main.swift -o "$bin_path/portable-number-pad-checks"
"$bin_path/portable-number-pad-checks"
python3 scripts/parse-apple.py "$swiftc_bin"
if "$swift_bin" format --help >/dev/null 2>&1; then
  "$swift_bin" format lint --strict --recursive Sources Tests Apple Package.swift
else
  echo 'swift format отсутствует; требуется Swift 6.2+ для проверки форматирования.' >&2; exit 1
fi
bash -n scripts/setup-linux.sh scripts/setup-macos.sh scripts/check-linux.sh
printf '\nLinux checks passed. Apple SDK type checking, rendering and runtime remain unverified.\n'
