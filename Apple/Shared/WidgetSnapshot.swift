import Foundation

struct WidgetSnapshot: Codable, Sendable {
  var workoutsThisWeek: Int
  var weeklyGoal: Int
  var updatedAt: Date
  static let empty = WidgetSnapshot(workoutsThisWeek: 0, weeklyGoal: 3, updatedAt: .now)
  static var defaults: UserDefaults? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "FitSessionAppGroup") as? String
    else { return nil }
    return UserDefaults(suiteName: group)
  }
  static func read() -> WidgetSnapshot? {
    guard let data = defaults?.data(forKey: "weeklySnapshot") else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
  func write() throws { defaults?.set(try JSONEncoder().encode(self), forKey: "weeklySnapshot") }
  static func clear() { defaults?.removeObject(forKey: "weeklySnapshot") }
}
