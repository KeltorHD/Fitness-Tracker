import SwiftUI

struct RootView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.scenePhase) private var phase
  var body: some View {
    @Bindable var store = store
    TabView {
      Tab("Сегодня", systemImage: "figure.strengthtraining.traditional") { DashboardView() }
      Tab("Планы", systemImage: "square.grid.2x2") { TemplatesView() }
      Tab("История", systemImage: "clock.arrow.circlepath") { HistoryView() }
      Tab("Прогресс", systemImage: "chart.xyaxis.line") { ProgressScreen() }
      Tab("Настройки", systemImage: "gearshape") { SettingsView() }
    }
    .sheet(isPresented: $store.showSession) {
      ActiveWorkoutView().environment(store).interactiveDismissDisabled()
    }
    .alert(
      "FitSession",
      isPresented: Binding(
        get: { store.error != nil && !store.showSession }, set: { if !$0 { store.error = nil } })
    ) {
      Button("Понятно", role: .cancel) { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .alert(
      "Готово",
      isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("Хорошо", role: .cancel) { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
    .onOpenURL { url in
      if url.scheme == "fitsession", url.host == "workout" {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "id" }?.value
        if let value, UUID(uuidString: value) == nil { return }
        store.openWorkout(id: value.flatMap { UUID(uuidString: $0) })
      }
    }
    .onChange(of: phase) { _, phase in
      if phase == .active {
        store.reload()
        store.refreshIntegrations()
      } else if phase == .background {
        Task { await store.prepareForBackground() }
      }
    }
  }
}
