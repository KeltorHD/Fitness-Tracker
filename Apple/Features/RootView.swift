import SwiftUI
import UIKit

struct RootView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.scenePhase) private var phase
  @Environment(\.calendar) private var calendar
  @State private var tab = 0
  @State private var pendingWorkoutStart: WorkoutStartSelection?
  @State private var presentingSession = false
  @AppStorage("keepScreenAwake") private var keepScreenAwake = false
  var body: some View {
    @Bindable var store = store
    TabView(selection: $tab) {
      Tab(value: 0) {
        DashboardView().tint(FitTheme.accent)
          .toolbar(.hidden, for: .tabBar)
      } label: {
        Label(L10n.text("Дневник", locale: locale), systemImage: "book")
          .environment(\.symbolVariants, SymbolVariants.none)
      }
      Tab(value: 1) {
        TemplatesView().tint(FitTheme.accent)
          .toolbar(.hidden, for: .tabBar)
      } label: {
        Label(L10n.text("Шаблоны", locale: locale), systemImage: "dumbbell")
          .environment(\.symbolVariants, SymbolVariants.none)
      }
      Tab(value: 2) {
        ProgressScreen().tint(.primary)
          .toolbar(.hidden, for: .tabBar)
      } label: {
        Label(L10n.text("Результаты", locale: locale), systemImage: "chart.bar.xaxis")
          .environment(\.symbolVariants, SymbolVariants.none)
      }
      Tab(value: 3) {
        SettingsView(model: store.settings).tint(FitTheme.accent)
          .toolbar(.hidden, for: .tabBar)
      } label: {
        Label(L10n.text("Настройки", locale: locale), systemImage: "gearshape")
          .environment(\.symbolVariants, SymbolVariants.none)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      WorkoutNavigationBar(selection: $tab, hasActiveWorkout: store.active != nil) {
        if store.active != nil {
          store.start()
        } else {
          store.showingWorkoutStart = true
        }
      }
    }
    .id(store.workspaceID)
    .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    .tint(.primary)
    .sheet(
      isPresented: Binding(
        get: { store.showingWorkoutStart || store.showSession },
        set: {
          if !$0 {
            store.showingWorkoutStart = false
            store.showSession = false
          }
        }),
      onDismiss: startSelectedWorkout
    ) {
      Group {
        if store.showSession || presentingSession {
          ActiveWorkoutView()
        } else {
          WorkoutStartView { selection in
            pendingWorkoutStart = selection
            store.showingWorkoutStart = false
          }
        }
      }
      .environment(store)
      .tint(FitTheme.accent)
      .presentationDetents(store.showSession || presentingSession ? [.large] : [.medium, .large])
      .presentationDragIndicator(.visible)
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    }
    .archiveTransferPresenter(
      when: !store.showSession && !store.showingWorkoutStart
        && !store.showingWorkoutDetail && !store.showingTemplateEditor
        && !store.showingBodyWeightEditor
    )
    .alert(
      "FitnessTracker",
      isPresented: Binding(
        get: {
          store.error != nil && !store.showSession && !store.showingWorkoutStart
            && !store.showingWorkoutDetail
            && !store.showingTemplateEditor && !store.showingBodyWeightEditor
            && !store.archiveTransfer.isPresented
        },
        set: { if !$0 { store.error = nil } })
    ) {
      Button(L10n.text("Понятно", locale: locale), role: .cancel) { store.error = nil }
    } message: {
      Text(L10n.text(store.error ?? "", locale: locale))
    }
    .alert(
      L10n.text("Готово", locale: locale),
      isPresented: Binding(
        get: {
          store.notice != nil && store.error == nil && !store.showSession
            && !store.showingWorkoutStart
            && !store.showingWorkoutDetail && !store.showingTemplateEditor
            && !store.showingBodyWeightEditor
            && !store.archiveTransfer.isPresented
        }, set: { if !$0 { store.notice = nil } })
    ) {
      Button(L10n.text("Хорошо", locale: locale), role: .cancel) { store.notice = nil }
    } message: {
      Text(L10n.text(store.notice ?? "", locale: locale))
    }
    .onOpenURL { url in
      if AppCompatibility.acceptsURL(url), url.host == "today" { tab = 0 }
      if AppCompatibility.acceptsURL(url), url.host == "workout" {
        tab = 0
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "id" }?.value
        if let value, UUID(uuidString: value) == nil { return }
        store.openWorkout(id: value.flatMap { UUID(uuidString: $0) })
      }
    }
    .onChange(of: keepScreenAwake) { updateIdleTimer() }
    .onChange(of: store.showSession, initial: true) {
      if store.showSession {
        presentingSession = true
        store.showingWorkoutStart = false
      }
    }
    .onChange(of: store.active?.status) { updateIdleTimer() }
    .onChange(of: phase, initial: true) { updateIdleTimer() }
    .task(
      id: HealthChartsObservation(
        day: store.healthCharts.day, calendar: calendar,
        enabled: store.healthCharts.enabled && !store.isDemoMode, active: phase == .active,
        request: store.healthCharts.request)
    ) {
      guard !Task.isCancelled else { return }
      guard store.healthCharts.enabled, !store.isDemoMode, phase == .active else {
        store.healthCharts.clear()
        return
      }
      await store.healthCharts.observe(calendar: calendar)
    }
    .task(id: phase) {
      if phase == .active {
        store.reload()
        store.refreshIntegrations()
      } else if phase == .background {
        await store.prepareForBackground()
      }
    }
  }
  private func startSelectedWorkout() {
    // Keep the session content during its dismissal animation, then allow the next picker.
    presentingSession = false
    guard let selection = pendingWorkoutStart else { return }
    pendingWorkoutStart = nil
    switch selection {
    case .empty: store.start()
    case .templates(let templates): store.start(templates: templates)
    }
  }
  private func updateIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled =
      keepScreenAwake && phase == .active && store.active?.status == .active
  }
}
