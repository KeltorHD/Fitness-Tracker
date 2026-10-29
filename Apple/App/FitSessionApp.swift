import FitSessionCore
import SwiftUI

@main struct FitSessionApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: AppStore?
  @State private var startupError: String?
  @AppStorage("appearance") private var appearance = "auto"
  var body: some Scene {
    WindowGroup {
      Group {
        if let store {
          RootView().environment(store)
            .environment(\.exerciseImageLoader, store.exerciseImages)
        } else if let startupError {
          ContentUnavailableView {
            Label("Хранилище недоступно", systemImage: "externaldrive.badge.exclamationmark")
          } description: {
            Text(startupError)
          } actions: {
            Button("Повторить") { boot() }.buttonStyle(.glassProminent)
            Text("Данные не удалены. Попробуйте открыть приложение ещё раз позже.")
              .font(.footnote).padding()
          }
        } else {
          ProgressView("FitSession")
        }
      }
      .tint(FitTheme.accent)
      .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
      .task { if store == nil && startupError == nil { boot() } }
    }
  }
  @MainActor private func boot() {
    do {
      let appStore = try FitSessionRuntime.store()
      appStore.seedTemplatesIfNeeded()
      appStore.startServices()
      store = appStore
      startupError = nil
    } catch {
      startupError = AppErrorReporter.message(
        for: error, operation: "openStore", fallback: "Не удалось открыть историю тренировок.")
    }
  }
}
