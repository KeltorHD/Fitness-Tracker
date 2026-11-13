import FitLifeCore
import Foundation

// Executable behavior checks of the real Foundation/Observation subset. No Apple SDK or radios.
private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class SensorStub: HeartRateBluetooth {
  var onChange: (@MainActor (HeartRateBluetoothSnapshot) -> Void)?
  var disconnectCount = 0
  func scan() {}
  func stopScan() {}
  func connect(_ id: UUID) {}
  func disconnect() { disconnectCount += 1 }
  func emit(_ reading: HeartRateReading, deviceName: String? = nil) {
    onChange?(
      HeartRateBluetoothSnapshot(connection: .connected, deviceName: deviceName, reading: reading))
  }
}

@MainActor private final class HealthStub: HealthMetricsReading {
  var dayAuthorizations = 0
  var heartAuthorizations = 0
  var workoutReads = 0
  var suspendSummary = false
  var dayValue: HealthDaySummary?
  var failDay = false
  var pending: CheckedContinuation<HealthDaySummary, any Error>?
  private var waiter: CheckedContinuation<Void, Never>?
  var suspendHeartRate = false
  var pendingHeartRate: CheckedContinuation<HeartRateRecording, Never>?
  private var heartWaiter: CheckedContinuation<Void, Never>?
  func requestReadAuthorization() async throws { dayAuthorizations += 1 }
  func requestHeartRateAuthorization() async throws { heartAuthorizations += 1 }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    if suspendSummary {
      return try await withCheckedThrowingContinuation {
        pending = $0
        waiter?.resume()
        waiter = nil
      }
    }
    if failDay { throw CheckFailure(message: "Private Health failure") }
    return dayValue ?? Self.summary(day)
  }
  static func summary(_ day: Date) -> HealthDaySummary {
    HealthDaySummary(
      day: day, steps: nil, activeEnergyKCal: nil, sleepSeconds: nil,
      latestHeartRate: nil, heartRateSource: nil)
  }
  func waitForSummary() async {
    if pending == nil { await withCheckedContinuation { waiter = $0 } }
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    workoutReads += 1
    if suspendHeartRate {
      return await withCheckedContinuation {
        pendingHeartRate = $0
        heartWaiter?.resume()
        heartWaiter = nil
      }
    }
    return try HeartRateRecording(
      workoutID: workout.id, mode: .appleHealth,
      readings: [HeartRateReading(date: workout.startedAt, beatsPerMinute: 80)])
  }
  func waitForHeartRate() async {
    if pendingHeartRate == nil { await withCheckedContinuation { heartWaiter = $0 } }
  }
}

private actor RecordingStub: HeartRateRecordingRepository {
  var records: [UUID: HeartRateRecording] = [:]
  var failing = false
  func setFailing(_ value: Bool) { failing = value }
  func recording(for workoutID: UUID) -> HeartRateRecording? { records[workoutID] }
  func save(_ recording: HeartRateRecording) throws {
    if failing { throw CheckFailure(message: "private diagnostic") }
    records[recording.workoutID] = recording
  }
  func remove(for workoutID: UUID) { records[workoutID] = nil }
  func compareAndSet(
    workoutID: UUID, expected: HeartRateRecording?, replacement: HeartRateRecording?
  ) throws -> Bool {
    guard recording(for: workoutID) == expected else { return false }
    if let replacement { try save(replacement) } else { remove(for: workoutID) }
    return true
  }

}

@main private struct PortableTrackerChecks {
  @MainActor static func main() async throws {
    try expect(AppIdentifiers.storeConfiguration == "Workouts", "Current workout store")
    try expect(AppIdentifiers.heartRateDirectory == "FitLife/HeartRate", "Current pulse directory")
    try expect(AppIdentifiers.watchArchiveFileName == "FitLife-watch.json", "Current Watch archive")
    try expect(AppIdentifiers.healthSyncPrefix == "FitLife.", "Current Health export identity")
    try expect(AppIdentifiers.weeklyWidgetKind == "FitLife.Weekly", "Current widget identity")
    for scheme in ["fitlife", "FITLIFE"] {
      guard let url = URL(string: scheme + "://workout?id=" + UUID().uuidString) else {
        throw CheckFailure(message: "URL fixture")
      }
      try expect(AppIdentifiers.acceptsURL(url), "FitLife URLs open the workout")
    }
    for scheme in ["fitnesstracker", "FITNESSTRACKER", "fitsession", "https"] {
      guard let url = URL(string: scheme + "://workout?id=" + UUID().uuidString) else {
        throw CheckFailure(message: "URL fixture")
      }
      try expect(!AppIdentifiers.acceptsURL(url), "Previous and unrelated URL schemes are rejected")
    }
    let tick = Date(timeIntervalSince1970: 1_700_000_000)
    let betweenTicks = HeartRateReading(date: tick.addingTimeInterval(0.6), beatsPerMinute: 90)
    try expect(!betweenTicks.isFresh(at: tick), "A scheduled tick may precede a new valid reading")
    try expect(
      betweenTicks.isFreshForDisplay(at: tick, now: tick.addingTimeInterval(0.7)),
      "A new reading remains visible between timer ticks")
    try expect(
      !betweenTicks.isFreshForDisplay(at: tick, now: tick.addingTimeInterval(17)),
      "Actual age still expires stale measurements")
    try expect(
      !betweenTicks.isFreshForDisplay(at: tick, now: tick.addingTimeInterval(0.2)),
      "Truly future measurements stay invalid")
    let suite = "FitLife.PortableTrackerTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 1_700_000_100)
    let health = HealthStub()
    let sensor = SensorStub()
    let repository = RecordingStub()
    let tracker = TrackerViewModel(
      health: health, sensor: sensor, recordings: repository,
      defaults: defaults, errorMessage: { _, _, fallback in fallback }, now: { now })

    try expect(
      health.dayAuthorizations == 0 && health.heartAuthorizations == 0,
      "No unsolicited Health permissions")
    try expect(
      tracker.deviceProfile == .xiaomiSmartBand10, "Existing installations keep Mi Band guidance")
    let disconnects = sensor.disconnectCount
    tracker.selectDeviceProfile(.huaweiWatchGT6Pro)
    try expect(
      tracker.mode == .appleHealth && sensor.disconnectCount == disconnects,
      "Selecting a model does not change transport or disconnect a device")
    let restored = TrackerViewModel(
      health: health, sensor: SensorStub(), recordings: repository,
      defaults: defaults, errorMessage: { _, _, fallback in fallback })
    try expect(
      restored.deviceProfile == .huaweiWatchGT6Pro,
      "Huawei profile persists across model recreation")
    try expect(
      health.dayAuthorizations == 0 && health.heartAuthorizations == 0,
      "Selecting Huawei does not request Health permissions")
    tracker.selectMode(.bluetooth)
    var workout = Workout(
      name: "Test", startedAt: now.addingTimeInterval(-100),
      exercises: [
        WorkoutExercise(
          exercise: Exercise(name: "Test", muscle: .fullBody),
          sets: [WorkoutSet(completedAt: now.addingTimeInterval(-20))])
      ])
    tracker.attach(workout)
    await tracker.flush()
    let first = HeartRateReading(date: now.addingTimeInterval(-10), beatsPerMinute: 80)
    let second = HeartRateReading(date: now.addingTimeInterval(-4), beatsPerMinute: 100)
    await repository.setFailing(true)
    sensor.emit(first)
    sensor.emit(second, deviceName: "HUAWEI WATCH GT 6 Pro-A12")
    try expect(
      tracker.bluetooth.deviceName == "HUAWEI WATCH GT 6 Pro-A12",
      "Display actual Bluetooth device identity")
    tracker.selectDeviceProfile(.other)
    try expect(
      tracker.recording?.readings == [first, second] && tracker.mode == .bluetooth,
      "Changing guidance must preserve the workout recording and selected mode")
    sensor.emit(HeartRateReading(date: now.addingTimeInterval(-50), beatsPerMinute: 200))
    await tracker.flush()
    try expect(
      tracker.recording?.readings == [first, second], "Fresh samples kept, delayed values ignored")
    try expect(
      tracker.hasPendingSaves && tracker.error != nil,
      "Storage failure remains visible and retryable")
    try expect(
      !(tracker.error?.contains("private diagnostic") ?? true), "Private details stay out of UI")
    await repository.setFailing(false)
    await tracker.retrySaving()
    let saved = await repository.recording(for: workout.id)
    try expect(
      saved?.readings == [first, second] && !tracker.hasPendingSaves,
      "Retry saves the newest complete recording")

    try WorkoutEngine.pause(&workout, at: now)
    tracker.attach(workout)
    sensor.emit(HeartRateReading(date: now, beatsPerMinute: 90))
    try expect(tracker.recording?.readings.count == 2, "Paused workout must not record")
    tracker.attach(nil)
    await tracker.flush()
    try expect(sensor.disconnectCount > 0, "Finishing detaches the sensor")
    let detail = WorkoutHeartRateViewModel(tracker: tracker)
    try WorkoutEngine.resume(&workout, at: now.addingTimeInterval(1))
    try WorkoutEngine.finish(&workout, at: now.addingTimeInterval(2))
    await detail.load(workout, importHealth: false)
    try expect(
      detail.recording?.average == 90 && detail.points.count == 2,
      "History loads real saved samples")
    do {
      _ = try await tracker.importHeartRate(for: workout)
      throw CheckFailure(message: "Bluetooth data overwritten")
    } catch is ServiceError {}
    try expect(
      health.workoutReads == 0 && health.heartAuthorizations == 0,
      "Bluetooth data is protected before requesting Health access")

    tracker.selectMode(.appleHealth)
    try expect(
      defaults.string(forKey: "trackerMode") == TrackerMode.appleHealth.rawValue,
      "Mode is persisted")
    health.suspendSummary = true
    let request = Task {
      await tracker.readHealth(day: now, calendar: Calendar(identifier: .gregorian))
    }
    await health.waitForSummary()
    tracker.selectMode(.bluetooth)
    health.pending?.resume(returning: HealthStub.summary(now))
    health.pending = nil
    await request.value
    try expect(
      tracker.summary == nil && !tracker.loadingHealth && tracker.healthReadAt == nil,
      "Late Health response cannot overwrite another mode")

    var other = workout
    other.id = UUID()
    _ = try await tracker.importHeartRate(for: other)
    try expect(
      health.heartAuthorizations == 1 && health.dayAuthorizations == 1,
      "Workout import requests heart rate only")
    tracker.removeRecording(for: workout.id)
    await tracker.flush()
    let removed = await repository.recording(for: workout.id)
    try expect(removed == nil, "Deleting a workout deletes its sensor sidecar")

    let deletionTracker = TrackerViewModel(
      health: health, sensor: SensorStub(), recordings: repository,
      defaults: defaults, errorMessage: { _, _, fallback in fallback })
    deletionTracker.attach(other)
    while deletionTracker.preparingRecording { await Task.yield() }
    try expect(deletionTracker.recording != nil, "Load cached pulse before a remote deletion")
    await repository.remove(for: other.id)
    try expect(
      deletionTracker.discardDeletedRecording(for: other.id), "Detach a committed deletion")
    deletionTracker.attach(nil)
    await deletionTracker.flush()
    let stillRemoved = await repository.recording(for: other.id)
    try expect(
      stillRemoved == nil, "Reloading after a remote deletion must not re-save the cached pulse")

    var importingWorkout = other
    importingWorkout.id = UUID()
    health.suspendHeartRate = true
    let pendingImport = Task { try await tracker.importHeartRate(for: importingWorkout) }
    await health.waitForHeartRate()
    try expect(
      tracker.hasPendingHeartRateImports,
      "Account switching observes an outstanding historical Health read")
    let concurrent = try HeartRateRecording(
      workoutID: importingWorkout.id, mode: .bluetooth, readings: [first])
    try await repository.save(concurrent)
    health.pendingHeartRate?.resume(
      returning: try HeartRateRecording(
        workoutID: importingWorkout.id, mode: .appleHealth, readings: [second]))
    health.pendingHeartRate = nil
    health.suspendHeartRate = false
    do {
      _ = try await pendingImport.value
      throw CheckFailure(message: "A stale Health read overwrote a newer sensor recording")
    } catch is ServiceError {}
    let preserved = await repository.recording(for: importingWorkout.id)
    try expect(
      preserved == concurrent && !tracker.hasPendingHeartRateImports,
      "History import uses atomic comparison and preserves the new source")
    tracker.trainingWritesSuspended = true
    do {
      _ = try await tracker.importHeartRate(for: other)
      throw CheckFailure(message: "Import started during an account switch")
    } catch is CancellationError {}
    tracker.trainingWritesSuspended = false

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = LocalHeartRateRepository(directory: directory)
    let local = try HeartRateRecording(workoutID: UUID(), mode: .bluetooth, readings: [first])
    try await files.save(local)
    let loaded = try await files.recording(for: local.workoutID)
    try expect(loaded == local, "Actual local file round trip")
    let path = directory.appendingPathComponent(local.workoutID.uuidString).appendingPathExtension(
      "json")
    let corrupt = Data("corrupt data".utf8)
    try corrupt.write(to: path)
    do {
      _ = try await files.recording(for: local.workoutID)
      throw CheckFailure(message: "Corrupt file accepted")
    } catch is DecodingError {}
    try expect(try Data(contentsOf: path) == corrupt, "Corrupt file must not be reset or deleted")
    try await files.remove(for: local.workoutID)
    let absent = try await files.recording(for: local.workoutID)
    try expect(absent == nil, "Explicit deletion removes local recording")
    health.suspendSummary = false
    tracker.selectMode(.appleHealth)
    await tracker.readHealth(day: now, calendar: .current)
    try expect(
      tracker.healthReadAt == now && tracker.summary?.isEmpty == true
        && tracker.healthReadChanged == nil,
      "A successful empty read must have a completion time and stay distinct from failure")
    await tracker.readHealth(day: now, calendar: .current)
    try expect(tracker.healthReadChanged == false, "An unchanged read must report no new data")
    health.dayValue = HealthDaySummary(
      day: now, steps: 0, activeEnergyKCal: nil, sleepSeconds: nil,
      latestHeartRate: nil, heartRateSource: nil)
    await tracker.readHealth(day: now, calendar: .current)
    try expect(
      tracker.healthReadChanged == true && tracker.summary?.isEmpty == false,
      "Actual zero steps is available data, rather than an empty read")
    health.failDay = true
    await tracker.readHealth(day: now, calendar: .current)
    try expect(
      tracker.healthReadAt == nil && tracker.error != nil && tracker.healthReadFailed
        && !tracker.loadingHealth,
      "A failed attempt must never claim a successful read")
    let liveSensor = SensorStub()
    let liveTracker = TrackerViewModel(
      health: health, sensor: liveSensor, recordings: RecordingStub(), defaults: defaults,
      errorMessage: { _, _, fallback in fallback }, now: { now })
    liveTracker.selectMode(.bluetooth)
    let liveWorkout = Workout(name: "Live", startedAt: now.addingTimeInterval(-100))
    liveTracker.attach(liveWorkout)
    let newerHealth = HeartRateReading(date: now, beatsPerMinute: 110)
    let sensorReading = HeartRateReading(date: now.addingTimeInterval(-1), beatsPerMinute: 105)
    var callbackReading: HeartRateReading?
    var callbacks = 0
    liveTracker.onHeartRateChange = {
      callbacks += 1
      callbackReading = liveTracker.liveActivityHeartRate(healthReading: nil)
    }
    liveSensor.emit(sensorReading)
    try expect(callbackReading == sensorReading, "A live callback sees the new sensor sample")
    try expect(
      liveTracker.liveActivityHeartRate(healthReading: newerHealth) == newerHealth,
      "The latest fresh reading wins across available sources")
    liveSensor.onChange?(HeartRateBluetoothSnapshot(connection: .disconnected))
    try expect(
      callbacks == 2 && callbackReading == nil,
      "Disconnect publishes missing data instead of retaining the old pulse")
    try expect(
      liveTracker.liveActivityHeartRate(
        healthReading:
          HeartRateReading(date: now.addingTimeInterval(-16), beatsPerMinute: 100)) == nil,
      "Stale Health data cannot be shown as a current activity pulse")
    var pausedWorkout = liveWorkout
    try WorkoutEngine.pause(&pausedWorkout, at: now)
    liveTracker.attach(pausedWorkout)
    try expect(
      liveTracker.liveActivityHeartRate(healthReading: newerHealth) == nil,
      "Paused workouts hide current heart rate")
    liveTracker.onHeartRateChange = nil
    liveTracker.attach(nil)
    print(
      "Portable tracker behavior: recording, pause, persistence failure/retry, mode races, permissions, history and file integrity passed (no Apple SDK)."
    )
  }
}
