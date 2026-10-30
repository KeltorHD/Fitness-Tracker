import FitSessionCore
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
  func emit(_ reading: HeartRateReading) {
    onChange?(HeartRateBluetoothSnapshot(connection: .connected, reading: reading))
  }
}

@MainActor private final class HealthStub: HealthMetricsReading {
  var dayAuthorizations = 0
  var heartAuthorizations = 0
  var workoutReads = 0
  var suspendSummary = false
  var pending: CheckedContinuation<HealthDaySummary, any Error>?
  private var waiter: CheckedContinuation<Void, Never>?
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
    return Self.summary(day)
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
    return try HeartRateRecording(
      workoutID: workout.id, mode: .appleHealth,
      readings: [HeartRateReading(date: workout.startedAt, beatsPerMinute: 80)])
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
}

@main private struct PortableTrackerChecks {
  @MainActor static func main() async throws {
    let suite = "FitSession.PortableTrackerTests.\(UUID().uuidString)"
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
    sensor.emit(second)
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
      tracker.summary == nil && !tracker.loadingHealth,
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
    print(
      "Portable tracker behavior: recording, pause, persistence failure/retry, mode races, permissions, history and file integrity passed (no Apple SDK)."
    )
  }
}
