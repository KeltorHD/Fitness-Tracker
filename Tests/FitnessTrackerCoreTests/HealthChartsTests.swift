import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func healthChartWindowUsesCalendarDaysAcrossDSTAndClipsToday() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
  let day = try #require(calendar.date(from: DateComponents(year: 2024, month: 3, day: 31)))
  let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: day))
  let historical = try HealthChartWindow(day: day, now: tomorrow, calendar: calendar)
  #expect(historical.day.duration == 23 * 3600)
  #expect(historical.stepDays.count == 7)
  #expect(calendar.component(.day, from: historical.stepDays[0]) == 25)
  #expect(historical.stepDays.last == day)
  let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
  let current = try HealthChartWindow(day: day, now: noon, calendar: calendar)
  #expect(current.day.end == noon)
  #expect(current.stepsInterval.end == noon)
  #expect(throws: TrainingError.invalidDate) {
    try HealthChartWindow(day: tomorrow, now: noon, calendar: calendar)
  }
}

@Test func heartRateChartRejectsInvalidPointsAndBreaksAtGapsAndPauses() {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  func reading(_ seconds: Double, _ bpm: Double = 90) -> HeartRateReading {
    HeartRateReading(date: start.addingTimeInterval(seconds), beatsPerMinute: bpm)
  }
  let points = HeartRateChartPoint.make(
    readings: [reading(50), reading(5), reading(0), reading(5), reading(10), reading(20, .nan)],
    pauses: [
      WorkoutPause(startedAt: start.addingTimeInterval(6), endedAt: start.addingTimeInterval(8))
    ])
  #expect(points.map(\.reading.date) == [0.0, 5, 10, 50].map { start.addingTimeInterval($0) })
  #expect(points.map(\.segment) == [0, 0, 1, 2])
}

@Test func heartRateChartThinningRetainsEndpointsAndSegmentIdentity() {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  let readings = (0..<5_000).map {
    HeartRateReading(date: start.addingTimeInterval(Double($0) * 5), beatsPerMinute: 80)
  }
  let points = HeartRateChartPoint.make(readings: readings, maximumPoints: 100)
  #expect(points.count == 100)
  #expect(points.first?.reading == readings.first)
  #expect(points.last?.reading == readings.last)
  #expect(points.allSatisfy { $0.segment == 0 })
  #expect(HeartRateChartPoint.make(readings: readings, maximumPoints: 1).isEmpty)
}

@Test func heartRateSelectionSnapsToSamplesAndDoesNotInterpolateAcrossGaps() throws {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  let points = HeartRateChartPoint.make(readings: [
    HeartRateReading(date: start, beatsPerMinute: 80),
    HeartRateReading(date: start.addingTimeInterval(10), beatsPerMinute: 95.5),
    HeartRateReading(date: start.addingTimeInterval(100), beatsPerMinute: 130),
  ])
  #expect(HeartRateChartPoint.nearest(to: start, in: []) == nil)
  #expect(HeartRateChartPoint.nearest(to: Date(timeIntervalSince1970: .nan), in: points) == nil)
  #expect(HeartRateChartPoint.nearest(to: start.addingTimeInterval(-1), in: points) == points.first)
  #expect(HeartRateChartPoint.nearest(to: start.addingTimeInterval(101), in: points) == points.last)
  #expect(HeartRateChartPoint.nearest(to: start.addingTimeInterval(5), in: points) == points[0])
  #expect(HeartRateChartPoint.nearest(to: start.addingTimeInterval(6), in: points) == points[1])
  #expect(HeartRateChartPoint.nearest(to: start.addingTimeInterval(10), in: points) == points[1])
  let gapPoint = try #require(
    HeartRateChartPoint.nearest(to: start.addingTimeInterval(60), in: points))
  #expect(gapPoint == points[2])
  #expect(gapPoint.reading.date == start.addingTimeInterval(100))
  #expect(HeartRateChartPoint.nearest(to: start, in: [points[1]]) == points[1])
}
