import FitnessTrackerCore
import SwiftUI
import WidgetKit

@main struct FitnessTrackerApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: AppStore?
  @State private var startupError: String?
  @State private var pendingFileURL: URL?
  @AppStorage("colorTheme") private var storedColorTheme = FitnessColorTheme.defaultTheme.rawValue
  @AppStorage("appearance") private var appearance = "auto"
  @AppStorage("appLanguage") private var language: AppLanguage = .system
  private var colorTheme: FitnessColorTheme {
    FitnessColorTheme(rawValue: storedColorTheme) ?? .defaultTheme
  }

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
            Text(L10n.text(startupError, locale: language.locale()))
          } actions: {
            Button("Повторить") { boot() }.buttonStyle(.glassProminent)
            Text("Данные не удалены. Попробуйте открыть приложение ещё раз позже.")
              .font(.footnote).padding()
          }
        } else {
          ProgressView("FitnessTracker")
        }
      }
      .tint(colorTheme.accent)
      .environment(\.fitnessColorTheme, colorTheme)
      .environment(\.locale, language.locale())
      .environment(\.calendar, presentationCalendar)
      .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
      .task { if store == nil && startupError == nil { boot() } }
      .onOpenURL { url in
        guard url.isFileURL else { return }
        if let store { store.archiveTransfer.openFile(url) } else { pendingFileURL = url }
      }
      .onChange(of: language, initial: true) {
        do { try WidgetSnapshot.publishLanguage(language) } catch {
          AppErrorReporter.record(error, operation: "shareLanguagePreference")
        }
        WidgetCenter.shared.reloadAllTimelines()
        store?.refreshIntegrations()
      }
    }
  }
  private var presentationCalendar: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = language.locale()
    return calendar
  }
  @MainActor private func boot() {
    do {
      let appStore = try FitnessTrackerRuntime.store()
      appStore.seedTemplatesIfNeeded()
      appStore.startServices()
      store = appStore
      startupError = nil
      if let url = pendingFileURL {
        pendingFileURL = nil
        appStore.archiveTransfer.openFile(url)
      }
    } catch {
      startupError = AppErrorReporter.message(
        for: error, operation: "openStore", fallback: "Не удалось открыть историю тренировок.")
    }
  }
}
