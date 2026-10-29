// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FitSessionCore",
  platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v14)],
  products: [.library(name: "FitSessionCore", targets: ["FitSessionCore"])],
  targets: [
    .target(name: "FitSessionCore"),
    .testTarget(name: "FitSessionCoreTests", dependencies: ["FitSessionCore"]),
  ],
  swiftLanguageModes: [.v6]
)
