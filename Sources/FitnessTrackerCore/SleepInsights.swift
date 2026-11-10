import Foundation

extension SleepNight {
  /// Only recorded awake intervals between the first and last sleep sample; gaps remain unknown.
  public var awakeDuration: TimeInterval? {
    guard let start = sleepStart, let end = sleepEnd,
      periods.contains(where: { $0.stage == .awake })
    else { return nil }
    return periods.filter {
      $0.stage == .awake && $0.interval.start >= start && $0.interval.end <= end
    }
    .reduce(0) { $0 + $1.interval.duration }
  }
  public var longestSleepEpisode: TimeInterval? {
    var best: TimeInterval = 0
    var running: TimeInterval = 0
    var end: Date?
    for period in periods {
      guard period.stage.isAsleep else {
        running = 0
        end = nil
        continue
      }
      running =
        end == period.interval.start ? running + period.interval.duration : period.interval.duration
      end = period.interval.end
      best = max(best, running)
    }
    return best > 0 ? best : nil
  }
  public func fraction(_ stage: SleepStage) -> Double? {
    guard stage.isAsleep, let asleep else { return nil }
    return duration(stage) / asleep
  }
  public func period(at date: Date) -> SleepPeriod? {
    guard date.timeIntervalSince1970.isFinite else { return nil }
    return periods.first { $0.interval.start <= date && date < $0.interval.end }
  }
}

public struct SleepTrend: Sendable {
  public let nights: [SleepNight]
  public let recorded: [SleepNight]
  public let average: TimeInterval?
  public let shortest: TimeInterval?
  public let longest: TimeInterval?
  public init(nights: [SleepNight], endingOn day: Date, days: Int, calendar: Calendar) {
    let end = calendar.startOfDay(for: day)
    let start = calendar.date(byAdding: .day, value: -(max(1, min(30, days)) - 1), to: end) ?? end
    self.nights = nights.filter { $0.day >= start && $0.day <= end }.sorted { $0.day < $1.day }
    recorded = self.nights.filter { $0.asleep != nil }
    let durations = recorded.compactMap(\.asleep)
    average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
    shortest = durations.min()
    longest = durations.max()
  }
  public func night(at date: Date, calendar: Calendar) -> SleepNight? {
    nights.first { calendar.isDate($0.day, inSameDayAs: date) }
  }
  public func differenceFromPrevious(_ night: SleepNight, calendar: Calendar) -> TimeInterval? {
    guard let previous = calendar.date(byAdding: .day, value: -1, to: night.day),
      let currentDuration = night.asleep,
      let previousDuration = self.night(at: previous, calendar: calendar)?.asleep
    else { return nil }
    return currentDuration - previousDuration
  }
}
