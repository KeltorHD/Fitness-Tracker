import FitLifeCore
import Foundation

private struct Failure: Error { let message: String }
private func expect(_ value: Bool, _ message: String) throws {
  if !value { throw Failure(message: message) }
}
@MainActor private final class Sensor: LiveHeartRateServing {
  var onChange: (@MainActor (LiveHeartRateSnapshot) -> Void)?
  var active: UUID?
  var starts = 0
  var waiter: CheckedContinuation<Void, Never>?
  func start(sessionID: UUID) async throws {
    active = sessionID
    starts += 1
    emit(.running)
    waiter?.resume()
    waiter = nil
  }
  func waitForStart() async {
    if active == nil { await withCheckedContinuation { waiter = $0 } }
  }
  func pause() { emit(.paused) }
  func resume() { emit(.running) }
  func stop() {
    emit(.stopped)
    active = nil
  }
  func emit(_ state: LiveHeartRateState, reading: HeartRateReading? = nil) {
    if let active {
      onChange?(LiveHeartRateSnapshot(sessionID: active, state: state, reading: reading))
    }
  }
}
@MainActor private final class Health: HealthMetricsReading {
  func requestReadAuthorization() async throws {
    throw Failure(message: "Unexpected Health access")
  }
  func requestHeartRateAuthorization() async throws {
    throw Failure(message: "Unexpected Health access")
  }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    throw Failure(message: "Unexpected Health access")
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    throw Failure(message: "Unexpected historical import")
  }
}
@MainActor private final class Bluetooth: HeartRateBluetooth {
  var onChange: (@MainActor (HeartRateBluetoothSnapshot) -> Void)?
  func scan() {}
  func stopScan() {}
  func connect(_ id: UUID) {}
  func disconnect() {}
}
private actor Records: HeartRateRecordingRepository {
  var data: [UUID: HeartRateRecording] = [:]
  func recording(for workoutID: UUID) -> HeartRateRecording? { data[workoutID] }
  func save(_ recording: HeartRateRecording) { data[recording.workoutID] = recording }
  func remove(for workoutID: UUID) { data[workoutID] = nil }
  func compareAndSet(
    workoutID: UUID, expected: HeartRateRecording?, replacement: HeartRateRecording?
  ) throws -> Bool {
    guard recording(for: workoutID) == expected else { return false }
    if let replacement { save(replacement) } else { remove(for: workoutID) }
    return true
  }

}

@main private struct Checks {
  @MainActor static func main() async throws {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    let sensor = Sensor()
    let watch = WatchHeartRateController(source: sensor, now: { now })
    var commands: [WatchHeartRateCommand] = []
    var events: [WatchHeartRateEvent] = []
    var snapshots: [LiveHeartRateSnapshot] = []
    let phone = AppleWatchHeartRateService(
      now: { now },
      send: { command in
        commands.append(command)
        watch.receive(command)
      })
    watch.send = { event in
      events.append(event)
      phone.receive(event)
    }
    phone.onChange = { snapshots.append($0) }
    let first = UUID()
    try await phone.start(sessionID: first)
    await sensor.waitForStart()
    try expect(
      snapshots.last?.state == .running && sensor.starts == 1,
      "Watch acknowledgement starts live reception")
    let sample = HeartRateReading(date: now, beatsPerMinute: 90)
    sensor.emit(.running, reading: sample)
    try expect(snapshots.last?.reading == sample, "Immediate wrist reading reaches iPhone")
    let validEvent = events.last!
    phone.receive(validEvent)
    try expect(
      snapshots.filter { $0.reading == sample }.count == 1,
      "Duplicate event cannot duplicate a reading")
    phone.receive(
      WatchHeartRateEvent(
        sessionID: first, sequence: 999, state: .running, date: now.addingTimeInterval(-40),
        reading: sample))
    try expect(
      snapshots.last?.reading == sample, "Delayed packet rejected before changing ordering state")
    phone.pause()
    sensor.emit(.running, reading: sample)
    try expect(snapshots.last?.state == .paused, "Late running events cannot undo journal pause")
    phone.resume()
    now = now.addingTimeInterval(6)
    let next = HeartRateReading(date: now, beatsPerMinute: 95)
    sensor.emit(.running, reading: next)
    try expect(snapshots.last?.reading == next, "Resume receives new readings")
    let oldStopSequence = commands.last!.sequence + 1
    phone.stop()
    try expect(
      sensor.active == nil && snapshots.last?.state == .stopped, "Stop ends wrist collection")
    let second = UUID()
    try await phone.start(sessionID: second)
    await sensor.waitForStart()
    phone.receive(validEvent)
    watch.receive(
      WatchHeartRateCommand(sessionID: first, sequence: oldStopSequence, action: .stop, date: now))
    try expect(
      sensor.active == second && snapshots.last?.sessionID == second,
      "Old session messages cannot affect the new request")
    phone.disconnected()
    try expect(
      snapshots.last?.state == .failed && sensor.active == nil,
      "Disconnect reports failure and sends a stop")
    watch.receive(
      WatchHeartRateCommand(
        sessionID: UUID(), sequence: 1, action: .start, date: now.addingTimeInterval(-120)))
    try expect(sensor.active == nil, "A stored or delayed start cannot reactivate the sensor")
    let encoded = try JSONEncoder().encode(validEvent)
    try expect(
      try JSONDecoder().decode(WatchHeartRateEvent.self, from: encoded) == validEvent,
      "Event wire roundtrip")

    let suite = "FitLife.WatchHeartRateChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(message: "Defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }
    let airPods = Sensor()
    let wrist = Sensor()
    let records = Records()
    let tracker = TrackerViewModel(
      health: Health(), sensor: Bluetooth(), liveSource: airPods, watchLiveSource: wrist,
      recordings: records, defaults: defaults, errorMessage: { _, _, fallback in fallback },
      now: { now })
    tracker.selectDeviceProfile(.appleWatch)
    try expect(
      !tracker.canStartLive && wrist.starts == 0,
      "Selecting Watch does not start sensors or request permissions")
    let workout = Workout(name: "Wrist", startedAt: now.addingTimeInterval(-10))
    tracker.attach(workout)
    await tracker.flush()
    try expect(tracker.canStartLive, "Active workout supports Watch source")
    await tracker.startLiveHeartRate()
    try expect(
      wrist.starts == 1 && airPods.starts == 0,
      "Watch selection never starts the AirPods/iPhone sensor")
    wrist.emit(.running, reading: HeartRateReading(date: now, beatsPerMinute: 100))
    await tracker.flush()
    try expect(
      await records.recording(for: workout.id)?.origin == .liveHealthKit,
      "Live Watch readings persist separately from workout exports")
    tracker.selectDeviceProfile(.airPodsPro3)
    try expect(
      wrist.active == nil && !tracker.hasLiveSession, "Switching profiles stops the previous source"
    )
    await tracker.startLiveHeartRate()
    try expect(airPods.starts == 1 && wrist.active == nil, "AirPods remains an independent source")
    tracker.attach(nil)
    await tracker.flush()
    print(
      "Portable Watch heart rate: live delivery, ordering, stale events, pause/resume, disconnect, source isolation and persistence passed (fake sensor; no Apple SDK)."
    )
  }
}
