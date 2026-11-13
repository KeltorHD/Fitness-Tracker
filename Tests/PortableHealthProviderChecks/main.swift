import FitLifeCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class Provider: HealthDataProviding {
  let id: HealthProviderID
  let supportedMetrics: Set<HealthMetric>
  var requests: [Set<HealthMetric>] = []
  var authorizationRequests: [Set<HealthMetric>] = []
  var values: [HealthMetric: Double] = [
    .steps: 0, .bodyWeight: 72.5, .heartRate: 70, .activeEnergy: 300, .totalEnergy: 1800,
  ]
  var emptyMetrics: Set<HealthMetric> = []
  var failure: HealthDataError?
  var reads = 0
  var authorizations = 0
  var suspend = false
  var pending: CheckedContinuation<HealthDataSnapshot, any Error>?
  var waiter: CheckedContinuation<Void, Never>?
  init(_ id: HealthProviderID, metrics: Set<HealthMetric> = [.steps, .bodyWeight]) {
    self.id = id
    supportedMetrics = metrics
  }
  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    authorizations += 1
    authorizationRequests.append(metrics)
    if let failure { throw failure }
    return metrics
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    reads += 1
    requests.append(metrics)
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
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: end.addingTimeInterval(-0.001))
    let date = max(start, end.addingTimeInterval(-60))
    let quantities = HealthMetric.allCases.compactMap { metric -> HealthQuantity? in
      guard metrics.contains(metric), !emptyMetrics.contains(metric), let value = values[metric]
      else { return nil }
      let additive = [.steps, .activeEnergy, .totalEnergy, .distance].contains(metric)
      let sampleDate = additive ? max(start, day) : date
      return HealthQuantity(
        id: UUID(), metric: metric, start: sampleDate, end: sampleDate,
        value: value, sourceID: id.rawValue, sourceName: id.rawValue)
    }
    let sleepStart = max(start, end.addingTimeInterval(-3600))
    let sleep =
      metrics.contains(.sleep) && !emptyMetrics.contains(.sleep) && end > sleepStart
      ? [
        HealthSleepRecord(
          id: UUID(), start: sleepStart, end: end,
          asleepSeconds: end.timeIntervalSince(sleepStart), sourceID: id.rawValue,
          sourceName: id.rawValue, segments: [])
      ] : []
    return try HealthDataSnapshot(
      provider: id, start: start, end: end, fetchedAt: end, metrics: metrics,
      quantities: quantities, sleep: sleep)
  }
  func waitForRead() async { if pending == nil { await withCheckedContinuation { waiter = $0 } } }
}

@MainActor
private final class AppleReader: HealthSleepReading, HealthChartsReading, HealthMetricsReading {
  var observedMetrics: Set<HealthMetric> = []
  var importedHeartRates = 0
  func authorize() async throws {}
  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] { [] }
  func requestChartAuthorization() async throws {}
  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    throw HealthDataError.unavailable
  }
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func changes(since: Date, metrics: Set<HealthMetric>) -> AsyncThrowingStream<Void, any Error> {
    observedMetrics = metrics
    return AsyncThrowingStream { $0.finish() }
  }
  func stopChanges() {}
  func requestReadAuthorization() async throws {}
  func requestHeartRateAuthorization() async throws {}
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    throw HealthDataError.unavailable
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    importedHeartRates += 1
    return try HeartRateRecording(
      workoutID: workout.id, mode: .appleHealth,
      readings: [HeartRateReading(date: workout.startedAt, beatsPerMinute: 80)])
  }
}

@MainActor private final class Namespace { var id = "account-a" }

@main private struct HealthProviderChecks {
  @MainActor static func mixedSources(defaults: UserDefaults, calendar: Calendar, now: Date)
    async throws
  {
    let account = Namespace()
    account.id = "mixed-account"
    let apple = Provider(
      .appleHealth, metrics: [.sleep, .steps, .bodyWeight, .heartRate, .activeEnergy])
    let cloud = Provider(
      .miFitness, metrics: [.sleep, .steps, .bodyWeight, .heartRate, .totalEnergy])
    apple.values[.steps] = 999
    cloud.values[.steps] = 120
    cloud.values[.bodyWeight] = 99
    let native = AppleReader()
    let cache = MemoryHealthDataCache()
    func sources() -> HealthDataSources {
      HealthDataSources(
        providers: [apple, cloud], appleSleep: native, appleMetrics: native,
        appleCharts: native, cache: cache, defaults: defaults, account: { account.id }, now: { now }
      )
    }
    let source = sources()
    source.select(.miFitness, for: .sleep)
    source.select(.miFitness, for: .steps)
    try expect(
      source.provider(for: .heartRate) == .appleHealth, "Choosing sleep/steps cannot change pulse")
    try expect(source.uses(.appleHealth) && source.uses(.miFitness), "Both sources are active")
    try expect(sources().provider(for: .steps) == .miFitness, "Metric preference survives restart")
    account.id = "mixed-other"
    source.refreshAccount()
    try expect(
      source.provider(for: .steps) == .appleHealth,
      "Another account cannot inherit metric overrides")
    account.id = "mixed-account"
    source.refreshAccount()
    try expect(
      source.provider(for: .steps) == .miFitness, "Switching back restores metric preferences")
    let beforeUnsupported = source.selection
    source.select(.miFitness, for: .activeEnergy)
    try expect(
      source.selection == beforeUnsupported,
      "Unsupported category cannot be routed to another metric's energy source")
    defaults.set("miFitness", forKey: "healthProvider.legacy-preference")
    account.id = "legacy-preference"
    source.refreshAccount()
    try expect(
      source.provider(for: .steps) == .miFitness && source.provider(for: .heartRate) == .miFitness,
      "Previous global preference initializes common categories")
    account.id = "mixed-account"
    source.refreshAccount()
    let start = calendar.startOfDay(for: now)
    let requested: Set<HealthMetric> = [
      .steps, .sleep, .bodyWeight, .heartRate, .activeEnergy, .totalEnergy,
    ]
    let result = try await source.read(
      start: start, end: now, metrics: requested, calendar: calendar, authorize: true)
    try expect(
      apple.authorizationRequests.last == [.bodyWeight, .heartRate, .activeEnergy],
      "Apple permissions contain only its selected metrics")
    try expect(
      cloud.authorizationRequests.last == [.steps, .sleep, .totalEnergy],
      "Xiaomi permissions contain only its selected metrics")
    try expect(
      result.snapshots.count == 2 && result.failures.isEmpty,
      "Independent snapshots preserve both providers")
    try expect(
      result.snapshot(for: .bodyWeight)?.latest(.bodyWeight)?.value == 72.5,
      "Weight uses its primary source")
    let summary = try await source.daySummary(for: now, calendar: calendar)
    try expect(
      summary.steps == 120, "Steps are not added to the same activity imported through Apple Health"
    )
    try expect(
      summary.activeEnergyKCal == 300, "Total Xiaomi energy cannot replace Apple active energy")
    try expect(
      summary.sleepSeconds == 3600 && summary.latestHeartRate?.beatsPerMinute == 70,
      "Daily summary combines categories, not overlapping sources")
    let chart = try await source.chartSnapshot(day: now, calendar: calendar)
    try expect(
      chart.steps.last?.steps == 120 && !chart.heartRate.isEmpty,
      "Charts route steps and heart rate independently")
    let nights = try await source.nights(endingOn: now, calendar: calendar)
    try expect(nights.last?.asleep == 3600, "Sleep diary follows its primary provider")
    _ = source.changes(since: start)
    try expect(
      native.observedMetrics == [.heartRate], "HealthKit observes only categories routed to Apple")
    source.stopChanges()
    let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 10)])
    var workout = Workout(name: "Mixed source", startedAt: start, exercises: [row])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id, repetitions: 10, weightKG: 0,
      at: start.addingTimeInterval(60))
    try WorkoutEngine.finish(&workout, at: now)
    let appleRecording = try await source.heartRate(for: workout)
    try expect(
      native.importedHeartRates == 1 && appleRecording.origin == nil,
      "Workout pulse follows Apple selection even when sleep is Xiaomi")
    source.select(.miFitness, for: .heartRate)
    let cloudRecording = try await source.heartRate(for: workout)
    try expect(
      cloudRecording.origin == .miFitnessCloud && !cloudRecording.readings.isEmpty,
      "Switching pulse source preserves Xiaomi recording provenance")
    source.select(.appleHealth, for: .heartRate)
    let model = HealthDataViewModel(sources: source, now: { now })
    await model.load(calendar: calendar)
    try expect(
      model.result == nil, "Expanded overview requires explicit permission to read both providers")
    await model.load(calendar: calendar, explicit: true)
    try expect(
      model.readings.first { $0.metric == .steps }?.provider == .miFitness,
      "Overview identifies each value's provider")
    try expect(
      model.readings.first { $0.metric == .bodyWeight }?.value == 72.5,
      "Overview keeps primary weight")
    cloud.emptyMetrics = [.steps]
    let absent = try await source.daySummary(for: now, calendar: calendar)
    try expect(
      absent.steps == nil && absent.latestHeartRate != nil,
      "Missing primary values do not fall back to the other provider")
    cloud.emptyMetrics = []
    cloud.failure = .notConnected
    let partial = try await source.daySummary(for: now, calendar: calendar)
    try expect(
      partial.steps == nil && partial.latestHeartRate != nil
        && partial.unavailableMetrics.contains(.steps),
      "Source failure keeps healthy metrics and marks missing ones")
    let partialChart = try await source.chartSnapshot(day: now, calendar: calendar)
    try expect(
      partialChart.steps.allSatisfy { $0.steps == nil } && !partialChart.heartRate.isEmpty
        && partialChart.unavailableMetrics.contains(.steps),
      "Chart shows partial failure without silent source substitution")
    await model.load(calendar: calendar, explicit: true)
    try expect(
      model.result != nil && model.error == nil
        && model.readings.first { $0.metric == .steps }?.failureMessage != nil,
      "Overview preserves Apple values and reports Xiaomi failure per metric")
    cloud.failure = nil
    _ = try await source.read(start: start, end: now, metrics: requested, calendar: calendar)
    cloud.failure = .unavailable
    let offline = try await source.read(
      start: start, end: now, metrics: requested, calendar: calendar)
    try expect(
      offline.cachedProviders == [.miFitness] && offline.snapshots[.appleHealth] != nil,
      "Offline cache stays provider scoped alongside fresh data")
    cloud.failure = nil
    cloud.suspend = true
    let pending = Task {
      try await source.read(
        start: start, end: now, metrics: [.steps, .bodyWeight], calendar: calendar)
    }
    await cloud.waitForRead()
    source.select(.appleHealth, for: .steps)
    cloud.pending?.resume(returning: try cloud.value(start: start, end: now, metrics: [.steps]))
    cloud.pending = nil
    do {
      _ = try await pending.value
      throw CheckFailure(message: "Late result from previous per-metric selection was accepted")
    } catch is CancellationError {}
    try expect(source.fetchedAt == nil, "Changed preferences discard old combined metadata")
    cloud.suspend = false
    source.select(.miFitness, for: .steps)
    cloud.suspend = true
    let oldAccount = Task {
      try await source.read(
        start: start, end: now, metrics: [.steps, .bodyWeight], calendar: calendar)
    }
    await cloud.waitForRead()
    account.id = "mixed-other"
    source.refreshAccount()
    cloud.pending?.resume(returning: try cloud.value(start: start, end: now, metrics: [.steps]))
    cloud.pending = nil
    do {
      _ = try await oldAccount.value
      throw CheckFailure(message: "Old account's combined result was accepted")
    } catch is CancellationError {}
    try expect(source.fetchedAt == nil, "Account switch discards every provider's pending metadata")
    cloud.suspend = false
    print(
      "Mixed health sources: per-metric routing, separate permissions, no double counting/fallback, partial failures, offline cache, restart, account isolation and stale results passed."
    )
  }

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
      sources.provider(for: .steps) == .appleHealth && apple.authorizations == 0,
      "No access before opt-in")
    sources.select(.miFitness, for: .steps)
    try await sources.authorize(metrics: [.steps])
    let fresh = try await sources.read(
      start: start, end: end, metrics: [.steps], calendar: calendar)
    try expect(
      !fresh.cached && fresh.snapshot(for: .steps)?.quantities.first?.value == 0,
      "Zero is actual data")
    cloud.failure = .unavailable
    try await sources.authorize(metrics: [.steps])
    let saved = try await sources.read(
      start: start, end: end.addingTimeInterval(60), metrics: [.steps], calendar: calendar)
    try expect(
      saved.cached && saved.snapshot(for: .steps)?.fetchedAt == end,
      "Offline preserves original fetch time")
    cloud.failure = .permissionRequired
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
      throw CheckFailure(message: "Revoked permissions cannot fall back to cache")
    } catch HealthDataError.permissionRequired {}
    cloud.failure = .unavailable
    account.id = "account-b"
    sources.refreshAccount()
    try expect(
      sources.provider(for: .steps) == .appleHealth && sources.fetchedAt == nil,
      "Selection and metadata isolated by account")
    sources.select(.miFitness, for: .steps)
    do {
      _ = try await sources.read(start: start, end: end, metrics: [.steps], calendar: calendar)
      throw CheckFailure(message: "Other account cannot read cached measurements")
    } catch HealthDataError.unavailable {}
    account.id = "account-a"
    sources.refreshAccount()
    try expect(sources.provider(for: .steps) == .miFitness, "Per-account preference restored")
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
    sources.select(.appleHealth, for: .steps)
    cloud.pending?.resume(returning: try cloud.value(start: start, end: end, metrics: [.steps]))
    cloud.pending = nil
    do {
      _ = try await reading.value
      throw CheckFailure(message: "Stale provider result accepted")
    } catch is CancellationError {}
    try expect(sources.fetchedAt == nil, "Stale source cannot publish metadata")
    cloud.suspend = false
    sources.select(.miFitness, for: .steps)
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
    try await mixedSources(
      defaults: defaults, calendar: calendar, now: start.addingTimeInterval(8 * 3600))
    print(
      "Health providers: account/timezone isolation, consent, offline, corruption, cancellation and opt-out passed (no Apple SDK or network)."
    )
  }
}
