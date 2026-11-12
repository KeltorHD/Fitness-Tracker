import XCTest

final class AccountBackupUITests: XCTestCase {
  @MainActor func testRestoreOpensImportPreviewWithoutConfirmingOrDeletingBackup() {
    let app = launchBackups()
    let restore = button("restoreServerBackup_", in: app)
    restore.tap()

    let importButton = app.buttons["confirmArchiveImport"]
    XCTAssertTrue(importButton.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Удалить"].exists)
    XCTAssertFalse(app.staticTexts["Резервная копия удалена."].exists)
    importButton.tap()
    let result = app.descendants(matching: .any).matching(identifier: "archiveTransferResult")
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    XCTAssertTrue(result.label.contains("Добавлено тренировок: 1"))
    app.buttons["Готово"].tap()
    XCTAssertTrue(restore.waitForExistence(timeout: 5))
    XCTAssertTrue(button("deleteServerBackup_", in: app).exists)
  }

  @MainActor func testDeleteRequiresItsOwnConfirmationAndDoesNotOpenImport() {
    let app = launchBackups()
    let delete = button("deleteServerBackup_", in: app)
    delete.tap()
    let confirmDelete = app.buttons["Удалить"]
    XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["confirmArchiveImport"].exists)
    app.buttons["Отменить"].tap()
    XCTAssertTrue(delete.exists)
    XCTAssertTrue(button("restoreServerBackup_", in: app).exists)

    delete.tap()
    XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
    confirmDelete.tap()
    XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Резервная копия удалена."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["confirmArchiveImport"].exists)
  }

  @MainActor private func launchBackups() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--ui-testing-backups", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
    ]
    app.launch()
    let settings = app.buttons["openSettings"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let backups = app.buttons["openAccountBackups"]
    for _ in 0..<4 where !backups.isHittable { app.swipeUp() }
    XCTAssertTrue(backups.isHittable)
    backups.tap()
    XCTAssertTrue(button("restoreServerBackup_", in: app).waitForExistence(timeout: 5))
    return app
  }

  @MainActor private func button(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
  }
}
