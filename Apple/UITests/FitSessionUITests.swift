import XCTest

final class FitSessionUITests: XCTestCase {
  @MainActor func testTrackerOffersBothModesWithoutRequestingPermissionsOnOpen() {
    let app = launch()
    let settings = app.tabBars.buttons["Настройки"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let tracker = app.buttons["openTracker"]
    if !tracker.isHittable { app.swipeUp() }
    XCTAssertTrue(tracker.waitForExistence(timeout: 5))
    tracker.tap()
    XCTAssertTrue(app.buttons["readTrackerHealth"].waitForExistence(timeout: 5))
    app.buttons["trackerDevicePicker"].tap()
    app.buttons["HUAWEI WATCH GT 6 Pro"].tap()
    XCTAssertTrue(app.staticTexts["trackerHealthSetup"].label.contains("HUAWEI Health"))
    app.buttons["trackerModePicker"].tap()
    app.buttons["Bluetooth-пульс"].tap()
    XCTAssertTrue(app.buttons["scanHeartRate"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["trackerBluetoothSetup"].label.contains("HR Data Broadcasts"))
    app.buttons["trackerDevicePicker"].tap()
    app.buttons["Xiaomi Smart Band 10"].tap()
    XCTAssertTrue(app.staticTexts["trackerBluetoothSetup"].label.contains("Share HR"))
    XCTAssertEqual(app.alerts.count, 0)
  }
  @MainActor func testLanguageCanBeChangedWithoutRelaunchingTheApp() {
    let app = launch()
    let settings = app.tabBars.buttons["Настройки"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let language = app.buttons["appLanguagePicker"]
    if !language.isHittable { app.swipeUp() }
    XCTAssertTrue(language.waitForExistence(timeout: 5))
    language.tap()
    app.buttons["English"].tap()
    XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
    let selectedLanguage = app.buttons["appLanguagePicker"]
    selectedLanguage.tap()
    app.buttons["Русский"].tap()
    XCTAssertTrue(app.tabBars.buttons["Настройки"].waitForExistence(timeout: 5))
  }

  @MainActor func testArchiveToolsAreAvailableFromSettings() {
    let app = launch()
    let settings = app.tabBars.buttons["Настройки"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let tools = app.buttons["openArchiveTransfer"]
    XCTAssertTrue(tools.waitForExistence(timeout: 10))
    tools.tap()
    XCTAssertTrue(app.buttons["chooseArchive"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["exportArchive"].exists)
    app.buttons["Готово"].tap()
    XCTAssertTrue(tools.waitForExistence(timeout: 5))
  }
  @MainActor private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()
    return app
  }
  @MainActor func testLogSetAndFindWorkoutInHistory() {
    let app = launch()
    let start = app.buttons["startWorkout"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    let squat = app.buttons.containing(.staticText, identifier: "Приседания").firstMatch
    XCTAssertTrue(squat.waitForExistence(timeout: 5))
    squat.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    let complete = app.buttons["completeSet"].firstMatch
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    complete.tap()
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    finish.tap()
    let alert = app.alerts["Готово"]
    if alert.waitForExistence(timeout: 3) { alert.buttons["Хорошо"].tap() }
    app.tabBars.buttons["Дневник"].tap()
    XCTAssertTrue(app.staticTexts["Свободная тренировка"].waitForExistence(timeout: 5))
  }
  @MainActor func testMinimizedSessionCanBeResumed() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    app.buttons["Свернуть"].tap()
    app.buttons["startWorkout"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
  }
}
