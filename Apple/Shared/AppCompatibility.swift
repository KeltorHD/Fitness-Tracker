import Foundation

/// Stable installed identities. These strings are storage/wire keys, never display branding.
enum AppCompatibility {
  static let storeConfiguration = "FitSession"
  static let heartRateDirectory = "FitSession/HeartRate"
  static let watchArchiveFileName = "FitSession-watch.json"
  static let healthSyncPrefix = "FitSession."
  static let weeklyWidgetKind = "FitSession.Weekly"

  static func acceptsURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return scheme == "fitnesstracker" || scheme == "fitsession"
  }
}
