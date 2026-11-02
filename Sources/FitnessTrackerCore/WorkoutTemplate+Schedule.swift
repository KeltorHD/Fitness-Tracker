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

/// Template discovery only; filtering does not change selection order or any stored workout data.
public struct WorkoutTemplateFilter: Equatable, Sendable {
  public enum Schedule: String, CaseIterable, Sendable {
    case all, today, unscheduled

    public var title: String {
      switch self {
      case .all: "Все шаблоны"
      case .today: "Только на сегодня"
      case .unscheduled: "Без расписания"
      }
    }
  }

  public var query = ""
  public var schedule = Schedule.all
  public var muscles = ExerciseMuscleSelection()
  public var equipment: Set<ExerciseEquipment> = []

  private static let library = Dictionary(
    uniqueKeysWithValues: ExerciseLibrary.entries.map { ($0.id, $0) })

  public init() {}

  public var hasFilters: Bool { schedule != .all || !muscles.isEmpty || !equipment.isEmpty }
  public var isActive: Bool {
    hasFilters || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public func apply(
    to templates: [WorkoutTemplate], date: Date, calendar: Calendar
  ) -> WorkoutTemplateSuggestions {
    let weekday = WorkoutWeekday(rawValue: calendar.component(.weekday, from: date))
    let tokens = Self.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    let filtered = templates.filter { template in
      switch schedule {
      case .all: break
      case .today:
        guard let weekday, template.preferredWeekdays.contains(weekday) else { return false }
      case .unscheduled:
        guard template.preferredWeekdays.isEmpty else { return false }
      }
      guard matchesMuscles(template) else { return false }
      if !equipment.isEmpty {
        guard
          template.exercises.contains(where: {
            equipment.contains(Self.library[$0.exercise.id]?.equipment ?? .unspecified)
          })
        else { return false }
      }
      guard !tokens.isEmpty else { return true }
      let names =
        [template.name]
        + template.exercises.flatMap { item in
          guard let entry = Self.library[item.exercise.id] else { return [item.exercise.name] }
          return [item.exercise.name, entry.name, entry.englishName] + entry.aliases
        }
      let text = Self.normalize(names.joined(separator: " "))
      return tokens.allSatisfy { text.contains($0) }
    }
    return WorkoutTemplateSuggestions(templates: filtered, date: date, calendar: calendar)
  }

  private func matchesMuscles(_ template: WorkoutTemplate) -> Bool {
    guard !muscles.isEmpty else { return true }
    let preference = template.muscleSelection
    if !preference.isEmpty {
      return !muscles.groups.isDisjoint(with: preference.groups)
        || ExerciseMuscle.allCases.contains { muscles.contains($0) && preference.contains($0) }
    }
    // Legacy templates without explicit targets are discoverable by their actual exercises.
    return template.exercises.contains { item in
      if let entry = Self.library[item.exercise.id] { return muscles.matches(entry) }
      return muscles.groups.contains(item.exercise.muscle)
    }
  }

  private static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
  }
}
