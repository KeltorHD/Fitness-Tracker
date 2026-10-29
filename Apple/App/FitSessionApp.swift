import FitSessionCore
import SwiftUI

@main struct FitSessionApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: AppStore?
  @State private var startupError: String?
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
      let appStore = try FitSessionRuntime.store()
      appStore.seedTemplatesIfNeeded()
      appStore.startServices()
      store = appStore
      startupError = nil
    } catch { startupError = error.localizedDescription }
  }
}
