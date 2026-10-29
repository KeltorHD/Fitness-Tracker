import Foundation
import UserNotifications

@MainActor protocol RestNotificationServing {
  func authorize() async throws -> Bool
  func schedule(until date: Date?) async throws
  func cancel()
}

@MainActor final class RestNotificationService: RestNotificationServing {
  private let center = UNUserNotificationCenter.current()
  func authorize() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }
  func schedule(until date: Date?) async throws {
    cancel()
    guard let date, date.timeIntervalSinceNow > 0 else { return }
    let settings = await center.notificationSettings()
    try Task.checkCancellation()
    guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
    let content = UNMutableNotificationContent()
    content.title = "Отдых завершён"
    content.body = "Следующий подход ждёт вас."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
    try await center.add(
      UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
  }
  func cancel() { center.removePendingNotificationRequests(withIdentifiers: ["rest"]) }
}
