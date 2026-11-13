import Foundation

public enum HealthProviderID: String, Codable, CaseIterable, Sendable {
  case appleHealth, miFitness
}

/// Units are part of the contract: kilograms, percentages, bpm, kcal and metres.
public enum HealthMetric: String, Codable, CaseIterable, Sendable {
  case sleep, steps, bodyWeight, bodyFatPercentage, heartRate, restingHeartRate
  case activeEnergy, totalEnergy, bloodOxygen, distance

  public func accepts(_ value: Double) -> Bool {
    guard value.isFinite else { return false }
    switch self {
    case .sleep: return false
    case .steps: return (0...1_000_000).contains(value) && value.rounded() == value
    case .bodyWeight: return value > 0 && value <= 1000
    case .bodyFatPercentage, .bloodOxygen: return (0...100).contains(value)
    case .heartRate, .restingHeartRate: return (1...300).contains(value)
    case .activeEnergy, .totalEnergy: return (0...100_000).contains(value)
    case .distance: return (0...10_000_000).contains(value)
    }
  }
}

public struct HealthQuantity: Identifiable, Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case id, metric, start, end, value, sourceName
    case sourceID = "sourceId"
  }
  public let id: UUID
  public let metric: HealthMetric
  public let start: Date
  public let end: Date
  public let value: Double
  public let sourceID: String
  public let sourceName: String

  public init(
    id: UUID, metric: HealthMetric, start: Date, end: Date, value: Double,
    sourceID: String, sourceName: String
  ) {
    self.id = id
    self.metric = metric
    self.start = start
    self.end = end
    self.value = value
    self.sourceID = sourceID
    self.sourceName = sourceName
  }

  public func validate() throws {
    guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
      end >= start, metric.accepts(value), !sourceID.isEmpty, sourceID.count <= 1024,
      !sourceName.isEmpty, sourceName.count <= 200
    else { throw HealthDataError.invalidData }
  }
}

public struct HealthSleepSegment: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let start: Date
  public let end: Date
  public let stage: SleepStage

  public init(id: UUID, start: Date, end: Date, stage: SleepStage) {
    self.id = id
    self.start = start
    self.end = end
    self.stage = stage
  }
}

/// A reported total is independent of stages: missing phases must never become a synthetic timeline.
public struct HealthSleepRecord: Identifiable, Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case id, start, end, asleepSeconds, sourceName, segments
    case sourceID = "sourceId"
  }
  public let id: UUID
  public let start: Date
  public let end: Date
  public let asleepSeconds: TimeInterval?
  public let sourceID: String
  public let sourceName: String
  public let segments: [HealthSleepSegment]

  public init(
    id: UUID, start: Date, end: Date, asleepSeconds: TimeInterval?, sourceID: String,
    sourceName: String, segments: [HealthSleepSegment]
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.asleepSeconds = asleepSeconds
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.segments = segments
  }

  public func validate() throws {
    guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
      end > start, end.timeIntervalSince(start) <= 7 * 86_400,
      !sourceID.isEmpty, sourceID.count <= 1024, !sourceName.isEmpty, sourceName.count <= 200,
      segments.count <= 10_000, Set(segments.map(\.id)).count == segments.count
    else { throw HealthDataError.invalidData }
    if let asleepSeconds {
      guard asleepSeconds.isFinite, asleepSeconds >= 0,
        asleepSeconds <= end.timeIntervalSince(start)
      else { throw HealthDataError.invalidData }
    }
    for segment in segments {
      guard segment.start.timeIntervalSince1970.isFinite,
        segment.end.timeIntervalSince1970.isFinite, segment.end > segment.start,
        segment.start >= start, segment.end <= end
      else { throw HealthDataError.invalidData }
    }
  }
}

public struct HealthDataSnapshot: Codable, Equatable, Sendable {
  public let provider: HealthProviderID
  public let start: Date
  public let end: Date
  public let fetchedAt: Date
  public let metrics: Set<HealthMetric>
  public let quantities: [HealthQuantity]
  public let sleep: [HealthSleepRecord]

  public init(
    provider: HealthProviderID, start: Date, end: Date, fetchedAt: Date,
    metrics: Set<HealthMetric>, quantities: [HealthQuantity], sleep: [HealthSleepRecord]
  ) throws {
    self.provider = provider
    self.start = start
    self.end = end
    self.fetchedAt = fetchedAt
    self.metrics = metrics
    self.quantities = quantities
    self.sleep = sleep
    try validate()
  }

  public func validate() throws {
    guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
      fetchedAt.timeIntervalSince1970.isFinite, end >= start,
      end.timeIntervalSince(start) <= 32 * 86_400,
      quantities.count <= 100_000, sleep.count <= 1000,
      sleep.reduce(0, { $0 + $1.segments.count }) <= 100_000,
      Set(quantities.map(\.id)).count == quantities.count,
      Set(sleep.map(\.id)).count == sleep.count,
      sleep.isEmpty || metrics.contains(.sleep)
    else { throw HealthDataError.invalidData }
    for quantity in quantities {
      try quantity.validate()
      guard metrics.contains(quantity.metric), quantity.start <= end, quantity.end >= start else {
        throw HealthDataError.invalidData
      }
    }
    for record in sleep {
      try record.validate()
      guard record.start < end, record.end > start else { throw HealthDataError.invalidData }
    }
  }

  private enum CodingKeys: CodingKey {
    case provider, start, end, fetchedAt, metrics, quantities, sleep
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      provider: container.decode(HealthProviderID.self, forKey: .provider),
      start: container.decode(Date.self, forKey: .start),
      end: container.decode(Date.self, forKey: .end),
      fetchedAt: container.decode(Date.self, forKey: .fetchedAt),
      metrics: container.decode(Set<HealthMetric>.self, forKey: .metrics),
      quantities: container.decode([HealthQuantity].self, forKey: .quantities),
      sleep: container.decode([HealthSleepRecord].self, forKey: .sleep))
  }

  public func latest(_ metric: HealthMetric) -> HealthQuantity? {
    quantities.filter { $0.metric == metric }.max {
      $0.end == $1.end ? $0.id.uuidString < $1.id.uuidString : $0.end < $1.end
    }
  }

  /// A query returns one provider's fused samples; UUIDs remain stable across repeated reads.
  public func total(_ metric: HealthMetric, during interval: DateInterval) -> Double? {
    guard [.steps, .activeEnergy, .totalEnergy, .distance].contains(metric) else { return nil }
    let values = quantities.filter {
      $0.metric == metric && $0.start >= interval.start && $0.start < interval.end
    }
    return values.isEmpty ? nil : values.reduce(0) { $0 + $1.value }
  }

  public func nights(endingOn day: Date, count: Int = 30, calendar: Calendar, cached: Bool = false)
    throws -> [SleepNight]
  {
    try validate()
    guard (1...30).contains(count) else { throw HealthDataError.invalidData }
    return try (-(count - 1)...0).map { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: day),
        let window = SleepNight.window(endingOn: date, calendar: calendar)
      else { throw TrainingError.invalidDate }
      let matching = sleep.filter { $0.start < window.end && $0.end > window.start }
      let samples = matching.flatMap { record in
        record.segments.map { segment in
          SleepSample(
            id: segment.id, interval: DateInterval(start: segment.start, end: segment.end),
            stage: segment.stage, sourceID: record.sourceID, sourceName: record.sourceName)
        }
      }
      let preferred = SleepNight(day: date, calendar: calendar, samples: samples).sourceID
      let groups = Dictionary(grouping: matching, by: \.sourceID)
      let source =
        preferred
        ?? groups.keys.sorted {
          let a = groups[$0, default: []].compactMap(\.asleepSeconds).max() ?? 0
          let b = groups[$1, default: []].compactMap(\.asleepSeconds).max() ?? 0
          return a == b ? $0 < $1 : a > b
        }.first
      let records = source.flatMap { groups[$0] }?.sorted { $0.start < $1.start } ?? []
      let summary: SleepNightSummary?
      if let first = records.first, let last = records.last,
        first.start >= window.start, last.end <= window.end,
        records.allSatisfy({ $0.asleepSeconds != nil }),
        zip(records, records.dropFirst()).allSatisfy({ $0.end <= $1.start })
      {
        summary = try SleepNightSummary(
          start: first.start, end: last.end,
          asleepSeconds: records.compactMap(\.asleepSeconds).reduce(0, +),
          sourceName: first.sourceName, sourceID: source)
      } else if samples.isEmpty,
        let report = records.filter({
          $0.start >= window.start && $0.end <= window.end && $0.asleepSeconds != nil
        }).max(by: {
          ($0.asleepSeconds ?? 0) < ($1.asleepSeconds ?? 0)
        }), let duration = report.asleepSeconds
      {
        // Overlapping reports cannot be added. Keep one actual report rather than estimating a union.
        summary = try SleepNightSummary(
          start: report.start, end: report.end, asleepSeconds: duration,
          sourceName: report.sourceName, sourceID: source)
      } else {
        summary = nil
      }
      return SleepNight(
        day: date, calendar: calendar, samples: samples, reportedSummary: summary,
        fetchedAt: fetchedAt, isCached: cached)
    }
  }
}

public enum HealthDataError: Error, Equatable, Sendable {
  case invalidData, unavailable, notConnected, permissionRequired, unsupportedMetric
}

@MainActor public protocol HealthDataProviding {
  var id: HealthProviderID { get }
  var supportedMetrics: Set<HealthMetric> { get }
  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric>
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
}
