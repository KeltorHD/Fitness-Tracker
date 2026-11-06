import XCTest

final class FitnessTrackerUITests: XCTestCase {
  @MainActor func testSettingsFromWorkoutMenusKeepTheSessionAndExerciseDraft() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    let title = app.staticTexts["activeWorkoutTitle"].label
    app.buttons["activeWorkoutActions"].tap()
    openSettingsAndReturn(in: app)
    XCTAssertTrue(app.buttons["activeWorkoutActions"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["activeWorkoutTitle"].label, title)
    app.buttons["addExercise"].tap()
    addCustomExercise("Проверка настроек", in: app)
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    ).firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    weight.tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_2"].tap()
    app.buttons["numberPadHide"].tap()
    app.buttons["activeExerciseActions"].tap()
    openSettingsAndReturn(in: app)
    XCTAssertTrue(app.buttons["activeExerciseActions"].waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "12")
    XCTAssertTrue(app.buttons["completeSet"].exists)
  }

  @MainActor func testSettingsFromTemplateMenuReturnToTheTemplate() {
    let app = launch()
    XCTAssertTrue(app.buttons["navigationTab_1"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_1"].tap()
    let bar = app.navigationBars["Шаблоны"]
    XCTAssertTrue(bar.buttons["Упражнения"].exists)
    XCTAssertTrue(bar.buttons["Создать тренировку"].exists)
    XCTAssertTrue(bar.buttons["openSettings"].exists)
    let template = app.buttons["templateRow_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["templateActions"].tap()
    openSettingsAndReturn(in: app)
    XCTAssertTrue(app.buttons["templateActions"].waitForExistence(timeout: 5))
    app.buttons["templateActions"].tap()
    XCTAssertTrue(app.buttons["editTemplate"].waitForExistence(timeout: 5))
  }

  @MainActor private func openSettingsAndReturn(in app: XCUIApplication) {
    let settings = app.buttons["openSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(app.buttons["appLanguagePicker"].waitForExistence(timeout: 5))
    app.navigationBars["Настройки"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["appLanguagePicker"].waitForNonExistence(timeout: 5))
  }

  @MainActor func testSettingsOpenFromEveryMainTabAndReturnToTheSameTab() {
    let app = launch()
    for index in 0...3 {
      let tab = app.buttons["navigationTab_\(index)"]
      XCTAssertTrue(tab.waitForExistence(timeout: 10))
      tab.tap()
      if index == 3 {
        XCTAssertEqual(tab.label, "Справка")
        XCTAssertTrue(app.staticTexts["Раздел пока в разработке."].exists)
        XCTAssertFalse(app.buttons["appLanguagePicker"].exists)
      }
      let settings = app.buttons["openSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      XCTAssertEqual(settings.label, "Настройки")
      settings.tap()
      XCTAssertTrue(app.buttons["appLanguagePicker"].waitForExistence(timeout: 5))
      XCTAssertTrue(tab.isSelected)
      app.navigationBars["Настройки"].buttons.element(boundBy: 0).tap()
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      XCTAssertTrue(tab.isSelected)
      XCTAssertFalse(app.buttons["appLanguagePicker"].exists)
    }
  }

  @MainActor func testWorkoutStartCanBeCancelledFromEveryTab() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    for index in 0...3 {
      app.buttons["navigationTab_\(index)"].tap()
      start.tap()
      XCTAssertTrue(app.buttons["startSelectedTemplates"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["startWorkoutWithoutTemplate"].exists)
      XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
      let first = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
      reveal(first, in: app)
      first.tap()
      XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
      dismissWorkoutStart(in: app)
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertEqual(start.label, "Начать тренировку")
      XCTAssertFalse(app.buttons["addExercise"].exists)
    }
  }

  @MainActor func testWorkoutSwipesInsertAroundAnchorAndConfirmRemoval() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let rows = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    reveal(rows.firstMatch, in: app)
    rows.firstMatch.swipeRight()
    app.buttons["insertWorkoutExerciseBefore"].tap()
    addCustomExercise("Вставка перед", in: app)
    XCTAssertEqual(rows.count, 4)
    XCTAssertTrue(rows.element(boundBy: 0).label.contains("Вставка перед"))
    XCTAssertTrue(rows.element(boundBy: 1).label.contains("Приседания"))
    reveal(rows.element(boundBy: 1), in: app)
    rows.element(boundBy: 1).swipeRight()
    app.buttons["insertWorkoutExerciseAfter"].tap()
    addCustomExercise("Вставка после", in: app)
    XCTAssertEqual(rows.count, 5)
    XCTAssertTrue(rows.element(boundBy: 2).label.contains("Вставка после"))
    reveal(rows.element(boundBy: 2), in: app)
    rows.element(boundBy: 2).swipeLeft()
    app.buttons["removeWorkoutExercise"].tap()
    let confirmRemoval = app.buttons.matching(identifier: "confirmRemoveWorkoutExercise").firstMatch
    XCTAssertTrue(confirmRemoval.waitForExistence(timeout: 5))
    let cancel = app.buttons["Отмена"]
    if cancel.exists && cancel.isHittable {
      cancel.tap()
    } else {
      // A confirmation popover can dismiss on an outside tap without a Cancel button.
      app.descendants(matching: .any).matching(identifier: "activeWorkoutHeader").firstMatch
        .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    XCTAssertTrue(confirmRemoval.waitForNonExistence(timeout: 5))
    XCTAssertEqual(rows.count, 5)
    rows.element(boundBy: 2).swipeLeft()
    app.buttons["removeWorkoutExercise"].tap()
    XCTAssertTrue(confirmRemoval.waitForExistence(timeout: 5))
    confirmRemoval.tap()
    XCTAssertTrue(confirmRemoval.waitForNonExistence(timeout: 5))
    let removal = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "count == 4"), object: rows)
    XCTAssertEqual(XCTWaiter.wait(for: [removal], timeout: 5), .completed)
    XCTAssertEqual(rows.count, 4)
    XCTAssertTrue(rows.element(boundBy: 2).label.contains("Жим лёжа"))
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testWorkoutLongPressReordersAndExerciseNavigationKeepsDrafts() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let rows = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    reveal(rows.element(boundBy: 1), in: app)
    let first = rows.element(boundBy: 0)
    let second = rows.element(boundBy: 1)
    first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 1,
        thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    XCTAssertTrue(rows.firstMatch.label.contains("Жим лёжа"))
    XCTAssertFalse(app.buttons["insertWorkoutExerciseBefore"].exists)
    rows.firstMatch.tap()
    let previous = app.buttons["previousWorkoutExercise"]
    let next = app.buttons["nextWorkoutExercise"]
    XCTAssertTrue(next.waitForExistence(timeout: 5))
    XCTAssertFalse(previous.isEnabled)
    XCTAssertGreaterThanOrEqual(next.frame.height, 44)
    XCTAssertGreaterThanOrEqual(next.frame.width, 44)
    let completion = app.buttons["completeSet"]
    XCTAssertLessThan(abs(next.frame.midY - completion.frame.midY), 12)
    XCTAssertLessThan(abs(previous.frame.midY - completion.frame.midY), 12)
    let weight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    )
    .firstMatch
    weight.tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_9"].tap()
    app.buttons["numberPadHide"].tap()
    next.tap()
    XCTAssertTrue(app.staticTexts["Приседания"].waitForExistence(timeout: 5))
    previous.tap()
    XCTAssertTrue(app.staticTexts["Жим лёжа"].waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "9")
  }

  @MainActor func testExerciseHeaderCanReplaceUnusedExercise() {
    let app = launch()
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let actions = app.buttons["activeExerciseActions"]
    XCTAssertTrue(actions.waitForExistence(timeout: 5))
    let clock = app.staticTexts["activeExerciseDuration"]
    XCTAssertTrue(clock.exists)
    XCTAssertEqual(clock.frame.midX, app.frame.midX, accuracy: 1)
    XCTAssertLessThan(
      app.buttons["closeWorkoutExercise"].frame.minX,
      app.staticTexts["activeExercisePosition"].frame.minX)
    actions.tap()
    app.buttons["replaceCurrentExercise"].tap()
    let custom = app.buttons["Своё упражнение"]
    XCTAssertTrue(custom.waitForExistence(timeout: 5))
    custom.tap()
    let name = app.textFields["customExerciseName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Новое упражнение")
    app.buttons["saveCustomExercise"].tap()
    XCTAssertTrue(app.staticTexts["activeExerciseTitle"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["activeExerciseTitle"].label, "Новое упражнение")
    XCTAssertFalse(app.buttons["finishWorkout"].exists)
  }

  @MainActor private func addCustomExercise(_ name: String, in app: XCUIApplication) {
    let custom = app.buttons["Своё упражнение"]
    XCTAssertTrue(custom.waitForExistence(timeout: 5))
    custom.tap()
    let field = app.textFields["customExerciseName"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(name)
    app.buttons["saveCustomExercise"].tap()
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor func testTemplateOrderBadgeShiftsOnlyTitleAndRenumbersAfterDeselection() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    let firstID = "20000000-0000-0000-0000-000000000001"
    let secondID = "20000000-0000-0000-0000-000000000002"
    let first = app.buttons["startWorkoutTemplate_\(firstID)"]
    let second = app.buttons["startWorkoutTemplate_\(secondID)"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    let title = app.staticTexts["startTemplateTitle_\(firstID)"]
    let expansion = app.buttons["expandStartTemplate_\(firstID)"]
    let initialLeading = first.frame.minX
    let titleLeading = title.frame.minX
    let expansionLeading = expansion.frame.minX
    first.tap()
    let firstBadge = app.staticTexts["templateSelectionOrder_\(firstID)"]
    XCTAssertTrue(firstBadge.waitForExistence(timeout: 5))
    XCTAssertEqual(firstBadge.label, "Порядок: 1")
    XCTAssertEqual(first.frame.minX, initialLeading, accuracy: 1)
    XCTAssertGreaterThan(title.frame.minX, titleLeading)
    XCTAssertLessThan(title.frame.minX - titleLeading, 40)
    XCTAssertLessThan(firstBadge.frame.maxX, title.frame.minX)
    XCTAssertEqual(expansion.frame.minX, expansionLeading, accuracy: 1)
    let card = app.descendants(matching: .any)
      .matching(identifier: "startTemplateCard_\(firstID)").firstMatch
    XCTAssertLessThan(firstBadge.frame.midY, card.frame.midY)
    XCTAssertEqual(firstBadge.frame.minX, initialLeading, accuracy: 1)
    reveal(second, in: app)
    second.tap()
    let secondBadge = app.staticTexts["templateSelectionOrder_\(secondID)"]
    XCTAssertEqual(secondBadge.label, "Порядок: 2")
    for _ in 0..<10 where !first.isHittable { app.swipeDown() }
    XCTAssertTrue(first.isHittable)
    first.tap()
    XCTAssertTrue(firstBadge.waitForNonExistence(timeout: 5))
    XCTAssertEqual(secondBadge.label, "Порядок: 1")
  }

  @MainActor func testTemplateExercisesExpandWithoutChangingSelectionAndSurviveSearch() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    let templateID = "20000000-0000-0000-0000-000000000001"
    let select = app.buttons["startWorkoutTemplate_\(templateID)"]
    let expand = app.buttons["expandStartTemplate_\(templateID)"]
    XCTAssertTrue(expand.waitForExistence(timeout: 5))
    expand.tap()
    let preview = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "startTemplateExercise_")
    ).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    XCTAssertEqual(preview.label, "Приседания")
    XCTAssertFalse(select.isSelected)
    XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
    select.tap()
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("несуществующий шаблон")
    let reset = app.buttons["resetWorkoutTemplateFilters"]
    reveal(reset, in: app)
    reset.tap()
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    XCTAssertTrue(select.isSelected)
    XCTAssertTrue(preview.exists)
    expand.tap()
    XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
    XCTAssertTrue(select.isSelected)
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "openWorkoutExercise").count, 3)
  }

  @MainActor func testDiaryStartOpensTemplatePickerAndSearchKeepsSelection() {
    let app = launch()
    let start = app.buttons["startWorkout"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let first = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    first.tap()
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("несуществующий шаблон")
    XCTAssertTrue(app.staticTexts["Нет подходящих шаблонов"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Выбрано вне фильтра: 1"].exists)
    XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
    let reset = app.buttons["resetWorkoutTemplateFilters"]
    reveal(reset, in: app)
    reset.tap()
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertTrue(first.isSelected)
    dismissWorkoutStart(in: app)
    XCTAssertFalse(app.buttons["addExercise"].exists)
    app.buttons["navigationTab_2"].tap()
    app.buttons["startWorkoutFromResults"].tap()
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
  }

  @MainActor func testNavigationGlassCanBeDraggedAcrossTabsWithoutStartingWorkout() {
    let app = launch()
    let diary = app.buttons["navigationTab_0"]
    let templates = app.buttons["navigationTab_1"]
    let results = app.buttons["navigationTab_2"]
    let help = app.buttons["navigationTab_3"]
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(diary.waitForExistence(timeout: 10))
    diary.press(forDuration: 0.1, thenDragTo: results)
    XCTAssertTrue(results.isSelected)
    XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
    results.press(forDuration: 0.1, thenDragTo: help)
    XCTAssertTrue(help.isSelected)
    help.press(forDuration: 0.1, thenDragTo: start)
    XCTAssertTrue(help.isSelected)
    XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
    help.press(forDuration: 0.1, thenDragTo: diary)
    XCTAssertTrue(diary.isSelected)
    templates.tap()
    XCTAssertTrue(templates.isSelected)
    for index in [0, 3, 1, 2, 0, 1] {
      let tab = app.buttons["navigationTab_\(index)"]
      tab.tap()
      XCTAssertTrue(tab.isSelected)
      XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
    }
    start.tap()
    XCTAssertTrue(app.buttons["startSelectedTemplates"].waitForExistence(timeout: 5))
    dismissWorkoutStart(in: app)
    XCTAssertTrue(templates.isSelected)
  }

  @MainActor func testTemplateParametersKeepSetCountWithoutWeightOrRepetitionTargets() {
    let app = launch()
    XCTAssertTrue(app.buttons["navigationTab_1"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_1"].tap()
    let template = app.buttons["templateRow_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["templateActions"].tap()
    app.buttons["editTemplate"].tap()
    let parameters = app.descendants(matching: .any)
      .matching(identifier: "templateExecutionParameters").firstMatch
    reveal(parameters, in: app)
    parameters.tap()
    let count = app.steppers.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "templateSetCount_")
    ).firstMatch
    reveal(count, in: app)
    let identifier = count.identifier
    let initial = count.label
    count.buttons.element(boundBy: 1).tap()
    let updated = count.label
    XCTAssertNotEqual(updated, initial)
    XCTAssertFalse(app.textFields["Добавленный вес, кг"].exists)
    XCTAssertFalse(
      app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Повторения:")).firstMatch
        .exists)
    app.navigationBars["План тренировки"].buttons["Сохранить"].tap()
    XCTAssertTrue(app.buttons["templateActions"].waitForExistence(timeout: 5))
    app.buttons["templateActions"].tap()
    app.buttons["editTemplate"].tap()
    reveal(parameters, in: app)
    parameters.tap()
    let savedCount = app.steppers[identifier]
    reveal(savedCount, in: app)
    XCTAssertEqual(savedCount.label, updated)
    XCTAssertFalse(app.textFields["Добавленный вес, кг"].exists)
    XCTAssertFalse(
      app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Повторения:")).firstMatch
        .exists)
  }

  @MainActor func testTemplateCardsSupportInlineAndSwipeRemovalWithoutSavingOnCancel() {
    let app = launch()
    XCTAssertTrue(app.buttons["navigationTab_1"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_1"].tap()
    let template = app.buttons["templateRow_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["templateActions"].tap()
    app.buttons["editTemplate"].tap()
    let removals = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "removeTemplateExercise_"))
    reveal(removals.firstMatch, in: app)
    let removalID = removals.firstMatch.identifier
    removals.firstMatch.tap()
    XCTAssertTrue(app.buttons[removalID].waitForNonExistence(timeout: 5))
    app.buttons["cancelTemplateEditing"].tap()
    app.buttons["templateActions"].tap()
    app.buttons["editTemplate"].tap()
    let restored = app.buttons[removalID]
    reveal(restored, in: app)
    let rowID = String(removalID.dropFirst("removeTemplateExercise_".count))
    let card = app.descendants(matching: .any)
      .matching(identifier: "templateExerciseCard_\(rowID)").firstMatch
    card.swipeLeft()
    XCTAssertTrue(restored.exists)
    let swipeRemoval = app.buttons["swipeRemoveTemplateExercise_\(rowID)"]
    XCTAssertTrue(swipeRemoval.waitForExistence(timeout: 5))
    swipeRemoval.tap()
    XCTAssertTrue(restored.waitForNonExistence(timeout: 5))
    app.buttons["cancelTemplateEditing"].tap()
    let technique = app.buttons["templateExerciseTechnique_\(rowID)"]
    reveal(technique, in: app)
    technique.tap()
    XCTAssertTrue(app.staticTexts["Работающие мышцы"].waitForExistence(timeout: 5))
  }

  @MainActor func testTemplateSwipeRequiresConfirmationAndCanBeCancelled() {
    let app = launch()
    XCTAssertTrue(app.buttons["navigationTab_1"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_1"].tap()
    let template = app.buttons["templateRow_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.swipeLeft()
    XCTAssertTrue(template.exists)
    let action = app.buttons["swipeDeleteTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(action.waitForExistence(timeout: 5))
    action.tap()
    XCTAssertTrue(app.buttons["confirmDeleteTemplate"].waitForExistence(timeout: 5))
    app.buttons["Отмена"].tap()
    XCTAssertTrue(template.exists)
    template.swipeLeft()
    action.tap()
    app.buttons["confirmDeleteTemplate"].tap()
    XCTAssertTrue(template.waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testCenterActionStartsEmptyWorkoutAndResumesIt() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let empty = app.buttons["startSelectedTemplates"]
    XCTAssertTrue(empty.waitForExistence(timeout: 5))
    empty.tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["finishWorkout"].isEnabled)
    XCTAssertFalse(app.buttons["openWorkoutExercise"].exists)
    app.buttons["Свернуть"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertEqual(start.label, "Продолжить тренировку")
    app.buttons["navigationTab_1"].tap()
    start.tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
    XCTAssertFalse(app.buttons["openWorkoutExercise"].exists)
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testCenterActionStartsSavedTemplate() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    reveal(template, in: app)
    template.tap()
    XCTAssertFalse(app.buttons["addExercise"].exists)
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["Приседания"].exists)
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testCenterActionCombinesMultipleTemplatesAndAllowsDeselection() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let first = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    let second = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000002"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    reveal(first, in: app)
    first.tap()
    reveal(second, in: app)
    second.tap()
    XCTAssertTrue(app.staticTexts["Выбрано шаблонов: 2"].exists)
    second.tap()
    XCTAssertTrue(app.staticTexts["Выбрано шаблонов: 1"].exists)
    second.tap()
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "openWorkoutExercise").count, 6)
    XCTAssertFalse(app.buttons["finishWorkout"].isEnabled)
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testHealthChartsAreAvailableWithoutRequestingAccessOnOpen() {
    let app = launch()
    app.buttons["navigationTab_2"].tap()
    let link = app.buttons["openHealthCharts"]
    reveal(link, in: app)
    link.tap()
    let toggle = app.switches["enableHealthCharts"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.value as? String, "0")
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "currentHeartRate").firstMatch.exists)
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "dailyHeartRateChart").firstMatch.exists)
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testWarmupAndDropStagesCanBeConfiguredBeforeCompletion() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    fillWorkoutSet(in: app, weight: 50, repetitions: 10)
    XCTAssertTrue(app.buttons["activeExerciseActions"].exists)
    let header = app.staticTexts["activeExerciseTitle"]
    let headerTop = header.frame.minY
    let pulse = app.descendants(matching: .any).matching(identifier: "exerciseHeartRateCard")
      .firstMatch
    XCTAssertTrue(pulse.exists)
    XCTAssertTrue(app.buttons["openWorkoutTracker"].exists)
    let visibility = app.buttons["toggleExerciseHeartRateVisibility"]
    visibility.tap()
    XCTAssertTrue(pulse.waitForNonExistence(timeout: 5))
    visibility.tap()
    XCTAssertTrue(pulse.waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "liveWorkoutHeartRateChart").firstMatch
        .exists)
    XCTAssertTrue(app.buttons["openExerciseTechnique"].exists)
    let media = app.buttons["openExerciseMedia"]
    XCTAssertTrue(media.exists)
    media.tap()
    let viewer = app.descendants(matching: .any).matching(identifier: "exerciseMediaViewer")
      .firstMatch
    XCTAssertTrue(viewer.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["selectLibraryExercise"].exists)
    app.buttons["closeExerciseMedia"].tap()
    XCTAssertTrue(app.buttons["completeSet"].waitForExistence(timeout: 5))
    let complete = app.buttons["completeSet"]
    XCTAssertLessThan(complete.frame.midY, app.buttons["pauseExerciseWorkout"].frame.midY)
    let plus = app.buttons["addWorkoutSet"]
    XCTAssertLessThan(complete.frame.midY, plus.frame.midY)
    XCTAssertGreaterThan(complete.frame.height, plus.frame.height)
    XCTAssertFalse(app.buttons["finishWorkout"].exists)
    XCTAssertGreaterThanOrEqual(plus.frame.width, 56)
    XCTAssertGreaterThanOrEqual(plus.frame.height, 52)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "exerciseActionBlock").firstMatch.exists)
    XCTAssertEqual(header.frame.minY, headerTop, accuracy: 1)
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["toggleSetWarmup"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "warmupSet").firstMatch.waitForExistence(
        timeout: 5))
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["toggleSetWarmup"].tap()
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["addDropStage"].tap()
    let group = app.descendants(matching: .any).matching(identifier: "dropSetGroup").firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["addDropStage"].tap()
    XCTAssertTrue(app.staticTexts["Дропсет · этапов: 3"].waitForExistence(timeout: 5))
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["removeDropSet"].tap()
    XCTAssertFalse(group.exists)
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["addDropStage"].tap()
    app.buttons["completeSet"].tap()
    let append = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "appendDropStage_")
    ).firstMatch
    XCTAssertTrue(append.waitForExistence(timeout: 5))
    append.tap()
    XCTAssertTrue(app.staticTexts["Дропсет · этапов: 3"].waitForExistence(timeout: 5))
    let correction = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "correctSetWeight_")
    ).firstMatch
    XCTAssertTrue(correction.waitForExistence(timeout: 5))
    correction.tap()
    XCTAssertTrue(app.textFields["correctCompletedWeight"].waitForExistence(timeout: 5))
    app.buttons["saveCompletedSetCorrection"].tap()
    let child = app.cells.containing(.any, identifier: "dropStage").firstMatch
    XCTAssertTrue(child.waitForExistence(timeout: 5))
    child.swipeLeft()
    app.buttons["Удалить этап дропсета"].firstMatch.tap()
    XCTAssertFalse(app.buttons["Удалить этап дропсета"].exists)
    XCTAssertTrue(app.staticTexts["Дропсет · этапов: 2"].waitForExistence(timeout: 5))
    XCTAssertTrue(group.exists)
    XCTAssertEqual(app.alerts.count, 0)
  }
  @MainActor func testNumberPadClearsValuesAndCopiesFollowingRepetitions() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    weights.firstMatch.tap()
    app.buttons["numberPadClear"].tap()
    for digit in [4, 2] { app.buttons["numberPadDigit_\(digit)"].tap() }
    app.buttons["numberPadDecimal"].tap()
    app.buttons["numberPadDigit_5"].tap()
    XCTAssertEqual(weights.firstMatch.value as? String, "42,5")
    weights.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
    app.buttons["numberPadDigit_9"].tap()
    XCTAssertEqual(weights.firstMatch.value as? String, "942,5")
    app.buttons["numberPadDelete"].tap()
    XCTAssertEqual(weights.firstMatch.value as? String, "42,5")
    XCTAssertFalse(app.buttons["toggleSetWarmup"].exists)
    app.buttons["numberPadNext"].tap()
    app.buttons["numberPadClear"].tap()
    XCTAssertFalse(app.buttons["numberPadDecimal"].isEnabled)
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_0"].tap()
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertEqual(repetitions.firstMatch.value as? String, "10")
    app.buttons["numberPadHide"].tap()
    app.buttons["addWorkoutSet"].tap()
    repetitions.firstMatch.tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_5"].tap()
    app.buttons["numberPadCopyDown"].tap()
    XCTAssertTrue(app.staticTexts["numberPadFeedback"].waitForExistence(timeout: 5))
    XCTAssertEqual(repetitions.element(boundBy: 1).value as? String, "15")
    app.buttons["numberPadHide"].tap()
    XCTAssertTrue(app.buttons["completeSet"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "workoutNumberPad").firstMatch.exists)
  }

  @MainActor func testNewWorkoutTargetsAreEmptyAndRequireManualInput() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    reveal(template, in: app)
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    let firstWeightID = weights.firstMatch.identifier
    assertEmptyWorkoutField(weights.firstMatch)
    assertEmptyWorkoutField(repetitions.firstMatch)
    app.buttons["completeSet"].tap()
    XCTAssertTrue(app.staticTexts["Вес должен быть от 0 до 1500 кг."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields[firstWeightID].exists)
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "correctSetWeight_"))
        .firstMatch.exists)
    fillWorkoutSet(in: app, repetitions: 0)
    app.buttons["completeSet"].tap()
    XCTAssertTrue(
      app.staticTexts["Число повторений должно быть от 1 до 1000."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields[firstWeightID].exists)
    fillWorkoutSet(in: app)
    app.buttons["completeSet"].tap()
    XCTAssertTrue(app.textFields[firstWeightID].waitForNonExistence(timeout: 5))
    assertEmptyWorkoutField(weights.firstMatch)
    assertEmptyWorkoutField(repetitions.firstMatch)
    app.buttons["closeWorkoutExercise"].tap()
    XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
  }

  @MainActor func testActiveWorkoutShowsRecordedPreviousValuesWithoutFillingNewTargets() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    reveal(template, in: app)
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let previousHeader = app.staticTexts["previousWorkoutValuesHeader"]
    XCTAssertTrue(previousHeader.waitForExistence(timeout: 5))
    XCTAssertEqual(previousHeader.label, "Нет предыдущих значений")
    fillWorkoutSet(in: app, weight: 42, repetitions: 7)
    app.buttons["completeSet"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "correctSetWeight_"))
        .firstMatch.waitForExistence(timeout: 5))
    app.buttons["closeWorkoutExercise"].tap()
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isEnabled)
    finish.tap()
    let notice = app.alerts["Готово"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    notice.buttons["Хорошо"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    reveal(template, in: app)
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    XCTAssertTrue(previousHeader.waitForExistence(timeout: 5))
    XCTAssertTrue(previousHeader.label.hasPrefix("Предыдущая тренировка: "))
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    assertEmptyWorkoutField(weights.firstMatch)
    assertEmptyWorkoutField(repetitions.firstMatch)
    let firstSetID = String(weights.firstMatch.identifier.dropFirst("setWeight_".count))
    let previous = app.staticTexts["previousSetValues_\(firstSetID)"]
    XCTAssertTrue(previous.waitForExistence(timeout: 5))
    XCTAssertTrue(previous.label.hasPrefix("Ранее: 42 "))
    XCTAssertTrue(previous.label.hasSuffix(" × 7"))
    let recordedValues = previous.label
    let secondWeight = weights.element(boundBy: 1)
    reveal(secondWeight, in: app)
    let secondSetID = String(secondWeight.identifier.dropFirst("setWeight_".count))
    let missingPrevious = app.staticTexts["previousSetValues_\(secondSetID)"]
    reveal(missingPrevious, in: app)
    XCTAssertEqual(missingPrevious.label, "Ранее: —")
    app.buttons["pauseExerciseWorkout"].tap()
    XCTAssertTrue(previousHeader.exists)
    for _ in 0..<6 where !previous.isHittable { app.swipeDown() }
    XCTAssertTrue(previous.waitForExistence(timeout: 5))
    XCTAssertEqual(previous.label, recordedValues)
    reveal(missingPrevious, in: app)
    XCTAssertEqual(missingPrevious.label, "Ранее: —")
    XCTAssertFalse(app.buttons["completeSet"].isEnabled)
  }

  @MainActor func testWorkoutTableKeepsEditingAndCompletedRowsReadOnly() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let template = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
    reveal(template, in: app)
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    let firstWeightID = weights.firstMatch.identifier
    weights.firstMatch.tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_5"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadNext"].tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadHide"].tap()
    app.buttons["completeSet"].tap()
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    XCTAssertNotEqual(weights.firstMatch.identifier, firstWeightID)
    XCTAssertFalse(app.textFields[firstWeightID].exists)
    weights.firstMatch.tap()
    app.buttons["numberPadClear"].tap()
    XCTAssertTrue(app.buttons["numberPadDigit_5"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testLastSetAdvancesToNextExerciseAndReadyWorkoutWaitsForExplicitSave() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    chooseFreeWorkout(in: app)
    let firstName = "Первое автоперехода"
    let secondName = "Второе автоперехода"
    app.buttons["addExercise"].tap()
    addCustomExercise(firstName, in: app)
    app.buttons["addExercise"].tap()
    addCustomExercise(secondName, in: app)
    let finish = app.buttons["finishWorkout"]
    XCTAssertEqual(finish.value as? String, "Выполнено этапов: 0 из 2")
    XCTAssertFalse(finish.isEnabled)
    let rows = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertEqual(rows.count, 2)
    rows.element(boundBy: 0).tap()
    let title = app.staticTexts.matching(identifier: "activeExerciseTitle").firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, firstName)
    fillWorkoutSet(in: app, weight: 25, repetitions: 5)
    app.buttons["completeSet"].tap()
    let nextExercise = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND label == %@", secondName), object: title)
    XCTAssertEqual(XCTWaiter.wait(for: [nextExercise], timeout: 5), .completed)
    XCTAssertTrue(app.buttons["completeSet"].isEnabled)
    fillWorkoutSet(in: app, repetitions: 8)
    app.buttons["completeSet"].tap()
    let screen = app.descendants(matching: .any).matching(identifier: "workoutExerciseScreen")
      .firstMatch
    XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertEqual(finish.label, "Завершить и сохранить тренировку")
    XCTAssertEqual(finish.value as? String, "Все упражнения выполнены")
    XCTAssertTrue(finish.isEnabled)
    XCTAssertTrue(app.buttons["addExercise"].isEnabled)
    XCTAssertFalse(app.alerts["Готово"].exists)

    let pause = app.buttons["pauseWorkout"]
    pause.tap()
    XCTAssertEqual(pause.label, "Продолжить")
    XCTAssertEqual(finish.value as? String, "Все упражнения выполнены")
    XCTAssertTrue(finish.isEnabled)
    pause.tap()
    rows.element(boundBy: 1).tap()
    XCTAssertTrue(app.buttons["addWorkoutSet"].waitForExistence(timeout: 5))
    app.buttons["addWorkoutSet"].tap()
    app.buttons["closeWorkoutExercise"].tap()
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertEqual(finish.value as? String, "Выполнено этапов: 2 из 3")
    XCTAssertTrue(finish.isEnabled)
    XCTAssertFalse(app.alerts["Готово"].exists)
    rows.element(boundBy: 1).tap()
    fillWorkoutSet(in: app, repetitions: 6)
    app.buttons["completeSet"].tap()
    XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertEqual(finish.value as? String, "Все упражнения выполнены")
    finish.tap()
    let notice = app.alerts["Готово"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    notice.buttons["Хорошо"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertEqual(start.label, "Начать тренировку")
    app.buttons["navigationTab_0"].tap()
    XCTAssertFalse(app.buttons["resumeWorkout"].exists)
    let saved = app.buttons.containing(.staticText, identifier: "Свободная тренировка").firstMatch
    reveal(saved, in: app)
    saved.tap()
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 2)
    XCTAssertTrue(rows.element(boundBy: 0).label.contains(firstName))
    XCTAssertTrue(rows.element(boundBy: 1).label.contains(secondName))
  }

  @MainActor func testDropSetStaysOpenUntilItsLastStageIsSaved() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    let name = "Дропсет автоперехода"
    addCustomExercise(name, in: app)
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    fillWorkoutSet(in: app, weight: 50, repetitions: 10)
    let index = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch
    index.press(forDuration: 1)
    app.buttons["addDropStage"].tap()
    XCTAssertTrue(app.staticTexts["Дропсет · этапов: 2"].waitForExistence(timeout: 5))
    let complete = app.buttons["completeSet"]
    complete.tap()
    let correction = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "correctSetWeight_")
    ).firstMatch
    XCTAssertTrue(correction.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["activeExerciseTitle"].label, name)
    XCTAssertEqual(complete.value as? String, "Выполнено этапов: 1 из 2")
    XCTAssertTrue(complete.isEnabled)
    fillWorkoutSet(in: app, weight: 40, repetitions: 8)
    complete.tap()
    let screen = app.descendants(matching: .any).matching(identifier: "workoutExerciseScreen")
      .firstMatch
    XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertEqual(finish.value as? String, "Все упражнения выполнены")
    XCTAssertTrue(finish.isEnabled)
    XCTAssertFalse(app.alerts["Готово"].exists)
    XCTAssertTrue(app.buttons["addExercise"].isEnabled)
  }

  @MainActor func testBodyWeightCanBeRecordedFromResults() {
    let app = launch()
    app.buttons["navigationTab_2"].tap()
    let record = app.buttons["recordBodyWeight"]
    reveal(record, in: app)
    record.tap()
    let input = app.textFields["bodyWeightInput"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText("72,5")
    app.buttons["saveBodyWeight"].tap()
    let weight = app.descendants(matching: .any).matching(identifier: "latestBodyWeight").firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    XCTAssertTrue(weight.label.contains("72,5"))
    app.buttons["openSettings"].tap()
    let setting = app.buttons["settingsBodyWeight"]
    XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
    reveal(setting, in: app)
    XCTAssertEqual(setting.value as? String, "72,5 кг")
    setting.tap()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "72,5")
    input.tap()
    input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "74,1")
    app.buttons["saveBodyWeight"].tap()
    XCTAssertTrue(input.waitForNonExistence(timeout: 5))
    XCTAssertEqual(setting.value as? String, "74,1 кг")
    app.navigationBars["Настройки"].buttons.element(boundBy: 0).tap()
    reveal(weight, in: app)
    XCTAssertTrue(weight.label.contains("74,1"))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    let workoutWeight = app.buttons["editWorkoutBodyWeight"]
    XCTAssertTrue(workoutWeight.waitForExistence(timeout: 5))
    XCTAssertTrue(workoutWeight.isHittable)
    XCTAssertEqual(workoutWeight.value as? String, "74,1 кг")
    workoutWeight.tap()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "74,1")
    app.navigationBars["Записать вес"].buttons["Отмена"].tap()
    XCTAssertTrue(input.waitForNonExistence(timeout: 5))
    app.buttons["Свернуть"].tap()
    XCTAssertTrue(app.buttons["navigationTab_2"].waitForExistence(timeout: 5))
    app.buttons["navigationTab_2"].tap()
    let history = app.buttons["openBodyWeightHistory"]
    for _ in 0..<4 where !history.isHittable { app.swipeDown() }
    XCTAssertTrue(history.isHittable)
    history.tap()
    XCTAssertTrue(app.staticTexts["Взвешивание"].waitForExistence(timeout: 5))
  }

  @MainActor func testBodyWeightIsSavedOnAnActiveWorkout() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    let edit = app.buttons["editWorkoutBodyWeight"]
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    XCTAssertTrue(edit.isHittable)
    edit.tap()
    let input = app.textFields["bodyWeightInput"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText("73,2")
    app.buttons["saveBodyWeight"].tap()
    XCTAssertTrue(input.waitForNonExistence(timeout: 5))
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    XCTAssertEqual(edit.value as? String, "73,2 кг")
    let summaryScreenshot = XCTAttachment(screenshot: app.screenshot())
    summaryScreenshot.name = "Active workout body weight summary"
    summaryScreenshot.lifetime = .keepAlways
    add(summaryScreenshot)
    edit.tap()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "73,2")
    app.navigationBars["Записать вес"].buttons["Отмена"].tap()
    XCTAssertTrue(input.waitForNonExistence(timeout: 5))
    app.buttons["Свернуть"].tap()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    let settings = app.buttons["openSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertTrue(settings.isHittable)
    settings.tap()
    let setting = app.buttons["settingsBodyWeight"]
    XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
    reveal(setting, in: app)
    XCTAssertEqual(setting.value as? String, "73,2 кг")
    app.navigationBars["Настройки"].buttons.element(boundBy: 0).tap()
    app.buttons["navigationTab_2"].tap()
    let weight = app.descendants(matching: .any).matching(identifier: "latestBodyWeight").firstMatch
    reveal(weight, in: app)
    XCTAssertTrue(weight.label.contains("73,2"))
    start.tap()
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    XCTAssertEqual(edit.value as? String, "73,2 кг")
  }

  @MainActor func testWorkoutExerciseThumbnailOpensMediaWithoutOpeningTheSetEditor() {
    let app = launch(additionalArguments: ["-appearance", "dark", "-colorTheme", "forest"])
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Goblet")
    let goblet = app.buttons.containing(.staticText, identifier: "Гоблет-приседания").firstMatch
    XCTAssertTrue(goblet.waitForExistence(timeout: 5))
    goblet.tap()
    XCTAssertTrue(app.navigationBars["Гоблет-приседания"].waitForExistence(timeout: 5))
    app.buttons["selectLibraryExercise"].tap()
    let row = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let weight = app.buttons["editWorkoutBodyWeight"]
    XCTAssertTrue(weight.exists)
    XCTAssertTrue(weight.isHittable)
    XCTAssertLessThan(weight.frame.maxY, row.frame.minY)
    let media = app.buttons["openWorkoutExerciseMedia"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(media.frame.width, 44)
    XCTAssertGreaterThanOrEqual(media.frame.height, 44)
    media.tap()
    let viewer = app.descendants(matching: .any).matching(identifier: "exerciseMediaViewer")
      .firstMatch
    XCTAssertTrue(viewer.waitForExistence(timeout: 5))
    let setEditor = app.descendants(matching: .any).matching(identifier: "workoutExerciseScreen")
      .firstMatch
    XCTAssertFalse(setEditor.exists)
    let mediaScreenshot = XCTAttachment(screenshot: app.screenshot())
    mediaScreenshot.name = "Workout exercise thumbnail media"
    mediaScreenshot.lifetime = .keepAlways
    add(mediaScreenshot)
    app.buttons["closeExerciseMedia"].tap()
    XCTAssertTrue(viewer.waitForNonExistence(timeout: 5))
    XCTAssertTrue(media.waitForExistence(timeout: 5))
    XCTAssertFalse(setEditor.exists)
    XCTAssertTrue(row.isHittable)
    row.tap()
    XCTAssertTrue(setEditor.waitForExistence(timeout: 5))
    XCTAssertFalse(viewer.exists)
  }

  @MainActor func testHistoryMonthMenuPreservesCalendarNavigation() {
    let app = launch()
    app.buttons["navigationTab_2"].tap()
    let title = app.staticTexts["trainingMonthTitle"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    let original = title.label
    app.buttons["historyPeriodMenu"].tap()
    app.buttons["Предыдущий месяц"].tap()
    XCTAssertNotEqual(title.label, original)
    app.buttons["historyPeriodMenu"].tap()
    app.buttons["Текущий месяц"].tap()
    XCTAssertEqual(title.label, original)
  }

  @MainActor func testHistoryMonthCanBeSwipedInBothDirections() {
    let app = launch()
    app.buttons["navigationTab_2"].tap()
    let title = app.staticTexts["trainingMonthTitle"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    let original = title.label
    let card = app.descendants(matching: .any).matching(identifier: "trainingMonthCard").firstMatch
    let shortDragStart = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    shortDragStart.press(
      forDuration: 0.05, thenDragTo: shortDragStart.withOffset(CGVector(dx: 30, dy: 0)))
    XCTAssertEqual(title.label, original)
    card.swipeLeft()
    XCTAssertNotEqual(title.label, original)
    app.buttons["historyPeriodMenu"].tap()
    app.buttons["Предыдущий месяц"].tap()
    XCTAssertEqual(title.label, original)
    card.swipeRight()
    XCTAssertNotEqual(title.label, original)
    app.buttons["historyPeriodMenu"].tap()
    app.buttons["Следующий месяц"].tap()
    XCTAssertEqual(title.label, original)
  }

  @MainActor func testResultsShowFiveExerciseChartsAndPeriodPicker() {
    let app = launch()
    openDemoProfile(in: app)
    app.buttons["navigationTab_2"].tap()
    let period = app.buttons["exerciseProgressPeriod"]
    reveal(period, in: app)
    period.tap()
    app.buttons["Всё время"].tap()
    for (title, metrics) in [
      ("Вес и сила", ["maximumWeight", "oneRepMax"]),
      ("Объём", ["volume"]),
      ("Подходы и повторы", ["sets", "repetitions"]),
    ] {
      let group = app.buttons[title]
      reveal(group, in: app)
      for metric in metrics {
        XCTAssertFalse(
          app.descendants(matching: .any).matching(identifier: "exerciseChart_\(metric)")
            .firstMatch.exists)
      }
      group.tap()
      for metric in metrics {
        let chart = app.descendants(matching: .any).matching(identifier: "exerciseChart_\(metric)")
          .firstMatch
        reveal(chart, in: app)
        XCTAssertTrue(chart.exists)
      }
    }
  }

  @MainActor func testExerciseHistoryDefaultsToRecordedSetsAndChartsExpandOnDemand() {
    let app = launch()
    openDemoProfile(in: app)
    app.buttons["navigationTab_0"].tap()
    let workout = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "ДЕМО ·"))
      .firstMatch
    reveal(workout, in: app)
    workout.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    reveal(exercise, in: app)
    exercise.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "workoutExerciseScreen").firstMatch
        .waitForExistence(timeout: 5))
    let progress = app.buttons["openExerciseProgress"].firstMatch
    reveal(progress, in: app)
    progress.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "exerciseProgressScreen").firstMatch
        .waitForExistence(timeout: 5))
    let history = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "exerciseHistoryWorkout_")
    ).firstMatch
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    let recordedSet = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "exerciseHistorySet_")
    ).firstMatch
    XCTAssertTrue(recordedSet.exists)
    XCTAssertTrue(app.staticTexts["Разминка"].firstMatch.exists)
    let chart = app.descendants(matching: .any).matching(identifier: "exerciseChart_maximumWeight")
      .firstMatch
    XCTAssertFalse(chart.exists)
    app.segmentedControls["exerciseHistorySection"].buttons["Графики"].tap()
    XCTAssertFalse(history.exists)
    XCTAssertFalse(chart.exists)
    let group = app.buttons["Вес и сила"]
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    group.tap()
    reveal(chart, in: app)
    XCTAssertTrue(chart.exists)
    for _ in 0..<6 where !group.isHittable { app.swipeDown() }
    group.tap()
    XCTAssertTrue(chart.waitForNonExistence(timeout: 5))
    let section = app.segmentedControls["exerciseHistorySection"]
    for _ in 0..<6 where !section.isHittable { app.swipeDown() }
    section.buttons["История"].tap()
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    XCTAssertTrue(recordedSet.exists)
  }

  @MainActor func testExerciseHistorySearchSortAndTypeFiltersCanBeReset() {
    let app = launch()
    openDemoProfile(in: app)
    app.buttons["navigationTab_0"].tap()
    let workout = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "ДЕМО ·"))
      .firstMatch
    reveal(workout, in: app)
    workout.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    reveal(exercise, in: app)
    exercise.tap()
    let progress = app.buttons["openExerciseProgress"].firstMatch
    reveal(progress, in: app)
    progress.tap()
    let cards = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "exerciseHistoryWorkout_"))
    XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
    let newestID = cards.firstMatch.identifier
    let search = app.textFields["exerciseHistorySearch"]
    search.tap()
    search.typeText("несуществующее занятие\n")
    XCTAssertTrue(app.staticTexts["Нет подходящих занятий"].waitForExistence(timeout: 5))
    XCTAssertFalse(cards.firstMatch.exists)
    app.buttons["resetExerciseHistoryFilters"].tap()
    XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(cards.firstMatch.identifier, newestID)
    app.buttons["exerciseHistorySort"].tap()
    app.buttons["Сначала старые"].tap()
    XCTAssertNotEqual(cards.firstMatch.identifier, newestID)
    app.buttons["exerciseHistoryFilters"].tap()
    app.buttons["Дропсеты"].tap()
    XCTAssertTrue(app.staticTexts["Нет подходящих занятий"].waitForExistence(timeout: 5))
    app.buttons["resetExerciseHistoryFilters"].tap()
    XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(cards.firstMatch.identifier, newestID)
  }

  @MainActor func testActiveExerciseCanOpenAnEmptyProgressHistory() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    reveal(exercise, in: app)
    exercise.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "workoutExerciseScreen").firstMatch
        .waitForExistence(timeout: 5))
    let progress = app.buttons["openExerciseProgress"].firstMatch
    reveal(progress, in: app)
    progress.tap()
    XCTAssertTrue(app.staticTexts["Нет выполненных подходов"].waitForExistence(timeout: 5))
    app.segmentedControls["exerciseHistorySection"].buttons["Графики"].tap()
    XCTAssertTrue(app.staticTexts["Нет данных за выбранный период"].waitForExistence(timeout: 5))
  }

  @MainActor func testFreeWorkoutCanAddTemplatesWithoutRestarting() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    let add = app.buttons["addWorkoutTemplates"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    XCTAssertTrue(add.isHittable)
    let controls = app.descendants(matching: .any).matching(identifier: "sessionControls")
      .firstMatch
    XCTAssertTrue(controls.buttons["addWorkoutTemplates"].exists)
    XCTAssertEqual(app.buttons.matching(identifier: "addWorkoutTemplates").count, 1)
    add.tap()
    let submit = app.buttons["addSelectedTemplates"]
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    XCTAssertFalse(submit.isEnabled)
    app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"].tap()
    XCTAssertTrue(submit.isEnabled)
    submit.tap()
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["activeWorkoutTitle"].label.contains("Свободная тренировка"))
    XCTAssertFalse(app.buttons["finishWorkout"].isEnabled)
    app.buttons["Свернуть"].tap()
    app.buttons["workoutStartAction"].tap()
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor func testWorkoutControlCancellationPreservesPausedSessionUntilConfirmation() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    addCustomExercise("Проверка отмены", in: app)
    let title = app.staticTexts["activeWorkoutTitle"].label
    let controls = app.descendants(matching: .any).matching(identifier: "sessionControls")
      .firstMatch
    XCTAssertTrue(controls.waitForExistence(timeout: 5))
    let cancel = controls.buttons["cancelWorkout"]
    let pause = controls.buttons["pauseWorkout"]
    let addExercise = controls.buttons["addExercise"]
    let addTemplates = controls.buttons["addWorkoutTemplates"]
    XCTAssertTrue(cancel.isHittable)
    XCTAssertTrue(addTemplates.isHittable)
    XCTAssertEqual(app.buttons.matching(identifier: "cancelWorkout").count, 1)
    XCTAssertEqual(app.buttons.matching(identifier: "addWorkoutTemplates").count, 1)
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "label == %@", "Отменить тренировку")).count, 1)
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "label == %@", "Добавить шаблоны")).count, 1)
    pause.tap()
    XCTAssertEqual(pause.label, "Продолжить")
    XCTAssertFalse(addExercise.isEnabled)
    XCTAssertFalse(addTemplates.isEnabled)
    XCTAssertTrue(cancel.isEnabled)
    cancel.tap()
    let confirm = app.buttons["confirmCancelWorkout"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    app.buttons["dismissCancelWorkout"].tap()
    XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["activeWorkoutTitle"].label, title)
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.label.contains("Проверка отмены"))
    XCTAssertEqual(pause.label, "Продолжить")
    pause.tap()
    XCTAssertTrue(addExercise.isEnabled)
    XCTAssertTrue(addTemplates.isEnabled)
    app.buttons["activeWorkoutActions"].tap()
    let menuCancel = app.buttons["cancelWorkoutMenu"]
    XCTAssertTrue(menuCancel.waitForExistence(timeout: 5))
    menuCancel.tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(controls.waitForNonExistence(timeout: 5))
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    XCTAssertTrue(app.buttons["startSelectedTemplates"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["openWorkoutExercise"].exists)
  }

  @MainActor private func chooseFreeWorkout(in app: XCUIApplication) {
    let choice = app.buttons["startSelectedTemplates"]
    XCTAssertTrue(choice.waitForExistence(timeout: 5))
    choice.tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
  }

  @MainActor private func assertEmptyWorkoutField(
    _ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(field.placeholderValue, "—", file: file, line: line)
    let value = field.value as? String ?? ""
    XCTAssertTrue(value.isEmpty || value == field.placeholderValue, file: file, line: line)
  }

  @MainActor private func fillWorkoutSet(
    in app: XCUIApplication, weight: Int = 0, repetitions: Int = 8
  ) {
    let field = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    ).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    app.buttons["numberPadClear"].tap()
    for digit in String(weight) { app.buttons["numberPadDigit_\(digit)"].tap() }
    app.buttons["numberPadNext"].tap()
    app.buttons["numberPadClear"].tap()
    for digit in String(repetitions) { app.buttons["numberPadDigit_\(digit)"].tap() }
    app.buttons["numberPadHide"].tap()
  }

  @MainActor private func dismissWorkoutStart(in app: XCUIApplication) {
    XCTAssertFalse(app.buttons["closeWorkoutStart"].exists)
    let titleBar = app.navigationBars["Шаблоны"]
    XCTAssertTrue(titleBar.waitForExistence(timeout: 5))
    titleBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
  }

  @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<10 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    XCTAssertTrue(element.isHittable)
  }

  @MainActor private func openDemoProfile(in app: XCUIApplication) {
    let settings = app.buttons["openSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let load = app.buttons["loadDemoData"]
    reveal(load, in: app)
    load.tap()
    let confirm = app.buttons["confirmLoadDemoData"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "demoModeBanner").firstMatch
        .waitForExistence(timeout: 5))
  }

  @MainActor func testDemoProfileCanBeOpenedAndClosedWithoutChangingPersonalHistory() {
    let app = launch()
    let settings = app.buttons["openSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let load = app.buttons["loadDemoData"]
    for _ in 0..<4 where !load.isHittable { app.swipeUp() }
    XCTAssertTrue(load.waitForExistence(timeout: 5))
    load.tap()
    let confirm = app.buttons["confirmLoadDemoData"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    let banner = app.descendants(matching: .any).matching(identifier: "demoModeBanner").firstMatch
    XCTAssertTrue(banner.waitForExistence(timeout: 5))
    settings.tap()
    let leave = app.buttons["leaveDemoData"]
    for _ in 0..<4 where !leave.isHittable { app.swipeUp() }
    XCTAssertTrue(leave.waitForExistence(timeout: 5))
    leave.tap()
    app.buttons["confirmLeaveDemoData"].tap()
    app.buttons["navigationTab_0"].tap()
    XCTAssertTrue(app.staticTexts["Начните свой дневник"].waitForExistence(timeout: 5))
    XCTAssertFalse(banner.exists)
  }
  @MainActor func testTrackerOffersBothModesWithoutRequestingPermissionsOnOpen() {
    let app = launch()
    let settings = app.buttons["openSettings"]
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
  @MainActor func testAirPodsSetupRequiresAnExplicitActiveWorkout() {
    let app = launch()
    app.buttons["openSettings"].tap()
    let tracker = app.buttons["openTracker"]
    reveal(tracker, in: app)
    tracker.tap()
    app.buttons["trackerDevicePicker"].tap()
    app.buttons["AirPods Pro 3"].tap()
    XCTAssertTrue(app.staticTexts["trackerAirPodsSetup"].waitForExistence(timeout: 5))
    let start = app.buttons["startLiveHeartRate"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(start.isEnabled)
    XCTAssertEqual(app.alerts.count, 0)
    app.buttons["trackerModePicker"].tap()
    app.buttons["Bluetooth-пульс"].tap()
    XCTAssertFalse(app.buttons["scanHeartRate"].exists)
    app.buttons["Выбрать Apple «Здоровье»"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(start.isEnabled)
    XCTAssertEqual(app.alerts.count, 0)
  }

  @MainActor func testMusclePickerAllowsWholeGroupsAndIndividualMuscles() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    app.buttons["addExercise"].tap()
    let choose = app.buttons["chooseExerciseMuscles"]
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    choose.tap()
    let arms = app.buttons["muscleGroup_arms"]
    XCTAssertTrue(arms.waitForExistence(timeout: 5))
    arms.tap()
    XCTAssertTrue(arms.isSelected)
    let expansion = app.descendants(matching: .any)
      .matching(identifier: "expandMuscleGroup_arms").firstMatch
    reveal(expansion, in: app)
    expansion.tap()
    let biceps = app.switches["muscle_biceps"]
    XCTAssertTrue(biceps.waitForExistence(timeout: 5))
    XCTAssertEqual(biceps.value as? String, "1")
    biceps.tap()
    XCTAssertEqual(biceps.value as? String, "0")
    XCTAssertEqual(app.switches["muscle_triceps"].value as? String, "1")
    XCTAssertEqual(arms.value as? String, "Частично выбрано")
    app.buttons["Готово"].tap()
    choose.tap()
    XCTAssertTrue(app.switches["muscle_biceps"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.switches["muscle_biceps"].value as? String, "0")
    let reset = app.buttons["clearMuscleSelection"]
    reveal(reset, in: app)
    reset.tap()
    XCTAssertFalse(reset.isEnabled)
    app.buttons["Готово"].tap()
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    XCTAssertEqual(choose.value as? String, "Все мышцы")
  }

  @MainActor func testColorThemeSwitchingKeepsActiveWorkoutAndPersistsChoice() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    app.buttons["Свернуть"].tap()
    app.buttons["openSettings"].tap()
    let themes = app.buttons["openColorThemePicker"]
    reveal(themes, in: app)
    themes.tap()
    for name in ["forest", "rose", "amber", "indigo", "ocean"] {
      let option = app.buttons["colorTheme_\(name)"]
      reveal(option, in: app)
      option.tap()
      XCTAssertTrue(option.isSelected)
    }
    // The navigation stack and the active session survive an environment update.
    XCTAssertTrue(app.buttons["colorTheme_ocean"].exists)
    start.tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["startSelectedTemplates"].exists)
    app.buttons["Свернуть"].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 10))
    app.buttons["openSettings"].tap()
    let restoredThemes = app.buttons["openColorThemePicker"]
    reveal(restoredThemes, in: app)
    restoredThemes.tap()
    XCTAssertTrue(app.buttons["colorTheme_ocean"].isSelected)
    app.buttons["colorTheme_indigo"].tap()
  }

  @MainActor func testLanguageCanBeChangedWithoutRelaunchingTheApp() {
    let app = launch()
    let settings = app.buttons["openSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let language = app.buttons["appLanguagePicker"]
    if !language.isHittable { app.swipeUp() }
    XCTAssertTrue(language.waitForExistence(timeout: 5))
    language.tap()
    app.buttons["English"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Journal"].exists)
    let selectedLanguage = app.buttons["appLanguagePicker"]
    selectedLanguage.tap()
    app.buttons["Русский"].tap()
    XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
  }

  @MainActor func testArchiveToolsAreAvailableFromSettings() {
    let app = launch()
    let settings = app.buttons["openSettings"]
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
  @MainActor func testDiaryCanLogManualFoodWithoutNetwork() {
    let app = launch()
    let nutrition = app.buttons["nutritionDiary"]
    XCTAssertTrue(nutrition.waitForExistence(timeout: 10))
    nutrition.tap()
    let snack = app.buttons["addFood_snack"]
    reveal(snack, in: app)
    snack.tap()
    app.buttons["addProduct"].tap()
    app.buttons["manualFood"].tap()
    let fields = [
      ("manualFoodName", "Тестовый продукт"), ("manualCalories", "200"),
      ("manualProtein", "10"), ("manualFat", "8"), ("manualCarbs", "22"),
    ]
    for (identifier, value) in fields {
      let field = app.textFields[identifier]
      reveal(field, in: app)
      field.tap()
      field.typeText(value)
    }
    let add = app.buttons["saveManualFood"]
    reveal(add, in: app)
    add.tap()
    let save = app.buttons["saveFoodEntry"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    save.tap()
    XCTAssertTrue(app.staticTexts["Тестовый продукт"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["200 ккал"].firstMatch.exists)
  }

  @MainActor private func launch(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] + additionalArguments
    app.launch()
    return app
  }
  @MainActor func testLogSetAndFindWorkoutInHistory() {
    let app = launch(additionalArguments: ["-appearance", "dark", "-colorTheme", "forest"])
    let start = app.buttons["startWorkout"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    chooseFreeWorkout(in: app)
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(finish.isEnabled)
    XCTAssertFalse(app.staticTexts["finishWorkoutHint"].exists)
    let add = app.buttons["addExercise"]
    let pause = app.buttons["pauseWorkout"]
    let cancel = app.buttons["cancelWorkout"]
    let templates = app.buttons["addWorkoutTemplates"]
    let controls = app.descendants(matching: .any).matching(identifier: "sessionControls")
      .firstMatch
    XCTAssertTrue(controls.exists)
    XCTAssertTrue(add.isHittable)
    XCTAssertTrue(cancel.isHittable)
    XCTAssertTrue(templates.isHittable)
    XCTAssertLessThan(cancel.frame.midX, pause.frame.midX)
    XCTAssertLessThan(pause.frame.midX, finish.frame.midX)
    XCTAssertGreaterThan(templates.frame.midX, finish.frame.midX)
    XCTAssertGreaterThan(add.frame.midX, templates.frame.midX)
    XCTAssertEqual(finish.frame.midX, controls.frame.midX, accuracy: 2)
    for button in [cancel, pause, templates, add] {
      XCTAssertEqual(button.frame.maxY, finish.frame.maxY, accuracy: 2)
      XCTAssertGreaterThan(button.frame.midY, finish.frame.midY)
      XCTAssertGreaterThanOrEqual(button.frame.width, 44)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
      XCTAssertEqual(button.frame.width, cancel.frame.width, accuracy: 2)
      XCTAssertGreaterThan(finish.frame.height, button.frame.height)
    }
    XCTAssertGreaterThanOrEqual(cancel.frame.minX, controls.frame.minX)
    XCTAssertLessThanOrEqual(add.frame.maxX, controls.frame.maxX)
    // The narrow layout removes gaps without shrinking the controls or overlapping their frames.
    XCTAssertLessThanOrEqual(pause.frame.maxX, finish.frame.minX)
    XCTAssertGreaterThanOrEqual(templates.frame.minX, finish.frame.maxX)
    XCTAssertEqual(finish.label, "Завершить тренировку")
    XCTAssertEqual(finish.value as? String, "Выполнено этапов: 0 из 0")
    let header = app.descendants(matching: .any).matching(identifier: "activeWorkoutHeader")
      .firstMatch
    XCTAssertTrue(header.exists)
    XCTAssertNotNil(
      (header.label + " " + (header.value as? String ?? "")).range(
        of: "[0-9]{2}:[0-9]{2}:[0-9]{2}", options: .regularExpression))
    add.tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Goblet")
    let squat = app.buttons.containing(.staticText, identifier: "Гоблет-приседания").firstMatch
    XCTAssertTrue(squat.waitForExistence(timeout: 5))
    squat.tap()
    XCTAssertTrue(app.navigationBars["Гоблет-приседания"].waitForExistence(timeout: 5))
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    let sessionPanelHeight = controls.frame.height
    let finishCircleWidth = finish.frame.width
    let sessionScreenshot = XCTAttachment(screenshot: app.screenshot())
    sessionScreenshot.name = "Active workout controls"
    sessionScreenshot.lifetime = .keepAlways
    self.add(sessionScreenshot)
    exercise.tap()
    XCTAssertTrue(app.buttons["addWorkoutSet"].waitForExistence(timeout: 5))
    app.buttons["addWorkoutSet"].tap()
    let complete = app.buttons["completeSet"].firstMatch
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    let exercisePanel = app.descendants(matching: .any).matching(identifier: "exerciseActionBlock")
      .firstMatch
    XCTAssertTrue(exercisePanel.waitForExistence(timeout: 5))
    XCTAssertEqual(exercisePanel.frame.height, sessionPanelHeight, accuracy: 2)
    XCTAssertEqual(complete.frame.width, finishCircleWidth, accuracy: 2)
    let exerciseScreenshot = XCTAttachment(screenshot: app.screenshot())
    exerciseScreenshot.name = "Exercise controls"
    exerciseScreenshot.lifetime = .keepAlways
    self.add(exerciseScreenshot)
    fillWorkoutSet(in: app)
    complete.tap()
    app.buttons["closeWorkoutExercise"].tap()
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isEnabled)
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(app.staticTexts["finishWorkoutHint"].exists)
    app.buttons["pauseWorkout"].tap()
    XCTAssertTrue(finish.isEnabled)
    finish.tap()
    let alert = app.alerts["Готово"]
    if alert.waitForExistence(timeout: 3) { alert.buttons["Хорошо"].tap() }
    app.buttons["navigationTab_0"].tap()
    XCTAssertTrue(app.staticTexts["Свободная тренировка"].waitForExistence(timeout: 5))
  }
  @MainActor func testMinimizedSessionCanBeResumed() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["Свернуть"].tap()
    app.buttons["startWorkout"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.exists)
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(finish.isEnabled)
  }

  @MainActor func testPullDownClosesExerciseThenMinimizesWorkoutWithoutLosingSets() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    XCTAssertTrue(app.buttons["addWorkoutSet"].waitForExistence(timeout: 5))
    app.buttons["addWorkoutSet"].tap()
    fillWorkoutSet(in: app)
    app.buttons["completeSet"].firstMatch.tap()

    let exerciseScroll = app.descendants(matching: .any).matching(
      identifier: "workoutExerciseScroll"
    ).firstMatch
    XCTAssertTrue(exerciseScroll.waitForExistence(timeout: 5))
    exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    let workoutScroll = app.descendants(matching: .any).matching(identifier: "activeWorkoutScroll")
      .firstMatch
    XCTAssertTrue(exerciseScroll.waitForNonExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
    workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.buttons["startWorkout"].isHittable)
    app.buttons["startWorkout"].tap()
    XCTAssertTrue(workoutScroll.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.exists)
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
  }

  @MainActor func testCompletedWorkoutAndExerciseDismissOneSheetAtATime() {
    let app = launch()
    openDemoProfile(in: app)
    app.buttons["navigationTab_0"].tap()
    let workout = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "ДЕМО ·"))
      .firstMatch
    reveal(workout, in: app)
    workout.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let exerciseScroll = app.descendants(matching: .any).matching(
      identifier: "workoutExerciseScroll"
    ).firstMatch
    XCTAssertTrue(exerciseScroll.waitForExistence(timeout: 5))
    exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    let workoutScroll = app.scrollViews["workoutDetailScroll"]
    XCTAssertTrue(exerciseScroll.waitForNonExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForExistence(timeout: 5))
    XCTAssertTrue(exercise.isHittable)
    workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForNonExistence(timeout: 5))
    XCTAssertFalse(exercise.exists)
    XCTAssertTrue(workout.exists)
  }
  @MainActor func testSetNoteAndContextInsertion() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    XCTAssertTrue(app.buttons["selectLibraryExercise"].waitForExistence(timeout: 5))
    app.buttons["selectLibraryExercise"].tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    )
    .firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    let initialWeightWidth = weight.frame.width
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["Заметка к подходу"].tap()
    let editor = app.textViews["setNoteEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("Keep elbows close")
    app.buttons["saveSetNote"].tap()
    let note = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "setNote_"))
      .firstMatch
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    XCTAssertLessThan(weight.frame.width, initialWeightWidth)
    XCTAssertEqual(note.value as? String, "Keep elbows close")
    XCTAssertLessThanOrEqual(note.frame.width, 112)
    note.tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Keep elbows close")
    app.buttons["Закрыть"].tap()
    let count = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    )
    .count
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setIndex_")
    ).firstMatch.press(forDuration: 1)
    app.buttons["Добавить подход после"].tap()
    XCTAssertEqual(
      app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")).count,
      count + 1)
    app.cells.containing(.textField, identifier: weight.identifier).firstMatch.swipeLeft()
    app.buttons["Удалить подход"].firstMatch.tap()
    XCTAssertFalse(app.buttons["Удалить подход"].exists)
    XCTAssertFalse(note.exists)
  }

}
