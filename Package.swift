// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FitnessTrackerCore",
  platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v14)],
  products: [.library(name: "FitnessTrackerCore", targets: ["FitnessTrackerCore"])],
  targets: [
    .target(
      name: "FitnessTrackerCore",
      resources: [
        .copy("Resources/ExerciseLibrary.ru.json"), .copy("Resources/ExerciseLibrary.en.json"),
      ]),
    .testTarget(name: "FitnessTrackerCoreTests", dependencies: ["FitnessTrackerCore"]),
  ],
  swiftLanguageModes: [.v6]
)
