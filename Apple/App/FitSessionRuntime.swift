import FitSessionCore
import Foundation

/// One store/context per app process, including a cold launch by LiveActivityIntent.
@MainActor enum FitSessionRuntime {
  private static var cachedStore: AppStore?

  static func store() throws -> AppStore {
    if let cachedStore { return cachedStore }
    let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let repository: any WorkoutRepository
    if testing {
      UserDefaults.standard.removeObject(forKey: "appLanguage")
      repository = MemoryWorkoutRepository()
    } else {
      repository = try SwiftDataWorkoutRepository(
        cloudEnabled: AppCapabilities.current.supportsCloudSync
          && UserDefaults.standard.bool(forKey: "cloudSync"))
    }
    let defaults: UserDefaults
    if testing {
      guard let testDefaults = UserDefaults(suiteName: "FitSession.UITests") else {
        throw ServiceError.unavailable("Не удалось открыть настройки тестового запуска.")
      }
      defaults = testDefaults
    } else {
      defaults = .standard
    }
    if testing { defaults.removePersistentDomain(forName: "FitSession.UITests") }
    defaults.register(defaults: ["weeklyGoal": 3, "liveActivities": !testing])
    let store = AppStore(
      repository: repository, health: HealthKitService(), defaults: defaults,
      platformServicesEnabled: !testing)
    cachedStore = store
    return store
  }
}
