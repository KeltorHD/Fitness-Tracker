import Foundation

public struct HealthChartWindow: Sendable {
  public let day: DateInterval
  public let stepDays: [Date]
  public let stepsInterval: DateInterval

  public init(day: Date, now: Date = Date(), calendar: Calendar = .current) throws {
    guard day.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
      let interval = calendar.dateInterval(of: .day, for: day), interval.start <= now,
      let start = calendar.date(byAdding: .day, value: -6, to: interval.start)
    else { throw TrainingError.invalidDate }
    self.day = DateInterval(start: interval.start, end: min(interval.end, now))
    stepDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    guard stepDays.count == 7 else { throw TrainingError.invalidDate }
    stepsInterval = DateInterval(start: start, end: self.day.end)
  }
}

public struct HealthStepDay: Identifiable, Equatable, Sendable {
  public let date: Date
  public let steps: Int?
  public var id: Date { date }
  public init(date: Date, steps: Int?) {
    self.date = date
    self.steps = steps
  }
}

public struct HealthChartSnapshot: Equatable, Sendable {
  public let day: Date
  public let steps: [HealthStepDay]
  public let heartRate: [HeartRateReading]
  public let latestHeartRate: HeartRateReading?
  public let heartRateSource: String?
  public let currentDayHeartRate: [HeartRateReading]
  public init(
    day: Date, steps: [HealthStepDay], heartRate: [HeartRateReading],
    latestHeartRate: HeartRateReading?, heartRateSource: String?,
    currentDayHeartRate: [HeartRateReading] = []
  ) {
    self.day = day
    self.steps = steps
    self.heartRate = heartRate
    self.latestHeartRate = latestHeartRate
    self.heartRateSource = heartRateSource
    self.currentDayHeartRate = currentDayHeartRate
  }
}

@MainActor public protocol HealthChartsReading {
  func requestChartAuthorization() async throws
  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error>
  func stopChanges()
}

public struct HeartRateChartPoint: Identifiable, Equatable, Sendable {
  public let reading: HeartRateReading
  public let segment: Int
  public var id: Date { reading.date }

  /// Finds an actual plotted sample; points must be sorted by date, as returned by make().
  /// Equal distances choose the earlier sample, including across gaps; no interpolation.
  public static func nearest(to date: Date, in points: [Self]) -> Self? {
    guard date.timeIntervalSince1970.isFinite, !points.isEmpty else { return nil }
    var lower = 0
    var upper = points.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if points[middle].reading.date < date {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    guard lower > 0 else { return points.first }
    guard lower < points.count else { return points.last }
    let before = points[lower - 1]
    let after = points[lower]
    return date.timeIntervalSince(before.reading.date) <= after.reading.date.timeIntervalSince(date)
      ? before : after
  }

  /// Segment before thinning, so a chart never draws a line across an actual recording gap.
  public static func make(
    readings: [HeartRateReading], pauses: [WorkoutPause] = [], gap: TimeInterval = 30,
    maximumPoints: Int = 1_000
  ) -> [Self] {
    guard maximumPoints >= 2 else { return [] }
    var previous: Date?
    var segment = 0
    let points = readings.filter(\.isValid).sorted { $0.date < $1.date }.compactMap {
      reading -> Self? in
      if previous == reading.date { return nil }
      if let previous,
        reading.date.timeIntervalSince(previous) > gap
          || pauses.contains(where: { $0.startedAt >= previous && $0.startedAt <= reading.date })
      {
        segment += 1
      }
      previous = reading.date
      return Self(reading: reading, segment: segment)
    }
    guard points.count > maximumPoints else { return points }
    return (0..<maximumPoints).map { index in
      points[index * (points.count - 1) / (maximumPoints - 1)]
    }
  }
}
