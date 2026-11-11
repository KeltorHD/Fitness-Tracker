import FitLifeCore
import XCTest

@testable import FitLife

final class WidgetSnapshotTests: XCTestCase {
  func testColorThemeCanBeSharedWithoutWorkoutOptInAndSurvivesClearingSummary() throws {
    let suite = "FitLife.ColorThemeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertNil(try WidgetSnapshot.colorThemeID(from: defaults))
    XCTAssertEqual(FitnessColorTheme.resolved(nil), .forest)
    for theme in FitnessColorTheme.allCases {
      try WidgetSnapshot.publishColorTheme(theme.rawValue, to: defaults)
      XCTAssertEqual(
        FitnessColorTheme.resolved(try WidgetSnapshot.colorThemeID(from: defaults)), theme)
      XCTAssertNil(try WidgetSnapshot.read(from: defaults))
    }
    try WidgetSnapshot.clear(from: defaults)
    XCTAssertEqual(
      try WidgetSnapshot.colorThemeID(from: defaults), FitnessColorTheme.allCases.last?.rawValue)
    XCTAssertEqual(FitnessColorTheme.resolved("unknown-theme"), .forest)
  }

  func testLanguageCanBeSharedWithoutPublishingWorkoutData() throws {
    let suite = "FitLife.LanguageTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try WidgetSnapshot.publishLanguage(.english, to: defaults)
    XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
    XCTAssertNil(try WidgetSnapshot.read(from: defaults))
    try WidgetSnapshot.clear(from: defaults)
    XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
  }

  func testCorruptSnapshotIsReportedAndPreserved() throws {
    let suite = "FitLife.SnapshotTests.\(UUID().uuidString)"
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
    let suite = "FitLife.SnapshotTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let date = Date(timeIntervalSince1970: 100)
    try WidgetSnapshot(workoutsThisWeek: 2, weeklyGoal: 3, updatedAt: date).write(to: defaults)
    XCTAssertThrowsError(
      try WidgetSnapshot(workoutsThisWeek: -1, weeklyGoal: 0, updatedAt: date).write(to: defaults))
    XCTAssertEqual(try WidgetSnapshot.read(from: defaults)?.workoutsThisWeek, 2)
  }
}
