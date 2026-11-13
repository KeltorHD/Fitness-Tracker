import Foundation
import Testing

@testable import FitLifeCore

private let healthTestStart = Date(timeIntervalSince1970: 1_700_006_400)

private func healthQuantity(
  _ metric: HealthMetric, value: Double, id: UUID = UUID(), offset: TimeInterval = 0
) -> HealthQuantity {
  HealthQuantity(
    id: id, metric: metric, start: healthTestStart.addingTimeInterval(offset),
    end: healthTestStart.addingTimeInterval(offset), value: value, sourceID: "miFitness",
    sourceName: "Mi Fitness")
}

private func healthSnapshot(
  _ quantities: [HealthQuantity],
  metrics: Set<HealthMetric> = [.steps, .bodyWeight, .activeEnergy, .totalEnergy]
) throws -> HealthDataSnapshot {
  try HealthDataSnapshot(
    provider: .miFitness, start: healthTestStart, end: healthTestStart.addingTimeInterval(3600),
    fetchedAt: healthTestStart.addingTimeInterval(3601), metrics: metrics, quantities: quantities,
    sleep: [])
}

@Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 1000.01])
func healthWeightRejectsInvalidNumbers(_ value: Double) {
  #expect(throws: HealthDataError.invalidData) {
    try healthQuantity(.bodyWeight, value: value).validate()
  }
}

@Test func healthMetricsPreserveTheirUnitsAndExactStepCounts() throws {
  try healthQuantity(.bodyWeight, value: 75.125).validate()
  try healthQuantity(.bodyFatPercentage, value: 18.5).validate()
  try healthQuantity(.bloodOxygen, value: 98).validate()
  try healthQuantity(.heartRate, value: 75.25).validate()
  #expect(throws: HealthDataError.invalidData) { try healthQuantity(.steps, value: 2.5).validate() }
  #expect(throws: HealthDataError.invalidData) {
    try healthQuantity(.heartRate, value: 301).validate()
  }
  #expect(throws: HealthDataError.invalidData) {
    try healthQuantity(.bodyFatPercentage, value: 101).validate()
  }
}

@Test func healthTotalsDistinguishMissingDataFromZeroAndTotalFromActiveEnergy() throws {
  let value = try healthSnapshot([
    healthQuantity(.steps, value: 0), healthQuantity(.totalEnergy, value: 2000),
  ])
  let interval = DateInterval(start: healthTestStart, duration: 3600)
  #expect(value.total(.steps, during: interval) == 0)
  #expect(value.total(.totalEnergy, during: interval) == 2000)
  #expect(value.total(.activeEnergy, during: interval) == nil)
  #expect(value.total(.bodyWeight, during: interval) == nil)
  #expect(value.latest(.bodyWeight) == nil)
}

@Test func healthSnapshotsRejectDuplicateIdentityAndUnrequestedMetrics() throws {
  let first = healthQuantity(.steps, value: 100)
  #expect(throws: HealthDataError.invalidData) { try healthSnapshot([first, first]) }
  #expect(throws: HealthDataError.invalidData) {
    try healthSnapshot([first], metrics: [.bodyWeight])
  }
  #expect(throws: HealthDataError.invalidData) {
    try healthSnapshot([healthQuantity(.steps, value: 1, offset: -1)])
  }
}

@Test func healthDecodingCannotBypassDataValidationAndPreservesSourceIdentity() throws {
  let expected = try healthSnapshot([healthQuantity(.bodyWeight, value: 75.25)])
  let encoder = JSONEncoder()
  let data = try encoder.encode(expected)
  #expect(try JSONDecoder().decode(HealthDataSnapshot.self, from: data) == expected)
  var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var records = try #require(json["quantities"] as? [[String: Any]])
  #expect(records[0]["sourceId"] as? String == "miFitness")
  records[0]["value"] = -75
  json["quantities"] = records
  let invalid = try JSONSerialization.data(withJSONObject: json)
  #expect(throws: HealthDataError.invalidData) {
    try JSONDecoder().decode(HealthDataSnapshot.self, from: invalid)
  }
}

@Test func healthLatestWeightDoesNotSumMeasurementsOrMixMetrics() throws {
  let old = healthQuantity(.bodyWeight, value: 75.25)
  let latest = healthQuantity(.bodyWeight, value: 75, offset: 10)
  let value = try healthSnapshot([latest, healthQuantity(.steps, value: 100, offset: 20), old])
  #expect(value.latest(.bodyWeight) == latest)
  #expect(
    value.total(.bodyWeight, during: DateInterval(start: healthTestStart, duration: 3600)) == nil)
}

@Test func healthSleepReportWithoutPhasesKeepsActualTotalAndNoSyntheticTimeline() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)))
  let start = day.addingTimeInterval(3600)
  let end = start.addingTimeInterval(8 * 3600)
  let record = HealthSleepRecord(
    id: UUID(), start: start, end: end, asleepSeconds: 6 * 3600,
    sourceID: "miFitness", sourceName: "Mi Fitness", segments: [])
  let snapshot = try HealthDataSnapshot(
    provider: .miFitness, start: day.addingTimeInterval(-12 * 3600),
    end: day.addingTimeInterval(12 * 3600), fetchedAt: end, metrics: [.sleep], quantities: [],
    sleep: [record])
  let night = try #require(snapshot.nights(endingOn: day, count: 1, calendar: calendar).first)
  #expect(night.asleep == 21_600.0)
  #expect(night.sleepStart == start)
  #expect(night.sleepEnd == end)
  #expect(night.sourceName == "Mi Fitness")
  #expect(night.periods.isEmpty)
  #expect(!night.hasStages)
  #expect(night.efficiency == nil)
  #expect(night.sleepOnsetLatency == nil)
}

@Test func healthSleepRejectsInvalidReportedDurationAndOutOfBoundsPhases() {
  let end = healthTestStart.addingTimeInterval(3600)
  let invalid = HealthSleepRecord(
    id: UUID(), start: healthTestStart, end: end, asleepSeconds: 3601,
    sourceID: "miFitness", sourceName: "Mi Fitness", segments: [])
  #expect(throws: HealthDataError.invalidData) { try invalid.validate() }
  let segment = HealthSleepSegment(
    id: UUID(), start: healthTestStart.addingTimeInterval(-1), end: end, stage: .deep)
  let outside = HealthSleepRecord(
    id: UUID(), start: healthTestStart, end: end, asleepSeconds: nil,
    sourceID: "miFitness", sourceName: "Mi Fitness", segments: [segment])
  #expect(throws: HealthDataError.invalidData) { try outside.validate() }
}

@Test func healthSleepSummaryIsNotProportionallyFabricatedAcrossDiaryBoundary() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)))
  let window = try #require(SleepNight.window(endingOn: day, calendar: calendar))
  let summary = try SleepNightSummary(
    start: window.start.addingTimeInterval(-3600), end: day,
    asleepSeconds: 6 * 3600, sourceName: "Mi Fitness")
  let night = SleepNight(day: day, calendar: calendar, samples: [], reportedSummary: summary)
  #expect(night.asleep == nil)
  #expect(night.periods.isEmpty)
}

@Test func healthSleepAddsDisjointReportsButDoesNotAddDevicesOrOverlaps() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)))
  func record(_ hour: Double, _ length: Double, source: String = "watch") -> HealthSleepRecord {
    HealthSleepRecord(
      id: UUID(), start: day.addingTimeInterval(hour * 3600),
      end: day.addingTimeInterval((hour + length) * 3600),
      asleepSeconds: length * 3600, sourceID: source, sourceName: source, segments: [])
  }
  func night(_ reports: [HealthSleepRecord]) throws -> SleepNight {
    try #require(
      HealthDataSnapshot(
        provider: .miFitness, start: day.addingTimeInterval(-12 * 3600),
        end: day.addingTimeInterval(12 * 3600), fetchedAt: day, metrics: [.sleep], quantities: [],
        sleep: reports
      )
      .nights(endingOn: day, count: 1, calendar: calendar, cached: true).first)
  }
  let total = try night([record(0, 6), record(9, 1), record(0, 6, source: "band")])
  // Equal source totals use lexical identity, so choose the watch with an explicitly longer night.
  let naps = try night([record(0, 7), record(9, 1), record(0, 6, source: "band")])
  #expect(naps.asleep == 28_800.0)
  #expect(naps.sourceID == "watch")
  #expect(total.asleep == 21_600.0)
  let overlaps = try night([record(0, 6), record(1, 6)])
  #expect(overlaps.asleep == 21_600.0)
  #expect(overlaps.periods.isEmpty)
  #expect(overlaps.isCached)
  #expect(overlaps.fetchedAt == day)
}

@Test func healthSummaryFetchMetadataDoesNotCountAsChangedMeasurements() {
  let first = HealthDaySummary(
    day: healthTestStart, steps: 0, activeEnergyKCal: nil, sleepSeconds: nil,
    latestHeartRate: nil, heartRateSource: nil, fetchedAt: healthTestStart)
  let cached = HealthDaySummary(
    day: healthTestStart, steps: 0, activeEnergyKCal: nil, sleepSeconds: nil,
    latestHeartRate: nil, heartRateSource: nil, fetchedAt: healthTestStart.addingTimeInterval(60),
    isCached: true)
  #expect(first.hasSameValues(as: cached))
}
