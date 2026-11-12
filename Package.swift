// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FitLifeCore",
  platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v14)],
  products: [.library(name: "FitLifeCore", targets: ["FitLifeCore"])],
  targets: [
    .target(
      name: "FitLifeCore",
      resources: [
        .copy("Resources/ExerciseLibrary.ru.json"), .copy("Resources/ExerciseLibrary.en.json"),
      ]),
    .testTarget(name: "FitLifeCoreTests", dependencies: ["FitLifeCore"]),
  ],
  swiftLanguageModes: [.v6]
)
