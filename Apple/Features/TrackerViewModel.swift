import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class TrackerViewModel {
  @ObservationIgnored var onHeartRateChange: (@MainActor () -> Void)?
  private(set) var mode: TrackerMode { didSet { onHeartRateChange?() } }
  private(set) var deviceProfile: TrackerDeviceProfile
  private(set) var bluetooth = HeartRateBluetoothSnapshot() { didSet { onHeartRateChange?() } }
  private(set) var summary: HealthDaySummary?
  private(set) var loadingHealth = false
  private(set) var hasRequestedHealth = false
  private(set) var healthReadAt: Date?
  private(set) var healthReadChanged: Bool?
  private(set) var healthReadFailed = false
  private(set) var recording: HeartRateRecording? { didSet { rebuildChart() } }
  private(set) var chartPoints: [HeartRateChartPoint] = []
  private(set) var preparingRecording = false
  private(set) var live = LiveHeartRateSnapshot() { didSet { onHeartRateChange?() } }
  private(set) var startingLive = false
  private(set) var attachedWorkoutStatus: WorkoutStatus?
  var hasLiveSession: Bool { [.starting, .running, .paused].contains(live.state) }
  var canStartLive: Bool {
    liveSource != nil && mode == .appleHealth && deviceProfile == .airPodsPro3
      && attachedWorkoutStatus == .active && !preparingRecording && !startingLive && !hasLiveSession
  }
  var error: String?
  var hasPendingSaves: Bool { !pendingSaves.isEmpty }
  var canRetryRecordingLoad: Bool { workout != nil && recording == nil && !preparingRecording }
  @ObservationIgnored private let health: any HealthMetricsReading
  @ObservationIgnored private let sensor: any HeartRateBluetooth
  @ObservationIgnored private let liveSource: (any LiveHeartRateServing)?
  @ObservationIgnored private let recordings: any HeartRateRecordingRepository
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let errorMessage: (any Error, String, String) -> String
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var workout: Workout? { didSet { rebuildChart() } }
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var pendingSaves: [UUID: HeartRateRecording] = [:]
  @ObservationIgnored private var healthRequest: UUID?
  @ObservationIgnored private var healthBaseline: HealthDaySummary?
  @ObservationIgnored private var lastQueuedAt: Date?
  @ObservationIgnored private var backgroundWorkCancelled = false
  @ObservationIgnored private var liveRequest: UUID?
  @ObservationIgnored private var liveWorkoutID: UUID?

  init(
    health: any HealthMetricsReading, sensor: any HeartRateBluetooth,
    liveSource: (any LiveHeartRateServing)? = nil,
    recordings: any HeartRateRecordingRepository, defaults: UserDefaults = .standard,
    errorMessage: @escaping (any Error, String, String) -> String,
    now: @escaping () -> Date = Date.init
  ) {
    self.health = health
    self.sensor = sensor
    self.liveSource = liveSource
    self.recordings = recordings
    self.defaults = defaults
    self.errorMessage = errorMessage
    self.now = now
    mode = TrackerMode(rawValue: defaults.string(forKey: "trackerMode") ?? "") ?? .appleHealth
    deviceProfile =
      TrackerDeviceProfile(rawValue: defaults.string(forKey: "trackerDeviceProfile") ?? "")
      ?? .xiaomiSmartBand10
    sensor.onChange = { [weak self] snapshot in self?.receive(snapshot) }
    liveSource?.onChange = { [weak self] snapshot in self?.receiveLive(snapshot) }
  }
  func liveActivityHeartRate(healthReading: HeartRateReading?) -> HeartRateReading? {
    guard let workout, workout.status == .active else { return nil }
    let candidates = [
      mode == .bluetooth && bluetooth.connection == .connected ? bluetooth.reading : nil,
      mode == .appleHealth && live.state == .running && liveWorkoutID == workout.id
        ? live.reading : nil,
      healthReading,
    ]
    let earliest = max(workout.startedAt, workout.pauses.last?.endedAt ?? workout.startedAt)
    return candidates.compactMap { $0 }
      .filter { $0.isFresh(at: now()) && $0.date >= earliest }
      .max { $0.date < $1.date }
  }

  func selectMode(_ mode: TrackerMode) {
    guard mode != self.mode else { return }
    queueSave()
    stopLiveSession()
    sensor.disconnect()
    healthRequest = nil
    loadingHealth = false
    healthReadAt = nil
    healthReadChanged = nil
    healthBaseline = nil
    healthReadFailed = false
    self.mode = mode
    defaults.set(mode.rawValue, forKey: "trackerMode")
    error = nil
  }
  func selectDeviceProfile(_ profile: TrackerDeviceProfile) {
    if profile != .airPodsPro3, liveRequest != nil {
      queueSave()
      stopLiveSession()
    }
    deviceProfile = profile
    defaults.set(profile.rawValue, forKey: "trackerDeviceProfile")
  }
  func scan() {
    if mode == .bluetooth {
      error = nil
      sensor.scan()
    }
  }
  func connect(_ id: UUID) { if mode == .bluetooth { sensor.connect(id) } }
  func disconnect() {
    queueSave()
    stopLiveSession()
    sensor.disconnect()
  }
  func leaveScreen() {
    sensor.stopScan()
    if workout == nil { sensor.disconnect() }
  }

  func retryRecordingLoad() { attach(workout, reload: true) }
  func attach(_ workout: Workout?, reload: Bool = false) {
    attachedWorkoutStatus = workout?.status
    if workout?.id == self.workout?.id && !reload {
      if workout?.status != self.workout?.status {
        queueSave()
        self.workout = workout
        if workout?.status == .paused {
          if startingLive { stopLiveSession() } else { liveSource?.pause() }
        } else if workout?.status == .active {
          liveSource?.resume()
        } else {
          stopLiveSession()
        }
      }
      self.workout = workout
      return
    }
    queueSave()
    stopLiveSession()
    if self.workout != nil { sensor.disconnect() }
    loadTask?.cancel()
    self.workout = workout
    recording = nil
    lastQueuedAt = nil
    preparingRecording = workout != nil
    guard let workout else { return }
    let previousSave = saveTask
    loadTask = Task { [weak self, recordings] in
      await previousSave?.value
      guard let self, !Task.isCancelled else { return }
      defer { if self.workout?.id == workout.id { self.preparingRecording = false } }
      do {
        let saved = try await recordings.recording(for: workout.id)
        try Task.checkCancellation()
        guard self.workout?.id == workout.id else { return }
        if let existing = self.pendingSaves[workout.id] ?? saved {
          self.recording = existing
        } else {
          self.recording = try HeartRateRecording(workoutID: workout.id, mode: .bluetooth)
        }
        self.error = nil
      } catch {
        guard !Task.isCancelled else { return }
        self.report(
          error, operation: "loadHeartRate",
          fallback: "Не удалось открыть запись пульса. Данные не удалены.")
      }
    }
  }

  private func receive(_ snapshot: HeartRateBluetoothSnapshot) {
    bluetooth = snapshot
    guard mode == .bluetooth, let reading = snapshot.reading, reading.isFresh(at: now()),
      let workout, !preparingRecording, let recording, recording.mode == .bluetooth
    else { return }
    append(reading, to: workout, recording: recording)
  }
  private func rebuildChart() {
    chartPoints = HeartRateChartPoint.make(
      readings: recording?.readings ?? [], pauses: workout?.pauses ?? [])
  }
  private func append(
    _ reading: HeartRateReading, to workout: Workout, recording original: HeartRateRecording
  ) {
    var recording = original
    do {
      if try recording.append(reading, to: workout) {
        self.recording = recording
        if lastQueuedAt == nil || reading.date.timeIntervalSince(lastQueuedAt ?? reading.date) >= 15
        {
          queueSave()
        }
      }
    } catch {
      disconnect()
      report(
        error, operation: "recordHeartRate",
        fallback: "Достигнут предел записи пульса для этой тренировки.")
    }
  }

  func startLiveHeartRate() async {
    guard !startingLive, !hasLiveSession else { return }
    guard mode == .appleHealth, deviceProfile == .airPodsPro3, let workout,
      workout.status == .active, let liveSource
    else {
      error = "Начните тренировку и выберите AirPods Pro 3 в режиме Apple «Здоровье»."
      return
    }
    let request = UUID()
    liveRequest = request
    liveWorkoutID = workout.id
    startingLive = true
    error = nil
    defer { if liveRequest == request { startingLive = false } }
    do {
      await loadTask?.value
      try Task.checkCancellation()
      guard liveRequest == request, self.workout?.id == workout.id,
        self.workout?.status == .active
      else { throw CancellationError() }
      guard let recording, !preparingRecording else {
        throw ServiceError.unavailable(
          "Сначала загрузите запись пульса. Повторите загрузку в разделе «Трекер».")
      }
      guard recording.readings.isEmpty || recording.origin == .liveHealthKit else {
        throw ServiceError.unavailable(
          "В этой тренировке уже есть пульс другого источника. Он не будет заменён новой записью.")
      }
      if recording.readings.isEmpty {
        self.recording = try HeartRateRecording(
          workoutID: workout.id, mode: .appleHealth, origin: .liveHealthKit)
      }
      try await liveSource.start(sessionID: request)
      try Task.checkCancellation()
      guard liveRequest == request, self.workout?.id == workout.id,
        self.workout?.status == .active
      else { throw CancellationError() }
    } catch {
      guard liveRequest == request else { return }
      stopLiveSession()
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      report(
        error, operation: "startLiveHeartRate",
        fallback: "Не удалось начать приём пульса. Проверьте AirPods и доступ к «Здоровью».")
    }
  }
  func stopLiveHeartRate() {
    queueSave()
    stopLiveSession()
  }
  private func stopLiveSession() {
    liveRequest = nil
    liveWorkoutID = nil
    startingLive = false
    liveSource?.stop()
    live = LiveHeartRateSnapshot(state: .stopped)
  }
  private func receiveLive(_ snapshot: LiveHeartRateSnapshot) {
    guard snapshot.sessionID == liveRequest, liveRequest != nil else { return }
    if snapshot.state == .running, workout?.status != .active { return }
    live = snapshot
    if snapshot.state == .failed || snapshot.state == .stopped {
      queueSave()
      liveRequest = nil
      liveWorkoutID = nil
      startingLive = false
      if snapshot.state == .failed {
        error = "Приём пульса остановлен. Проверьте подключение AirPods и начните снова."
        liveSource?.stop()
      }
      return
    }
    guard snapshot.state == .running, mode == .appleHealth, deviceProfile == .airPodsPro3,
      let workout, workout.id == liveWorkoutID, let reading = snapshot.reading,
      reading.isFresh(at: now()), !preparingRecording, let recording,
      recording.origin == .liveHealthKit
    else { return }
    append(reading, to: workout, recording: recording)
  }
  private func queueSave() {
    guard let recording, !recording.readings.isEmpty else { return }
    lastQueuedAt = recording.readings.last?.date
    enqueue(recording)
  }
  private func enqueue(_ recording: HeartRateRecording) {
    pendingSaves[recording.workoutID] = recording
    let previous = saveTask
    saveTask = Task { [weak self, recordings] in
      await previous?.value
      do {
        try await recordings.save(recording)
        if self?.pendingSaves[recording.workoutID] == recording {
          self?.pendingSaves[recording.workoutID] = nil
        }
      } catch {
        self?.report(
          error, operation: "saveHeartRate",
          fallback: "Не удалось сохранить пульс. Повторите сохранение в разделе «Трекер».")
      }
    }
  }
  func retrySaving() async {
    error = nil
    for recording in Array(pendingSaves.values) { enqueue(recording) }
    await saveTask?.value
  }
  func flush() async {
    guard !Task.isCancelled else { return }
    backgroundWorkCancelled = false
    await loadTask?.value
    guard !Task.isCancelled, !backgroundWorkCancelled else { return }
    queueSave()
    await saveTask?.value
  }
  func cancelPendingWork() {
    backgroundWorkCancelled = true
    loadTask?.cancel()
    saveTask?.cancel()
  }
  func recording(for workoutID: UUID) async throws -> HeartRateRecording? {
    await saveTask?.value
    if let pending = pendingSaves[workoutID] { return pending }
    return try await recordings.recording(for: workoutID)
  }
  func removeRecording(for workoutID: UUID) {
    pendingSaves[workoutID] = nil
    let previous = saveTask
    saveTask = Task { [weak self, recordings] in
      await previous?.value
      do { try await recordings.remove(for: workoutID) } catch {
        self?.report(
          error, operation: "deleteHeartRate",
          fallback: "Не удалось удалить запись пульса. Повторите действие.")
      }
    }
  }

  func readHealth(day: Date, calendar: Calendar) async {
    guard mode == .appleHealth else { return }
    let request = UUID()
    healthRequest = request
    loadingHealth = true
    healthReadAt = nil
    healthReadChanged = nil
    healthReadFailed = false
    summary = nil
    error = nil
    defer { if healthRequest == request { loadingHealth = false } }
    do {
      try await health.requestReadAuthorization()
      try Task.checkCancellation()
      guard healthRequest == request else { return }
      hasRequestedHealth = true
      let summary = try await health.daySummary(for: day, calendar: calendar)
      try Task.checkCancellation()
      if healthRequest == request {
        healthReadChanged = healthBaseline.flatMap { previous in
          calendar.isDate(previous.day, inSameDayAs: summary.day) ? previous != summary : nil
        }
        healthBaseline = summary
        self.summary = summary
        healthReadAt = now()
      }
    } catch {
      guard !Task.isCancelled, healthRequest == request else { return }
      healthReadFailed = true
      report(
        error, operation: "readHealthMetrics",
        fallback: "Не удалось прочитать показатели. Проверьте доступ к «Здоровью» и повторите.")
    }
  }
  func importHeartRate(for workout: Workout) async throws -> HeartRateRecording {
    try Validation.workout(workout)
    guard workout.status == .completed else { throw TrainingError.invalidState }
    if let existing = try await recording(for: workout.id), existing.mode == .bluetooth {
      throw ServiceError.unavailable(
        "Пульс Bluetooth уже сохранён. Он не будет заменён данными из «Здоровья».")
    }
    if let existing = try await recording(for: workout.id), existing.origin == .liveHealthKit {
      throw ServiceError.unavailable(
        "Пульс этой тренировки уже записан в реальном времени. Он не будет заменён импортом из «Здоровья»."
      )
    }
    try await health.requestHeartRateAuthorization()
    try Task.checkCancellation()
    let imported = try await health.heartRate(for: workout)
    try Task.checkCancellation()
    guard !imported.readings.isEmpty else { return imported }
    try await recordings.save(imported)
    return imported
  }
  private func report(_ error: any Error, operation: String, fallback: String) {
    self.error = message(for: error, operation: operation, fallback: fallback)
  }
  func message(for error: any Error, operation: String, fallback: String) -> String {
    errorMessage(error, operation, fallback)
  }
}
