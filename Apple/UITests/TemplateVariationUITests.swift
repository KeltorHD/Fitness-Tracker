import XCTest

final class TemplateVariationUITests: XCTestCase {
  private let templateID = "90000000-0000-0000-0000-000000000001"
  private let historyID = "90000000-0000-0000-0000-000000000003"

  @MainActor func testFirstVariationCanBeRenamedWithoutRenamingTheTemplate() throws {
    let app = launch()
    openFixtureTemplate(in: app)
    editCurrentTemplate(in: app)
    let editor = app.collectionViews["templateEditorList"]
    let name = editor.textFields["templateVariationName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText(" · штанга\n")
    let savedName = try XCTUnwrap(name.value as? String)
    attachScreenshot("First variation name after editing", in: app)
    XCTAssertTrue(savedName.lowercased().contains("штанга"), "Actual variation name: \(savedName)")
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.buttons["templateVariationMenu_\(templateID)"].value as? String, savedName)
    editCurrentTemplate(in: app)
    XCTAssertEqual(editor.textFields["templateVariationName"].value as? String, savedName)
    XCTAssertEqual(editor.textFields["templateName"].value as? String, "Тест: жим на грудь")
    attachScreenshot("Renamed first variation", in: app)
  }

  @MainActor func testTemplateReplacementAndSwipeKeepEachExerciseIndependent() {
    let app = launch()
    openFixtureTemplate(in: app)
    editCurrentTemplate(in: app)
    let editor = app.collectionViews["templateEditorList"]
    let result = editor.staticTexts.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "templateExerciseResult_")
    ).firstMatch
    reveal(result, in: app, named: "latest recorded results")
    XCTAssertTrue(result.label.contains("40") && result.label.contains("8"))
    let replacements = editor.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "replaceTemplateExercise_"))
    reveal(replacements.firstMatch, in: app, named: "replace first template exercise")
    replacements.firstMatch.tap()
    createCustomExercise("Тест: замена кнопкой", in: app)
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    let secondID = replacements.element(boundBy: 1).identifier.replacingOccurrences(
      of: "replaceTemplateExercise_", with: "")
    let second = editor.descendants(matching: .any).matching(
      identifier: "templateExerciseCard_\(secondID)"
    ).firstMatch
    reveal(second, in: app, named: "second exercise card")
    second.swipeLeft()
    let replace = app.buttons["swipeReplaceTemplateExercise_\(secondID)"]
    XCTAssertTrue(replace.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["swipeRemoveTemplateExercise_\(secondID)"].exists)
    attachScreenshot("Template replacement and destructive swipe", in: app)
    replace.tap()
    createCustomExercise("Тест: замена свайпом", in: app)
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Тест: замена кнопкой"].exists)
    let replaced = app.staticTexts["Тест: замена свайпом"]
    reveal(replaced, in: app, named: "saved replacement")
    XCTAssertFalse(app.staticTexts["Тест: жим в наклоне"].exists)
    attachScreenshot("Saved independent exercise replacements", in: app)
  }

  @MainActor func testTemplateExercisesCanBeDraggedAndTheNewOrderIsSaved() async throws {
    let app = launch()
    openFixtureTemplate(in: app)
    editCurrentTemplate(in: app)
    let editor = app.collectionViews["templateEditorList"]
    let first = editor.staticTexts["Тест: жим штанги"]
    let second = editor.staticTexts["Тест: жим в наклоне"]
    reveal(first, in: app, named: "first draggable exercise")
    reveal(second, in: app, named: "second draggable exercise")
    XCTAssertTrue(first.isHittable && second.isHittable)
    let secondCell = editor.cells.containing(.staticText, identifier: "Тест: жим в наклоне")
      .firstMatch
    XCTAssertTrue(secondCell.exists)
    reveal(secondCell, in: app, named: "full destination exercise card")
    let dropPoint = CGPoint(
      x: secondCell.frame.midX,
      y: min(
        secondCell.frame.midY + secondCell.frame.height * 0.1, editor.frame.maxY - 80,
        app.frame.maxY - 100))
    XCTAssertTrue(editor.frame.contains(dropPoint))
    XCTAssertGreaterThan(dropPoint.y, secondCell.frame.midY)
    let destination = app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: dropPoint.x, dy: dropPoint.y))
    first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: 2, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1)
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while second.frame.minY >= first.frame.minY && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertLessThan(second.frame.minY, first.frame.minY)
    let movedCell = editor.cells.containing(.staticText, identifier: "Тест: жим в наклоне")
      .firstMatch
    let followingCell = editor.cells.containing(.staticText, identifier: "Тест: жим штанги")
      .firstMatch
    let position = NSPredicate(format: "identifier BEGINSWITH %@", "templateExercisePosition_")
    let movedPosition = movedCell.staticTexts.matching(position).firstMatch
    let followingPosition = followingCell.staticTexts.matching(position).firstMatch
    while (movedPosition.label.filter(\.isNumber) != "1"
      || followingPosition.label.filter(\.isNumber) != "2") && ContinuousClock.now < deadline
    {
      try await Task.sleep(for: .milliseconds(100))
    }
    attachScreenshot("Template exercises reordered by dragging", in: app)
    XCTAssertEqual(movedPosition.label.filter(\.isNumber), "1", movedPosition.label)
    XCTAssertEqual(followingPosition.label.filter(\.isNumber), "2", followingPosition.label)
    let replaceID = movedCell.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "replaceTemplateExercise_")
    ).firstMatch.identifier.replacingOccurrences(of: "replaceTemplateExercise_", with: "")
    movedCell.swipeLeft()
    XCTAssertTrue(
      app.buttons["swipeReplaceTemplateExercise_\(replaceID)"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["swipeRemoveTemplateExercise_\(replaceID)"].exists)
    attachScreenshot("Reordered exercise retains swipe actions", in: app)
    movedCell.swipeRight()
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    editCurrentTemplate(in: app)
    let cards = editor.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "templateExerciseCard_"))
    reveal(cards.firstMatch, in: app, named: "reopened first card")
    XCTAssertTrue(cards.firstMatch.staticTexts["Тест: жим в наклоне"].exists)
    XCTAssertEqual(
      cards.firstMatch.staticTexts.matching(position).firstMatch.label.filter(\.isNumber), "1")
  }

  @MainActor func testBottomContentClearsTheNavigationBarOnTemplatesAndResults() {
    let app = launch()
    openFixtureTemplate(in: app)
    let technique = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "templateExerciseTechnique_")
    ).element(boundBy: 1)
    reveal(technique, in: app, named: "last template action")
    app.scrollViews.firstMatch.swipeUp()
    let navigation = app.descendants(matching: .any).matching(identifier: "workoutNavigationBar")
      .firstMatch
    XCTAssertTrue(technique.isHittable)
    XCTAssertLessThanOrEqual(technique.frame.maxY, navigation.frame.minY + 1)
    attachScreenshot("Template bottom remains above navigation", in: app)
    app.buttons["navigationTab_2"].tap()
    let footer = app.staticTexts["resultsFooter"]
    reveal(footer, in: app, named: "results footer")
    app.scrollViews.firstMatch.swipeUp()
    XCTAssertLessThanOrEqual(footer.frame.maxY, navigation.frame.minY + 1)
    attachScreenshot("Results bottom remains above navigation", in: app)
  }

  @MainActor func testActiveExerciseSwipeButtonsHaveMatchingFramesAndNotesClearTheDock() {
    let app = launch()
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_\(templateID)"]
    reveal(template, in: app, named: "fixture template")
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let row = app.buttons.matching(identifier: "openWorkoutExercise").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.swipeLeft()
    let remove = app.buttons["removeWorkoutExercise"]
    let replace = app.buttons["replaceWorkoutExercise"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5) && replace.exists)
    XCTAssertEqual(remove.frame.width, replace.frame.width, accuracy: 1)
    XCTAssertEqual(remove.frame.height, replace.frame.height, accuracy: 1)
    attachScreenshot("Uniform trailing workout swipe actions", in: app)
    row.swipeRight()
    if !app.buttons["insertWorkoutExerciseBefore"].exists { row.swipeRight() }
    let before = app.buttons["insertWorkoutExerciseBefore"]
    let after = app.buttons["insertWorkoutExerciseAfter"]
    XCTAssertTrue(before.waitForExistence(timeout: 5) && after.exists)
    XCTAssertEqual(before.frame.width, after.frame.width, accuracy: 1)
    XCTAssertEqual(before.frame.height, after.frame.height, accuracy: 1)
    attachScreenshot("Uniform leading workout swipe actions", in: app)
    row.swipeLeft()
    row.press(forDuration: 1)
    XCTAssertFalse(app.buttons["groupWorkoutExercise"].exists)
    let notes = app.descendants(matching: .any).matching(identifier: "workoutNotes").firstMatch
    reveal(notes, in: app, named: "workout notes")
    let controls = app.descendants(matching: .any).matching(identifier: "sessionControls")
      .firstMatch
    XCTAssertTrue(notes.isHittable)
    XCTAssertLessThanOrEqual(notes.frame.maxY, controls.frame.minY + 1)
    attachScreenshot("Workout notes remain above the action dock", in: app)
  }

  @MainActor func testRegionalMusclesCanBeSelectedInTheTemplateAndReopened() {
    let app = launch()
    openFixtureTemplate(in: app)
    editCurrentTemplate(in: app)
    app.buttons["chooseTemplateMuscles"].tap()
    let group = app.descendants(matching: .any).matching(identifier: "expandMuscleGroup_chest")
      .firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    group.tap()
    let muscle = app.descendants(matching: .any).matching(identifier: "expandMuscle_chest")
      .firstMatch
    XCTAssertTrue(muscle.waitForExistence(timeout: 5))
    muscle.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let upper = app.switches["muscleRegion_chestUpper"]
    XCTAssertTrue(upper.waitForExistence(timeout: 5))
    upper.tap()
    XCTAssertEqual(upper.value as? String, "1")
    XCTAssertEqual(app.switches["muscleRegion_chestLower"].value as? String, "0")
    attachScreenshot("Anatomically labelled chest regions", in: app)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["saveTemplate"].tap()
    XCTAssertTrue(app.collectionViews["templateEditorList"].waitForNonExistence(timeout: 5))
    editCurrentTemplate(in: app)
    app.buttons["chooseTemplateMuscles"].tap()
    XCTAssertTrue(upper.waitForExistence(timeout: 5))
    XCTAssertEqual(upper.value as? String, "1")
  }

  @MainActor private func createCustomExercise(_ name: String, in app: XCUIApplication) {
    let custom = app.buttons["Своё упражнение"]
    XCTAssertTrue(custom.waitForExistence(timeout: 5))
    custom.tap()
    let field = app.textFields["customExerciseName"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(name)
    app.buttons["saveCustomExercise"].tap()
  }

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
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
      .press(
        forDuration: 0.1,
        thenDragTo:
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
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
