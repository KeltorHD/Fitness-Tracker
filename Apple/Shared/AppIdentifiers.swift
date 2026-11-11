import Foundation

/// Identifiers shared by the FitLife application, Watch and widgets.
enum AppIdentifiers {
  static let storeConfiguration = "Workouts"
  static let heartRateDirectory = "FitLife/HeartRate"
  static let watchArchiveFileName = "FitLife-watch.json"
  static let healthSyncPrefix = "FitLife."
  static let weeklyWidgetKind = "FitLife.Weekly"

  static func acceptsURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return scheme == "fitlife"
  }
}
