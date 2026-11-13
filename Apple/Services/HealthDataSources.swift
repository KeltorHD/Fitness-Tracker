import FitLifeCore
import Foundation
import Observation

struct HealthDataReadResult: Sendable {
  let snapshot: HealthDataSnapshot
  let cached: Bool
}

@MainActor @Observable
final class HealthDataSources: HealthSleepReading, HealthChartsReading, HealthMetricsReading {
  private(set) var selected: HealthProviderID
  private(set) var revision = 0
  private(set) var cached = false
  private(set) var fetchedAt: Date?
  @ObservationIgnored var onSelectionChange: (@MainActor () -> Void)?
  @ObservationIgnored private let providers: [HealthProviderID: any HealthDataProviding]
  @ObservationIgnored private let appleSleep: any HealthSleepReading
  @ObservationIgnored private let appleMetrics: any HealthMetricsReading
  @ObservationIgnored private let appleCharts: any HealthChartsReading
  @ObservationIgnored private let cache: any HealthDataCaching
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let account: @MainActor () -> String
  @ObservationIgnored private let now: @MainActor () -> Date
  @ObservationIgnored private var namespace: String
  @ObservationIgnored private var generation = UUID()

  init(
    providers: [any HealthDataProviding], appleSleep: any HealthSleepReading,
    appleMetrics: any HealthMetricsReading, appleCharts: any HealthChartsReading,
    cache: any HealthDataCaching, defaults: UserDefaults = .standard,
    account: @escaping @MainActor () -> String, now: @escaping @MainActor () -> Date = Date.init
  ) {
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.appleSleep = appleSleep
    self.appleMetrics = appleMetrics
    self.appleCharts = appleCharts
    self.cache = cache
    self.defaults = defaults
    self.account = account
    self.now = now
    namespace = account()
    selected =
      HealthProviderID(rawValue: defaults.string(forKey: "healthProvider." + namespace) ?? "")
      ?? .appleHealth
  }

  var supportedMetrics: Set<HealthMetric> { providers[selected]?.supportedMetrics ?? [] }
  var accountID: String { account() }
  var preferences: UserDefaults { defaults }
  var miFitness: MiFitnessDataProvider? { providers[.miFitness] as? MiFitnessDataProvider }

  func refreshAccount() {
    guard namespace != account() else { return }
    namespace = account()
    selected =
      HealthProviderID(rawValue: defaults.string(forKey: "healthProvider." + namespace) ?? "")
      ?? .appleHealth
    invalidate()
  }

  func select(_ provider: HealthProviderID) {
    refreshAccount()
    guard selected != provider else { return }
    selected = provider
    defaults.set(provider.rawValue, forKey: "healthProvider." + namespace)
    invalidate()
  }

  private func invalidate() {
    generation = UUID()
    stopChanges()
    fetchedAt = nil
    cached = false
    revision += 1
    onSelectionChange?()
  }

  func authorize(metrics: Set<HealthMetric>) async throws {
    refreshAccount()
    let token = generation
    let scope = namespace
    let id = selected
    guard let provider = providers[selected] else { throw HealthDataError.unavailable }
    let requested = metrics.intersection(provider.supportedMetrics)
    let consentKey = "healthConsent." + scope + "." + id.rawValue
    do {
      let authorized = try await provider.authorize(metrics: requested)
      try check(token, account: scope, provider: id)
      defaults.set(authorized.map(\.rawValue), forKey: consentKey)
    } catch {
      try check(token, account: scope, provider: id)
      guard error as? ServerError == .unavailable || error as? HealthDataError == .unavailable,
        let saved = defaults.stringArray(forKey: consentKey),
        !Set(saved.compactMap(HealthMetric.init(rawValue:))).intersection(requested).isEmpty
      else { throw error }
    }
    try check(token, account: scope, provider: id)
  }

  func snapshot(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    try await read(start: start, end: end, metrics: metrics, calendar: calendar).snapshot
  }

  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataReadResult
  {
    refreshAccount()
    let token = generation
    let scope = namespace
    let id = selected
    guard let provider = providers[id] else { throw HealthDataError.unavailable }
    let requested = metrics.intersection(provider.supportedMetrics)
    guard !requested.isEmpty else { throw HealthDataError.unsupportedMetric }
    let key = HealthDataCacheKey(
      account: scope, provider: id, metrics: requested, timeZoneID: calendar.timeZone.identifier)
    var result: HealthDataSnapshot
    let stale: Bool
    do {
      result = try await provider.read(
        start: start, end: end, metrics: requested, calendar: calendar)
      try check(token, account: scope, provider: id)
      try await Self.validate(result)
      guard result.provider == id, abs(result.start.timeIntervalSince(start)) < 0.001,
        abs(result.end.timeIntervalSince(end)) < 0.001, result.metrics.isSubset(of: requested)
      else { throw HealthDataError.invalidData }
      stale = false
    } catch {
      try check(token, account: scope, provider: id)
      guard error as? ServerError == .unavailable || error as? HealthDataError == .unavailable,
        let saved = try await cache.load(key), abs(saved.start.timeIntervalSince(start)) < 0.001,
        calendar.isDate(saved.end, inSameDayAs: end), saved.end <= end
      else { throw error }
      result = saved
      stale = true
    }
    try check(token, account: scope, provider: id)
    if !stale { try await cache.save(result, for: key) }
    try check(token, account: scope, provider: id)
    fetchedAt = result.fetchedAt
    cached = stale
    return HealthDataReadResult(snapshot: result, cached: stale)
  }

  private func check(_ token: UUID, account scope: String, provider: HealthProviderID) throws {
    try Task.checkCancellation()
    guard generation == token, namespace == scope, account() == scope, selected == provider else {
      throw CancellationError()
    }
  }

  @concurrent nonisolated private static func validate(_ snapshot: HealthDataSnapshot) async throws
  {
    try snapshot.validate()
  }

  func disconnectMiFitness() async throws {
    refreshAccount()
    let scope = namespace
    guard let miFitness else { throw HealthDataError.unavailable }
    try await miFitness.disconnect()
    guard account() == scope else { throw CancellationError() }
    invalidate()
    defaults.removeObject(forKey: "healthConsent." + scope + ".miFitness")
    defaults.set(false, forKey: "healthOverview." + scope + ".miFitness")
    try await cache.remove(account: scope, provider: .miFitness)
  }

  func authorize() async throws {
    refreshAccount()
    if selected == .appleHealth {
      try await appleSleep.authorize()
    } else {
      try await authorize(metrics: [.sleep])
    }
  }

  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] {
    refreshAccount()
    let token = generation
    let scope = namespace
    let provider = selected
    if selected == .appleHealth {
      let result = try await appleSleep.nights(endingOn: day, calendar: calendar)
      try check(token, account: scope, provider: provider)
      return result
    }
    guard let firstDay = calendar.date(byAdding: .day, value: -29, to: day),
      let first = SleepNight.window(endingOn: firstDay, calendar: calendar),
      let last = SleepNight.window(endingOn: day, calendar: calendar)
    else { throw TrainingError.invalidDate }
    guard first.start < now() else { return [] }
    let result = try await read(
      start: first.start, end: min(last.end, now()), metrics: [.sleep], calendar: calendar)
    let nights = try await Self.makeNights(result, day: day, calendar: calendar)
    try check(token, account: scope, provider: provider)
    return nights
  }

  func requestChartAuthorization() async throws {
    refreshAccount()
    if selected == .appleHealth {
      try await appleCharts.requestChartAuthorization()
    } else {
      try await authorize(metrics: [.steps, .heartRate])
    }
  }

  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    refreshAccount()
    let token = generation
    let scope = namespace
    let provider = selected
    if selected == .appleHealth {
      let result = try await appleCharts.chartSnapshot(day: day, calendar: calendar)
      try check(token, account: scope, provider: provider)
      return result
    }
    let window = try HealthChartWindow(day: day, now: now(), calendar: calendar)
    let currentDay = calendar.startOfDay(for: now())
    let history = try await read(
      start: window.stepsInterval.start, end: window.day.end, metrics: [.steps, .heartRate],
      calendar: calendar)
    try check(token, account: scope, provider: provider)
    let value = history.snapshot
    var fetched = value.fetchedAt
    var stale = history.cached
    let allRates = value.quantities.filter { $0.metric == .heartRate }.map {
      HeartRateReading(date: $0.start, beatsPerMinute: $0.value)
    }.sorted { $0.date < $1.date }
    let currentRates: [HeartRateReading]
    if calendar.isDate(day, inSameDayAs: now()) {
      currentRates = allRates.filter { $0.date >= currentDay }
    } else if currentDay < now() {
      let currentRead = try await read(
        start: currentDay, end: now(), metrics: [.heartRate], calendar: calendar)
      let current = currentRead.snapshot
      fetched = min(fetched, current.fetchedAt)
      stale = stale || currentRead.cached
      currentRates = current.quantities.filter { $0.metric == .heartRate }.map {
        HeartRateReading(date: $0.start, beatsPerMinute: $0.value)
      }.sorted { $0.date < $1.date }
    } else {
      currentRates = []
    }
    let steps = window.stepDays.map { date in
      HealthStepDay(
        date: date,
        steps: calendar.dateInterval(of: .day, for: date).flatMap {
          value.total(.steps, during: $0)
        }.flatMap(Int.init(exactly:)))
    }
    try check(token, account: scope, provider: provider)
    return HealthChartSnapshot(
      day: window.day.start, steps: steps,
      heartRate: allRates.filter { $0.date >= window.day.start && $0.date <= window.day.end },
      latestHeartRate: currentRates.last, heartRateSource: "Mi Fitness",
      currentDayHeartRate: currentRates,
      fetchedAt: fetched, isCached: stale)
  }

  func changes(since date: Date) -> AsyncThrowingStream<Void, any Error> {
    selected == .appleHealth
      ? appleCharts.changes(since: date) : AsyncThrowingStream { $0.finish() }
  }
  func stopChanges() { appleCharts.stopChanges() }

  @concurrent nonisolated private static func makeNights(
    _ result: HealthDataReadResult, day: Date, calendar: Calendar
  ) async throws -> [SleepNight] {
    try result.snapshot.nights(endingOn: day, calendar: calendar, cached: result.cached)
  }

  func requestReadAuthorization() async throws {
    refreshAccount()
    if selected == .appleHealth {
      try await appleMetrics.requestReadAuthorization()
    } else {
      try await authorize(metrics: [.sleep, .steps, .heartRate])
    }
  }
  func requestHeartRateAuthorization() async throws {
    refreshAccount()
    if selected == .appleHealth {
      try await appleMetrics.requestHeartRateAuthorization()
    } else {
      try await authorize(metrics: [.heartRate])
    }
  }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    refreshAccount()
    let token = generation
    let scope = namespace
    let provider = selected
    if selected == .appleHealth {
      let result = try await appleMetrics.daySummary(for: day, calendar: calendar)
      try check(token, account: scope, provider: provider)
      return result
    }
    guard let dayInterval = calendar.dateInterval(of: .day, for: day),
      let night = SleepNight.window(endingOn: day, calendar: calendar)
    else { throw TrainingError.invalidDate }
    let result = try await read(
      start: min(night.start, dayInterval.start), end: min(max(night.end, dayInterval.end), now()),
      metrics: [.sleep, .steps, .heartRate], calendar: calendar)
    let summary = try await Self.makeSummary(
      result, day: day, calendar: calendar, dayInterval: dayInterval)
    try check(token, account: scope, provider: provider)
    return summary
  }

  @concurrent nonisolated private static func makeSummary(
    _ result: HealthDataReadResult, day: Date, calendar: Calendar, dayInterval: DateInterval
  ) async throws -> HealthDaySummary {
    let value = result.snapshot
    let latest = value.quantities.filter {
      $0.metric == .heartRate && $0.start >= dayInterval.start && $0.start < dayInterval.end
    }.max { $0.start < $1.start }
    return HealthDaySummary(
      day: dayInterval.start,
      steps: value.total(.steps, during: dayInterval).flatMap(Int.init(exactly:)),
      activeEnergyKCal: nil,
      sleepSeconds: try value.nights(endingOn: day, count: 1, calendar: calendar).first?.asleep,
      latestHeartRate: latest.map { HeartRateReading(date: $0.start, beatsPerMinute: $0.value) },
      heartRateSource: latest?.sourceName,
      fetchedAt: value.fetchedAt, isCached: result.cached)
  }

  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    refreshAccount()
    let token = generation
    let scope = namespace
    let provider = selected
    if selected == .appleHealth {
      let result = try await appleMetrics.heartRate(for: workout)
      try check(token, account: scope, provider: provider)
      return result
    }
    try Validation.workout(workout)
    guard workout.status == .completed, let end = workout.endedAt else {
      throw TrainingError.invalidState
    }
    if end == workout.startedAt {
      return try HeartRateRecording(
        workoutID: workout.id, mode: .appleHealth, origin: .miFitnessCloud)
    }
    let value = try await snapshot(
      start: workout.startedAt, end: end, metrics: [.heartRate], calendar: .current)
    let result = try await Self.makeRecording(value, workout: workout, end: end)
    try check(token, account: scope, provider: provider)
    return result
  }

  @concurrent nonisolated private static func makeRecording(
    _ value: HealthDataSnapshot, workout: Workout, end: Date
  ) async throws -> HeartRateRecording {
    var seen = Set<Date>()
    let rates = value.quantities.filter { $0.metric == .heartRate }.sorted { $0.start < $1.start }
      .compactMap { quantity -> HeartRateReading? in
        guard quantity.start >= workout.startedAt, quantity.start <= end,
          seen.insert(quantity.start).inserted,
          !workout.pauses.contains(where: { ($0.startedAt...$0.endedAt).contains(quantity.start) })
        else { return nil }
        return HeartRateReading(date: quantity.start, beatsPerMinute: quantity.value)
      }
    let stride = max(1, Int(ceil(Double(rates.count) / Double(HeartRateRecording.maximumReadings))))
    var sampled = rates.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    if let last = rates.last, sampled.last != last {
      if sampled.count == HeartRateRecording.maximumReadings { sampled.removeLast() }
      sampled.append(last)
    }
    return try HeartRateRecording(
      workoutID: workout.id, mode: .appleHealth, readings: sampled, origin: .miFitnessCloud)
  }
}
