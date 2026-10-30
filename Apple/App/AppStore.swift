import FitnessTrackerCore
import Foundation
import Observation
import UIKit
import WidgetKit

@MainActor @Observable final class AppStore {
  private(set) var workouts: [Workout] = []
  private(set) var completed: [Workout] = []
  private(set) var templates: [WorkoutTemplate] = []
  private(set) var bodyWeights: [BodyWeightEntry] = []
  private(set) var active: Workout?
  var error: String?
  var notice: String?
  var showSession = false
  var showingWorkoutDetail = false
  var showingTemplateEditor = false
  var showingBodyWeightEditor = false
  private(set) var isDemoMode = false
  private(set) var switchingDemo = false
  private(set) var workspaceID = UUID()
  let settings: SettingsViewModel
  let tracker: TrackerViewModel
  let healthCharts: HealthChartsViewModel
  @ObservationIgnored let exerciseImages: any ExerciseImageLoading
  @ObservationIgnored private let repository: WorkoutWorkspaceRepository
  @ObservationIgnored private let health: any HealthWorkoutExporting
  @ObservationIgnored private let notifications: any RestNotificationServing
  @ObservationIgnored private let liveActivity = LiveActivityService()
  @ObservationIgnored private let watch = PhoneWatchBridge()
  @ObservationIgnored private var integrationTask: Task<Void, Never>?
  @ObservationIgnored private var servicesStarted = false
  @ObservationIgnored private let platformServicesEnabled: Bool
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let archiveFiles: any ArchiveFileHandling
  @ObservationIgnored lazy var archiveTransfer = ArchiveTransferViewModel(
    files: archiveFiles,
    snapshot: { [weak self] in
      guard let self else { throw ArchiveFileError.unreadable }
      return try self.archiveSnapshot()
    },
    plan: { [weak self] archive in
      guard let self else { throw ArchiveFileError.unreadable }
      return try ArchiveImportPlan(
        archive: archive, existingWorkouts: self.repository.workouts(),
        existingTemplates: self.repository.templates(),
        existingBodyWeights: self.repository.bodyWeights()
      ).summary
    },
    commit: { [weak self] archive in
      guard let self else { throw ArchiveFileError.unreadable }
      return try self.importArchive(archive)
    })

  init(
    repository: any WorkoutRepository, health: any HealthWorkoutExporting,
    defaults: UserDefaults = .standard, platformServicesEnabled: Bool = true,
    notifications: any RestNotificationServing = RestNotificationService(),
    cloud: any CloudAccountChecking = CloudKitService(),
    exerciseImages: any ExerciseImageLoading = ExerciseImageLoader(),
    archiveFiles: any ArchiveFileHandling = ArchiveFileService(),
    tracker: TrackerViewModel? = nil,
    healthCharts: HealthChartsViewModel? = nil
  ) {
    self.repository = WorkoutWorkspaceRepository(personal: repository)
    self.health = health
    self.defaults = defaults
    self.platformServicesEnabled = platformServicesEnabled
    self.notifications = notifications
    self.settings = SettingsViewModel(cloud: cloud, notifications: notifications)
    self.exerciseImages = exerciseImages
    self.archiveFiles = archiveFiles
    self.tracker =
      tracker
      ?? TrackerViewModel(
        health: HealthMetricsReader(), sensor: BluetoothHeartRateService(),
        liveSource: AirPodsHeartRateService(),
        recordings: LocalHeartRateRepository(), defaults: defaults,
        errorMessage: { AppErrorReporter.message(for: $0, operation: $1, fallback: $2) })
    self.healthCharts =
      healthCharts
      ?? HealthChartsViewModel(
        reader: HealthMetricsReader(), defaults: defaults,
        errorMessage: {
          AppErrorReporter.message(
            for: $0, operation: "healthCharts",
            fallback:
              "Не удалось загрузить пульс и шаги. Проверьте доступ к «Здоровью» и повторите.")
        })
    watch.receive = { [weak self] workout in self?.importWatch(workout) ?? false }
    watch.failure = { [weak self] error in
      self?.report(
        error, operation: "watchConnection",
        message: "Не удалось обменяться данными с Apple Watch. Попробуйте ещё раз.")
    }
    reload()
  }
  func startServices() {
    guard platformServicesEnabled, !servicesStarted else { return }
    servicesStarted = true
    watch.activate()
    refreshIntegrations()
  }
  func reload() {
    do { try loadRepository() } catch {
      report(
        error, operation: "reload",
        message: "Не удалось прочитать историю. Попробуйте открыть приложение ещё раз.")
    }
  }
  func loadDemoData(at date: Date = Date(), calendar: Calendar = .current) async {
    guard !switchingDemo else { return }
    guard isDemoMode || active == nil else {
      error = "Завершите текущую тренировку перед открытием демо-профиля."
      return
    }
    switchingDemo = true
    defer { switchingDemo = false }
    do {
      let archive = try DemoWorkoutData.archive(
        relativeTo: date, calendar: calendar, language: L10n.language)
      let previous = integrationTask
      // Finish the personal workspace's last notification/widget update before switching data.
      await previous?.value
      try Task.checkCancellation()
      guard !showSession, !showingWorkoutDetail, !showingTemplateEditor,
        !showingBodyWeightEditor,
        !archiveTransfer.isPresented, !archiveTransfer.isSaving
      else { throw TrainingError.invalidState }
      try repository.openDemo(archive)
      isDemoMode = true
      tracker.disconnect()
      tracker.attach(nil)
      healthCharts.attach(nil)
      healthCharts.clear()
      try loadRepository()
      resetWorkspacePresentation()
    } catch {
      guard !Task.isCancelled else { return }
      report(
        error, operation: "loadDemo",
        message: "Не удалось загрузить демо-данные. Ваши тренировки сохранены; попробуйте ещё раз.")
    }
  }
  func leaveDemoMode() async {
    guard isDemoMode, !switchingDemo, !showingBodyWeightEditor else { return }
    switchingDemo = true
    defer { switchingDemo = false }
    do {
      try Task.checkCancellation()
      let snapshot = try repository.closeDemo()
      isDemoMode = false
      applySnapshot(
        workouts: snapshot.workouts, templates: snapshot.templates,
        bodyWeights: snapshot.bodyWeights)
      resetWorkspacePresentation()
      refreshIntegrations()
    } catch {
      report(
        error, operation: "leaveDemo",
        message: "Не удалось открыть личную историю. Демо-профиль сохранён; попробуйте ещё раз.")
    }
  }
  private func resetWorkspacePresentation() {
    error = nil
    notice = nil
    showSession = false
    showingWorkoutDetail = false
    showingTemplateEditor = false
    showingBodyWeightEditor = false
    archiveTransfer.cancelReading()
    archiveTransfer.isPresented = false
    workspaceID = UUID()
  }
  private func loadRepository() throws {
    // Publish only after all reads succeed; a partial read preserves the previous UI snapshot.
    let loaded = try repository.workouts()
    let routines = try repository.templates()
    let measurements = try repository.bodyWeights()
    applySnapshot(workouts: loaded, templates: routines, bodyWeights: measurements)
  }
  private func applySnapshot(
    workouts loaded: [Workout], templates routines: [WorkoutTemplate],
    bodyWeights measurements: [BodyWeightEntry]
  ) {
    workouts = loaded
    completed = loaded.filter { $0.status == .completed }
    templates = routines
    bodyWeights = measurements
    let unfinished = loaded.filter { [.active, .paused].contains($0.status) }
    active = unfinished.first { $0.id == active?.id } ?? unfinished.first
    if !isDemoMode {
      tracker.attach(active)
      healthCharts.attach(active)
    }
  }

  private func archiveSnapshot() throws -> WorkoutArchive {
    WorkoutArchive(
      workouts: try repository.workouts(), templates: try repository.templates(),
      bodyWeights: try repository.bodyWeights())
  }

  @discardableResult func saveBodyWeight(_ entry: BodyWeightEntry) -> Bool {
    do {
      try repository.saveBodyWeight(entry)
      try loadRepository()
      return true
    } catch {
      report(
        error, operation: "saveBodyWeight", message: "Не удалось сохранить вес. Попробуйте ещё раз."
      )
      return false
    }
  }
  @discardableResult func setBodyWeight(_ weightKG: Double?, for workoutID: UUID) -> Bool {
    if active?.id == workoutID {
      return mutate { try WorkoutEngine.setBodyWeight(weightKG, in: &$0) }
    }
    guard var workout = workouts.first(where: { $0.id == workoutID }), workout.status == .completed
    else {
      error = "Эта тренировка уже завершена или удалена."
      return false
    }
    workout.bodyWeightKG = weightKG
    return updateCompleted(workout)
  }
  @discardableResult func deleteBodyWeight(_ point: BodyWeightPoint) -> Bool {
    switch point.source {
    case .workout(let id): return setBodyWeight(nil, for: id)
    case .measurement(let id):
      do {
        try repository.deleteBodyWeight(id: id)
        try loadRepository()
        return true
      } catch {
        report(
          error, operation: "deleteBodyWeight",
          message: "Не удалось удалить запись веса. Попробуйте ещё раз.")
        return false
      }
    }
  }

  private func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    let result = try repository.importArchive(archive)
    // Once the transaction commits, a later read failure is reported separately by reload().
    reload()
    refreshIntegrations()
    return result
  }
  func seedTemplatesIfNeeded() {
    guard !isDemoMode else { return }
    // An explicit flag prevents deleted defaults from returning on every launch.
    guard !defaults.bool(forKey: "seededTemplates") else { return }
    do {
      for template in ExerciseCatalog.starterTemplates { try repository.saveTemplate(template) }
      defaults.set(true, forKey: "seededTemplates")
      try loadRepository()
    } catch {
      report(
        error, operation: "seedTemplates",
        message: "Не удалось сохранить стартовые планы. Попробуйте ещё раз.")
    }
  }
  func start(template: WorkoutTemplate? = nil) {
    guard active == nil else {
      showSession = true
      return
    }
    do {
      let workout =
        try template?.start()
        ?? Workout(name: L10n.text(isDemoMode ? "Демо-тренировка" : "Свободная тренировка"))
      try activate(workout)
    } catch {
      report(
        error, operation: "startWorkout",
        message: "Не удалось начать тренировку. Попробуйте ещё раз.")
    }
  }
  private func activate(_ workout: Workout) throws {
    try repository.save(workout)
    try loadRepository()
    showSession = true
    if platformServicesEnabled, !isDemoMode,
      defaults.object(forKey: "liveActivities") as? Bool != false
    {
      // Request synchronously while foregrounded, before notification/widget async work.
      do { try liveActivity.startIfNeeded(for: workout) } catch {
        report(
          error, operation: "startLiveActivity",
          message:
            "Не удалось показать тренировку на экране блокировки. Тренировка сохранена в приложении."
        )
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
      report(
        error, operation: "repeatWorkout",
        message: "Не удалось повторить тренировку. Попробуйте ещё раз.")
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
      try loadRepository()
      refreshIntegrations()
      return true
    } catch {
      report(
        error, operation: "updateCompleted",
        message: "Не удалось сохранить изменения тренировки. Попробуйте ещё раз.")
      return false
    }
  }
  @discardableResult func mutate(_ action: (inout Workout) throws -> Void) -> Bool {
    guard var workout = active else { return false }
    do {
      try action(&workout)
      try repository.save(workout)
      try loadRepository()
      refreshIntegrations()
      return true
    } catch {
      report(
        error, operation: "updateWorkout",
        message: "Не удалось сохранить изменения тренировки. Попробуйте ещё раз.")
      return false
    }
  }
  func finish() {
    guard mutate({ try WorkoutEngine.finish(&$0) }) else { return }
    if active == nil {
      showSession = false
      notice = "Тренировка сохранена. Отличная работа."
    }
  }
  func cancel() {
    let cancelledID = active?.id
    guard mutate({ try WorkoutEngine.cancel(&$0) }) else { return }
    if active == nil {
      showSession = false
      if let cancelledID, !isDemoMode { tracker.removeRecording(for: cancelledID) }
    }
  }
  func save(template: WorkoutTemplate) -> Bool {
    do {
      try repository.saveTemplate(template)
      try loadRepository()
      return true
    } catch {
      report(
        error, operation: "saveTemplate", message: "Не удалось сохранить план. Попробуйте ещё раз.")
      return false
    }
  }
  func delete(template: WorkoutTemplate) {
    do {
      try repository.deleteTemplate(id: template.id)
      try loadRepository()
    } catch {
      report(
        error, operation: "deleteTemplate", message: "Не удалось удалить план. Попробуйте ещё раз.")
    }
  }
  func delete(workout: Workout) {
    do {
      try repository.deleteWorkout(id: workout.id)
      if !isDemoMode { tracker.removeRecording(for: workout.id) }
      try loadRepository()
      refreshIntegrations()
    } catch {
      report(
        error, operation: "deleteWorkout",
        message: "Не удалось удалить тренировку. Попробуйте ещё раз.")
    }
  }
  func exportHealth(_ workout: Workout) async {
    guard !isDemoMode else {
      error = "Демонстрационные тренировки не отправляются в «Здоровье»."
      return
    }
    guard workout.durationIsKnown != false else {
      error = "В исходном файле нет длительности тренировки. Экспорт в «Здоровье» недоступен."
      return
    }
    do {
      try Task.checkCancellation()
      try await health.requestAuthorization()
      try Task.checkCancellation()
      guard !isDemoMode else { return }
      try await health.export(workout)
      try Task.checkCancellation()
      notice = "Тренировка отправлена в «Здоровье»."
    } catch {
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      report(
        error, operation: "exportHealth",
        message:
          "Не удалось отправить тренировку в «Здоровье». Проверьте разрешение на запись и попробуйте ещё раз."
      )
    }
  }
  private func importWatch(_ workout: Workout) -> Bool {
    guard !isDemoMode else { return false }
    do {
      // Re-delivery must not erase body weight or other edits already saved on the phone.
      _ = try repository.importArchive(WorkoutArchive(workouts: [workout], templates: []))
      try loadRepository()
      refreshIntegrations()
      return true
    } catch {
      report(
        error, operation: "importWatch",
        message: "Не удалось сохранить тренировку с Apple Watch. Часы повторят отправку.")
      return false
    }
  }
  /// Intents use the same context as the UI, even when the system cold-launches the process.
  func performLiveAction(_ action: WorkoutLiveAction, workoutID: UUID) async throws {
    guard !isDemoMode else { throw TrainingError.invalidState }
    do {
      guard var workout = try repository.workouts().first(where: { $0.id == workoutID }) else {
        throw TrainingError.invalidState
      }
      if try action.apply(to: &workout, expectedWorkoutID: workoutID) {
        try repository.save(workout)
      }
      active = workout
      try loadRepository()
    } catch {
      report(
        error, operation: "liveAction",
        message: "Не удалось изменить тренировку. Откройте FitnessTracker и повторите действие.")
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
    let tracker = tracker
    lease.begin {
      pending?.cancel()
      tracker.cancelPendingWork()
    }
    defer { lease.end() }
    await tracker.flush()
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
    guard platformServicesEnabled, !isDemoMode else { return }
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
      } catch {
        if firstError == nil {
          firstError = error
        } else {
          AppErrorReporter.record(error, operation: "updateLiveActivity")
        }
      }
      guard !Task.isCancelled else { return }
      do {
        if defaults.bool(forKey: "widgetSharing") {
          let week = TrainingStatistics.weeks(in: workouts, count: 1).first
          try WidgetSnapshot(
            workoutsThisWeek: week?.workouts ?? 0,
            weeklyGoal: max(1, defaults.integer(forKey: "weeklyGoal")), updatedAt: .now
          ).write()
        } else {
          try WidgetSnapshot.clear()
        }
        WidgetCenter.shared.reloadAllTimelines()
      } catch {
        if firstError == nil {
          firstError = error
        } else {
          AppErrorReporter.record(error, operation: "publishWidget")
        }
      }
      if let firstError, !Task.isCancelled {
        report(
          firstError, operation: "refreshIntegrations",
          message:
            "Не удалось обновить уведомления или виджеты. Откройте приложение ещё раз, чтобы повторить обновление."
        )
      }
    }
  }
  private func report(_ error: any Error, operation: String, message: String) {
    self.error = AppErrorReporter.message(for: error, operation: operation, fallback: message)
  }
}
