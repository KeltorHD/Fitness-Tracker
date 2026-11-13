import FitLifeCore
import Foundation
import HealthKit

@MainActor final class AppleHealthDataProvider: HealthDataProviding {
  let id = HealthProviderID.appleHealth
  let supportedMetrics: Set<HealthMetric> = [
    .sleep, .steps, .bodyWeight, .bodyFatPercentage, .heartRate, .restingHeartRate, .activeEnergy,
    .bloodOxygen, .distance,
  ]
  private let sleep: any HealthSleepReading
  private let cryptography: any ServerCryptography
  init(
    sleep: any HealthSleepReading = HealthSleepReader(),
    cryptography: any ServerCryptography = AppleServerCryptography()
  ) {
    self.sleep = sleep
    self.cryptography = cryptography
  }

  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    guard metrics.isSubset(of: supportedMetrics) else { throw HealthDataError.unsupportedMetric }
    try await Self.authorizeTypes(metrics)
    return metrics
  }

  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    guard metrics.isSubset(of: supportedMetrics) else { throw HealthDataError.unsupportedMetric }
    let quantities = try await Self.readQuantities(
      start: start, end: end, metrics: metrics, calendar: calendar, cryptography: cryptography)
    let nights =
      metrics.contains(.sleep) ? try await sleep.nights(endingOn: end, calendar: calendar) : []
    return try await Self.makeSnapshot(
      start: start, end: end, metrics: metrics, quantities: quantities, nights: nights,
      cryptography: cryptography)
  }

  @concurrent nonisolated private static func makeSnapshot(
    start: Date, end: Date, metrics: Set<HealthMetric>, quantities: [HealthQuantity],
    nights: [SleepNight], cryptography: any ServerCryptography
  ) async throws -> HealthDataSnapshot {
    var records: [HealthSleepRecord] = []
    for night in nights {
      guard let first = night.periods.first, let last = night.periods.last else { continue }
      let source = night.sourceID ?? "appleHealth"
      let segments = try night.periods.map { period in
        HealthSleepSegment(
          id: try Self.identity(
            "sleep-" + period.stage.rawValue, source: source, start: period.interval.start,
            end: period.interval.end, cryptography: cryptography),
          start: period.interval.start, end: period.interval.end, stage: period.stage)
      }
      records.append(
        HealthSleepRecord(
          id: try Self.identity(
            "sleep", source: source, start: first.interval.start, end: last.interval.end,
            cryptography: cryptography),
          start: first.interval.start, end: last.interval.end, asleepSeconds: night.asleep,
          sourceID: source,
          sourceName: night.sourceName ?? "Apple Health", segments: segments))
    }
    try Task.checkCancellation()
    return try HealthDataSnapshot(
      provider: .appleHealth, start: start, end: end, fetchedAt: Date(), metrics: metrics,
      quantities: quantities, sleep: records.filter { $0.start < end && $0.end > start })
  }

  nonisolated static func type(_ metric: HealthMetric) -> (
    HKQuantityTypeIdentifier, HKUnit
  )? {
    switch metric {
    case .steps: (.stepCount, .count())
    case .bodyWeight: (.bodyMass, .gramUnit(with: .kilo))
    case .bodyFatPercentage: (.bodyFatPercentage, .percent())
    case .heartRate: (.heartRate, .count().unitDivided(by: .minute()))
    case .restingHeartRate: (.restingHeartRate, .count().unitDivided(by: .minute()))
    case .activeEnergy: (.activeEnergyBurned, .kilocalorie())
    case .bloodOxygen: (.oxygenSaturation, .percent())
    case .distance: (.distanceWalkingRunning, .meter())
    case .sleep, .totalEnergy: nil
    }
  }

  @concurrent nonisolated private static func authorizeTypes(_ metrics: Set<HealthMetric>)
    async throws
  {
    guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }
    var types = Set<HKObjectType>(metrics.compactMap { type($0).map { HKQuantityType($0.0) } })
    if metrics.contains(.sleep) { types.insert(HKCategoryType(.sleepAnalysis)) }
    try await HKHealthStore().requestAuthorization(toShare: [], read: types)
  }

  @concurrent nonisolated private static func readQuantities(
    start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar,
    cryptography: any ServerCryptography
  ) async throws -> [HealthQuantity] {
    guard start < end, end.timeIntervalSince(start) <= 32 * 86_400,
      HKHealthStore.isHealthDataAvailable()
    else {
      throw HealthDataError.invalidData
    }
    let store = HKHealthStore()
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    var result: [HealthQuantity] = []
    for metric in metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
      try Task.checkCancellation()
      guard let (identifier, unit) = type(metric) else { continue }
      if [.steps, .activeEnergy, .distance].contains(metric) {
        let values = try await HKStatisticsCollectionQueryDescriptor(
          predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
          options: .cumulativeSum,
          anchorDate: calendar.startOfDay(for: start),
          intervalComponents: DateComponents(
            calendar: calendar, timeZone: calendar.timeZone, day: 1)
        ).result(for: store)
        for index in 0..<33 {
          guard
            let day = calendar.date(
              byAdding: .day, value: index, to: calendar.startOfDay(for: start)), day < end,
            let next = calendar.date(byAdding: .day, value: 1, to: day)
          else { break }
          guard let quantity = values.statistics(for: day)?.sumQuantity() else { continue }
          let value = quantity.doubleValue(for: unit)
          guard metric.accepts(value) else { throw HealthDataError.invalidData }
          result.append(
            HealthQuantity(
              id: try identity(
                metric.rawValue, source: "appleHealth", start: day, end: next,
                cryptography: cryptography), metric: metric,
              start: day, end: min(next, end), value: value, sourceID: "appleHealth",
              sourceName: "Apple Health"))
        }
      } else {
        let samples = try await HKSampleQueryDescriptor(
          predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
          sortDescriptors: [SortDescriptor(\.startDate)], limit: 100_001
        ).result(for: store)
        guard result.count + samples.count <= 100_000 else { throw HealthDataError.invalidData }
        for sample in samples where sample.startDate <= end && sample.endDate >= start {
          let fraction = sample.quantity.doubleValue(for: unit)
          let value =
            [.bodyFatPercentage, .bloodOxygen].contains(metric) ? fraction * 100 : fraction
          guard metric.accepts(value) else { continue }
          result.append(
            HealthQuantity(
              id: sample.uuid, metric: metric, start: sample.startDate, end: sample.endDate,
              value: value,
              sourceID: sample.sourceRevision.source.bundleIdentifier,
              sourceName: sample.sourceRevision.source.name))
        }
      }
    }
    return result
  }

  nonisolated private static func identity(
    _ metric: String, source: String, start: Date, end: Date, cryptography: any ServerCryptography
  ) throws -> UUID {
    let hash = Array(
      cryptography.sha256(
        Data(
          "appleHealth|\(metric)|\(source)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)"
            .utf8)
      ).prefix(32))
    guard hash.count == 32,
      let id = UUID(
        uuidString: String(hash[0..<8]) + "-" + String(hash[8..<12]) + "-" + String(hash[12..<16])
          + "-" + String(hash[16..<20]) + "-" + String(hash[20..<32]))
    else { throw HealthDataError.invalidData }
    return id
  }
}
