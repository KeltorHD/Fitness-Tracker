import FitLifeCore
import Foundation

/// One store/context per app process, including a cold launch by LiveActivityIntent.
@MainActor enum FitLifeRuntime {
  private static var cachedStore: AppStore?

  static func store() throws -> AppStore {
    if let cachedStore { return cachedStore }
    let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let serverTrainingConfigured =
      !testing
      && ["FitLifeAuthenticationURL", "FitLifeBackendURL"].contains {
        !(Bundle.main.object(forInfoDictionaryKey: $0) as? String ?? "").isEmpty
      }
    let serverConfiguration: ServerConfiguration?
    do { serverConfiguration = testing ? nil : try ServerConfiguration.configured() } catch {
      AppErrorReporter.record(error, operation: "configureAccountServer")
      serverConfiguration = nil
    }
    let repository: any WorkoutRepository
    if testing {
      UserDefaults.standard.removeObject(forKey: "appLanguage")
      UserDefaults.standard.removeObject(forKey: "trainingDiaryInsightsExpanded")
      UserDefaults.standard.removeObject(forKey: "nutritionDiaryInsightsExpanded")
      repository = MemoryWorkoutRepository()
    } else {
      repository = try SwiftDataWorkoutRepository(
        cloudEnabled: !serverTrainingConfigured && AppCapabilities.current.supportsCloudSync
          && UserDefaults.standard.bool(forKey: "cloudSync"))
    }
    let defaults: UserDefaults
    if testing {
      guard let testDefaults = UserDefaults(suiteName: "FitLife.UITests") else {
        throw ServiceError.unavailable("Не удалось открыть настройки тестового запуска.")
      }
      defaults = testDefaults
    } else {
      defaults = .standard
    }
    if testing { defaults.removePersistentDomain(forName: "FitLife.UITests") }
    if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-training-groups") {
      try TrainingGroupsUITestFixture.seed(into: repository)
    }
    if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-previous-sets") {
      try TrainingGroupsUITestFixture.seedPreviousSets(into: repository)
    }
    #if DEBUG
      if testing, ProcessInfo.processInfo.arguments.contains("--ui-testing-diary-insights") {
        try DiaryInsightsUITestFixture.seed(into: repository)
      }
    #endif
    if testing { try AccountTrainingUITestFixture.seed(into: repository) }
    defaults.register(defaults: ["weeklyGoal": 3, "liveActivities": !testing])
    let accountSession: AccountSession?
    do {
      if !testing, let configuration = serverConfiguration {
        accountSession = AccountSession(
          configuration: configuration, http: ServerHTTPClient(),
          credentials: KeychainAccountTokenStore(
            service: (Bundle.main.bundleIdentifier ?? "FitLife") + ".authentication",
            account: configuration.authenticationURL.absoluteString + configuration.oauthClientID))
      } else {
        accountSession = try AccountTrainingUITestFixture.session()
      }
    } catch {
      AppErrorReporter.record(error, operation: "configureAccountServer")
      accountSession = nil
    }
    let store = AppStore(
      repository: repository, health: HealthKitService(), defaults: defaults,
      platformServicesEnabled: !testing, accountSession: accountSession,
      sleepAlarmScheduler: SleepUITestFixture.scheduler(),
      serverTrainingConfigured: serverTrainingConfigured)
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
