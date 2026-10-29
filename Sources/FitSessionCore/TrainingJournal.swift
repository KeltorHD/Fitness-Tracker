import Foundation

public struct JournalWeek: Identifiable, Equatable, Sendable {
  public var id: Date { start }
  public let start: Date
  public let workouts: [Workout]
  public let personalRecords: Int
}

public struct TrainingCalendarDay: Identifiable, Equatable, Sendable {
  public var id: Date { date }
  public let date: Date
  public let isInMonth: Bool
  public let hasWorkout: Bool
  public init(date: Date, isInMonth: Bool, hasWorkout: Bool) {
    self.date = date
    self.isInMonth = isInMonth
    self.hasWorkout = hasWorkout
  }
}

public enum TrainingJournal {
  public static func weeks(
    in workouts: [Workout], on day: Date? = nil, now: Date = Date(), calendar: Calendar = .current
  ) -> [JournalWeek] {
    let completed = workouts.filter { $0.status == .completed && $0.startedAt <= now }
    let records = recordCounts(in: completed)
    // A day filter must preserve record comparisons against the entire preceding history.
    let visible =
      day.map { day in
        completed.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
      } ?? completed
    let grouped = Dictionary(grouping: visible) {
      calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start
        ?? calendar.startOfDay(for: $0.startedAt)
    }
    return grouped.map { start, sessions in
      JournalWeek(
        start: start, workouts: sessions.sorted { $0.startedAt > $1.startedAt },
        personalRecords: sessions.reduce(0) { $0 + (records[$1.id] ?? 0) })
    }.sorted { $0.start > $1.start }
  }

  /// Count one new maximum working weight per exercise/session, excluding warmups/bodyweight.
  public static func recordCounts(in workouts: [Workout]) -> [UUID: Int] {
    var best: [UUID: Double] = [:]
    var counts: [UUID: Int] = [:]
    let ordered = workouts.filter { $0.status == .completed }.sorted {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
    }
    for workout in ordered {
      var maximums: [UUID: Double] = [:]
      for item in workout.exercises {
        let weight =
          item.sets.filter { $0.completedAt != nil && !$0.isWarmup }.map(\.weightKG).max() ?? 0
        maximums[item.exercise.id] = max(maximums[item.exercise.id] ?? 0, weight)
      }
      var count = 0
      for (id, weight) in maximums where weight > (best[id] ?? 0) {
        best[id] = weight
        count += 1
      }
      counts[workout.id] = count
    }
    return counts
  }

  public static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
    guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  public static func monthDays(
    containing date: Date, workouts: [Workout], now: Date = Date(), calendar: Calendar = .current
  ) -> [TrainingCalendarDay] {
    guard let month = calendar.dateInterval(of: .month, for: date),
      let days = calendar.range(of: .day, in: .month, for: date)
    else { return [] }
    let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
    guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else {
      return []
    }
    let count = ((offset + days.count + 6) / 7) * 7
    let trainedDays = Set(
      workouts.filter { $0.status == .completed && $0.startedAt <= now }.map {
        calendar.startOfDay(for: $0.startedAt)
      })
    return (0..<count).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
      return TrainingCalendarDay(
        date: day, isInMonth: day >= month.start && day < month.end,
        hasWorkout: trainedDays.contains(calendar.startOfDay(for: day)))
    }
  }
}
