import FitLifeCore
import Foundation
import Observation

struct HealthDataReadResult: Sendable {
  let routes: [HealthMetric: HealthProviderID]
  let snapshots: [HealthProviderID: HealthDataSnapshot]
  let cachedProviders: Set<HealthProviderID>
  let failures: [HealthProviderID: any Error]
  var cached: Bool { !cachedProviders.isEmpty }
  var fetchedAt: Date? { snapshots.values.map(\.fetchedAt).min() }
  var unavailableMetrics: Set<HealthMetric> {
    Set(
      routes.keys.filter { metric in
        guard let id = routes[metric] else { return true }
        return failures[id] != nil || snapshots[id]?.metrics.contains(metric) != true
      })
  }
  func snapshot(for metric: HealthMetric) -> HealthDataSnapshot? {
    routes[metric].flatMap { snapshots[$0] }
  }
}

private struct HealthProviderRead: Sendable {
  let snapshot: HealthDataSnapshot
  let cached: Bool
}

@MainActor @Observable
final class HealthDataSources: HealthSleepReading, HealthChartsReading, HealthMetricsReading {
  private(set) var selection: HealthSourceSelection
  private(set) var revision = 0
  private(set) var cached = false
  private(set) var fetchedAt: Date?
  let appleSync: AppleHealthSyncCoordinator?
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
    account: @escaping @MainActor () -> String, now: @escaping @MainActor () -> Date = Date.init,
    appleSync: AppleHealthSyncCoordinator? = nil
  ) {
    self.appleSync = appleSync
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.appleSleep = appleSleep
    self.appleMetrics = appleMetrics
    self.appleCharts = appleCharts
    self.cache = cache
    self.defaults = defaults
    self.account = account
    self.now = now
    namespace = account()
    selection = Self.loadSelection(defaults: defaults, account: namespace)
  }

  private static func loadSelection(defaults: UserDefaults, account: String)
    -> HealthSourceSelection
  {
    let preferred = defaults.dictionary(forKey: "healthProviderMetrics." + account) ?? [:]
    var metrics: [HealthMetric: HealthProviderID] = [:]
    for (key, value) in preferred {
      if let metric = HealthMetric(rawValue: key), let raw = value as? String,
        let provider = HealthProviderID(rawValue: raw)
      {
        metrics[metric] = provider
      }
    }
    return HealthSourceSelection(
      defaultProvider: HealthProviderID(
        rawValue: defaults.string(forKey: "healthProvider." + account) ?? "") ?? .appleHealth,
      preferences: metrics)
  }

  var usesServerAppleHistory: Bool { appleSync?.available == true && appleSync?.enabled != true }
  var supportedMetrics: Set<HealthMetric> {
    Set(HealthMetric.allCases.filter { provider(for: $0) != nil })
  }
  var accountID: String { account() }
  var contextID: String { accountID + ":" + String(revision) }
  var preferences: UserDefaults { defaults }
  var miFitness: MiFitnessDataProvider? { providers[.miFitness] as? MiFitnessDataProvider }

  func providers(for metric: HealthMetric) -> [HealthProviderID] {
    HealthProviderID.allCases.filter { providers[$0]?.supportedMetrics.contains(metric) == true }
  }
  func provider(for metric: HealthMetric) -> HealthProviderID? {
    selection.provider(for: metric, supportedBy: providers.mapValues(\.supportedMetrics))
  }
  func uses(_ provider: HealthProviderID) -> Bool {
    supportedMetrics.contains { self.provider(for: $0) == provider }
  }
  private func routes(for metrics: Set<HealthMetric>) -> [HealthMetric: HealthProviderID] {
    Dictionary(
      uniqueKeysWithValues: metrics.compactMap { metric in
        provider(for: metric).map { (metric, $0) }
      })
  }

  func refreshAccount() {
    guard namespace != account() else { return }
    namespace = account()
    selection = Self.loadSelection(defaults: defaults, account: namespace)
    invalidate()
  }

  func appleHistoryDidChange() {
    guard uses(.appleHealth), appleSync?.available == true else { return }
    invalidate()
  }

  func select(_ provider: HealthProviderID, for metric: HealthMetric) {
    refreshAccount()
    guard providers(for: metric).contains(provider), self.provider(for: metric) != provider else {
      return
    }
    selection.preferences[metric] = provider
    defaults.set(
      Dictionary(
        uniqueKeysWithValues: selection.preferences.map { ($0.key.rawValue, $0.value.rawValue) }),
      forKey: "healthProviderMetrics." + namespace)
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

  private func authorize(
    _ id: HealthProviderID, metrics: Set<HealthMetric>, token: UUID, scope: String
  ) async throws {
    guard let provider = providers[id] else { throw HealthDataError.unavailable }
    let consentKey = "healthConsent." + scope + "." + id.rawValue
    do {
      let authorized = try await provider.authorize(metrics: metrics)
      try check(token, account: scope)
      defaults.set(authorized.map(\.rawValue), forKey: consentKey)
    } catch {
      try check(token, account: scope)
      guard error as? ServerError == .unavailable || error as? HealthDataError == .unavailable,
        let saved = defaults.stringArray(forKey: consentKey),
        !Set(saved.compactMap(HealthMetric.init(rawValue:))).intersection(metrics).isEmpty
      else { throw error }
    }
    try check(token, account: scope)
  }

  func authorize(metrics: Set<HealthMetric>) async throws {
    refreshAccount()
    let token = generation
    let scope = namespace
    let requested = routes(for: metrics)
    guard !requested.isEmpty else { throw HealthDataError.unsupportedMetric }
    var success = false
    var failure: (any Error)?
    for id in HealthProviderID.allCases {
      let subset = Set(requested.keys.filter { requested[$0] == id })
      guard !subset.isEmpty else { continue }
      do {
        try await authorize(id, metrics: subset, token: token, scope: scope)
        success = true
      } catch is CancellationError { throw CancellationError() } catch { failure = error }
    }
    try check(token, account: scope)
    if !success, let failure { throw failure }
  }

  /// Reads providers independently. A failure cannot select another source or hide healthy metrics.
  func read(
    start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar, authorize: Bool = false
  ) async throws -> HealthDataReadResult {
    refreshAccount()
    let token = generation
    let scope = namespace
    let requested = routes(for: metrics)
    guard !requested.isEmpty else { throw HealthDataError.unsupportedMetric }
    var snapshots: [HealthProviderID: HealthDataSnapshot] = [:]
    var stale: Set<HealthProviderID> = []
    var failures: [HealthProviderID: any Error] = [:]
    try await withThrowingTaskGroup(
      of: (HealthProviderID, Result<HealthProviderRead, any Error>).self
    ) { group in
      for id in HealthProviderID.allCases {
        let subset = Set(requested.keys.filter { requested[$0] == id })
        guard !subset.isEmpty else { continue }
        group.addTask {
          do {
            if authorize {
              try await self.authorize(id, metrics: subset, token: token, scope: scope)
            }
            let value = try await self.readProvider(
              id, start: start, end: end, metrics: subset, calendar: calendar, token: token,
              scope: scope)
            return (id, .success(value))
          } catch is CancellationError { throw CancellationError() } catch {
            return (id, .failure(error))
          }
        }
      }
      for try await (id, outcome) in group {
        switch outcome {
        case .success(let value):
          snapshots[id] = value.snapshot
          if value.cached { stale.insert(id) }
        case .failure(let error): failures[id] = error
        }
      }
    }
    try check(token, account: scope)
    if snapshots.isEmpty,
      let failed = HealthProviderID.allCases.first(where: { failures[$0] != nil }),
      let error = failures[failed]
    {
      throw error
    }
    let result = HealthDataReadResult(
      routes: requested, snapshots: snapshots, cachedProviders: stale, failures: failures)
    fetchedAt = result.fetchedAt
    cached = result.cached
    return result
  }

  private func readProvider(
    _ id: HealthProviderID, start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar,
    token: UUID, scope: String
  ) async throws -> HealthProviderRead {
    guard let provider = providers[id] else { throw HealthDataError.unavailable }
    let key = HealthDataCacheKey(
      account: scope, provider: id, metrics: metrics, timeZoneID: calendar.timeZone.identifier)
    var result: HealthDataSnapshot
    let stale: Bool
    do {
      result = try await provider.read(start: start, end: end, metrics: metrics, calendar: calendar)
      try check(token, account: scope)
      try await Self.validate(result)
      guard result.provider == id, abs(result.start.timeIntervalSince(start)) < 0.001,
        abs(result.end.timeIntervalSince(end)) < 0.001, result.metrics.isSubset(of: metrics)
      else { throw HealthDataError.invalidData }
      stale = false
    } catch {
      try check(token, account: scope)
      guard error as? ServerError == .unavailable || error as? HealthDataError == .unavailable,
        let saved = try await cache.load(key), abs(saved.start.timeIntervalSince(start)) < 0.001,
        calendar.isDate(saved.end, inSameDayAs: end), saved.end <= end
      else { throw error }
      result = saved
      stale = true
    }
    try check(token, account: scope)
    if !stale { try await cache.save(result, for: key) }
    try check(token, account: scope)
    return HealthProviderRead(snapshot: result, cached: stale)
  }

  private func check(_ token: UUID, account scope: String) throws {
    try Task.checkCancellation()
    guard generation == token, namespace == scope, account() == scope else {
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
    try await cache.remove(account: scope, provider: .miFitness)
  }

  func authorize() async throws {
    refreshAccount()
    if provider(for: .sleep) == .appleHealth && !usesServerAppleHistory {
      try await appleSleep.authorize()
    } else {
      try await authorize(metrics: [.sleep])
    }
  }

  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] {
    refreshAccount()
    let token = generation
    let scope = namespace
    if provider(for: .sleep) == .appleHealth && !usesServerAppleHistory {
      let result = try await appleSleep.nights(endingOn: day, calendar: calendar)
      try check(token, account: scope)
      return result
    }
    guard let firstDay = calendar.date(byAdding: .day, value: -29, to: day),
      let first = SleepNight.window(endingOn: firstDay, calendar: calendar),
      let last = SleepNight.window(endingOn: day, calendar: calendar)
    else { throw TrainingError.invalidDate }
    guard first.start < now() else { return [] }
    let result = try await read(
      start: first.start, end: min(last.end, now()), metrics: [.sleep], calendar: calendar)
    guard let value = result.snapshot(for: .sleep) else { throw HealthDataError.unavailable }
    let nights = try await Self.makeNights(
      value, cached: result.cached, day: day, calendar: calendar)
    try check(token, account: scope)
    return nights
  }

  func requestChartAuthorization() async throws {
    refreshAccount()
    if provider(for: .steps) == .appleHealth, provider(for: .heartRate) == .appleHealth,
      !usesServerAppleHistory
    {
      try await appleCharts.requestChartAuthorization()
    } else {
      try await authorize(metrics: [.steps, .heartRate])
    }
  }

  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    refreshAccount()
    let token = generation
    let scope = namespace
    if provider(for: .steps) == .appleHealth, provider(for: .heartRate) == .appleHealth,
      !usesServerAppleHistory
    {
      let result = try await appleCharts.chartSnapshot(day: day, calendar: calendar)
      try check(token, account: scope)
      return result
    }
    let window = try HealthChartWindow(day: day, now: now(), calendar: calendar)
    let currentDay = calendar.startOfDay(for: now())
    let history = try await read(
      start: window.stepsInterval.start, end: window.day.end, metrics: [.steps, .heartRate],
      calendar: calendar)
    var current = history
    if !calendar.isDate(day, inSameDayAs: now()), currentDay < now() {
      do {
        current = try await read(
          start: currentDay, end: now(), metrics: [.heartRate], calendar: calendar)
      } catch is CancellationError { throw CancellationError() } catch {
        let routes = routes(for: [.heartRate])
        current = HealthDataReadResult(
          routes: routes, snapshots: [:], cachedProviders: [],
          failures: Dictionary(uniqueKeysWithValues: routes.values.map { ($0, error) }))
      }
    }
    let result = await Self.makeChart(
      history: history, current: current, window: window, currentDay: currentDay, calendar: calendar
    )
    try check(token, account: scope)
    return result
  }

  @concurrent nonisolated private static func makeChart(
    history: HealthDataReadResult, current: HealthDataReadResult, window: HealthChartWindow,
    currentDay: Date, calendar: Calendar
  ) async -> HealthChartSnapshot {
    let rates =
      history.snapshot(for: .heartRate)?.quantities.filter { $0.metric == .heartRate }.map {
        HeartRateReading(date: $0.start, beatsPerMinute: $0.value)
      }.sorted { $0.date < $1.date } ?? []
    let currentRates =
      current.snapshot(for: .heartRate)?.quantities.filter {
        $0.metric == .heartRate && $0.start >= currentDay
      }.map { HeartRateReading(date: $0.start, beatsPerMinute: $0.value) }.sorted {
        $0.date < $1.date
      } ?? []
    return HealthChartSnapshot(
      day: window.day.start,
      steps: window.stepDays.map { date in
        HealthStepDay(
          date: date,
          steps: calendar.dateInterval(of: .day, for: date).flatMap {
            history.snapshot(for: .steps)?.total(.steps, during: $0)
          }.flatMap(Int.init(exactly:)))
      },
      heartRate: rates.filter { $0.date >= window.day.start && $0.date <= window.day.end },
      latestHeartRate: currentRates.last,
      heartRateSource: current.snapshot(for: .heartRate)?.quantities.filter {
        $0.metric == .heartRate && $0.start >= currentDay
      }.max(by: { $0.start < $1.start })?.sourceName,
      currentDayHeartRate: currentRates,
      fetchedAt: [history.fetchedAt, current.fetchedAt].compactMap { $0 }.min(),
      isCached: history.cached || current.cached,
      unavailableMetrics: history.unavailableMetrics.union(current.unavailableMetrics))
  }

  func changes(since date: Date) -> AsyncThrowingStream<Void, any Error> {
    let metrics = Set(
      [HealthMetric.steps, .heartRate].filter { provider(for: $0) == .appleHealth })
    return !metrics.isEmpty && !usesServerAppleHistory
      ? appleCharts.changes(since: date, metrics: metrics) : AsyncThrowingStream { $0.finish() }
  }
  func stopChanges() { appleCharts.stopChanges() }

  @concurrent nonisolated private static func makeNights(
    _ value: HealthDataSnapshot, cached: Bool, day: Date, calendar: Calendar
  ) async throws -> [SleepNight] {
    try value.nights(endingOn: day, count: 30, calendar: calendar, cached: cached)
  }

  func requestReadAuthorization() async throws {
    try await authorize(metrics: [.sleep, .steps, .heartRate, .activeEnergy])
  }
  func requestHeartRateAuthorization() async throws {
    refreshAccount()
    if provider(for: .heartRate) == .appleHealth && !usesServerAppleHistory {
      try await appleMetrics.requestHeartRateAuthorization()
    } else {
      try await authorize(metrics: [.heartRate])
    }
  }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    refreshAccount()
    let token = generation
    let scope = namespace
    if [.sleep, .steps, .heartRate, .activeEnergy].allSatisfy({ provider(for: $0) == .appleHealth }
    ),
      !usesServerAppleHistory
    {
      let result = try await appleMetrics.daySummary(for: day, calendar: calendar)
      try check(token, account: scope)
      return result
    }
    guard let dayInterval = calendar.dateInterval(of: .day, for: day),
      let night = SleepNight.window(endingOn: day, calendar: calendar)
    else { throw TrainingError.invalidDate }
    let result = try await read(
      start: min(night.start, dayInterval.start), end: min(max(night.end, dayInterval.end), now()),
      metrics: [.sleep, .steps, .heartRate, .activeEnergy], calendar: calendar)
    let summary = try await Self.makeSummary(
      result, day: day, calendar: calendar, dayInterval: dayInterval)
    try check(token, account: scope)
    return summary
  }

  @concurrent nonisolated private static func makeSummary(
    _ result: HealthDataReadResult, day: Date, calendar: Calendar, dayInterval: DateInterval
  ) async throws -> HealthDaySummary {
    let latest = result.snapshot(for: .heartRate)?.quantities.filter {
      $0.metric == .heartRate && $0.start >= dayInterval.start && $0.start < dayInterval.end
    }.max { $0.start < $1.start }
    return HealthDaySummary(
      day: dayInterval.start,
      steps: result.snapshot(for: .steps)?.total(.steps, during: dayInterval).flatMap(
        Int.init(exactly:)),
      activeEnergyKCal: result.snapshot(for: .activeEnergy)?.total(
        .activeEnergy, during: dayInterval),
      sleepSeconds: try result.snapshot(for: .sleep)?.nights(
        endingOn: day, count: 1, calendar: calendar
      ).first?.asleep,
      latestHeartRate: latest.map { HeartRateReading(date: $0.start, beatsPerMinute: $0.value) },
      heartRateSource: latest?.sourceName,
      fetchedAt: result.fetchedAt, isCached: result.cached,
      unavailableMetrics: result.unavailableMetrics)
  }

  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    refreshAccount()
    let token = generation
    let scope = namespace
    let source = provider(for: .heartRate)
    if source == .appleHealth && !usesServerAppleHistory {
      let result = try await appleMetrics.heartRate(for: workout)
      try check(token, account: scope)
      return result
    }
    try Validation.workout(workout)
    guard workout.status == .completed, let end = workout.endedAt else {
      throw TrainingError.invalidState
    }
    if end == workout.startedAt {
      return try HeartRateRecording(
        workoutID: workout.id, mode: .appleHealth,
        origin: source == .miFitness ? .miFitnessCloud : nil)
    }
    let result = try await read(
      start: workout.startedAt, end: end, metrics: [.heartRate], calendar: .current)
    guard let value = result.snapshot(for: .heartRate) else { throw HealthDataError.unavailable }
    let recording = try await Self.makeRecording(value, workout: workout, end: end)
    try check(token, account: scope)
    return recording
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
      workoutID: workout.id, mode: .appleHealth, readings: sampled,
      origin: value.provider == .miFitness ? .miFitnessCloud : nil)
  }
}
