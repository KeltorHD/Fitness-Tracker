import FitnessTrackerCore
import Foundation

/// One store/context per app process, including a cold launch by LiveActivityIntent.
@MainActor enum FitnessTrackerRuntime {
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
      guard let testDefaults = UserDefaults(suiteName: "FitnessTracker.UITests") else {
        throw ServiceError.unavailable("Не удалось открыть настройки тестового запуска.")
      }
      defaults = testDefaults
    } else {
      defaults = .standard
    }
    if testing { defaults.removePersistentDomain(forName: "FitnessTracker.UITests") }
    if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-training-groups") {
      try TrainingGroupsUITestFixture.seed(into: repository)
    }
    if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-previous-sets") {
      try TrainingGroupsUITestFixture.seedPreviousSets(into: repository)
    }
    defaults.register(defaults: ["weeklyGoal": 3, "liveActivities": !testing])
    let accountSession: AccountSession?
    do {
      if !testing, let configuration = try ServerConfiguration.configured() {
        accountSession = AccountSession(
          configuration: configuration, http: ServerHTTPClient(),
          credentials: KeychainAccountTokenStore(
            service: (Bundle.main.bundleIdentifier ?? "FitnessTracker") + ".authentication",
            account: configuration.authenticationURL.absoluteString + configuration.oauthClientID))
      } else {
        accountSession = nil
      }
    } catch {
      AppErrorReporter.record(error, operation: "configureAccountServer")
      accountSession = nil
    }
    let store = AppStore(
      repository: repository, health: HealthKitService(), defaults: defaults,
      platformServicesEnabled: !testing, accountSession: accountSession,
      sleepAlarmScheduler: SleepUITestFixture.scheduler())
    #if DEBUG
      if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-sleep") {
        store.sleepAlarms.setWatchConnection(
          ProcessInfo.processInfo.arguments.contains("--ui-testing-sleep-watch")
            ? .reachable : .appNotInstalled)
      }
    #endif
    cachedStore = store
    return store
  }
}
