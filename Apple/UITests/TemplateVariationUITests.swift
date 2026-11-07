import XCTest

final class TemplateVariationUITests: XCTestCase {
  private let templateID = "90000000-0000-0000-0000-000000000001"
  private let historyID = "90000000-0000-0000-0000-000000000003"

  @MainActor func testStartingSelectedTemplateVariationUsesItsExercises() {
    let app = launch()
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_\(templateID)"]
    reveal(template, in: app, named: "startWorkoutTemplate_\(templateID)")
    template.tap()
    let next = app.buttons["nextTemplateVariation_\(templateID)"]
    reveal(next, in: app, named: "nextTemplateVariation_\(templateID)")
    next.tap()
    let menu = app.buttons["templateVariationMenu_\(templateID)"]
    XCTAssertEqual(menu.value as? String, "Гантели")
    XCTAssertTrue(app.staticTexts["Тест: жим гантелей"].waitForExistence(timeout: 5))
    attachScreenshot("Selected template variation", in: app)
    app.buttons["startSelectedTemplates"].tap()

    let rows = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(rows.count, 2)
    XCTAssertTrue(rows.element(boundBy: 0).label.contains("Тест: жим гантелей"))
    XCTAssertTrue(rows.element(boundBy: 1).label.contains("Тест: жим в наклоне"))
    XCTAssertFalse(rows.element(boundBy: 0).label.contains("Тест: жим штанги"))
  }

  @MainActor func testEditedNewVariationIsSavedIndependentlyFromBaseExercises() throws {
    let app = launch()
    openFixtureTemplate(in: app)
    editCurrentTemplate(in: app)
    app.buttons["addTemplateVariation"].tap()
    let name = app.textFields["templateVariationName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText(" сохранён\n")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    let savedName = try XCTUnwrap(name.value as? String)
    let removals = templateRemovals(in: app)
    reveal(removals.firstMatch, in: app, named: "templateEditorList/removeTemplateExercise_*")
    let removedID = removals.firstMatch.identifier
    removals.firstMatch.tap()
    XCTAssertTrue(
      removals.matching(identifier: removedID).firstMatch.waitForNonExistence(timeout: 5))
    attachScreenshot("Editing a template variation", in: app)
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(app.collectionViews["templateEditorList"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.buttons["templateActions"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Тест: жим штанги"].exists)
    XCTAssertTrue(app.staticTexts["Тест: жим в наклоне"].exists)

    editCurrentTemplate(in: app)
    let editor = app.collectionViews["templateEditorList"]
    let next = editor.buttons["nextTemplateVariation_\(templateID)"]
    XCTAssertTrue(next.waitForExistence(timeout: 5))
    next.tap()
    next.tap()
    XCTAssertEqual(editor.textFields["templateVariationName"].value as? String, savedName)
    reveal(removals.firstMatch, in: app, named: "templateEditorList/removeTemplateExercise_*")
    XCTAssertEqual(removals.count, 1)
    XCTAssertFalse(editor.buttons[removedID].exists)
    XCTAssertTrue(editor.staticTexts["Тест: жим в наклоне"].exists)
    XCTAssertFalse(editor.staticTexts["Тест: жим штанги"].exists)
  }

  @MainActor func testHistoryCreatesEditableTemplateWithoutChangingCompletedWorkout() throws {
    let app = launch()
    let history = app.buttons["historyWorkout_\(historyID)"]
    reveal(history, in: app, named: "historyWorkout_\(historyID)")
    history.press(forDuration: 1)
    let create = app.buttons["createTemplateFromHistory_\(historyID)"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    create.tap()
    let name = app.textFields["templateName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText(" новый шаблон\n")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    let savedName = try XCTUnwrap(name.value as? String)
    let removals = templateRemovals(in: app)
    reveal(removals.firstMatch, in: app, named: "templateEditorList/removeTemplateExercise_*")
    removals.firstMatch.tap()
    let add = app.buttons["addTemplateExercise"]
    reveal(add, in: app, named: "addTemplateExercise")
    add.tap()
    let custom = app.buttons["Своё упражнение"]
    XCTAssertTrue(custom.waitForExistence(timeout: 5))
    custom.tap()
    let customName = app.textFields["customExerciseName"]
    XCTAssertTrue(customName.waitForExistence(timeout: 5))
    customName.tap()
    customName.typeText("Тест: новое упражнение шаблона")
    app.buttons["saveCustomExercise"].tap()
    XCTAssertTrue(app.buttons["saveTemplate"].waitForExistence(timeout: 5))
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(app.textFields["templateName"].waitForNonExistence(timeout: 5))

    reveal(history, in: app, named: "historyWorkout_\(historyID)")
    history.tap()
    let originalRows = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertTrue(originalRows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(originalRows.count, 2)
    XCTAssertTrue(originalRows.element(boundBy: 0).label.contains("Тест: жим штанги"))
    XCTAssertTrue(originalRows.element(boundBy: 1).label.contains("Тест: жим в наклоне"))
    app.buttons["closeWorkoutDetail"].tap()
    app.buttons["navigationTab_1"].tap()
    let saved = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "templateRow_", savedName)
    ).firstMatch
    reveal(saved, in: app, named: "templateRow_* containing \(savedName)")
    saved.tap()
    XCTAssertTrue(app.staticTexts["Тест: новое упражнение шаблона"].exists)
    XCTAssertTrue(app.staticTexts["Тест: жим в наклоне"].exists)
    XCTAssertFalse(app.staticTexts["Тест: жим штанги"].exists)
    attachScreenshot("New template created from workout history", in: app)
  }

  @MainActor private func launch() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--ui-testing-training-groups",
      "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 15))
    return app
  }

  @MainActor private func openFixtureTemplate(in app: XCUIApplication) {
    app.buttons["navigationTab_1"].tap()
    let template = app.buttons["templateRow_\(templateID)"]
    reveal(template, in: app, named: "templateRow_\(templateID)")
    template.tap()
    XCTAssertTrue(app.buttons["templateActions"].waitForExistence(timeout: 5))
  }

  @MainActor private func editCurrentTemplate(in app: XCUIApplication) {
    app.buttons["templateActions"].tap()
    let edit = app.buttons["editTemplate"]
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
    XCTAssertTrue(app.buttons["addTemplateVariation"].waitForExistence(timeout: 5))
  }

  @MainActor private func templateRemovals(in app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "templateEditorList").firstMatch
      .buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeTemplateExercise_"))
  }

  @MainActor private func reveal(
    _ element: XCUIElement, in app: XCUIApplication, named identifier: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for _ in 0..<10 {
      let viewport = visibleViewport(in: app)
      let exists = element.exists
      let target = exists ? element.frame : .zero
      if exists && element.isHittable && viewport.contains(target) { return }
      let movingDown = exists && target.minY < viewport.minY
      let origin = app.coordinate(withNormalizedOffset: .zero)
      let start = origin.withOffset(
        CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * (movingDown ? 0.3 : 0.7)))
      let end = origin.withOffset(
        CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * (movingDown ? 0.7 : 0.3)))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    let exists = element.waitForExistence(timeout: 5)
    let hittable = exists && element.isHittable && visibleViewport(in: app).contains(element.frame)
    if !hittable {
      attachScreenshot("Unreachable element: \(identifier)", in: app)
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Accessibility hierarchy for \(identifier)"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertTrue(exists, "Missing element: \(identifier)", file: file, line: line)
    XCTAssertTrue(hittable, "Element not hittable: \(identifier)", file: file, line: line)
  }

  @MainActor private func visibleViewport(in app: XCUIApplication) -> CGRect {
    let frame = app.frame
    let top = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? frame.minY
    let keyboard = app.keyboards.firstMatch
    let bottom = keyboard.exists ? keyboard.frame.minY : frame.maxY - 34
    var viewport = CGRect(x: frame.minX, y: top, width: frame.width, height: max(44, bottom - top))
    let editor = app.collectionViews["templateEditorList"]
    if editor.exists { viewport = viewport.intersection(editor.frame) }
    return viewport
  }

  @MainActor private func attachScreenshot(_ name: String, in app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
