import Foundation

/// A selected calendar week, including only completed sessions recorded by `now`.
public struct DiaryTrainingSummary: Equatable, Sendable {
  public let start: Date
  public let end: Date
  public let workouts: Int
  public let workingSets: Int
  public let volumeKG: Double
  public let duration: TimeInterval?
  public let trainedDays: Set<Date>

  public init(workouts: [Workout], day: Date, now: Date, calendar: Calendar) {
    let week = calendar.dateInterval(of: .weekOfYear, for: day)
    let start = week?.start ?? calendar.startOfDay(for: day)
    let end = week?.end ?? start
    self.start = start
    self.end = end
    let sessions = workouts.filter {
      $0.status == .completed && $0.startedAt >= start && $0.startedAt < end
        && $0.startedAt <= now
    }
    self.workouts = sessions.count
    workingSets =
      sessions.flatMap(\.exercises).flatMap(\.sets).filter {
        $0.completedAt != nil && !$0.isWarmup
      }.count
    volumeKG = sessions.reduce(0) { $0 + $1.volume }
    let durations = sessions.filter { $0.durationIsKnown != false && $0.endedAt != nil }
      .map { $0.duration(at: now) }
    duration = durations.isEmpty ? nil : durations.reduce(0, +)
    trainedDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
  }

  public func progress(goal: Int) -> Double {
    guard goal > 0 else { return 0 }
    return min(1, Double(workouts) / Double(goal))
  }
}

/// Resolves the chart's cumulative angle value, including exact end-point taps.
public enum DiaryRingSelection {
  public static func index(at value: Double, weights: [Double]) -> Int? {
    guard value.isFinite, value >= 0,
      weights.allSatisfy({ $0.isFinite && $0 >= 0 })
    else { return nil }
    let total = weights.reduce(0, +)
    guard total.isFinite, total > 0, value <= total else { return nil }
    var accumulated = 0.0
    for (index, weight) in weights.enumerated() where weight > 0 {
      accumulated += weight
      if value < accumulated { return index }
    }
    return weights.lastIndex(where: { $0 > 0 })
  }
}
