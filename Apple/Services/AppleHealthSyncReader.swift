import FitLifeCore
import Foundation
import HealthKit

@MainActor final class AppleHealthSyncReader: AppleHealthSyncReading {
  func authorize() async throws {
    _ = try await AppleHealthDataProvider().authorize(
      metrics: Set(HealthMetric.allCases).subtracting([.totalEnergy]))
  }
  func page(metric: HealthMetric, since: Date, anchor: Data?) async throws -> HealthAnchoredPage {
    try await Self.readPage(metric: metric, since: since, encodedAnchor: anchor)
  }
  func aggregate(_ bucket: HealthSyncBucket) async throws -> Double? {
    try await Self.readAggregate(bucket)
  }
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { await Self.observe(since: since, continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  @concurrent nonisolated private static func readPage(
    metric: HealthMetric, since: Date, encodedAnchor: Data?
  ) async throws -> HealthAnchoredPage {
    guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }
    let anchor = try encodedAnchor.map { bytes in
      guard
        let result = try NSKeyedUnarchiver.unarchivedObject(
          ofClass: HKQueryAnchor.self, from: bytes)
      else { throw HealthDataError.invalidData }
      return result
    }
    let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
    let store = HKHealthStore()
    if metric == .sleep {
      let result = try await HKAnchoredObjectQueryDescriptor(
        predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
        anchor: anchor, limit: 200
      ).result(for: store)
      var records: [HealthSleepRecord] = []
      for sample in result.addedSamples {
        let stage: SleepStage
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: stage = .inBed
        case .awake: stage = .awake
        case .asleepCore: stage = .core
        case .asleepDeep: stage = .deep
        case .asleepREM: stage = .rem
        case .asleepUnspecified: stage = .unspecified
        default: continue
        }
        guard sample.endDate > sample.startDate else { continue }
        let record = HealthSleepRecord(
          id: sample.uuid, start: sample.startDate, end: sample.endDate, asleepSeconds: nil,
          sourceID: source(sample), sourceName: sample.sourceRevision.source.name,
          segments: [
            HealthSleepSegment(
              id: sample.uuid, start: sample.startDate, end: sample.endDate, stage: stage)
          ])
        try record.validate()
        records.append(record)
      }
      let deleted = Set(result.deletedObjects.map(\.uuid))
      return HealthAnchoredPage(
        quantities: [], sleep: records.filter { !deleted.contains($0.id) },
        deletedIDs: Array(deleted),
        anchor: try NSKeyedArchiver.archivedData(
          withRootObject: result.newAnchor, requiringSecureCoding: true),
        exhausted: result.addedSamples.isEmpty && result.deletedObjects.isEmpty)
    }
    guard let (identifier, unit) = AppleHealthDataProvider.type(metric) else {
      throw HealthDataError.unsupportedMetric
    }
    let result = try await HKAnchoredObjectQueryDescriptor(
      predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
      anchor: anchor, limit: 200
    ).result(for: store)
    let quantities = try result.addedSamples.map { sample in
      let fraction = sample.quantity.doubleValue(for: unit)
      let value = [.bodyFatPercentage, .bloodOxygen].contains(metric) ? fraction * 100 : fraction
      let result = HealthQuantity(
        id: sample.uuid, metric: metric, start: sample.startDate, end: sample.endDate, value: value,
        sourceID: source(sample), sourceName: sample.sourceRevision.source.name)
      try result.validate()
      return result
    }
    let deleted = Set(result.deletedObjects.map(\.uuid))
    return HealthAnchoredPage(
      quantities: quantities.filter { !deleted.contains($0.id) }, sleep: [],
      deletedIDs: Array(deleted),
      anchor: try NSKeyedArchiver.archivedData(
        withRootObject: result.newAnchor, requiringSecureCoding: true),
      exhausted: result.addedSamples.isEmpty && result.deletedObjects.isEmpty)
  }

  @concurrent nonisolated private static func readAggregate(_ bucket: HealthSyncBucket) async throws
    -> Double?
  {
    try bucket.validate()
    guard let zone = TimeZone(identifier: bucket.timeZoneID),
      let (identifier, unit) = AppleHealthDataProvider.type(bucket.metric)
    else { throw HealthDataError.invalidData }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard bucket.start < Date() else { return nil }
    let dates = HKQuery.predicateForSamples(
      withStart: bucket.start, end: min(bucket.end, Date()), options: [])
    let predicate =
      bucket.excludedIDs.isEmpty
      ? dates
      : NSCompoundPredicate(andPredicateWithSubpredicates: [
        dates,
        NSCompoundPredicate(
          notPredicateWithSubpredicate: HKQuery.predicateForObjects(with: Set(bucket.excludedIDs))),
      ])
    let result = try await HKStatisticsCollectionQueryDescriptor(
      predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
      options: .cumulativeSum, anchorDate: bucket.start,
      intervalComponents: DateComponents(calendar: calendar, timeZone: zone, day: 1)
    ).result(for: HKHealthStore())
    guard let quantity = result.statistics(for: bucket.start)?.sumQuantity() else { return nil }
    let value = quantity.doubleValue(for: unit)
    guard bucket.metric.accepts(value) else { throw HealthDataError.invalidData }
    return value
  }
  nonisolated private static func source(_ sample: HKSample) -> String {
    let prefix = sample.sourceRevision.productType?.hasPrefix("Watch") == true ? "watch:" : ""
    return prefix + sample.sourceRevision.source.bundleIdentifier + "|"
      + (sample.sourceRevision.productType ?? "")
  }

  @concurrent nonisolated private static func observe(
    since: Date, continuation: AsyncThrowingStream<Void, any Error>.Continuation
  ) async {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for metric in HealthMetric.allCases where metric != .totalEnergy {
          group.addTask {
            try await observeMetric(metric, since: since, continuation: continuation)
          }
        }
        for try await _ in group {}
      }
      continuation.finish()
    } catch { continuation.finish(throwing: error) }
  }
  @concurrent nonisolated private static func observeMetric(
    _ metric: HealthMetric, since: Date,
    continuation: AsyncThrowingStream<Void, any Error>.Continuation
  ) async throws {
    let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
    let store = HKHealthStore()
    if metric == .sleep {
      let query = HKAnchoredObjectQueryDescriptor(
        predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
        anchor: nil, limit: 1)
      for try await _ in query.results(for: store) {
        try Task.checkCancellation()
        continuation.yield(())
      }
    } else if let (identifier, _) = AppleHealthDataProvider.type(metric) {
      let query = HKAnchoredObjectQueryDescriptor(
        predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
        anchor: nil, limit: 1)
      for try await _ in query.results(for: store) {
        try Task.checkCancellation()
        continuation.yield(())
      }
    }
  }
}
