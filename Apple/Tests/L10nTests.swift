import FitSessionCore
import XCTest

@testable import FitSession

final class L10nTests: XCTestCase {
  func testExplicitLanguageUsesTheCompiledCatalogInTheHostApp() {
    XCTAssertEqual(L10n.text("Настройки", locale: Locale(identifier: "en_US")), "Settings")
    XCTAssertEqual(L10n.text("Настройки", locale: Locale(identifier: "ru_RU")), "Настройки")
    XCTAssertEqual(
      L10n.text("custom user text", locale: Locale(identifier: "en_US")), "custom user text")
  }

  func testCountFormsAndFormatArgumentsInBothLanguages() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    XCTAssertEqual(L10n.workoutCount(1, locale: english), "1 workout")
    XCTAssertEqual(L10n.workoutCount(2, locale: english), "2 workouts")
    XCTAssertEqual(L10n.workoutCount(1, locale: russian), "1 тренировка")
    XCTAssertEqual(L10n.workoutCount(2, locale: russian), "2 тренировки")
    XCTAssertEqual(L10n.workoutCount(5, locale: russian), "5 тренировок")
    XCTAssertEqual(L10n.workoutCount(21, locale: russian), "21 тренировка")
    XCTAssertEqual(L10n.format("Далее: подход %@", "3", locale: english), "Next: set 3")
  }

  func testCatalogNamesArePresentedWithoutMutatingSavedExercises() throws {
    let entry = try XCTUnwrap(ExerciseLibrary.entries.first)
    let saved = entry.exercise
    XCTAssertEqual(L10n.exerciseName(saved, locale: Locale(identifier: "en_US")), entry.englishName)
    XCTAssertEqual(saved.name, entry.name)
    let custom = Exercise(name: "Моё упражнение", muscle: .fullBody)
    XCTAssertEqual(L10n.exerciseName(custom, locale: Locale(identifier: "en_US")), custom.name)
  }
}
