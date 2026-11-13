import FitLifeCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class Provider: HealthDataProviding {
  let id: HealthProviderID
  let supportedMetrics: Set<HealthMetric> = [.steps, .bodyWeight]
  var failure: HealthDataError?
  var reads = 0
  var authorizations = 0
  var suspend = false
  var pending: CheckedContinuation<HealthDataSnapshot, any Error>?
  var waiter: CheckedContinuation<Void, Never>?
  init(_ id: HealthProviderID) { self.id = id }
  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    authorizations += 1
    if let failure { throw failure }
    return metrics
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    reads += 1
    if let failure { throw failure }
    if suspend {
      return try await withCheckedThrowingContinuation {
        pending = $0
        waiter?.resume()
        waiter = nil
      }
    }
    return try value(start: start, end: end, metrics: metrics)
  }
  func value(start: Date, end: Date, metrics: Set<HealthMetric>) throws -> HealthDataSnapshot {
    try HealthDataSnapshot(
      provider: id, start: start, end: end, fetchedAt: end, metrics: metrics,
      quantities: [
        HealthQuantity(
          id: UUID(), metric: .steps, start: start, end: start, value: 0, sourceID: id.rawValue,
          sourceName: id.rawValue)
      ], sleep: [])
  }
  func waitForRead() async { if pending == nil { await withCheckedContinuation { waiter = $0 } } }
}

@MainActor
private final class AppleReader: HealthSleepReading, HealthChartsReading, HealthMetricsReading {
  func authorize() async throws {}
  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] { [] }
  func requestChartAuthorization() async throws {}
  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    throw HealthDataError.unavailable
  }
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func stopChanges() {}
  func requestReadAuthorization() async throws {}
  func requestHeartRateAuthorization() async throws {}
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    throw HealthDataError.unavailable
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    throw HealthDataError.unavailable
  }
}

@MainActor private final class Namespace { var id = "account-a" }

@main private struct HealthProviderChecks {
  @MainActor static func main() async throws {
    let suite = "FitLife.HealthProviderChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "Defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_700_006_400)
    let end = start.addingTimeInterval(3600)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FitLife-Health-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = HealthDataCache(directory: root)
    let apple = Provider(.appleHealth)
    let cloud = Provider(.miFitness)
    let reader = AppleReader()
    let account = Namespace()
    let sources = HealthDataSources(
      providers: [apple, cloud], appleSleep: reader, appleMetrics: reader, appleCharts: reader,
      cache: disk, defaults: defaults, account: { account.id }, now: { end })
    try expect(
      sources.selected == .appleHealth && apple.authorizations == 0, "No access before opt-in")
    sources.select(.miFitness)
    try await sources.authorize(metrics: [.steps])
    let fresh = try await sources.read(
      start: start, end: end, metrics: [.steps], calendar: calendar)
    try expect(!fresh.cached && fresh.snapshot.quantities.first?.value == 0, "Zero is actual data")
    cloud.failure = .unavailable
    try await sources.authorize(metrics: [.steps])
    let saved = try await sources.read(
      start: start, end: end.addingTimeInterval(60), metrics: [.steps], calendar: calendar)
    try expect(
      saved.cached && saved.snapshot.fetchedAt == end, "Offline preserves original fetch time")
    cloud.failure = .permissionRequired
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
      throw CheckFailure(message: "Revoked permissions cannot fall back to cache")
    } catch HealthDataError.permissionRequired {}
    cloud.failure = .unavailable
    account.id = "account-b"
    sources.refreshAccount()
    try expect(
      sources.selected == .appleHealth && sources.fetchedAt == nil,
      "Selection and metadata isolated by account")
    sources.select(.miFitness)
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
      throw CheckFailure(message: "Other account cannot read cached measurements")
    } catch HealthDataError.unavailable {}
    account.id = "account-a"
    sources.refreshAccount()
    try expect(sources.selected == .miFitness, "Per-account preference restored")
    var otherZone = calendar
    otherZone.timeZone = TimeZone(identifier: "Europe/Moscow")!
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: otherZone)
      throw CheckFailure(message: "Daily totals cannot reuse another timezone")
    } catch HealthDataError.unavailable {}
    let key = HealthDataCacheKey(
      account: "account-a", provider: .miFitness, metrics: [.steps],
      timeZoneID: calendar.timeZone.identifier)
    let path = root.appendingPathComponent("account-a").appendingPathComponent(key.component)
      .appendingPathExtension("json")
    try Data("corrupt".utf8).write(to: path)
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
      throw CheckFailure(message: "Corruption cannot become successful empty data")
    } catch is DecodingError {}
    try expect(FileManager.default.fileExists(atPath: path.path), "Corrupted file preserved")
    cloud.failure = nil
    cloud.suspend = true
    let reading = Task {
      try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
    }
    await cloud.waitForRead()
    sources.select(.appleHealth)
    cloud.pending?.resume(returning: try cloud.value(start: start, end: end, metrics: [.steps]))
    cloud.pending = nil
    do {
      _ = try await reading.value
      throw CheckFailure(message: "Stale provider result accepted")
    } catch is CancellationError {}
    try expect(sources.fetchedAt == nil, "Stale source cannot publish metadata")
    cloud.suspend = false
    sources.select(.miFitness)
    let model = HealthDataViewModel(sources: sources, now: { end })
    await model.load(calendar: calendar)
    try expect(model.result == nil, "Overview requires opt-in")
    await model.load(calendar: calendar, explicit: true)
    try expect(model.enabled && model.result != nil, "Explicit read enables overview")
    model.stopDisplaying()
    await model.load(calendar: calendar)
    try expect(!model.enabled && model.result == nil, "Opt-out stops automatic loading")
    try await disk.remove(account: "account-a", provider: .miFitness)
    try expect(try await disk.load(key) == nil, "Disconnect removes only selected provider cache")
    print(
      "Health providers: account/timezone isolation, consent, offline, corruption, cancellation and opt-out passed (no Apple SDK or network)."
    )
  }
}
