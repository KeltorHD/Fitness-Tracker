import FitLifeCore
import Foundation

struct SupplementReminder: Equatable, Sendable {
  let id: String
  let date: Date
}

enum SupplementReminderPermission: Equatable, Sendable { case allowed, denied }

@MainActor protocol SupplementReminderServing {
  func authorize() async throws -> Bool
  /// Removes only supplement notifications; an empty list also clears previous-account requests.
  func replace(_ reminders: [SupplementReminder]) async throws -> SupplementReminderPermission
}

enum SupplementReminderPlanner {
  static func reminders(
    plans: [SupplementPlan], entries: [SupplementEntry], namespace: String, now: Date
  ) -> [SupplementReminder] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    guard let end = calendar.date(byAdding: .day, value: 30, to: now) else { return [] }
    let completed = Set(entries.map(\.id))
    var result: [SupplementReminder] = []
    for plan in plans where plan.enabled && plan.remindersEnabled {
      let dates = plan.occurrences(from: now.addingTimeInterval(1), through: end, limit: 48)
      for date in dates {
        let id = plan.intake(scheduledFor: date, takenAt: date).id
        guard !completed.contains(id) else { continue }
        result.append(
          SupplementReminder(id: "supplement.\(namespace).\(id.uuidString)", date: date))
      }
    }
    result.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    return Array(result.prefix(48))
  }
}
