import FitSessionCore
import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class AppStore {
  private(set) var workouts: [Workout] = []
  private(set) var templates: [WorkoutTemplate] = []
  private(set) var active: Workout?
  var error: String?
  var notice: String?
  var showSession = false
  let purchases = PurchaseStore()
  @ObservationIgnored private let repository: any WorkoutRepository
  @ObservationIgnored private let health: any HealthWorkoutExporting
  @ObservationIgnored private let notifications = RestNotificationService()
  @ObservationIgnored private let liveActivity = LiveActivityService()
  @ObservationIgnored private let watch = PhoneWatchBridge()
  @ObservationIgnored private var integrationTask: Task<Void, Never>?
  @ObservationIgnored private let platformServicesEnabled: Bool
  @ObservationIgnored private let defaults: UserDefaults

  init(
    repository: any WorkoutRepository, health: any HealthWorkoutExporting,
    defaults: UserDefaults = .standard, platformServicesEnabled: Bool = true
  ) {
    self.repository = repository
    self.health = health
    self.defaults = defaults
    self.platformServicesEnabled = platformServicesEnabled
    watch.receive = { [weak self] workout in self?.importWatch(workout) ?? false }
    watch.failure = { [weak self] message in self?.error = message }
    reload()
  }
  func startServices() {
    guard platformServicesEnabled else { return }
    purchases.start()
    watch.activate()
    refreshIntegrations()
  }
  func reload() {
    do {
      let loaded = try repository.workouts()
      let routines = try repository.templates()
      workouts = loaded
      templates = routines
      active = loaded.first { [.active, .paused].contains($0.status) }
    } catch { self.error = "Не удалось прочитать данные: \(error.localizedDescription)" }
  }
  func seedTemplatesIfNeeded() {
    // An explicit flag prevents deleted defaults from returning on every launch.
    guard !defaults.bool(forKey: "seededTemplates") else { return }
    do {
      for template in ExerciseCatalog.starterTemplates { try repository.saveTemplate(template) }
      defaults.set(true, forKey: "seededTemplates")
      reload()
    } catch { self.error = error.localizedDescription }
  }
  func start(template: WorkoutTemplate? = nil) {
    guard active == nil else {
      showSession = true
      return
    }
    do {
      let workout = try template?.start() ?? Workout(name: "Свободная тренировка")
      try repository.save(workout)
      reload()
      showSession = true
      refreshIntegrations()
    } catch { self.error = error.localizedDescription }
  }
  func mutate(_ action: (inout Workout) throws -> Void) {
    guard var workout = active else { return }
    do {
      try action(&workout)
      try repository.save(workout)
      reload()
      refreshIntegrations()
    } catch { self.error = error.localizedDescription }
  }
  func finish() {
    mutate { try WorkoutEngine.finish(&$0) }
    if active == nil {
      showSession = false
      notice = "Тренировка сохранена. Отличная работа."
    }
  }
  func cancel() {
    mutate { try WorkoutEngine.cancel(&$0) }
    if active == nil { showSession = false }
  }
  func save(template: WorkoutTemplate) -> Bool {
    do {
      try repository.saveTemplate(template)
      reload()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func delete(template: WorkoutTemplate) {
    do {
      try repository.deleteTemplate(id: template.id)
      reload()
    } catch { self.error = error.localizedDescription }
  }
  func delete(workout: Workout) {
    do {
      try repository.deleteWorkout(id: workout.id)
      reload()
      refreshIntegrations()
    } catch { self.error = error.localizedDescription }
  }
  func exportHealth(_ workout: Workout) async {
    do {
      try await health.requestAuthorization()
      try await health.export(workout)
      notice = "Тренировка отправлена в «Здоровье»."
    } catch { self.error = error.localizedDescription }
  }
  func enableNotifications() async -> Bool {
    do { return try await notifications.authorize() } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  private func importWatch(_ workout: Workout) -> Bool {
    do {
      try repository.save(workout)
      reload()
      refreshIntegrations()
      return true
    } catch {
      self.error = "Тренировка с Watch не сохранена: \(error.localizedDescription)"
      return false
    }
  }
  func refreshIntegrations() {
    guard platformServicesEnabled else { return }
    integrationTask?.cancel()
    let workout = active
    integrationTask = Task {
      do {
        if defaults.bool(forKey: "restNotifications") {
          try await notifications.schedule(until: workout?.restEndsAt)
        } else {
          notifications.cancel()
        }
        guard !Task.isCancelled else { return }
        try await liveActivity.update(
          for: defaults.object(forKey: "liveActivities") as? Bool == false ? nil : workout)
        guard !Task.isCancelled else { return }
        if defaults.bool(forKey: "widgetSharing") {
          let week = TrainingStatistics.weeks(in: workouts, count: 1).first
          try WidgetSnapshot(
            workoutsThisWeek: week?.workouts ?? 0,
            weeklyGoal: max(1, defaults.integer(forKey: "weeklyGoal")), updatedAt: .now
          ).write()
        } else {
          WidgetSnapshot.clear()
        }
        WidgetCenter.shared.reloadAllTimelines()
      } catch {
        if !Task.isCancelled {
          self.error = "Дополнительная функция: \(error.localizedDescription)"
        }
      }
    }
  }
  var completed: [Workout] { workouts.filter { $0.status == .completed } }
}
