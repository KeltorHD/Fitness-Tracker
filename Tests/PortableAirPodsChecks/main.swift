import FitnessTrackerCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class SensorStub: HeartRateBluetooth {
  var onChange: (@MainActor (HeartRateBluetoothSnapshot) -> Void)?
  func scan() {}
  func stopScan() {}
  func connect(_ id: UUID) {}
  func disconnect() {}
}

@MainActor private final class HealthStub: HealthMetricsReading {
  var permissions = 0
  func requestReadAuthorization() async throws { permissions += 1 }
  func requestHeartRateAuthorization() async throws { permissions += 1 }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    throw CheckFailure(message: "Unexpected daily query")
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    throw CheckFailure(message: "Unexpected historical import")
  }
}

private actor RecordingStub: HeartRateRecordingRepository {
  var records: [UUID: HeartRateRecording] = [:]
  var failLoad = false
  func setLoadFailure(_ value: Bool) { failLoad = value }
  func recording(for id: UUID) throws -> HeartRateRecording? {
    if failLoad { throw CheckFailure(message: "Private file error") }
    return records[id]
  }
  func save(_ recording: HeartRateRecording) { records[recording.workoutID] = recording }
  func remove(for id: UUID) { records[id] = nil }
}

@MainActor private final class LiveStub: LiveHeartRateServing {
  var onChange: (@MainActor (LiveHeartRateSnapshot) -> Void)?
  var starts: [UUID] = []
  var stops = 0
  var pauses = 0
  var resumes = 0
  var active: UUID?
  var denied = false
  var suspendStart = false
  private var pending: CheckedContinuation<Void, Never>?
  private var waiter: CheckedContinuation<Void, Never>?
  func start(sessionID: UUID) async throws {
    starts.append(sessionID)
    active = sessionID
    emit(.starting, id: sessionID)
    if suspendStart {
      await withCheckedContinuation {
        pending = $0
        waiter?.resume()
        waiter = nil
      }
    }
    try Task.checkCancellation()
    guard active == sessionID else { throw CancellationError() }
    if denied {
      active = nil
      emit(.failed, id: sessionID)
      throw ServiceError.unavailable("Denied")
    }
    emit(.running, id: sessionID)
  }
  func waitForStart() async {
    if pending == nil { await withCheckedContinuation { waiter = $0 } }
  }
  func releaseStart() {
    pending?.resume()
    pending = nil
  }
  func pause() {
    guard let active else { return }
    pauses += 1
    emit(.paused, id: active)
  }
  func resume() {
    guard let active else { return }
    resumes += 1
    emit(.running, id: active)
  }
  func stop() {
    guard let id = active else { return }
    active = nil
    stops += 1
    emit(.stopped, id: id)
  }
  func emit(_ state: LiveHeartRateState, id: UUID, reading: HeartRateReading? = nil) {
    onChange?(LiveHeartRateSnapshot(sessionID: id, state: state, reading: reading))
  }
}

@main private struct PortableAirPodsChecks {
  @MainActor static func main() async throws {
    let suite = "FitnessTracker.AirPodsChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "Defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    var now = Date(timeIntervalSince1970: 1_700_000_100)
    let health = HealthStub()
    let source = LiveStub()
    let files = RecordingStub()
    let model = TrackerViewModel(
      health: health, sensor: SensorStub(), liveSource: source, recordings: files,
      defaults: defaults, errorMessage: { _, _, fallback in fallback }, now: { now })
    model.selectDeviceProfile(.airPodsPro3)
    try expect(
      source.starts.isEmpty && health.permissions == 0,
      "Profile selection must not request permissions")
    await model.startLiveHeartRate()
    try expect(
      source.starts.isEmpty && !model.canStartLive, "An active journal workout is required")
    var workout = Workout(
      name: "Test", startedAt: now.addingTimeInterval(-100),
      exercises: [
        WorkoutExercise(
          exercise: Exercise(name: "Test", muscle: .fullBody),
          sets: [WorkoutSet(completedAt: now.addingTimeInterval(-20))])
      ])
    model.attach(workout)
    await model.flush()
    try expect(model.canStartLive, "An attached active workout can explicitly enable the sensor")
    await model.startLiveHeartRate()
    let firstID = try require(source.active)
    try expect(
      model.live.state == .running && source.starts.count == 1,
      "Explicit start owns one live session")
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-10), beatsPerMinute: 80))
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-9), beatsPerMinute: 81))
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-4), beatsPerMinute: 100))
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-30), beatsPerMinute: 200))
    try expect(
      model.recording?.readings.count == 2,
      "Samples are fresh, ordered and limited to one per five seconds")
    model.leaveScreen()
    try expect(
      source.active == firstID, "Navigating away preserves an already running workout sensor")
    try WorkoutEngine.pause(&workout, at: now.addingTimeInterval(-2))
    model.attach(workout)
    try expect(
      source.pauses == 1 && model.live.state == .paused, "Journal pause pauses the live service")
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-1), beatsPerMinute: 90))
    try expect(
      model.recording?.readings.count == 2 && model.live.state == .paused,
      "No recording or live display while paused, even for a late callback")
    try WorkoutEngine.resume(&workout, at: now)
    model.attach(workout)
    try expect(source.resumes == 1, "Journal resume resumes the live service")
    source.emit(
      .running, id: firstID,
      reading: HeartRateReading(date: now.addingTimeInterval(-1), beatsPerMinute: 90))
    now = now.addingTimeInterval(6)
    source.emit(.running, id: firstID, reading: HeartRateReading(date: now, beatsPerMinute: 110))
    try expect(
      model.recording?.readings.count == 3, "Delayed pause samples remain excluded after resume")
    model.selectMode(.bluetooth)
    try expect(
      source.active == nil && !model.hasLiveSession, "Changing transport stops the owned session")
    source.emit(.failed, id: firstID)
    try expect(
      model.error == nil && model.live.state == .stopped,
      "Late callbacks cannot revive a stopped session")
    model.selectMode(.appleHealth)
    await model.startLiveHeartRate()
    let secondID = try require(source.active)
    source.emit(.stopped, id: firstID)
    try expect(
      model.hasLiveSession && secondID != firstID, "Old generations cannot stop a new session")
    model.selectDeviceProfile(.other)
    try expect(source.active == nil, "Selecting another device stops live HealthKit collection")
    model.selectDeviceProfile(.airPodsPro3)
    await model.startLiveHeartRate()
    try WorkoutEngine.finish(&workout, at: now.addingTimeInterval(1))
    model.attach(workout)
    await model.flush()
    try expect(source.active == nil, "Completing a workout ends the live session")
    let saved = try await files.recording(for: workout.id)
    try expect(
      saved?.origin == .liveHealthKit && saved?.readings.count == 3,
      "Live data and provenance survive saving")
    do {
      _ = try await model.importHeartRate(for: workout)
      throw CheckFailure(message: "Live recording replaced by Health import")
    } catch is ServiceError {}
    try expect(
      health.permissions == 0, "Protect recorded data before requesting historical Health access")

    var other = Workout(name: "Other", startedAt: now.addingTimeInterval(-10))
    source.suspendStart = true
    model.attach(other)
    await model.flush()
    let delayed = Task { await model.startLiveHeartRate() }
    await source.waitForStart()
    model.selectMode(.bluetooth)
    source.releaseStart()
    await delayed.value
    try expect(
      !model.hasLiveSession && !model.startingLive && source.active == nil && model.error == nil,
      "Mode change during authorization invalidates the pending start")
    model.selectMode(.appleHealth)
    let cancelled = Task { await model.startLiveHeartRate() }
    await source.waitForStart()
    cancelled.cancel()
    source.releaseStart()
    await cancelled.value
    try expect(
      !model.hasLiveSession && source.active == nil && model.error == nil,
      "Cancelled UI task tears down the pending start")
    let switching = Task { await model.startLiveHeartRate() }
    await source.waitForStart()
    other.id = UUID()
    model.attach(other)
    source.releaseStart()
    await switching.value
    try expect(
      !model.hasLiveSession && source.active == nil, "Workout change invalidates a pending start")
    source.suspendStart = false
    await model.flush()
    source.denied = true
    await model.startLiveHeartRate()
    try expect(
      model.error != nil && !model.hasLiveSession && !model.startingLive,
      "Permission denial is visible and retryable")
    source.denied = false
    await model.startLiveHeartRate()
    let failingID = try require(source.active)
    source.emit(.failed, id: failingID)
    try expect(
      source.active == nil && model.error != nil,
      "Service failure stops collection and exposes retry")
    model.attach(nil)

    await files.setLoadFailure(true)
    other.id = UUID()
    model.attach(other)
    await model.flush()
    let count = source.starts.count
    await model.startLiveHeartRate()
    try expect(
      source.starts.count == count && model.error != nil,
      "Storage load failure cannot overwrite an unknown recording")
    await files.setLoadFailure(false)
    model.retryRecordingLoad()
    await model.flush()
    await files.save(
      try HeartRateRecording(
        workoutID: other.id, mode: .bluetooth,
        readings: [HeartRateReading(date: now, beatsPerMinute: 80)]))
    model.retryRecordingLoad()
    await model.flush()
    await model.startLiveHeartRate()
    try expect(
      source.starts.count == count && model.recording?.mode == .bluetooth
        && model.recording?.readings.count == 1,
      "Existing Bluetooth recording is never replaced by live HealthKit data")
    try expect(
      health.permissions == 0,
      "Live mode does not request unrelated daily metrics or historical imports")
    print(
      "Portable AirPods presentation: explicit authorization, freshness, pause/resume, persistence, source protection, stale callbacks, mode/workout races, cancellation, denial and storage failure passed (fake sensor; no Apple SDK)."
    )
  }
  private static func require<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(message: "Missing expected value") }
    return value
  }
}
