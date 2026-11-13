import XCTest

final class AccountTrainingUITests: XCTestCase {
  @MainActor func testServerChoiceDoesNotTriggerLocalChoiceOrAccountDeletion() {
    let app = launchConflict()
    let accept = app.buttons["acceptServerTrainingVersion"]
    accept.tap()
    let confirm = app.buttons["Сохранить выбранную версию"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Удалить"].exists)
    app.buttons["Отменить"].tap()
    XCTAssertTrue(accept.exists)
    XCTAssertTrue(app.buttons["keepLocalTrainingVersion"].exists)
    accept.tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(accept.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["UI sync fixture"].exists)
    XCTAssertTrue(app.buttons["deleteServerAccount"].exists)
  }
  @MainActor func testLocalChoiceRequiresConfirmationAndRetainsAccount() {
    let app = launchConflict()
    app.buttons["keepLocalTrainingVersion"].tap()
    let confirm = app.buttons["Сохранить выбранную версию"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.buttons["keepLocalTrainingVersion"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["UI sync fixture"].exists)
    XCTAssertTrue(app.buttons["syncTrainingNow"].exists)
  }
  @MainActor private func launchConflict() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--ui-testing-training-sync", "-AppleLanguages", "(ru)", "-AppleLocale",
      "ru_RU",
    ]
    app.launch()
    let settings = app.buttons["openSettings"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let account = app.buttons["openAccountTraining"]
    for _ in 0..<4 where !account.isHittable { app.swipeUp() }
    XCTAssertTrue(account.isHittable)
    account.tap()
    let conflict = app.buttons["UI: server version"]
    XCTAssertTrue(conflict.waitForExistence(timeout: 10))
    conflict.tap()
    XCTAssertTrue(app.buttons["acceptServerTrainingVersion"].waitForExistence(timeout: 5))
    return app
  }
}
