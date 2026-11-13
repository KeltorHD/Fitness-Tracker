import Foundation

/// A server version of one native, fused calendar bucket; raw device samples are never summed.
public struct HealthSyncBucket: Codable, Equatable, Hashable, Sendable {
  public let metric: HealthMetric
  public let start: Date
  public let end: Date
  public let timeZoneID: String
  public let revision: Int64
  public let excludedIDs: [UUID]
  public var key: String {
    metric.rawValue + "|" + timeZoneID + "|" + String(start.timeIntervalSince1970)
  }
  private enum CodingKeys: String, CodingKey {
    case metric, start, end, revision
    case timeZoneID = "timeZoneId"
    case excludedIDs = "excludedIds"
  }
  public init(
    metric: HealthMetric, start: Date, end: Date, timeZoneID: String, revision: Int64,
    excludedIDs: [UUID] = []
  ) {
    self.metric = metric
    self.start = start
    self.end = end
    self.timeZoneID = timeZoneID
    self.revision = revision
    self.excludedIDs = excludedIDs
  }
  public func validate() throws {
    guard [.steps, .activeEnergy, .distance].contains(metric), revision > 0,
      start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
      end > start, end.timeIntervalSince(start) <= 26 * 3600,
      excludedIDs.count <= 10_000, Set(excludedIDs).count == excludedIDs.count,
      timeZoneID.utf8.count <= 80, let zone = TimeZone(identifier: timeZoneID)
    else { throw HealthDataError.invalidData }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let day = calendar.dateInterval(of: .day, for: start), day.start == start, day.end == end
    else { throw HealthDataError.invalidData }
  }
}

public struct HealthSyncAggregate: Codable, Equatable, Sendable {
  public let bucket: HealthSyncBucket
  public let value: Double?
  public init(bucket: HealthSyncBucket, value: Double?) {
    self.bucket = bucket
    self.value = value
  }
}

public struct HealthSyncBatch: Codable, Equatable, Sendable {
  public let deviceID: UUID
  public let sequence: Int64
  public let batchID: UUID
  public let timeZoneID: String
  public let observedAt: Date
  public let quantities: [HealthQuantity]
  public let sleep: [HealthSleepRecord]
  public let deletedIDs: [UUID]
  public let aggregates: [HealthSyncAggregate]
  private enum CodingKeys: String, CodingKey {
    case sequence, observedAt, quantities, sleep, aggregates
    case deviceID = "deviceId"
    case batchID = "batchId"
    case timeZoneID = "timeZoneId"
    case deletedIDs = "deletedIds"
  }
  public init(
    deviceID: UUID, sequence: Int64, batchID: UUID = UUID(), timeZoneID: String, observedAt: Date,
    quantities: [HealthQuantity] = [], sleep: [HealthSleepRecord] = [], deletedIDs: [UUID] = [],
    aggregates: [HealthSyncAggregate] = []
  ) throws {
    self.deviceID = deviceID
    self.sequence = sequence
    self.batchID = batchID
    self.timeZoneID = timeZoneID
    self.observedAt = observedAt
    self.quantities = quantities
    self.sleep = sleep
    self.deletedIDs = deletedIDs
    self.aggregates = aggregates
    try validate()
  }
  public func validate() throws {
    let ids = quantities.map(\.id) + sleep.map(\.id) + deletedIDs
    guard sequence > 0, observedAt.timeIntervalSince1970.isFinite,
      timeZoneID.utf8.count <= 80, TimeZone(identifier: timeZoneID) != nil,
      ids.count <= 1000, Set(ids).count == ids.count, aggregates.count <= 100,
      Set(aggregates.map { $0.bucket.key }).count == aggregates.count,
      aggregates.reduce(0, { $0 + $1.bucket.excludedIDs.count }) <= 10_000
    else { throw HealthDataError.invalidData }
    for quantity in quantities {
      try quantity.validate()
      guard quantity.metric != .totalEnergy,
        quantity.end.timeIntervalSince(quantity.start) <= 7 * 86_400
      else { throw HealthDataError.invalidData }
    }
    for record in sleep {
      try record.validate()
      guard record.asleepSeconds == nil, record.segments.count == 1,
        record.segments[0].id == record.id, record.segments[0].start == record.start,
        record.segments[0].end == record.end
      else { throw HealthDataError.invalidData }
    }
    for aggregate in aggregates {
      try aggregate.bucket.validate()
      if let value = aggregate.value, !aggregate.bucket.metric.accepts(value) {
        throw HealthDataError.invalidData
      }
    }
  }
}

public struct HealthSyncAcknowledgement: Codable, Equatable, Sendable {
  public let batchID: UUID
  public let sequence: Int64
  public let buckets: [HealthSyncBucket]
  private enum CodingKeys: String, CodingKey {
    case sequence, buckets
    case batchID = "batchId"
  }
  public init(batchID: UUID, sequence: Int64, buckets: [HealthSyncBucket]) {
    self.batchID = batchID
    self.sequence = sequence
    self.buckets = buckets
  }
  public func validate(for batch: HealthSyncBatch) throws {
    guard batchID == batch.batchID, sequence == batch.sequence, buckets.count <= 2000,
      Set(buckets.map(\.key)).count == buckets.count
    else { throw HealthDataError.invalidData }
    guard buckets.reduce(0, { $0 + $1.excludedIDs.count }) <= 10_000 else {
      throw HealthDataError.invalidData
    }
    for bucket in buckets { try bucket.validate() }
  }
}

public enum HealthSyncFailure: Error, Sendable { case stateConflict, limit }

/// Health HTTP DTOs use ISO 8601; the independent training journal and local sync-state files use Unix seconds.
public enum HealthSyncCoding {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
    }
    return encoder
  }
  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
      }
      return try Date.ISO8601FormatStyle().parse(value)
    }
    return decoder
  }
}
