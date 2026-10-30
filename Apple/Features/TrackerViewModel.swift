import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class TrackerViewModel {
  private(set) var mode: TrackerMode
  private(set) var deviceProfile: TrackerDeviceProfile
  private(set) var bluetooth = HeartRateBluetoothSnapshot()
  private(set) var summary: HealthDaySummary?
  private(set) var loadingHealth = false
  private(set) var hasRequestedHealth = false
  private(set) var recording: HeartRateRecording?
  private(set) var preparingRecording = false
  var error: String?
  var hasPendingSaves: Bool { !pendingSaves.isEmpty }
  var canRetryRecordingLoad: Bool { workout != nil && recording == nil && !preparingRecording }
  @ObservationIgnored private let health: any HealthMetricsReading
  @ObservationIgnored private let sensor: any HeartRateBluetooth
  @ObservationIgnored private let recordings: any HeartRateRecordingRepository
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let errorMessage: (any Error, String, String) -> String
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var workout: Workout?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var pendingSaves: [UUID: HeartRateRecording] = [:]
  @ObservationIgnored private var healthRequest: UUID?
  @ObservationIgnored private var lastQueuedAt: Date?
  @ObservationIgnored private var backgroundWorkCancelled = false

  init(
    health: any HealthMetricsReading, sensor: any HeartRateBluetooth,
    recordings: any HeartRateRecordingRepository, defaults: UserDefaults = .standard,
    errorMessage: @escaping (any Error, String, String) -> String,
    now: @escaping () -> Date = Date.init
  ) {
    self.health = health
    self.sensor = sensor
    self.recordings = recordings
    self.defaults = defaults
    self.errorMessage = errorMessage
    self.now = now
    mode = TrackerMode(rawValue: defaults.string(forKey: "trackerMode") ?? "") ?? .appleHealth
    deviceProfile =
      TrackerDeviceProfile(rawValue: defaults.string(forKey: "trackerDeviceProfile") ?? "")
      ?? .xiaomiSmartBand10
    sensor.onChange = { [weak self] snapshot in self?.receive(snapshot) }
  }
  func selectMode(_ mode: TrackerMode) {
    guard mode != self.mode else { return }
    queueSave()
    sensor.disconnect()
    healthRequest = nil
    loadingHealth = false
    self.mode = mode
    defaults.set(mode.rawValue, forKey: "trackerMode")
    error = nil
  }
  func selectDeviceProfile(_ profile: TrackerDeviceProfile) {
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
    sensor.disconnect()
  }
  func leaveScreen() {
    sensor.stopScan()
    if workout == nil { sensor.disconnect() }
  }

  func retryRecordingLoad() { attach(workout, reload: true) }
  func attach(_ workout: Workout?, reload: Bool = false) {
    if workout?.id == self.workout?.id && !reload {
      if workout?.status != self.workout?.status { queueSave() }
      self.workout = workout
      return
    }
    queueSave()
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
      let workout, !preparingRecording, var recording, recording.mode == .bluetooth
    else { return }
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
      if healthRequest == request { self.summary = summary }
    } catch {
      guard !Task.isCancelled, healthRequest == request else { return }
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
