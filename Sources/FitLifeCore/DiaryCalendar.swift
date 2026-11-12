import Foundation

public enum DiaryCalendarMode: String, Hashable, Sendable { case week, month }

public struct DiaryCalendarPage: Equatable, Sendable {
  public let date: Date
  public let days: [TrainingCalendarDay]
}

public enum DiaryCalendar {
  public static func shifted(
    _ date: Date, by offset: Int, mode: DiaryCalendarMode, calendar: Calendar
  ) -> Date? {
    guard date.timeIntervalSince1970.isFinite else { return nil }
    return calendar.date(byAdding: mode == .week ? .weekOfYear : .month, value: offset, to: date)
  }

  /// Only the visible period is selectable. Six month rows keep the calendar height stable.
  public static func page(
    containing date: Date, mode: DiaryCalendarMode, workouts: [Workout], now: Date,
    calendar: Calendar
  ) -> DiaryCalendarPage? {
    guard date.timeIntervalSince1970.isFinite,
      let month = calendar.dateInterval(of: .month, for: date)
    else { return nil }
    let trained = Set(
      workouts.filter { $0.status == .completed && $0.startedAt <= now }.map {
        calendar.startOfDay(for: $0.startedAt)
      })
    let start: Date
    let count: Int
    switch mode {
    case .week:
      guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
      start = week.start
      count = 7
    case .month:
      let padding =
        (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
      guard let first = calendar.date(byAdding: .day, value: -padding, to: month.start) else {
        return nil
      }
      start = first
      count = 42
    }
    let days = (0..<count).compactMap { index -> TrainingCalendarDay? in
      guard let day = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
      return TrainingCalendarDay(
        date: day, isInMonth: day >= month.start && day < month.end,
        hasWorkout: trained.contains(calendar.startOfDay(for: day)))
    }
    return DiaryCalendarPage(date: date, days: days)
  }
}
