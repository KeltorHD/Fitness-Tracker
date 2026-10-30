import FitnessTrackerCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class Reader: HealthChartsReading {
  var authorizations = 0
  var reads = 0
  var value: HealthChartSnapshot
  var fail = false
  var suspend = false
  var pending: CheckedContinuation<HealthChartSnapshot, any Error>?
  var changesContinuation: AsyncThrowingStream<Void, any Error>.Continuation?
  var stops = 0
  private var readWaiter: (Int, CheckedContinuation<Void, Never>)?
  private var observationWaiter: CheckedContinuation<Void, Never>?
  init(_ value: HealthChartSnapshot) { self.value = value }
  func requestChartAuthorization() async throws { authorizations += 1 }
  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    reads += 1
    if suspend {
      return try await withCheckedThrowingContinuation {
        pending = $0
        notifyRead()
      }
    }
    if fail { throw CheckFailure(message: "Private service details") }
    notifyRead()
    return value
  }
  func changes(since date: Date) -> AsyncThrowingStream<Void, any Error> {
    AsyncThrowingStream {
      changesContinuation = $0
      observationWaiter?.resume()
      observationWaiter = nil
    }
  }
  func waitForObservation() async {
    if changesContinuation == nil {
      await withCheckedContinuation { observationWaiter = $0 }
    }
  }
  func stopChanges() {
    stops += 1
    changesContinuation?.finish()
    changesContinuation = nil
  }
  func waitForRead(_ count: Int) async {
    if reads < count { await withCheckedContinuation { readWaiter = (count, $0) } }
  }
  private func notifyRead() {
    if let (count, continuation) = readWaiter, reads >= count {
      readWaiter = nil
      continuation.resume()
    }
  }
}

@main private struct PortableHealthChartsChecks {
  @MainActor static func main() async throws {
    let suite = "FitnessTracker.HealthChartsChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "Defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let reading = HeartRateReading(date: day, beatsPerMinute: 90)
    let empty = HealthChartSnapshot(
      day: day, steps: [HealthStepDay(date: day, steps: nil)], heartRate: [],
      latestHeartRate: nil, heartRateSource: nil)
    let populated = HealthChartSnapshot(
      day: day, steps: [HealthStepDay(date: day, steps: 120)], heartRate: [reading],
      latestHeartRate: reading, heartRateSource: "Test source",
      currentDayHeartRate: [
        HeartRateReading(date: day.addingTimeInterval(-20), beatsPerMinute: 70), reading,
        HeartRateReading(date: day.addingTimeInterval(10), beatsPerMinute: 100),
      ])
    let reader = Reader(empty)
    let model = HealthChartsViewModel(
      reader: reader, defaults: defaults, now: { day }, errorMessage: { _ in "Safe failure" })
    try expect(!model.enabled && reader.authorizations == 0, "No Health access before opt-in")
    await model.observe(calendar: .current)
    try expect(reader.authorizations == 0, "Disabled models must not ask for permission")
    model.enabled = true
    let task = Task { await model.observe(calendar: .current) }
    await reader.waitForObservation()
    try expect(model.observing && model.snapshot == empty, "Empty data must stay empty")
    reader.value = populated
    reader.changesContinuation?.yield(())
    await reader.waitForRead(2)
    try expect(model.snapshot == populated && model.points.count == 1, "Events refresh both charts")
    var workout = Workout(name: "Test", startedAt: day.addingTimeInterval(-5), exercises: [])
    model.attach(workout)
    try expect(
      model.workoutPoints.map(\.reading) == [reading],
      "Live chart must exclude other sessions and future measurements")
    try WorkoutEngine.pause(&workout, at: day.addingTimeInterval(-1))
    model.attach(workout)
    try expect(model.workoutPoints.isEmpty, "Paused workouts must not show later measurements")
    model.attach(nil)
    try expect(model.workoutPoints.isEmpty, "Detaching clears the live chart")
    task.cancel()
    await task.value
    try expect(!model.observing && !model.loading, "Cancellation must stop live status")
    try expect(reader.changesContinuation == nil, "Cancellation must explicitly stop the source")
    let failingObservation = Task { await model.observe(calendar: .current) }
    await reader.waitForObservation()
    reader.changesContinuation?.finish(throwing: CheckFailure(message: "Private stream failure"))
    await failingObservation.value
    try expect(
      model.error == "Safe failure" && reader.changesContinuation == nil && !model.observing,
      "Stream errors must finish the source and expose a retryable error")
    reader.fail = true
    await model.observe(calendar: .current)
    try expect(
      model.error == "Safe failure" && !model.loading, "Failure must be safe and retryable")
    reader.fail = false
    reader.suspend = true
    let old = Task { await model.observe(calendar: .current) }
    await reader.waitForRead(5)
    try expect(reader.pending != nil, "The old request must reach the read")
    model.enabled = false
    model.clear()
    reader.pending?.resume(returning: populated)
    reader.pending = nil
    await old.value
    try expect(
      model.snapshot == nil && model.points.isEmpty && model.workoutPoints.isEmpty,
      "Late callbacks must not undo opt-out")
    let restored = HealthChartsViewModel(
      reader: reader, defaults: defaults, now: { day }, errorMessage: { _ in "Safe failure" })
    try expect(!restored.enabled, "Only the opt-in setting is persisted")
    print(
      "Portable health charts: opt-in, empty data, event updates, cancellation, failure and stale request isolation passed (no Apple SDK)."
    )
  }
}
