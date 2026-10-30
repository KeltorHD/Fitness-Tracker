import FitnessTrackerCore
import Foundation

struct WidgetSnapshot: Codable, Sendable {
  var workoutsThisWeek: Int
  var weeklyGoal: Int
  var updatedAt: Date
  static let empty = WidgetSnapshot(workoutsThisWeek: 0, weeklyGoal: 3, updatedAt: .now)
  private static func sharedDefaults() throws -> UserDefaults {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "FitnessTrackerAppGroup") as? String,
      !group.isEmpty, !group.contains("$("), let defaults = UserDefaults(suiteName: group)
    else { throw WidgetSnapshotError.unavailable }
    return defaults
  }
  static func read(from defaults: UserDefaults? = nil) throws -> WidgetSnapshot? {
    let storage = try defaults ?? sharedDefaults()
    guard let data = storage.data(forKey: "weeklySnapshot") else { return nil }
    let snapshot = try JSONDecoder().decode(Self.self, from: data)
    try snapshot.validate()
    return snapshot
  }
  func write(to defaults: UserDefaults? = nil) throws {
    try validate()
    let storage = try defaults ?? Self.sharedDefaults()
    storage.set(try JSONEncoder().encode(self), forKey: "weeklySnapshot")
  }
  static func clear(from defaults: UserDefaults? = nil) throws {
    let storage = try defaults ?? sharedDefaults()
    storage.removeObject(forKey: "weeklySnapshot")
  }
  static func publishLanguage(_ language: AppLanguage, to defaults: UserDefaults? = nil) throws {
    let storage = try defaults ?? sharedDefaults()
    storage.set(language.rawValue, forKey: "appLanguage")
  }
  private func validate() throws {
    guard workoutsThisWeek >= 0, (1...7).contains(weeklyGoal),
      updatedAt.timeIntervalSince1970.isFinite
    else { throw WidgetSnapshotError.invalidData }
  }
}

enum WidgetSnapshotError: Error {
  case unavailable, invalidData
}
