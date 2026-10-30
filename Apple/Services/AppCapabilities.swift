import Foundation

/// Build availability is separate from the user's persisted iCloud preference.
struct AppCapabilities: Equatable, Sendable {
  let supportsCloudSync: Bool

  init(info: [String: Any]) {
    supportsCloudSync = info["FitnessTrackerCloudSyncAvailable"] as? String == "YES"
  }

  static var current: Self { Self(info: Bundle.main.infoDictionary ?? [:]) }
}
