import FitLifeCore
import Foundation
import Network
import Observation
import UIKit
import WidgetKit

@MainActor @Observable final class AppStore {
  private(set) var workouts: [Workout] = []
  private(set) var completed: [Workout] = []
  private(set) var templates: [WorkoutTemplate] = []
  private(set) var bodyWeights: [BodyWeightEntry] = []
  private(set) var currentBodyWeightKG: Double?
  private(set) var active: Workout?
  var error: String?
  var notice: String?
  var showSession = false
  var showingWorkoutStart = false
  var showingWorkoutDetail = false
  var showingTemplateEditor = false
  var showingBodyWeightEditor = false
  private(set) var isDemoMode = false
  private(set) var switchingDemo = false
  private(set) var switchingTrainingAccount = false
  private(set) var workspaceID = UUID()
  let nutrition: NutritionDiaryModel?
  let sleepAlarms: SleepAlarmStore
  let settings: SettingsViewModel
  let tracker: TrackerViewModel
  let healthCharts: HealthChartsViewModel
  let healthData: HealthDataSources
  @ObservationIgnored let exerciseImages: any ExerciseImageLoading
  @ObservationIgnored private let repository: WorkoutWorkspaceRepository
  @ObservationIgnored private let health: any HealthWorkoutExporting
  @ObservationIgnored private let notifications: any RestNotificationServing
  @ObservationIgnored private let liveActivity = LiveActivityService()
  @ObservationIgnored private let watch = PhoneWatchBridge()
  @ObservationIgnored private var integrationTask: Task<Void, Never>?
  @ObservationIgnored private var heartRateUpdateTask: Task<Void, Never>?
  @ObservationIgnored private var servicesStarted = false
  @ObservationIgnored private let platformServicesEnabled: Bool
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let archiveFiles: any ArchiveFileHandling
  @ObservationIgnored private let accountSession: AccountSession?
  @ObservationIgnored private let trainingHeartRates: any TrainingHeartRateRepository
  @ObservationIgnored private let trainingStateStorage: any TrainingSyncStateStoring
  @ObservationIgnored private var trainingForeground = true
  @ObservationIgnored private var trainingNetworkMonitor: NWPathMonitor?
  let usesServerTraining: Bool
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var exerciseDraftStore: WorkoutExerciseDraftStore?
  @ObservationIgnored lazy var account: AccountTrainingViewModel? = {
    guard let accountSession else { return nil }
    let cryptography = AppleServerCryptography()
    let sync = TrainingSyncCoordinator(
      remote: RemoteTrainingClient(session: accountSession), storage: trainingStateStorage,
      cryptography: cryptography,
      snapshot: { [weak self] in
        guard let self else { throw CancellationError() }
        return try await self.trainingSnapshot()
      },
      current: { [weak self] key in
        guard let self else { throw CancellationError() }
        return try await self.currentTrainingValue(key)
      },
      apply: { [weak self] change, expected, pulse in
        guard let self else { throw CancellationError() }
        return try await self.applyTrainingChange(change, expected: expected, relatedPulse: pulse)
      },
      available: { [weak self] in
        guard let self else { return false }
        return self.trainingForeground && !self.isDemoMode && !self.switchingDemo
          && !self.switchingTrainingAccount
      })
    return AccountTrainingViewModel(
      session: accountSession, sync: sync, storage: trainingStateStorage,
      cryptography: cryptography,
      activate: { [weak self] namespace in
        guard let self else { throw CancellationError() }
        try await self.activateTrainingAccount(namespace)
      }, selection: { [weak self] in self?.repository.trainingAccountSelection })
  }()
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
    healthCharts: HealthChartsViewModel? = nil,
    healthData: HealthDataSources? = nil,
    accountSession: AccountSession? = nil, sleepAlarmScheduler: (any SleepAlarmScheduling)? = nil,
    trainingHeartRates: (any TrainingHeartRateRepository)? = nil,
    trainingStateStorage: (any TrainingSyncStateStoring)? = nil,
    serverTrainingConfigured: Bool = false,
    now: @escaping () -> Date = Date.init
  ) {
    self.sleepAlarms = SleepAlarmStore(
      scheduler: sleepAlarmScheduler ?? SystemSleepAlarm(), defaults: defaults, now: now)
    self.repository = WorkoutWorkspaceRepository(personal: repository)
    self.nutrition = (repository as? any NutritionRepository).map {
      NutritionDiaryModel(repository: $0)
    }
    self.health = health
    self.defaults = defaults
    self.platformServicesEnabled = platformServicesEnabled
    self.notifications = notifications
    self.settings = SettingsViewModel(cloud: cloud, notifications: notifications)
    self.exerciseImages = exerciseImages
    self.archiveFiles = archiveFiles
    self.accountSession = accountSession
    self.usesServerTraining = serverTrainingConfigured || accountSession != nil
    if let trainingHeartRates {
      self.trainingHeartRates = trainingHeartRates
    } else if platformServicesEnabled {
      self.trainingHeartRates = LocalHeartRateRepository(
        scope: (repository as? any TrainingAccountRepository)?.trainingAccountSelection
          .currentAccountID)
    } else {
      self.trainingHeartRates = MemoryTrainingHeartRateRepository()
    }
    if let trainingStateStorage {
      self.trainingStateStorage = trainingStateStorage
    } else if platformServicesEnabled {
      self.trainingStateStorage = TrainingSyncStateStore()
    } else {
      self.trainingStateStorage = MemoryTrainingSyncStateStore()
    }
    self.now = now
    let healthAccount: @MainActor () -> String = {
      (repository as? any TrainingAccountRepository)?.trainingAccountSelection.currentAccountID
        ?? "local"
    }
    let healthCache: any HealthDataCaching
    if platformServicesEnabled {
      healthCache = HealthDataCache()
    } else {
      healthCache = MemoryHealthDataCache()
    }
    let cryptography = AppleServerCryptography()
    let appleProvider: any HealthDataProviding
    let appleSync: AppleHealthSyncCoordinator?
    if let accountSession, platformServicesEnabled {
      let remote = RemoteHealthSyncClient(
        session: accountSession, cryptography: cryptography, account: healthAccount)
      let sync = AppleHealthSyncCoordinator(
        reader: AppleHealthSyncReader(), remote: remote,
        storage: HealthSyncStateStore(), defaults: defaults, account: healthAccount, now: { now() })
      appleSync = sync
      appleProvider = SyncedAppleHealthProvider(
        local: AppleHealthDataProvider(), remote: remote, preferLocal: { sync.enabled })
    } else {
      appleSync = nil
      appleProvider = AppleHealthDataProvider()
    }
    self.healthData =
      healthData
      ?? HealthDataSources(
        providers: [
          appleProvider,
          MiFitnessDataProvider(
            session: accountSession, cryptography: cryptography, account: healthAccount),
        ],
        appleSleep: HealthSleepReader(), appleMetrics: HealthMetricsReader(),
        appleCharts: HealthMetricsReader(),
        cache: healthCache, defaults: defaults, account: healthAccount, now: { now() },
        appleSync: appleSync)
    appleSync?.onUpdate = { [weak sources = self.healthData] in sources?.appleHistoryDidChange() }
    let watchPulse = AppleWatchHeartRateService { [weak watch] command in
      guard let watch else { throw TrainingError.invalidState }
      try watch.sendHeartRateCommand(command)
    }
    self.tracker =
      tracker
      ?? TrackerViewModel(
        health: self.healthData, sensor: BluetoothHeartRateService(),
        liveSource: HealthKitLiveHeartRateService(), watchLiveSource: watchPulse,
        recordings: self.trainingHeartRates, defaults: defaults,
        errorMessage: {
          $0 is HealthDataError
            ? HealthProviderMessage.error($0)
            : AppErrorReporter.message(for: $0, operation: $1, fallback: $2)
        })
    self.healthCharts =
      healthCharts
      ?? HealthChartsViewModel(
        reader: self.healthData, defaults: defaults,
        errorMessage: {
          $0 is HealthDataError
            ? HealthProviderMessage.error($0)
            : AppErrorReporter.message(
              for: $0, operation: "healthCharts",
              fallback:
                "Не удалось загрузить пульс и шаги. Проверьте доступ к «Здоровью» и повторите.")
        })
    self.tracker.onHeartRateChange = { [weak self] in self?.scheduleHeartRateUpdate() }
    self.tracker.onRecordingSaved = { [weak self] in self?.account?.sync.requestSync() }
    self.nutrition?.onChange = { [weak self] in self?.account?.sync.requestSync() }
    if platformServicesEnabled { self.nutrition?.reminderService = SupplementNotificationService() }
    self.nutrition?.accountNamespace = { [weak self] in
      self?.repository.trainingAccountSelection?.currentAccountID
    }
    self.repository.onTrainingChange = { [weak self] in self?.account?.sync.requestSync() }
    self.healthCharts.onHeartRateChange = { [weak self] in self?.scheduleHeartRateUpdate() }
    self.healthData.onSelectionChange = { [weak self] in
      guard let self else { return }
      self.tracker.healthDataSourceChanged()
      self.healthCharts.clear()
      if self.healthCharts.enabled { self.healthCharts.retry() }
    }
    watch.heartRateEvent = { [weak watchPulse] in watchPulse?.receive($0) }
    watch.heartRateFailure = { [weak watchPulse] in watchPulse?.connectionFailed(sessionID: $0) }
    watch.heartRateDisconnected = { [weak watchPulse] in watchPulse?.disconnected() }
    sleepAlarms.send = { [weak watch] value in watch?.sendSleepAlarms(value) }
    watch.sleepEvent = { [weak sleepAlarms] event in sleepAlarms?.receive(event) }
    watch.sleepReady = { [weak sleepAlarms] in sleepAlarms?.refresh() }
    watch.sleepConnection = { [weak sleepAlarms] connection in
      sleepAlarms?.setWatchConnection(connection)
    }
    watch.receive = { [weak self] workout, owner in
      self?.importWatch(workout, owner: owner) ?? false
    }
    watch.failure = { [weak self] error in
      self?.report(
        error, operation: "watchConnection",
        message: "Не удалось обменяться данными с Apple Watch. Попробуйте ещё раз.")
    }
    reload()
    sendWatchTrainingContext()
  }
  func startServices() {
    guard platformServicesEnabled, !servicesStarted else { return }
    servicesStarted = true
    sleepAlarms.refresh()
    watch.activate()
    refreshIntegrations()
    Task { [weak self] in await self?.account?.foreground() }
  }
  func reload() {
    nutrition?.reload()
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
      guard !showSession, !showingWorkoutStart, !showingWorkoutDetail, !showingTemplateEditor,
        !showingBodyWeightEditor, nutrition?.isPresenting != true,
        !archiveTransfer.isPresented, !archiveTransfer.isSaving, account?.isBusy != true,
        account?.sync.isSyncing != true, !switchingTrainingAccount
      else { throw TrainingError.invalidState }
      try repository.openDemo(archive)
      isDemoMode = true
      nutrition?.switchWorkspace(isDemo: true)
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
    guard isDemoMode, !switchingDemo, !showingBodyWeightEditor, nutrition?.isPresenting != true
    else { return }
    switchingDemo = true
    defer { switchingDemo = false }
    do {
      try Task.checkCancellation()
      let snapshot = try repository.closeDemo()
      isDemoMode = false
      nutrition?.switchWorkspace(isDemo: false)
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
    exerciseDraftStore = nil
    dismissNavigationPresentations()
    workspaceID = UUID()
  }
  /// Closes presentation state without replacing the workspace, workout or exercise input drafts.
  func dismissNavigationPresentations() {
    error = nil
    notice = nil
    showSession = false
    showingWorkoutStart = false
    showingWorkoutDetail = false
    showingTemplateEditor = false
    showingBodyWeightEditor = false
    nutrition?.isPresenting = false
    archiveTransfer.dismissForNavigation()
  }
  private func loadRepository(refreshTracker: Bool = true) throws {
    // Publish only after all reads succeed; a partial read preserves the previous UI snapshot.
    let loaded = try repository.workouts()
    let routines = try repository.templates()
    let measurements = try repository.bodyWeights()
    applySnapshot(
      workouts: loaded, templates: routines, bodyWeights: measurements,
      refreshTracker: refreshTracker)
  }
  private func applySnapshot(
    workouts loaded: [Workout], templates routines: [WorkoutTemplate],
    bodyWeights measurements: [BodyWeightEntry], refreshTracker: Bool = true
  ) {
    healthData.refreshAccount()
    workouts = loaded
    completed = loaded.filter { $0.status == .completed }
    templates = routines
    bodyWeights = measurements
    let unfinished = loaded.filter { [.active, .paused].contains($0.status) }
    active = unfinished.first { $0.id == active?.id } ?? unfinished.first
    if exerciseDraftStore?.workoutID != active?.id { exerciseDraftStore = nil }
    currentBodyWeightKG =
      BodyWeightSummary(entries: measurements, workouts: loaded, now: now()).latest?.weightKG
      ?? active?.bodyWeightKG
    if !isDemoMode && refreshTracker {
      tracker.attach(active)
      healthCharts.attach(active)
    }
  }

  private func archiveSnapshot() throws -> WorkoutArchive {
    WorkoutArchive(
      workouts: try repository.workouts(), templates: try repository.templates(),
      bodyWeights: try repository.bodyWeights())
  }
  private func trainingSnapshot() async throws -> TrainingSnapshot {
    let workouts = workouts
    let templates = templates
    let weights = bodyWeights
    var pulse: [HeartRateRecording] = []
    for workout in workouts {
      try Task.checkCancellation()
      if let recording = try await trainingHeartRates.recording(for: workout.id) {
        pulse.append(recording)
      }
    }
    return try TrainingSnapshot(
      workouts: workouts, templates: templates, bodyWeights: weights, heartRate: pulse,
      nutrition: nutrition?.syncSnapshot() ?? NutritionSnapshot())
  }

  func currentTrainingValue(_ key: TrainingRecordKey) async throws -> TrainingValue? {
    if key.kind != .heartRate { return try currentRootTrainingValue(key) }
    return try await trainingHeartRates.recording(for: key.id).map(TrainingValue.heartRate)
  }

  private func currentRootTrainingValue(_ key: TrainingRecordKey) throws -> TrainingValue? {
    if key.kind.isNutrition {
      return try nutrition?.syncValue(key)
    }
    return
      switch key.kind
    {
    case .workout: workouts.first { $0.id == key.id }.map(TrainingValue.workout)
    case .template: templates.first { $0.id == key.id }.map(TrainingValue.template)
    case .bodyWeight: bodyWeights.first { $0.id == key.id }.map(TrainingValue.bodyWeight)
    case .heartRate, .foodEntry, .waterEntry, .supplementEntry, .supplementPlan, .nutritionProfile:
      nil
    }
  }

  private func applyTrainingChange(
    _ change: TrainingChange, expected: TrainingValue?, relatedPulse: TrainingValue?
  ) async throws -> TrainingLocalApplyResult {
    guard !isDemoMode, !switchingTrainingAccount else { throw CancellationError() }
    if change.key.kind == .heartRate {
      if pulseIsBusy(for: change.key.id) { return .activeWorkout }
      let previous: HeartRateRecording?
      let next: HeartRateRecording?
      if case .heartRate(let value) = expected { previous = value } else { previous = nil }
      if case .heartRate(let value) = change.value { next = value } else { next = nil }
      let applied = try await trainingHeartRates.compareAndSet(
        workoutID: change.key.id, expected: previous, replacement: next)
      if applied { tracker.reloadStoredRecording(for: change.key.id) }
      return applied ? .applied : .changed
    }
    // Read again immediately before the synchronous save; edits made during awaits stay local.
    let current = try currentRootTrainingValue(change.key)
    guard current == expected else { return .changed }
    if change.key.kind == .workout
      && (showingWorkoutDetail || showSession && active?.id == change.key.id)
      || change.key.kind == .template && showingTemplateEditor
      || change.key.kind == .bodyWeight && showingBodyWeightEditor
      || change.key.kind.isNutrition && nutrition?.isPresenting == true
    {
      return .changed
    }
    if change.key.kind == .workout && change.deleted && pulseIsBusy(for: change.key.id) {
      return .activeWorkout
    }
    var removedPulse: HeartRateRecording?
    if change.key.kind == .workout && change.deleted {
      if case .heartRate(let value) = relatedPulse { removedPulse = value }
      guard
        try await trainingHeartRates.compareAndSet(
          workoutID: change.key.id, expected: removedPulse, replacement: nil)
      else { return .changed }
      if try currentRootTrainingValue(change.key) != expected || pulseIsBusy(for: change.key.id) {
        if let removedPulse {
          _ = try await trainingHeartRates.compareAndSet(
            workoutID: change.key.id, expected: nil, replacement: removedPulse)
        }
        return .changed
      }
    }
    do {
      let wasActive = active?.id == change.key.id && change.key.kind == .workout
      try repository.applyTrainingChanges([change])
      if change.key.kind.isNutrition { nutrition?.reload() }
      if change.key.kind == .workout && change.deleted {
        tracker.discardDeletedRecording(for: change.key.id)
      }
      let updatedActive: Bool
      if case .workout(let value) = change.value {
        updatedActive = [.active, .paused].contains(value.status)
      } else {
        updatedActive = false
      }
      try loadRepository(refreshTracker: wasActive || updatedActive)
      if active == nil { showSession = false }
      refreshIntegrations(allowStart: false)
      return .applied
    } catch {
      if let removedPulse {
        _ = try await trainingHeartRates.compareAndSet(
          workoutID: change.key.id, expected: nil, replacement: removedPulse)
      }
      if error as? TrainingSyncError == .activeWorkout { return .activeWorkout }
      throw error
    }
  }

  private func pulseIsBusy(for workoutID: UUID) -> Bool {
    if tracker.hasPendingHeartRateImports { return true }
    guard tracker.attachedWorkoutID == workoutID else { return false }
    return tracker.hasLiveSession || tracker.startingLive || tracker.hasPendingSaves
      || tracker.loadingHealth || tracker.preparingRecording
      || tracker.bluetooth.connection == .connected && tracker.attachedWorkoutStatus == .active
  }

  private func activateTrainingAccount(_ namespace: String) async throws {
    guard !isDemoMode, !switchingDemo, !switchingTrainingAccount,
      let selection = repository.trainingAccountSelection
    else { throw TrainingSyncError.unsupportedStore }
    guard selection.currentAccountID != namespace else { return }
    if selection.firstAccountID != nil,
      active != nil || showSession || showingWorkoutStart || showingWorkoutDetail
        || showingTemplateEditor || showingBodyWeightEditor || nutrition?.isPresenting == true
        || archiveTransfer.isSaving
    {
      throw TrainingSyncError.activeWorkout
    }
    switchingTrainingAccount = true
    repository.personalWritesSuspended = true
    tracker.trainingWritesSuspended = true
    nutrition?.writesSuspended = true
    nutrition?.refreshReminders()
    defer {
      switchingTrainingAccount = false
      repository.personalWritesSuspended = false
      tracker.trainingWritesSuspended = false
      nutrition?.writesSuspended = false
      nutrition?.switchWorkspace(isDemo: false)
    }
    do {
      guard !tracker.loadingHealth, !tracker.hasPendingHeartRateImports else {
        throw TrainingSyncError.activeWorkout
      }
      tracker.disconnect()
      tracker.attach(nil)
      await tracker.flush()
      guard !tracker.hasPendingSaves else { throw TrackerDataError.invalidRecording }
      guard !tracker.hasPendingHeartRateImports else { throw TrainingSyncError.activeWorkout }
      try await trainingHeartRates.activateTrainingAccount(
        namespace, adoptUnscoped: selection.firstAccountID == nil)
      try repository.activateTrainingAccount(namespace)
      try loadRepository()
      sendWatchTrainingContext()
      refreshIntegrations(allowStart: false)
    } catch {
      let actual = repository.trainingAccountSelection?.currentAccountID
      try await trainingHeartRates.setTrainingAccountScope(actual)
      if actual != selection.currentAccountID {
        applySnapshot(workouts: [], templates: [], bodyWeights: [])
      } else {
        try loadRepository()
      }
      throw error
    }
  }

  func resumeTrainingSync() async {
    trainingForeground = true
    nutrition?.refreshReminders()
    if accountSession != nil, trainingNetworkMonitor == nil, platformServicesEnabled {
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { [weak self] path in
        guard path.status == .satisfied else { return }
        Task { @MainActor in
          self?.account?.sync.requestSync(immediately: true)
          self?.healthData.appleSync?.requestSync()
        }
      }
      trainingNetworkMonitor = monitor
      monitor.start(queue: DispatchQueue(label: "FitLife.TrainingNetwork"))
    }
    await account?.foreground()
  }

  func suspendTrainingSync() async {
    trainingForeground = false
    trainingNetworkMonitor?.cancel()
    trainingNetworkMonitor = nil
    await account?.suspend()
  }

  private var watchTrainingContext: WatchTrainingContext {
    let selection = repository.trainingAccountSelection
    return WatchTrainingContext(
      currentAccountID: selection?.currentAccountID, firstAccountID: selection?.firstAccountID)
  }
  private func sendWatchTrainingContext() { watch.sendTrainingContext(watchTrainingContext) }

  @discardableResult func saveBodyWeight(_ entry: BodyWeightEntry) -> Bool {
    do {
      try commitBodyWeight(entry, snapshot: archiveSnapshot(), isCurrentUpdate: false)
      return true
    } catch {
      report(
        error, operation: "saveBodyWeight", message: "Не удалось сохранить вес. Попробуйте ещё раз."
      )
      return false
    }
  }
  @discardableResult func setCurrentBodyWeight(_ weightKG: Double) -> Bool {
    do {
      try Validation.bodyWeight(weightKG)
      let snapshot = try archiveSnapshot()
      let previous = active.flatMap { workout in
        snapshot.bodyWeights.first { $0.workoutID == workout.id }
      }
      let entry = BodyWeightEntry(
        id: previous?.id ?? UUID(), measuredAt: now(), weightKG: weightKG,
        workoutID: active?.id)
      try commitBodyWeight(entry, snapshot: snapshot, isCurrentUpdate: true)
      return true
    } catch {
      report(
        error, operation: "saveBodyWeight", message: "Не удалось сохранить вес. Попробуйте ещё раз."
      )
      return false
    }
  }
  private func commitBodyWeight(
    _ value: BodyWeightEntry, snapshot: WorkoutArchive, isCurrentUpdate: Bool
  ) throws {
    try Validation.bodyWeightEntry(value)
    var entry = value
    var measurements = snapshot.bodyWeights.filter { $0.id != entry.id } + [entry]
    var workouts = snapshot.workouts
    var updated: Workout?
    if let active {
      guard let index = workouts.firstIndex(where: { $0.id == active.id }),
        [.active, .paused].contains(workouts[index].status)
      else { throw TrainingError.invalidState }
      let previousEntry = snapshot.bodyWeights.first { $0.id == entry.id }
      let latest = BodyWeightSummary(
        entries: measurements, workouts: workouts, now: now()
      ).latest
      let isRecentReading =
        entry.measuredAt >= active.startedAt
        && (previousEntry == nil || previousEntry.map { $0.measuredAt >= active.startedAt } == true)
        && (entry.workoutID == nil || entry.workoutID == active.id)
        && latest?.source == .measurement(entry.id)
      if isCurrentUpdate || isRecentReading {
        try WorkoutEngine.setBodyWeight(entry.weightKG, in: &workouts[index])
        entry.workoutID = active.id
        measurements = measurements.map { $0.id == entry.id ? entry : $0 }
        updated = workouts[index]
      }
    }
    // All reads and transformations finish before the single transactional write.
    try repository.saveBodyWeight(entry, updating: updated)
    measurements.sort {
      $0.measuredAt == $1.measuredAt
        ? $0.id.uuidString < $1.id.uuidString : $0.measuredAt > $1.measuredAt
    }
    applySnapshot(workouts: workouts, templates: snapshot.templates, bodyWeights: measurements)
    if updated != nil { refreshIntegrations() }
  }
  @discardableResult func setBodyWeight(_ weightKG: Double?, for workoutID: UUID) -> Bool {
    if active?.id == workoutID {
      if let weightKG { return setCurrentBodyWeight(weightKG) }
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
        let snapshot = try archiveSnapshot()
        let entry = snapshot.bodyWeights.first { $0.id == id }
        var workouts = snapshot.workouts
        var updated: Workout?
        if let entry, let workoutID = entry.workoutID,
          let index = workouts.firstIndex(where: { $0.id == workoutID }),
          workouts[index].bodyWeightKG == entry.weightKG
        {
          if [.active, .paused].contains(workouts[index].status) {
            try WorkoutEngine.setBodyWeight(nil, in: &workouts[index])
          } else {
            workouts[index].bodyWeightKG = nil
            try Validation.workout(workouts[index])
          }
          updated = workouts[index]
        }
        try repository.deleteBodyWeight(id: id, updating: updated)
        applySnapshot(
          workouts: workouts, templates: snapshot.templates,
          bodyWeights: snapshot.bodyWeights.filter { $0.id != id })
        if updated != nil { refreshIntegrations() }
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
  /// All general start buttons use the picker; resuming never replaces the active session.
  func presentWorkoutStart() {
    if active != nil {
      showingWorkoutStart = false
      showSession = true
    } else {
      showingWorkoutStart = true
    }
  }

  func start(template: WorkoutTemplate? = nil) {
    start(templates: template.map { [$0] } ?? [])
  }
  func start(templates: [WorkoutTemplate]) {
    guard active == nil else {
      showSession = true
      return
    }
    do {
      let workout: Workout
      switch templates.count {
      case 0:
        workout = Workout(name: L10n.text(isDemoMode ? "Демо-тренировка" : "Свободная тренировка"))
      case 1:
        workout = try templates[0].start(prefillTargets: false)
      default:
        workout = try WorkoutTemplate.start(combining: templates, prefillTargets: false)
      }
      try activate(workout)
    } catch {
      report(
        error, operation: "startWorkout",
        message: "Не удалось начать тренировку. Попробуйте ещё раз.")
    }
  }
  private func activate(_ workout: Workout) throws {
    var workout = workout
    try WorkoutEngine.applyPreviousTargets(
      to: Set(workout.exercises.map(\.id)), in: &workout, history: workouts)
    try WorkoutEngine.setBodyWeight(currentBodyWeightKG, in: &workout)
    try repository.save(workout)
    try loadRepository()
    showSession = true
    if platformServicesEnabled, !isDemoMode,
      defaults.object(forKey: "liveActivities") as? Bool != false
    {
      // Request synchronously while foregrounded, before notification/widget async work.
      do {
        try liveActivity.startIfNeeded(
          for: workout, heartRate: currentLiveHeartRate,
          colorTheme: FitnessColorTheme.resolved(defaults.string(forKey: "colorTheme")))
      } catch {
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
    let original = workout
    do {
      try action(&workout)
      if workout.status == .active {
        let added = workout.exercises.filter { row in
          !original.exercises.contains { $0.id == row.id && $0.exercise.id == row.exercise.id }
        }
        try WorkoutEngine.applyPreviousTargets(
          to: Set(added.map(\.id)), in: &workout, history: workouts)
      }
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
  func exerciseDrafts(for workout: Workout, unit: WeightUnit) -> WorkoutExerciseDraftStore {
    guard active?.id == workout.id else {
      return WorkoutExerciseDraftStore(workoutID: workout.id, unit: unit)
    }
    if let exerciseDraftStore,
      exerciseDraftStore.workoutID == workout.id, exerciseDraftStore.unit == unit
    {
      return exerciseDraftStore
    }
    let drafts = WorkoutExerciseDraftStore(workoutID: workout.id, unit: unit)
    exerciseDraftStore = drafts
    return drafts
  }

  func saveExerciseInputs(_ model: WorkoutExercisePresentation, workoutID: UUID) {
    guard let active, active.id == workoutID else { return }
    let values = model.pendingValues(in: active, includingCompleted: true)
    guard !values.isEmpty else { return }
    mutate { try WorkoutEngine.updateEditableValues(values, in: &$0) }
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
  private func importWatch(_ workout: Workout, owner: String?) -> Bool {
    guard !isDemoMode, !switchingTrainingAccount, watchTrainingContext.accepts(owner) else {
      return false
    }
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
    guard !isDemoMode, !switchingTrainingAccount else { throw TrainingError.invalidState }
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
        message: "Не удалось изменить тренировку. Откройте FitLife и повторите действие.")
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
    heartRateUpdateTask?.cancel()
    refreshIntegrations(allowStart: false)
    let pending = integrationTask
    let lease = BackgroundTaskLease()
    let tracker = tracker
    lease.begin { [weak self] in
      pending?.cancel()
      self?.heartRateUpdateTask?.cancel()
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

  private var currentLiveHeartRate: HeartRateReading? {
    tracker.liveActivityHeartRate(
      healthReading: healthCharts.enabled ? healthCharts.snapshot?.latestHeartRate : nil)
  }

  private func scheduleHeartRateUpdate() {
    guard platformServicesEnabled, !isDemoMode, active != nil,
      defaults.object(forKey: "liveActivities") as? Bool != false,
      heartRateUpdateTask == nil
    else { return }
    // Coalesce sensor callbacks; no polling or widget/notification refresh per measurement.
    // This finite task belongs to the store and never starts a background activity.
    heartRateUpdateTask = Task { [weak self] in
      guard let self else { return }
      defer { self.heartRateUpdateTask = nil }
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      guard !Task.isCancelled else { return }
      self.refreshIntegrations(allowStart: false, liveActivityOnly: true)
      await self.integrationTask?.value
    }
  }

  func refreshIntegrations(allowStart: Bool? = nil, liveActivityOnly: Bool = false) {
    guard platformServicesEnabled, !isDemoMode else { return }
    let previous = integrationTask
    if !liveActivityOnly { previous?.cancel() }
    let workout = active
    let canStart = allowStart ?? (UIApplication.shared.applicationState == .active)
    integrationTask = Task {
      // Await the old operation so a late completion cannot overwrite the newest state.
      await previous?.value
      guard !Task.isCancelled else { return }
      var firstError: (any Error)?
      do {
        if !liveActivityOnly {
          if defaults.bool(forKey: "restNotifications") {
            try await notifications.schedule(until: workout?.restEndsAt)
          } else {
            notifications.cancel()
          }
        }
      } catch { firstError = error }
      guard !Task.isCancelled else { return }
      do {
        try await liveActivity.update(
          for: defaults.object(forKey: "liveActivities") as? Bool == false ? nil : workout,
          allowStart: canStart, heartRate: currentLiveHeartRate,
          colorTheme: FitnessColorTheme.resolved(defaults.string(forKey: "colorTheme")))
      } catch {
        if firstError == nil {
          firstError = error
        } else {
          AppErrorReporter.record(error, operation: "updateLiveActivity")
        }
      }
      guard !Task.isCancelled else { return }
      if liveActivityOnly {
        if let firstError { AppErrorReporter.record(firstError, operation: "updateLiveHeartRate") }
        return
      }
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
