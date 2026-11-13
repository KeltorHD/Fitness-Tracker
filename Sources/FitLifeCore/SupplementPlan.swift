import Foundation

public enum SupplementRecurrence: String, Codable, CaseIterable, Sendable {
  case daily, weekdays, intervalDays
  public var title: String {
    switch self {
    case .daily: "Каждый день"
    case .weekdays: "По дням недели"
    case .intervalDays: "Через несколько дней"
    }
  }
}

/// A schedule is a prescription entered by the user, never an automatically recorded intake.
public struct SupplementPlan: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var prototype: SupplementEntry
  public var recurrence: SupplementRecurrence
  public var intervalDays: Int
  /// Calendar weekday numbers: Sunday = 1, Monday = 2.
  public var weekdays: [Int]
  /// Minutes from midnight in the saved time zone, in ascending order.
  public var times: [Int]
  public var startDate: Date
  public var endDate: Date?
  public var timeZoneID: String
  public var enabled: Bool
  public var remindersEnabled: Bool

  public init(
    prototype: SupplementEntry, recurrence: SupplementRecurrence = .daily,
    intervalDays: Int = 1, weekdays: [Int] = [], times: [Int] = [540],
    startDate: Date = .now, endDate: Date? = nil,
    timeZoneID: String = TimeZone.current.identifier, enabled: Bool = true,
    remindersEnabled: Bool = false
  ) {
    id = prototype.id
    self.prototype = prototype
    self.recurrence = recurrence
    self.intervalDays = intervalDays
    self.weekdays = weekdays.sorted()
    self.times = times.sorted()
    self.startDate = startDate
    self.endDate = endDate
    self.timeZoneID = timeZoneID
    self.enabled = enabled
    self.remindersEnabled = remindersEnabled
  }

  public func validate() throws {
    try prototype.validate()
    guard prototype.id == id, prototype.planID == nil, prototype.scheduledFor == nil,
      (1...365).contains(intervalDays), !times.isEmpty, times.count <= 8,
      times == Array(Set(times)).sorted(), times.allSatisfy({ (0..<1440).contains($0) }),
      weekdays == Array(Set(weekdays)).sorted(), weekdays.allSatisfy({ (1...7).contains($0) }),
      recurrence != .weekdays || !weekdays.isEmpty,
      startDate.timeIntervalSince1970.isFinite, endDate?.timeIntervalSince1970.isFinite != false,
      TimeZone(identifier: timeZoneID) != nil,
      endDate.map({ $0 >= startDate }) ?? true
    else { throw NutritionError.invalidSupplementPlan }
  }

  /// Bounded calendar enumeration preserves interval phase and DST without assuming 86400s days.
  public func occurrences(from lower: Date, through upper: Date, limit: Int = 256) -> [Date] {
    guard enabled, lower <= upper, limit > 0, (try? validate()) != nil,
      let zone = TimeZone(identifier: timeZoneID)
    else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let first = calendar.startOfDay(for: startDate)
    let last = endDate.map { calendar.startOfDay(for: $0) }
    var day = max(first, calendar.startOfDay(for: lower))
    var result: [Date] = []
    // A single call visits at most a year; callers replenish the upcoming window on app activity.
    for _ in 0..<367 {
      guard day <= upper, last.map({ day <= $0 }) ?? true else { break }
      let offset = calendar.dateComponents([.day], from: first, to: day).day ?? 0
      let matches =
        switch recurrence {
        case .daily: true
        case .weekdays: weekdays.contains(calendar.component(.weekday, from: day))
        case .intervalDays: offset % intervalDays == 0
        }
      if matches {
        for minute in times {
          if let date = calendar.date(
            bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
            calendar.isDate(date, inSameDayAs: day), date >= lower, date <= upper
          {
            result.append(date)
            if result.count == limit { return result }
          }
        }
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return result
  }

  public func intake(scheduledFor date: Date, takenAt: Date) -> SupplementEntry {
    var entry = prototype
    // Calendar slots use whole Unix seconds. Formatting avoids trapping on invalid imported dates;
    // the resulting entry still fails validation and can never be persisted with a nonfinite date.
    let seconds = String(
      format: "%.0f", locale: Locale(identifier: "en_US_POSIX"),
      date.timeIntervalSince1970.rounded(.towardZero))
    entry.id = StableIdentifier.uuid(
      "com.fitlife.supplement-intake/\(id.uuidString.lowercased())/\(seconds)"
    )
    entry.planID = id
    entry.scheduledFor = date
    entry.date = takenAt
    return entry
  }
}
