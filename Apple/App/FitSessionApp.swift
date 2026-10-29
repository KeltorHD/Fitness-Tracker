import FitSessionCore
import SwiftUI

@main struct FitSessionApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: AppStore?
  @State private var startupError: String?
  private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
  var body: some Scene {
    WindowGroup {
      Group {
        if let store {
          RootView().environment(store)
        } else if let startupError {
          ContentUnavailableView {
            Label("Хранилище недоступно", systemImage: "externaldrive.badge.exclamationmark")
          } description: {
            Text(startupError)
          } actions: {
            Button("Повторить") { boot() }.buttonStyle(.glassProminent)
            Text("Данные не удалены. Если включён iCloud, проверьте Signing & Capabilities.")
              .font(.footnote).padding()
          }
        } else {
          ProgressView("FitSession")
        }
      }
      .tint(Color.accentColor)
      .task { if store == nil && startupError == nil { boot() } }
    }
  }
  @MainActor private func boot() {
    do {
      let repository: any WorkoutRepository
      if isUITesting {
        repository = MemoryWorkoutRepository()
      } else {
        repository = try SwiftDataWorkoutRepository(
          cloudEnabled: UserDefaults.standard.bool(forKey: "cloudSync"))
      }
      let defaults = isUITesting ? UserDefaults(suiteName: "FitSession.UITests")! : .standard
      if isUITesting { defaults.removePersistentDomain(forName: "FitSession.UITests") }
      defaults.register(defaults: ["weeklyGoal": 3, "liveActivities": !isUITesting])
      let appStore = AppStore(
        repository: repository, health: HealthKitService(), defaults: defaults,
        platformServicesEnabled: !isUITesting)
      appStore.seedTemplatesIfNeeded()
      if !isUITesting { appStore.startServices() }
      store = appStore
      startupError = nil
    } catch { startupError = error.localizedDescription }
  }
}
