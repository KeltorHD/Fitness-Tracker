import XCTest

final class FitnessTrackerUITests: XCTestCase {
  @MainActor func testWorkoutStartCanBeCancelledFromEveryTab() {
    let app = launch()
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    for index in 0...3 {
      app.buttons["navigationTab_\(index)"].tap()
      start.tap()
      XCTAssertTrue(app.buttons["startWorkoutWithoutTemplate"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["startSelectedTemplates"].isEnabled)
      let first = app.buttons["startWorkoutTemplate_20000000-0000-0000-0000-000000000001"]
      reveal(first, in: app)
      first.tap()
      XCTAssertTrue(app.buttons["startSelectedTemplates"].isEnabled)
      app.buttons["closeWorkoutStart"].tap()
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertEqual(start.label, "Начать тренировку")
      XCTAssertFalse(app.buttons["addExercise"].exists)
    }
  }

  @MainActor func testNavigationGlassCanBeDraggedAcrossTabsWithoutStartingWorkout() {
    let app = launch()
    let diary = app.buttons["navigationTab_0"]
    let templates = app.buttons["navigationTab_1"]
    let results = app.buttons["navigationTab_2"]
    let settings = app.buttons["navigationTab_3"]
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(diary.waitForExistence(timeout: 10))
    diary.press(forDuration: 0.1, thenDragTo: results)
    XCTAssertTrue(results.isSelected)
    XCTAssertFalse(app.buttons["startWorkoutWithoutTemplate"].exists)
    results.press(forDuration: 0.1, thenDragTo: settings)
    XCTAssertTrue(settings.isSelected)
    settings.press(forDuration: 0.1, thenDragTo: start)
    XCTAssertTrue(settings.isSelected)
    XCTAssertFalse(app.buttons["startWorkoutWithoutTemplate"].exists)
    settings.press(forDuration: 0.1, thenDragTo: diary)
    XCTAssertTrue(diary.isSelected)
    templates.tap()
    XCTAssertTrue(templates.isSelected)
    start.tap()
    XCTAssertTrue(app.buttons["startWorkoutWithoutTemplate"].waitForExistence(timeout: 5))
    app.buttons["closeWorkoutStart"].tap()
    XCTAssertTrue(templates.isSelected)
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
    let empty = app.buttons["startWorkoutWithoutTemplate"]
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
    XCTAssertFalse(app.buttons["startWorkoutWithoutTemplate"].exists)
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
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
      .firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    weight.tap()
    XCTAssertTrue(app.buttons["numberPadDigit_5"].waitForExistence(timeout: 5))
    app.buttons["numberPadDigit_5"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadHide"].tap()
    let menu = app.buttons["Действия упражнения"]
    menu.tap()
    app.buttons["toggleSetWarmup"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "warmupSet").firstMatch.waitForExistence(
        timeout: 5))
    menu.tap()
    app.buttons["toggleSetWarmup"].tap()
    menu.tap()
    app.buttons["addDropStage"].tap()
    let group = app.descendants(matching: .any).matching(identifier: "dropSetGroup").firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    menu.tap()
    app.buttons["addDropStage"].tap()
    XCTAssertTrue(app.staticTexts["Дропсет · этапов: 3"].waitForExistence(timeout: 5))
    menu.tap()
    app.buttons["removeDropSet"].tap()
    XCTAssertFalse(group.exists)
    XCTAssertEqual(app.alerts.count, 0)
  }
  @MainActor func testNumberPadReplacesValuesAndCopiesFollowingRepetitions() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    app.buttons.containing(.staticText, identifier: "Приседания").firstMatch.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weights = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    weights.firstMatch.tap()
    for digit in [4, 2] { app.buttons["numberPadDigit_\(digit)"].tap() }
    app.buttons["numberPadDecimal"].tap()
    app.buttons["numberPadDigit_5"].tap()
    XCTAssertEqual(weights.firstMatch.value as? String, "42,5")
    app.buttons["numberPadNext"].tap()
    XCTAssertFalse(app.buttons["numberPadDecimal"].isEnabled)
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_0"].tap()
    let repetitions = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertEqual(repetitions.firstMatch.value as? String, "10")
    app.buttons["numberPadHide"].tap()
    app.buttons["addWorkoutSet"].tap()
    repetitions.firstMatch.tap()
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
    let weights = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    let firstWeightID = weights.firstMatch.identifier
    weights.firstMatch.tap()
    app.buttons["numberPadDigit_5"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadNext"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadHide"].tap()
    app.buttons["completeSet"].tap()
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    XCTAssertNotEqual(weights.firstMatch.identifier, firstWeightID)
    XCTAssertFalse(app.buttons[firstWeightID].exists)
    weights.firstMatch.tap()
    XCTAssertTrue(app.buttons["numberPadDigit_5"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.alerts.count, 0)
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
    XCTAssertTrue(weight.label.contains("72"))
    let history = app.buttons["openBodyWeightHistory"]
    for _ in 0..<4 where !history.isHittable { app.swipeDown() }
    XCTAssertTrue(history.isHittable)
    history.tap()
    XCTAssertTrue(app.staticTexts["Взвешивание"].waitForExistence(timeout: 5))
  }

  @MainActor func testBodyWeightIsSavedOnAnActiveWorkout() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
    let edit = app.buttons["editWorkoutBodyWeight"]
    reveal(edit, in: app)
    edit.tap()
    let input = app.textFields["bodyWeightInput"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText("73,2")
    app.buttons["saveBodyWeight"].tap()
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertTrue((input.value as? String)?.contains("73") == true)
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
    for metric in ["maximumWeight", "volume", "oneRepMax", "repetitions", "sets"] {
      let chart = app.descendants(matching: .any).matching(identifier: "exerciseChart_\(metric)")
        .firstMatch
      reveal(chart, in: app)
      XCTAssertTrue(chart.exists)
    }
  }

  @MainActor func testExerciseChartsCanBeOpenedFromCompletedWorkout() {
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
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "exerciseChart_maximumWeight").firstMatch
        .exists)
  }

  @MainActor func testActiveExerciseCanOpenAnEmptyProgressHistory() {
    let app = launch()
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
    app.buttons["startWorkout"].tap()
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
    XCTAssertTrue(app.staticTexts["Нет данных за выбранный период"].waitForExistence(timeout: 5))
  }

  @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<10 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    XCTAssertTrue(element.isHittable)
  }

  @MainActor private func openDemoProfile(in app: XCUIApplication) {
    let settings = app.buttons["navigationTab_3"]
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
    let settings = app.buttons["navigationTab_3"]
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
    let settings = app.buttons["navigationTab_3"]
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
    app.buttons["navigationTab_3"].tap()
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
    app.buttons["startWorkoutWithoutTemplate"].tap()
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
    app.buttons["startWorkoutWithoutTemplate"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    app.buttons["Свернуть"].tap()
    app.buttons["navigationTab_3"].tap()
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
    XCTAssertFalse(app.buttons["startWorkoutWithoutTemplate"].exists)
    app.buttons["Свернуть"].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["navigationTab_3"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_3"].tap()
    let restoredThemes = app.buttons["openColorThemePicker"]
    reveal(restoredThemes, in: app)
    restoredThemes.tap()
    XCTAssertTrue(app.buttons["colorTheme_ocean"].isSelected)
    app.buttons["colorTheme_indigo"].tap()
  }

  @MainActor func testLanguageCanBeChangedWithoutRelaunchingTheApp() {
    let app = launch()
    let settings = app.buttons["navigationTab_3"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let language = app.buttons["appLanguagePicker"]
    if !language.isHittable { app.swipeUp() }
    XCTAssertTrue(language.waitForExistence(timeout: 5))
    language.tap()
    app.buttons["English"].tap()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Journal"].exists)
    let selectedLanguage = app.buttons["appLanguagePicker"]
    selectedLanguage.tap()
    app.buttons["Русский"].tap()
    XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: 5))
  }

  @MainActor func testArchiveToolsAreAvailableFromSettings() {
    let app = launch()
    let settings = app.buttons["navigationTab_3"]
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
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(finish.isEnabled)
    XCTAssertFalse(app.staticTexts["finishWorkoutHint"].exists)
    app.buttons["addExercise"].tap()
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Приседания")
    let squat = app.buttons.containing(.staticText, identifier: "Приседания").firstMatch
    XCTAssertTrue(squat.waitForExistence(timeout: 5))
    squat.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    XCTAssertTrue(app.buttons["addWorkoutSet"].waitForExistence(timeout: 5))
    app.buttons["addWorkoutSet"].tap()
    let complete = app.buttons["completeSet"].firstMatch
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
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
    app.buttons["completeSet"].firstMatch.tap()

    let exerciseScroll = app.scrollViews["workoutExerciseScroll"]
    XCTAssertTrue(exerciseScroll.waitForExistence(timeout: 5))
    exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: exerciseScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    let workoutScroll = app.scrollViews["activeWorkoutScroll"]
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
    let exerciseScroll = app.scrollViews["workoutExerciseScroll"]
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
}
