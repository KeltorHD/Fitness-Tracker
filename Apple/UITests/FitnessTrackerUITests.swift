import XCTest

final class FitnessTrackerUITests: XCTestCase {
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

  @MainActor func testBodyWeightCanBeRecordedFromResults() {
    let app = launch()
    app.tabBars.buttons["Результаты"].tap()
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
    app.tabBars.buttons["Результаты"].tap()
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
    app.tabBars.buttons["Результаты"].tap()
    let title = app.staticTexts["trainingMonthTitle"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    let original = title.label
    let card = app.descendants(matching: .any).matching(identifier: "trainingMonthCard").firstMatch
    card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.05,
        thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.5)))
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
    app.tabBars.buttons["Результаты"].tap()
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
    app.tabBars.buttons["Дневник"].tap()
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
    let settings = app.tabBars.buttons["Настройки"]
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
    let settings = app.tabBars.buttons["Настройки"]
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
    app.tabBars.buttons["Дневник"].tap()
    XCTAssertTrue(app.staticTexts["Начните свой дневник"].waitForExistence(timeout: 5))
    XCTAssertFalse(banner.exists)
  }
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
  @MainActor func testAirPodsSetupRequiresAnExplicitActiveWorkout() {
    let app = launch()
    app.tabBars.buttons["Настройки"].tap()
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
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(finish.isEnabled)
    XCTAssertTrue(app.staticTexts["finishWorkoutHint"].exists)
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
    XCTAssertTrue(workoutScroll.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
    workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
      .press(
        forDuration: 0.05,
        thenDragTo: workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5))
    app.buttons["startWorkout"].tap()
    XCTAssertTrue(workoutScroll.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.exists)
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
  }
}
