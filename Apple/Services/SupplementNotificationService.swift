import Foundation
import UserNotifications

/// Notifications use generic lock-screen text so supplement names and doses are not exposed.
@MainActor final class SupplementNotificationService: SupplementReminderServing {
  private let center: UNUserNotificationCenter
  init(center: UNUserNotificationCenter = .current()) { self.center = center }

  func authorize() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }

  func replace(_ reminders: [SupplementReminder]) async throws -> SupplementReminderPermission {
    let pending = await center.pendingNotificationRequests()
    try Task.checkCancellation()
    let own = pending.filter { $0.identifier.hasPrefix("supplement.") }.map(\.identifier)
    center.removePendingNotificationRequests(withIdentifiers: own)
    let delivered = await center.deliveredNotifications()
    try Task.checkCancellation()
    center.removeDeliveredNotifications(
      withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix("supplement.") })
    let settings = await center.notificationSettings()
    try Task.checkCancellation()
    guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
      return .denied
    }
    // Respect the shared system queue, leaving room for rest and other app notifications.
    let available = max(0, 60 - pending.filter { !$0.identifier.hasPrefix("supplement.") }.count)
    for reminder in reminders.prefix(available) {
      try Task.checkCancellation()
      guard reminder.date > .now else { continue }
      let content = UNMutableNotificationContent()
      content.title = L10n.text("Время приёма добавки")
      content.body = L10n.text("Откройте дневник питания, чтобы отметить приём.")
      content.sound = .default
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: reminder.date)
      components.calendar = calendar
      components.timeZone = calendar.timeZone
      try await center.add(
        UNNotificationRequest(
          identifier: reminder.id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
    return .allowed
  }
}
