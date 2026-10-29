import FitSessionCore
import Foundation
import Observation
import UIKit
import WidgetKit

@MainActor @Observable final class AppStore {
  private(set) var workouts: [Workout] = []
  private(set) var templates: [WorkoutTemplate] = []
  private(set) var active: Workout?
  var error: String?
  var notice: String?
  var showSession = false
  @ObservationIgnored private let repository: any WorkoutRepository
  @ObservationIgnored private let health: any HealthWorkoutExporting
  @ObservationIgnored private let notifications = RestNotificationService()
  @ObservationIgnored private let liveActivity = LiveActivityService()
  @ObservationIgnored private let watch = PhoneWatchBridge()
  @ObservationIgnored private var integrationTask: Task<Void, Never>?
  @ObservationIgnored private var servicesStarted = false
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
    guard platformServicesEnabled, !servicesStarted else { return }
    servicesStarted = true
    watch.activate()
    refreshIntegrations()
  }
  func reload() {
    do {
      let loaded = try repository.workouts()
      let routines = try repository.templates()
      workouts = loaded
      templates = routines
      let unfinished = loaded.filter { [.active, .paused].contains($0.status) }
      active = unfinished.first { $0.id == active?.id } ?? unfinished.first
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
      try activate(workout)
    } catch { self.error = error.localizedDescription }
  }
  private func activate(_ workout: Workout) throws {
    try repository.save(workout)
    reload()
    showSession = true
    if platformServicesEnabled, defaults.object(forKey: "liveActivities") as? Bool != false {
      // Request synchronously while foregrounded, before notification/widget async work.
      do { try liveActivity.startIfNeeded(for: workout) } catch {
        self.error = "Live Activity: \(error.localizedDescription)"
      }
    }
    refreshIntegrations()
  }
  func repeatWorkout(_ original: Workout) {
    guard active == nil else {
      showSession = true
      return
    }
    do { try activate(WorkoutEngine.repeatWorkout(original)) } catch {
      error = error.localizedDescription
    }
  }
  func updateCompleted(_ workout: Workout) -> Bool {
    do {
      guard workout.status == .completed,
        try repository.workouts().contains(where: { $0.id == workout.id && $0.status == .completed }
        )
      else {
        throw TrainingError.invalidState
      }
      try repository.save(workout)
      reload()
      refreshIntegrations()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
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
  /// Intents use the same context as the UI, even when the system cold-launches the process.
  func performLiveAction(_ action: WorkoutLiveAction, workoutID: UUID) async throws {
    do {
      guard var workout = try repository.workouts().first(where: { $0.id == workoutID }) else {
        throw TrainingError.invalidState
      }
      if try action.apply(to: &workout, expectedWorkoutID: workoutID) {
        try repository.save(workout)
      }
      active = workout
      reload()
    } catch {
      self.error = error.localizedDescription
      reload()
      refreshIntegrations(allowStart: false)
      await integrationTask?.value
      throw error
    }
    // ActivityKit updates must finish before perform() returns to the system.
    refreshIntegrations(allowStart: false)
    await integrationTask?.value
  }

  func prepareForBackground() async {
    guard platformServicesEnabled else { return }
    refreshIntegrations(allowStart: false)
    let pending = integrationTask
    let lease = BackgroundTaskLease()
    lease.begin { pending?.cancel() }
    defer { lease.end() }
    await pending?.value
  }

  func openWorkout(id: UUID?) {
    reload()
    if let id {
      guard
        let workout = workouts.first(where: {
          $0.id == id && [.active, .paused].contains($0.status)
        })
      else {
        notice = "Эта тренировка уже завершена или удалена."
        return
      }
      active = workout
    }
    showSession = active != nil
  }

  func refreshIntegrations(allowStart: Bool? = nil) {
    guard platformServicesEnabled else { return }
    let previous = integrationTask
    previous?.cancel()
    let workout = active
    let canStart = allowStart ?? (UIApplication.shared.applicationState == .active)
    integrationTask = Task {
      // Await the old operation so a late completion cannot overwrite the newest state.
      await previous?.value
      guard !Task.isCancelled else { return }
      var firstError: (any Error)?
      do {
        if defaults.bool(forKey: "restNotifications") {
          try await notifications.schedule(until: workout?.restEndsAt)
        } else {
          notifications.cancel()
        }
      } catch { firstError = error }
      guard !Task.isCancelled else { return }
      do {
        try await liveActivity.update(
          for: defaults.object(forKey: "liveActivities") as? Bool == false ? nil : workout,
          allowStart: canStart)
      } catch { if firstError == nil { firstError = error } }
      guard !Task.isCancelled else { return }
      do {
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
      } catch { if firstError == nil { firstError = error } }
      if let firstError, !Task.isCancelled {
        self.error = "Дополнительная функция: \(firstError.localizedDescription)"
      }
    }
  }
  var completed: [Workout] { workouts.filter { $0.status == .completed } }
}
