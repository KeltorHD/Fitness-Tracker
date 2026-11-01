import Foundation

/// Stable Calendar weekday values, independent of the locale's first day of the week.
public enum WorkoutWeekday: Int, Codable, CaseIterable, Sendable {
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7
  case sunday = 1

  public var title: String {
    switch self {
    case .monday: "Понедельник"
    case .tuesday: "Вторник"
    case .wednesday: "Среда"
    case .thursday: "Четверг"
    case .friday: "Пятница"
    case .saturday: "Суббота"
    case .sunday: "Воскресенье"
    }
  }

  public static func ordered(in calendar: Calendar) -> [Self] {
    allCases.sorted {
      ($0.rawValue - calendar.firstWeekday + 7) % 7
        < ($1.rawValue - calendar.firstWeekday + 7) % 7
    }
  }
}

/// A suggestion only: templates remain available on every day, in their original relative order.
public struct WorkoutTemplateSuggestions: Equatable, Sendable {
  public let today: [WorkoutTemplate]
  public let others: [WorkoutTemplate]

  public init(templates: [WorkoutTemplate], date: Date, calendar: Calendar) {
    let weekday = WorkoutWeekday(rawValue: calendar.component(.weekday, from: date))
    var today: [WorkoutTemplate] = []
    var others: [WorkoutTemplate] = []
    for template in templates {
      if let weekday, template.preferredWeekdays.contains(weekday) {
        today.append(template)
      } else {
        others.append(template)
      }
    }
    self.today = today
    self.others = others
  }
}
