import FitLifeCore
import Foundation
import Observation

struct HealthMetricReading: Identifiable, Equatable, Sendable {
  var id: HealthMetric { metric }
  let metric: HealthMetric
  let value: Double?
  let date: Date?
  let permitted: Bool
}

@MainActor @Observable final class HealthDataViewModel {
  var day: Date
  var historyDays = 30
  private(set) var result: HealthDataReadResult?
  private(set) var connection: HealthConnectionStatus?
  private(set) var loading = false
  private(set) var connecting = false
  private(set) var error: String?
  private(set) var connectionError: String?
  private(set) var enabled: Bool
  private(set) var readings: [HealthMetricReading] = []
  @ObservationIgnored let sources: HealthDataSources
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let now: @MainActor () -> Date
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var context: String

  init(
    sources: HealthDataSources, defaults: UserDefaults? = nil,
    now: @escaping @MainActor () -> Date = Date.init
  ) {
    let preferences = defaults ?? sources.preferences
    self.sources = sources
    self.defaults = preferences
    self.now = now
    day = now()
    context = sources.accountID + sources.selected.rawValue + String(sources.revision)
    enabled = preferences.bool(
      forKey: "healthOverview." + sources.accountID + "." + sources.selected.rawValue)
  }

  func resetContext() {
    sources.refreshAccount()
    let context = sources.accountID + sources.selected.rawValue + String(sources.revision)
    guard self.context != context else { return }
    self.context = context
    generation = UUID()
    result = nil
    readings = []
    connection = nil
    connectionError = nil
    enabled = defaults.bool(
      forKey: "healthOverview." + sources.accountID + "." + sources.selected.rawValue)
    loading = false
    connecting = false
    error = nil
  }

  func select(_ provider: HealthProviderID) {
    sources.select(provider)
    resetContext()
  }

  func loadConnection() async {
    resetContext()
    guard let cloud = sources.miFitness else { return }
    let token = generation
    do {
      let status = try await cloud.connection()
      guard token == generation, !Task.isCancelled else { return }
      connection = status
      connectionError = nil
    } catch is CancellationError {} catch {
      guard token == generation, !Task.isCancelled else { return }
      // Opening settings doesn't claim that an absent/offline session has been explicitly disconnected.
      connection = nil
      connectionError = HealthProviderMessage.error(error)
    }
  }

  func load(calendar: Calendar, explicit: Bool = false) async {
    resetContext()
    guard !loading, enabled || explicit else { return }
    let token = UUID()
    generation = token
    let context = context
    loading = true
    result = nil
    readings = []
    error = nil
    defer { if generation == token { loading = false } }
    do {
      let metrics = sources.supportedMetrics
      if explicit { try await sources.authorize(metrics: metrics) }
      guard [1, 7, 30].contains(historyDays),
        let start = calendar.date(
          byAdding: .day, value: -(historyDays - 1), to: calendar.startOfDay(for: day)),
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
      else { throw TrainingError.invalidDate }
      let value = try await sources.read(
        start: start, end: min(end, now()), metrics: metrics, calendar: calendar)
      let readings = try await Self.makeReadings(
        value.snapshot, day: day, calendar: calendar, metrics: metrics)
      guard generation == token, !Task.isCancelled,
        context == sources.accountID + sources.selected.rawValue + String(sources.revision)
      else { return }
      result = value
      self.readings = readings
      enabled = true
      defaults.set(
        true, forKey: "healthOverview." + sources.accountID + "." + sources.selected.rawValue)
    } catch is CancellationError {} catch {
      guard generation == token, !Task.isCancelled else { return }
      self.error = HealthProviderMessage.error(error)
    }
  }

  func connect(
    using account: AccountTrainingViewModel?, authenticate: @MainActor (URL) async throws -> URL
  ) async {
    guard !connecting else { return }
    guard let account else {
      error = HealthProviderMessage.error(HealthDataError.unavailable)
      return
    }
    connecting = true
    defer { connecting = false }
    error = nil
    await account.perform(.manageHealth, browser: authenticate)
    resetContext()
    if let message = account.errorMessage { error = message }
    await loadConnection()
  }

  func disconnect() async {
    guard !connecting else { return }
    connecting = true
    defer { connecting = false }
    error = nil
    do {
      try await sources.disconnectMiFitness()
      result = nil
      readings = []
      enabled = false
      connection = nil
      defaults.set(false, forKey: "healthOverview." + sources.accountID + ".miFitness")
      await loadConnection()
    } catch is CancellationError {} catch { self.error = HealthProviderMessage.error(error) }
  }

  func stopDisplaying() {
    generation = UUID()
    loading = false
    result = nil
    readings = []
    enabled = false
    error = nil
    defaults.set(
      false, forKey: "healthOverview." + sources.accountID + "." + sources.selected.rawValue)
  }

  @concurrent nonisolated private static func makeReadings(
    _ snapshot: HealthDataSnapshot, day: Date, calendar: Calendar,
    metrics: Set<HealthMetric>
  ) async throws -> [HealthMetricReading] {
    guard let interval = calendar.dateInterval(of: .day, for: day) else {
      throw TrainingError.invalidDate
    }
    return try HealthMetric.allCases.filter(metrics.contains).map { metric in
      let value: Double?
      let date: Date?
      if metric == .sleep {
        let night = try snapshot.nights(endingOn: day, count: 1, calendar: calendar).first
        value = night?.asleep
        date = night?.sleepEnd
      } else if [.steps, .activeEnergy, .totalEnergy, .distance].contains(metric) {
        value = snapshot.total(metric, during: interval)
        date = nil
      } else {
        let latest = snapshot.latest(metric)
        value = latest?.value
        date = latest?.end
      }
      return HealthMetricReading(
        metric: metric, value: value, date: date, permitted: snapshot.metrics.contains(metric))
    }
  }
}
