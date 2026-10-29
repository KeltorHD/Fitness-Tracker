import SwiftUI
import UIKit

struct RootView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.scenePhase) private var phase
  @State private var tab = 0
  @AppStorage("keepScreenAwake") private var keepScreenAwake = false
  var body: some View {
    @Bindable var store = store
    TabView(selection: $tab) {
      Tab("Дневник", systemImage: "book.closed", value: 0) { DashboardView().tint(FitTheme.accent) }
      Tab("Каталог", systemImage: "dumbbell", value: 1) { TemplatesView().tint(FitTheme.accent) }
      Tab("Результаты", systemImage: "chart.bar", value: 2) {
        ProgressScreen().tint(FitTheme.accent)
      }
      Tab("Настройки", systemImage: "gearshape", value: 3) {
        SettingsView(model: store.settings).tint(FitTheme.accent)
      }
    }
    .tint(.primary)
    .sheet(isPresented: $store.showSession) {
      ActiveWorkoutView().environment(store).tint(FitTheme.accent).interactiveDismissDisabled()
    }
    .alert(
      "FitSession",
      isPresented: Binding(
        get: { store.error != nil && !store.showSession && !store.showingWorkoutDetail },
        set: { if !$0 { store.error = nil } })
    ) {
      Button("Понятно", role: .cancel) { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .alert(
      "Готово",
      isPresented: Binding(
        get: {
          store.notice != nil && store.error == nil && !store.showSession
            && !store.showingWorkoutDetail
        }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("Хорошо", role: .cancel) { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
    .onOpenURL { url in
      if url.scheme == "fitsession", url.host == "today" { tab = 0 }
      if url.scheme == "fitsession", url.host == "workout" {
        tab = 0
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "id" }?.value
        if let value, UUID(uuidString: value) == nil { return }
        store.openWorkout(id: value.flatMap { UUID(uuidString: $0) })
      }
    }
    .onChange(of: keepScreenAwake) { updateIdleTimer() }
    .onChange(of: store.active?.status) { updateIdleTimer() }
    .onChange(of: phase, initial: true) { updateIdleTimer() }
    .task(id: phase) {
      if phase == .active {
        store.reload()
        store.refreshIntegrations()
      } else if phase == .background {
        await store.prepareForBackground()
      }
    }
  }
  private func updateIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled =
      keepScreenAwake && phase == .active && store.active?.status == .active
  }
}
