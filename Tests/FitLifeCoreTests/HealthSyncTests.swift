import Foundation
import Testing

@testable import FitLifeCore

private let syncDay = Date(timeIntervalSince1970: 1_711_756_800)

@Test func healthSyncWirePreservesNativeIdsAndServerDeletionExclusions() throws {
  let nativeID = UUID()
  let point = HealthQuantity(
    id: nativeID, metric: .bodyWeight, start: syncDay, end: syncDay, value: 72.35,
    sourceID: "source", sourceName: "Source")
  let batch = try HealthSyncBatch(
    deviceID: UUID(), sequence: 1, timeZoneID: "UTC", observedAt: syncDay, quantities: [point])
  let data = try HealthSyncCoding.encoder().encode(batch)
  let decoded = try HealthSyncCoding.decoder().decode(HealthSyncBatch.self, from: data)
  try decoded.validate()
  #expect(decoded == batch)
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(
    json["deviceId"] != nil && json["batchId"] != nil && json["timeZoneId"] != nil
      && json["deletedIds"] != nil)
  let bucket = HealthSyncBucket(
    metric: .steps, start: syncDay, end: syncDay.addingTimeInterval(86_400), timeZoneID: "UTC",
    revision: 2, excludedIDs: [nativeID])
  let ack = HealthSyncAcknowledgement(batchID: batch.batchID, sequence: 1, buckets: [bucket])
  let restored = try HealthSyncCoding.decoder().decode(
    HealthSyncAcknowledgement.self, from: HealthSyncCoding.encoder().encode(ack))
  try restored.validate(for: batch)
  #expect(restored.buckets[0].excludedIDs == [nativeID])
}

@Test func healthSyncRejectsAmbiguousIdsAndInventedSleepSummary() throws {
  let id = UUID()
  let point = HealthQuantity(
    id: id, metric: .steps, start: syncDay, end: syncDay, value: 10, sourceID: "source",
    sourceName: "Source")
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncBatch(
      deviceID: UUID(), sequence: 1, timeZoneID: "UTC", observedAt: syncDay, quantities: [point],
      deletedIDs: [id])
  }
  let report = HealthSleepRecord(
    id: id, start: syncDay, end: syncDay.addingTimeInterval(3600), asleepSeconds: 3600,
    sourceID: "source", sourceName: "Source", segments: [])
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncBatch(
      deviceID: UUID(), sequence: 1, timeZoneID: "UTC", observedAt: syncDay, sleep: [report])
  }
}

@Test func healthSyncCannotAcceptAnotherAcknowledgementOrDuplicateBucket() throws {
  let batch = try HealthSyncBatch(
    deviceID: UUID(), sequence: 2, timeZoneID: "UTC", observedAt: syncDay)
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncAcknowledgement(batchID: UUID(), sequence: 2, buckets: []).validate(for: batch)
  }
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncAcknowledgement(batchID: batch.batchID, sequence: 1, buckets: []).validate(
      for: batch)
  }
  let bucket = HealthSyncBucket(
    metric: .steps, start: syncDay, end: syncDay.addingTimeInterval(86_400), timeZoneID: "UTC",
    revision: 1)
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncAcknowledgement(batchID: batch.batchID, sequence: 2, buckets: [bucket, bucket])
      .validate(for: batch)
  }
}

@Test(arguments: [(3, 31, 23.0), (10, 27, 25.0)])
func healthSyncBucketsRespectDSTAndRejectArbitraryDayLengths(
  _ month: Int, _ day: Int, _ hours: Double
) throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
  let date = try #require(
    calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: 12)))
  let interval = try #require(calendar.dateInterval(of: .day, for: date))
  #expect(interval.duration == hours * 3600)
  try HealthSyncBucket(
    metric: .steps, start: interval.start, end: interval.end,
    timeZoneID: calendar.timeZone.identifier, revision: 1
  ).validate()
  #expect(throws: HealthDataError.invalidData) {
    try HealthSyncBucket(
      metric: .steps, start: interval.start, end: interval.start.addingTimeInterval(86_400),
      timeZoneID: calendar.timeZone.identifier, revision: 1
    ).validate()
  }
}

@Test func healthSyncMissingAggregateAndZeroRemainDifferent() throws {
  let bucket = HealthSyncBucket(
    metric: .steps, start: syncDay, end: syncDay.addingTimeInterval(86_400), timeZoneID: "UTC",
    revision: 1)
  let missing = try HealthSyncBatch(
    deviceID: UUID(), sequence: 1, timeZoneID: "UTC", observedAt: syncDay,
    aggregates: [HealthSyncAggregate(bucket: bucket, value: nil)])
  let zero = try HealthSyncBatch(
    deviceID: UUID(), sequence: 1, timeZoneID: "UTC", observedAt: syncDay,
    aggregates: [HealthSyncAggregate(bucket: bucket, value: 0)])
  #expect(missing.aggregates[0].value == nil)
  #expect(zero.aggregates[0].value == 0)
}
