import FitSessionCore
import XCTest

@testable import FitSession

final class WidgetSnapshotTests: XCTestCase {
  func testLanguageCanBeSharedWithoutPublishingWorkoutData() throws {
    let suite = "FitSession.LanguageTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try WidgetSnapshot.publishLanguage(.english, to: defaults)
    XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
    XCTAssertNil(try WidgetSnapshot.read(from: defaults))
    try WidgetSnapshot.clear(from: defaults)
    XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
  }

  func testCorruptSnapshotIsReportedAndPreserved() throws {
    let suite = "FitSession.SnapshotTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let corrupt = Data("invalid JSON".utf8)
    defaults.set(corrupt, forKey: "weeklySnapshot")
    XCTAssertThrowsError(try WidgetSnapshot.read(from: defaults))
    XCTAssertEqual(defaults.data(forKey: "weeklySnapshot"), corrupt)
    try WidgetSnapshot(
      workoutsThisWeek: 2, weeklyGoal: 3, updatedAt: Date(timeIntervalSince1970: 100)
    ).write(to: defaults)
    XCTAssertEqual(try WidgetSnapshot.read(from: defaults)?.workoutsThisWeek, 2)
    try WidgetSnapshot.clear(from: defaults)
    XCTAssertNil(try WidgetSnapshot.read(from: defaults))
  }

  func testInvalidValuesDoNotOverwriteAnExistingSnapshot() throws {
    let suite = "FitSession.SnapshotTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let date = Date(timeIntervalSince1970: 100)
    try WidgetSnapshot(workoutsThisWeek: 2, weeklyGoal: 3, updatedAt: date).write(to: defaults)
    XCTAssertThrowsError(
      try WidgetSnapshot(workoutsThisWeek: -1, weeklyGoal: 0, updatedAt: date).write(to: defaults))
    XCTAssertEqual(try WidgetSnapshot.read(from: defaults)?.workoutsThisWeek, 2)
  }
}
