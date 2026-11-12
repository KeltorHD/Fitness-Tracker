import XCTest

final class FitnessTrackerUITests: XCTestCase {
  @MainActor func testCalendarWorkoutFiltersKeepHistoryScopeUntilSelectingADay() {
    let app = launch(additionalArguments: ["--ui-testing-diary-insights", "-appearance", "light"])
    let filters = app.buttons["diaryWorkoutFilters"]
    XCTAssertTrue(filters.waitForExistence(timeout: 10))
    let calendar = app.descendants(matching: .any).matching(identifier: "diaryCalendar").firstMatch
    XCTAssertGreaterThanOrEqual(filters.frame.minY, calendar.frame.minY)
    XCTAssertLessThanOrEqual(filters.frame.maxY, calendar.frame.maxY)
    app.buttons["expandTrainingInsights"].tap()
    let scope = app.staticTexts["historyScope"]
    XCTAssertTrue(scope.waitForExistence(timeout: 5))
    XCTAssertNotEqual(scope.label, "Все тренировки")
    filters.tap()
    let allHistory = app.descendants(matching: .any).matching(identifier: "calendarAllHistory")
      .firstMatch
    XCTAssertTrue(allHistory.waitForExistence(timeout: 5))
    allHistory.tap()
    XCTAssertEqual(scope.label, "Все тренировки")
    let statistics = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "historyWeekStatistics_")
    ).firstMatch
    XCTAssertTrue(statistics.waitForExistence(timeout: 5))
    filters.tap()
    let weeklyStats = app.descendants(matching: .any).matching(identifier: "calendarWeekStatistics")
      .firstMatch
    XCTAssertTrue(weeklyStats.waitForExistence(timeout: 5))
    weeklyStats.tap()
    XCTAssertFalse(statistics.exists)
    let section = app.segmentedControls["diarySection"]
    section.buttons["Питание"].tap()
    XCTAssertFalse(filters.exists)
    section.buttons["Тренировки"].tap()
    XCTAssertTrue(filters.waitForExistence(timeout: 5))
    XCTAssertEqual(scope.label, "Все тренировки")
    XCTAssertFalse(statistics.exists)
    filters.tap()
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Workout filters inside the shared calendar"
    image.lifetime = .keepAlways
    add(image)
    weeklyStats.tap()
    XCTAssertTrue(statistics.waitForExistence(timeout: 5))
    app.buttons["selectedDiaryCalendarDay"].tap()
    XCTAssertNotEqual(scope.label, "Все тренировки")
  }

  @MainActor func testDiaryHeaderTabsFitAboveWeekAndMonthCalendar() {
    let app = launch(additionalArguments: ["--ui-testing-diary-insights", "-appearance", "light"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    let title = app.staticTexts["diaryHeaderTitle"]
    XCTAssertEqual(title.label, "Дневник")
    XCTAssertGreaterThan(title.frame.width, 65)
    XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
    XCTAssertLessThan(section.frame.maxX, title.frame.minX)
    XCTAssertLessThanOrEqual(section.frame.width, 200)
    XCTAssertLessThan(section.frame.maxX, app.buttons["openSettings"].frame.minX)
    XCTAssertFalse(app.navigationBars.buttons["Начать тренировку"].exists)
    for title in ["Тренировки", "Питание", "Сон"] {
      XCTAssertTrue(section.buttons[title].isHittable)
      XCTAssertGreaterThanOrEqual(section.buttons[title].frame.width, 44)
    }
    let calendar = app.descendants(matching: .any).matching(identifier: "diaryCalendar").firstMatch
    XCTAssertLessThan(section.frame.maxY, calendar.frame.minY)
    XCTAssertLessThanOrEqual(calendar.frame.height, 120)
    let selected = app.buttons["selectedDiaryCalendarDay"]
    XCTAssertGreaterThanOrEqual(selected.frame.height, 44)
    XCTAssertGreaterThanOrEqual(selected.frame.width, 44)
    let week = XCTAttachment(screenshot: app.screenshot())
    week.name = "Compact diary header tabs above shared week calendar"
    week.lifetime = .keepAlways
    add(week)
    let toggle = app.buttons["expandDiaryCalendar"]
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "Месяц")
    XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
    XCTAssertLessThan(section.frame.maxY, calendar.frame.minY)
    XCTAssertLessThan(section.frame.maxX, app.buttons["openSettings"].frame.minX)
    let month = XCTAttachment(screenshot: app.screenshot())
    month.name = "Compact diary header tabs above expanded month calendar"
    month.lifetime = .keepAlways
    add(month)
    section.buttons["Питание"].tap()
    XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
    section.buttons["Сон"].tap()
    XCTAssertGreaterThan(title.frame.width, 65)
    XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
    XCTAssertLessThan(section.frame.maxX, app.buttons["openSettings"].frame.minX)
    app.buttons["workoutStartAction"].tap()
    XCTAssertTrue(app.buttons["startSelectedTemplates"].waitForExistence(timeout: 5))
  }

  @MainActor func testNutritionDayCopyIsAvailableWithoutHeaderMenu() {
    let app = launch(additionalArguments: ["--ui-testing-diary-insights"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Питание"].tap()
    XCTAssertEqual(app.staticTexts["nutritionDailyCalories"].label, "720 ккал")
    XCTAssertFalse(app.navigationBars.buttons["Действия питания"].exists)
    XCTAssertEqual(app.staticTexts["diaryHeaderTitle"].label, "Дневник")
    XCTAssertGreaterThan(app.staticTexts["diaryHeaderTitle"].frame.width, 65)
    XCTAssertEqual(app.staticTexts["diaryHeaderTitle"].frame.midX, app.frame.midX, accuracy: 2)
    let copy = app.buttons["copyNutritionDay"]
    reveal(copy, in: app)
    XCTAssertTrue(copy.isEnabled)
    copy.tap()
    XCTAssertTrue(app.buttons["confirmCopyNutrition"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Все приёмы пищи"].exists)
  }

  @MainActor func testSharedDiaryCalendarSwipesWeeksWithoutSwitchingDiaryTabs() {
    let app = launch(additionalArguments: ["--ui-testing-diary-insights"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    let grid = app.descendants(matching: .any).matching(identifier: "diaryCalendarGrid").firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    XCTAssertLessThan(section.frame.maxY, grid.frame.minY)
    XCTAssertLessThan(section.frame.maxX, app.buttons["openSettings"].frame.minX)
    let selected = app.buttons["selectedDiaryCalendarDay"]
    let original = selected.label
    let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)))
    XCTAssertEqual(selected.label, original)
    grid.swipeLeft()
    XCTAssertNotEqual(selected.label, original)
    XCTAssertTrue(section.buttons["Тренировки"].isSelected)
    grid.swipeRight()
    XCTAssertEqual(selected.label, original)
    section.buttons["Питание"].tap()
    XCTAssertEqual(app.staticTexts["nutritionDailyCalories"].label, "720 ккал")
    grid.swipeLeft()
    XCTAssertTrue(section.buttons["Питание"].isSelected)
    XCTAssertEqual(app.staticTexts["nutritionDailyCalories"].label, "0 ккал")
    app.buttons["diaryToday"].tap()
    XCTAssertEqual(app.staticTexts["nutritionDailyCalories"].label, "720 ккал")
    XCTAssertEqual(selected.label, original)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Shared week calendar above nutrition tabs, synthetic UI data"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor func testSharedDiaryMonthExpandsSwipesAndSelectsDatesIndependentlyOfSleepTab() {
    let app = launch(additionalArguments: ["--ui-testing-sleep", "-sleepDiaryEnabled", "YES"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    let toggle = app.buttons["expandDiaryCalendar"]
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "Месяц")
    let original = toggle.label
    let grid = app.descendants(matching: .any).matching(identifier: "diaryCalendarGrid").firstMatch
    XCTAssertGreaterThan(grid.frame.height, 240)
    grid.swipeLeft()
    XCTAssertNotEqual(toggle.label, original)
    XCTAssertTrue(section.buttons["Сон"].isSelected)
    grid.swipeRight()
    XCTAssertEqual(toggle.label, original)
    let day = grid.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "diaryCalendarDay_")
    ).element(boundBy: 10)
    let dateLabel = day.label
    day.tap()
    XCTAssertEqual(app.buttons["selectedDiaryCalendarDay"].label, dateLabel)
    XCTAssertTrue(section.buttons["Сон"].isSelected)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Shared expanded month above sleep diary"
    image.lifetime = .keepAlways
    add(image)
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "Неделя")
    XCTAssertLessThan(grid.frame.height, 60)
  }

  @MainActor func testTrainingTripleRingsUseRecordedPreviousWeekAndAllowSelectingMetrics() {
    let app = launch(additionalArguments: [
      "--ui-testing-diary-insights", "-weeklyGoal", "3", "-appearance", "dark",
    ])
    let sets = app.buttons["trainingRing_sets"]
    XCTAssertTrue(sets.waitForExistence(timeout: 10))
    sets.tap()
    XCTAssertTrue(sets.isSelected)
    let comparison = app.staticTexts["trainingRingComparison"]
    XCTAssertTrue(comparison.label.contains("100"))
    let volume = app.buttons["trainingRing_volume"]
    volume.tap()
    XCTAssertTrue(volume.isSelected)
    XCTAssertTrue(comparison.label.contains("800"))
    XCTAssertTrue(comparison.label.contains("50"))
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Three concentric training rings, synthetic current and previous week"
    image.lifetime = .keepAlways
    add(image)
    volume.tap()
    XCTAssertFalse(volume.isSelected)
    XCTAssertFalse(sets.isSelected)
    let reset = XCTAttachment(screenshot: app.screenshot())
    reset.name = "Training rings restored to full brightness"
    reset.lifetime = .keepAlways
    add(reset)
  }

  @MainActor func testDiaryRingSummariesStartExpandedAndCanBeHiddenIndependently() {
    let app = launch(additionalArguments: [
      "--ui-testing-training-groups", "-weeklyGoal", "3", "-appearance", "dark",
    ])
    let training = app.buttons["expandTrainingInsights"]
    XCTAssertTrue(training.waitForExistence(timeout: 10))
    XCTAssertEqual(training.value as? String, "Развёрнуто")
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "trainingGoalRing").firstMatch.exists)
    let trainingImage = XCTAttachment(screenshot: app.screenshot())
    trainingImage.name = "Training diary weekly activity ring"
    trainingImage.lifetime = .keepAlways
    add(trainingImage)
    training.tap()
    XCTAssertEqual(training.value as? String, "Свёрнуто")
    let section = app.segmentedControls["diarySection"]
    section.buttons["Питание"].tap()
    let nutrition = app.buttons["expandNutritionInsights"]
    XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
    XCTAssertEqual(nutrition.value as? String, "Развёрнуто")
    nutrition.tap()
    XCTAssertEqual(nutrition.value as? String, "Свёрнуто")
    section.buttons["Тренировки"].tap()
    XCTAssertEqual(training.value as? String, "Свёрнуто")
    training.tap()
    XCTAssertEqual(training.value as? String, "Развёрнуто")
    section.buttons["Питание"].tap()
    XCTAssertEqual(nutrition.value as? String, "Свёрнуто")
    nutrition.tap()
    XCTAssertEqual(nutrition.value as? String, "Развёрнуто")
  }

  @MainActor func testNutritionRingSelectionAndSharedDateUseRecordedTotals() {
    let app = launch(additionalArguments: [
      "--ui-testing-diary-insights", "-appearance", "light",
    ])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Питание"].tap()
    let calories = app.staticTexts["nutritionDailyCalories"]
    XCTAssertTrue(calories.waitForExistence(timeout: 5))
    XCTAssertEqual(calories.label, "720 ккал")
    let protein = app.buttons["nutritionMacro_protein"]
    protein.tap()
    XCTAssertTrue(protein.isSelected)
    let ring = app.descendants(matching: .any).matching(identifier: "nutritionMacroRing").firstMatch
    XCTAssertTrue(ring.exists)
    XCTAssertEqual(ring.frame.width, ring.frame.height, accuracy: 2)
    XCTAssertGreaterThan(ring.frame.width, 120)
    ring.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)).tap()
    XCTAssertTrue(app.buttons["nutritionMacro_carbohydrates"].isSelected)
    protein.tap()
    ring.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)).tap()
    XCTAssertTrue(app.buttons["nutritionMacro_carbohydrates"].isSelected)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Nutrition ratios and calorie goal, synthetic UI fixture"
    image.lifetime = .keepAlways
    add(image)
    app.buttons["previousDiaryPeriod"].tap()
    XCTAssertEqual(calories.label, "0 ккал")
    app.buttons["diaryToday"].tap()
    XCTAssertEqual(calories.label, "720 ккал")
  }

  @MainActor func testSleepAlarmOffersThreeDestinationsAndPhoneNeedsNoWatch() {
    let app = launch(additionalArguments: ["--ui-testing-sleep", "-sleepDiaryEnabled", "NO"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    app.buttons["addSleepAlarm"].tap()
    let delivery = app.descendants(matching: .any).matching(identifier: "sleepAlarmDelivery")
      .firstMatch
    XCTAssertTrue(delivery.waitForExistence(timeout: 5))
    delivery.tap()
    XCTAssertTrue(app.buttons["На всех устройствах"].exists)
    XCTAssertTrue(app.buttons["На Apple Watch"].exists)
    XCTAssertFalse(app.buttons["На Apple Watch"].isEnabled)
    app.buttons["На iPhone"].tap()
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "sleepAlarmWindow").firstMatch.exists)
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "sleepWatchConnection").firstMatch.exists
    )
    let editor = XCTAttachment(screenshot: app.screenshot())
    editor.name = "Phone delivery needs no Watch app, system mirroring explained"
    editor.lifetime = .keepAlways
    add(editor)
    app.buttons["saveSleepAlarm"].tap()
    XCTAssertTrue(app.buttons["expandSleepAlarms"].waitForExistence(timeout: 5))
    app.buttons["expandSleepAlarms"].tap()
    let edit = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "editSleepAlarm_")
    ).firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
    XCTAssertTrue(app.navigationBars["Изменить будильник"].waitForExistence(timeout: 5))
    delivery.tap()
    let allDevices = app.buttons["На всех устройствах"]
    XCTAssertTrue(allDevices.waitForExistence(timeout: 5))
    allDevices.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "sleepAlarmWindow").firstMatch.exists)
    app.buttons["saveSleepAlarm"].tap()
    XCTAssertTrue(
      app.staticTexts["iPhone готов · Watch ожидает подготовки"].waitForExistence(timeout: 5))
  }

  @MainActor func testWatchOnlyDestinationKeepsPhoneReserveUntilConfirmation() {
    let app = launch(additionalArguments: [
      "--ui-testing-sleep", "--ui-testing-sleep-watch", "-sleepDiaryEnabled", "NO",
    ])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    app.buttons["addSleepAlarm"].tap()
    let delivery = app.descendants(matching: .any).matching(identifier: "sleepAlarmDelivery")
      .firstMatch
    XCTAssertTrue(delivery.waitForExistence(timeout: 5))
    delivery.tap()
    let watch = app.buttons["На Apple Watch"]
    XCTAssertTrue(watch.isEnabled)
    watch.tap()
    app.buttons["saveSleepAlarm"].tap()
    XCTAssertTrue(
      app.staticTexts["iPhone включён до подтверждения Watch"].waitForExistence(timeout: 5))
  }

  @MainActor func testSleepRingCanToggleSelectionAndDragWithoutClearingIt() {
    let app = launch(additionalArguments: ["--ui-testing-sleep", "-sleepDiaryEnabled", "YES"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    let ring = app.descendants(matching: .any).matching(identifier: "sleepPhaseRing").firstMatch
    XCTAssertTrue(ring.waitForExistence(timeout: 10))
    let deep = ring.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
    deep.tap()
    XCTAssertTrue((ring.value as? String ?? "").contains("Глубокий"))
    let selected = XCTAttachment(screenshot: app.screenshot())
    selected.name = "Sleep phase selected by one tap"
    selected.lifetime = .keepAlways
    add(selected)
    deep.tap()
    XCTAssertEqual(ring.value as? String, "Все фазы")
    let cleared = XCTAttachment(screenshot: app.screenshot())
    cleared.name = "Sleep phases restored after tapping the selected sector"
    cleared.lifetime = .keepAlways
    add(cleared)
    let core = ring.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75))
    ring.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25))
      .press(forDuration: 0.6, thenDragTo: core)
    XCTAssertTrue((ring.value as? String ?? "").contains("Базовый"))
    core.tap()
    XCTAssertEqual(ring.value as? String, "Все фазы")
  }

  @MainActor func testSleepInsightsSelectStageAndMonth() {
    let app = launch(additionalArguments: ["--ui-testing-sleep", "-sleepDiaryEnabled", "YES"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    XCTAssertTrue(app.staticTexts["selectedSleepDuration"].waitForExistence(timeout: 10))
    let ring = app.descendants(matching: .any).matching(identifier: "sleepPhaseRing").firstMatch
    XCTAssertTrue(ring.waitForExistence(timeout: 5))
    ring.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)).tap()
    let header = XCTAttachment(screenshot: app.screenshot())
    header.name = "Interactive sleep overview with labeled UI fixture data"
    header.lifetime = .keepAlways
    add(header)
    let deep = app.buttons["sleepStage_deep"]
    reveal(deep, in: app)
    XCTAssertTrue(
      deep.isSelected, "A tap inside the ring's hole should select the nearby deep-sleep sector")
    let awake = app.buttons["sleepStage_awake"]
    reveal(awake, in: app)
    awake.tap()
    XCTAssertTrue(awake.isSelected)
    deep.tap()
    let detail = app.descendants(matching: .any).matching(identifier: "selectedSleepPhase")
      .firstMatch
    XCTAssertTrue(detail.waitForExistence(timeout: 5))
    XCTAssertTrue(deep.isSelected)
    let phase = XCTAttachment(screenshot: app.screenshot())
    phase.name = "Selected deep sleep interval with UI fixture data"
    phase.lifetime = .keepAlways
    add(phase)
    let period = app.segmentedControls["sleepTrendPeriod"]
    reveal(period, in: app)
    period.buttons["Месяц"].tap()
    XCTAssertTrue(period.buttons["Месяц"].isSelected)
    XCTAssertTrue(app.staticTexts["29 ночей с данными"].exists)
    let month = XCTAttachment(screenshot: app.screenshot())
    month.name = "Sleep month chart excluding one missing night, UI fixture data"
    month.lifetime = .keepAlways
    add(month)
  }

  @MainActor func testSleepAlarmCanBeCreatedDisabledAndEditedWithoutSystemAlarm() {
    let app = launch(additionalArguments: ["--ui-testing-sleep", "-sleepDiaryEnabled", "NO"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    let addAlarm = app.buttons["addSleepAlarm"]
    XCTAssertTrue(addAlarm.waitForExistence(timeout: 10))
    addAlarm.tap()
    app.buttons["saveSleepAlarm"].tap()
    XCTAssertTrue(addAlarm.waitForExistence(timeout: 5))
    app.buttons["expandSleepAlarms"].tap()
    let enabled = app.switches.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "enableSleepAlarm_")
    ).firstMatch
    XCTAssertTrue(enabled.waitForExistence(timeout: 5))
    enabled.tap()
    XCTAssertTrue(app.staticTexts["Выключен"].waitForExistence(timeout: 5))
    let edit = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "editSleepAlarm_")
    ).firstMatch
    edit.tap()
    XCTAssertTrue(app.navigationBars["Изменить будильник"].waitForExistence(timeout: 5))
    app.buttons["saveSleepAlarm"].tap()
    XCTAssertTrue(app.staticTexts["Выключен"].waitForExistence(timeout: 5))
    enabled.tap()
    XCTAssertTrue(
      app.staticTexts["iPhone готов · Watch ожидает подготовки"].waitForExistence(timeout: 5))
  }

  @MainActor func testSleepDiaryOpensAlarmEditorWithoutHealthPermission() {
    let app = launch(additionalArguments: ["-sleepDiaryEnabled", "NO"])
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Сон"].tap()
    XCTAssertTrue(app.buttons["enableSleepDiary"].waitForExistence(timeout: 10))
    let addAlarm = app.buttons["addSleepAlarm"]
    reveal(addAlarm, in: app)
    XCTAssertTrue(addAlarm.isHittable)
    let diary = XCTAttachment(screenshot: app.screenshot())
    diary.name = "Sleep diary before Health opt-in"
    diary.lifetime = .keepAlways
    add(diary)
    addAlarm.tap()
    XCTAssertTrue(app.buttons["saveSleepAlarm"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Новый будильник"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "sleepAlarmWindow").firstMatch.exists)
    let editor = XCTAttachment(screenshot: app.screenshot())
    editor.name = "Sleep alarm deadline and smart window editor"
    editor.lifetime = .keepAlways
    add(editor)
  }

  @MainActor func testNewExerciseRestoresAllThreeHistoricalSetsWithoutCompletionMarks() {
    let app = launch(additionalArguments: ["--ui-testing-previous-sets"])
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    exercise.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(weights.count, 3)
    XCTAssertEqual(repetitions.count, 3)
    let firstSetID = String(weights.firstMatch.identifier.dropFirst("setWeight_".count))
    let note = app.buttons["setNote_\(firstSetID)"]
    XCTAssertTrue(note.exists)
    XCTAssertEqual(note.value as? String, "Рабочий подход")
    let thirdSetID = String(weights.element(boundBy: 2).identifier.dropFirst("setWeight_".count))
    XCTAssertEqual(app.buttons["setNote_\(thirdSetID)"].value as? String, "Заметка")
    for (index, pair) in [(30, 12), (35, 10), (40, 8)].enumerated() {
      XCTAssertEqual(weights.element(boundBy: index).value as? String, String(pair.0))
      XCTAssertEqual(repetitions.element(boundBy: index).value as? String, String(pair.1))
    }
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "correctSetWeight_"))
        .firstMatch.exists)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Three historical targets restored as pending sets"
    screen.lifetime = .keepAlways
    add(screen)
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    XCTAssertEqual(note.value as? String, "Рабочий подход")
  }

  @MainActor func testUncompletedInputsSurviveClosingAndReopeningExercise() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let pendingRepetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_")
    )
    .firstMatch
    XCTAssertTrue(pendingRepetitions.waitForExistence(timeout: 5))
    pendingRepetitions.tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadHide"].tap()
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let pendingWeight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    )
    .firstMatch
    XCTAssertTrue(pendingWeight.waitForExistence(timeout: 5))
    assertEmptyWorkoutField(pendingWeight)
    XCTAssertEqual(pendingRepetitions.value as? String, "11")
    fillWorkoutSet(in: app, weight: 45, repetitions: 11)
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let weight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    ).firstMatch
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_")
    ).firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "45")
    XCTAssertEqual(repetitions.value as? String, "11")
    XCTAssertTrue(app.buttons["completeSet"].isEnabled)
    app.buttons["addWorkoutSet"].tap()
    let copiedWeights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let copiedRepetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertTrue(copiedWeights.element(boundBy: 1).waitForExistence(timeout: 5))
    XCTAssertEqual(copiedWeights.count, 2)
    XCTAssertEqual(copiedWeights.element(boundBy: 1).value as? String, "45")
    XCTAssertEqual(copiedRepetitions.element(boundBy: 1).value as? String, "11")
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Pending values retained in workout overview"
    screen.lifetime = .keepAlways
    add(screen)
  }

  @MainActor private func dismissWorkoutSheet(in app: XCUIApplication) {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
      .press(
        forDuration: 0.1,
        thenDragTo:
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
  }

  @MainActor func testMuscleRegionsStayWithTheirNamedParent() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    app.buttons["addExercise"].tap()
    app.buttons["chooseExerciseMuscles"].tap()
    let arms = app.buttons["expandMuscleGroup_arms"]
    reveal(arms, in: app)
    arms.tap()
    let regions = app.buttons["expandMuscle_biceps"]
    XCTAssertTrue(regions.waitForExistence(timeout: 5))
    XCTAssertEqual(regions.label, "Области: Бицепс")
    regions.tap()
    let longHead = app.switches["muscleRegion_bicepsLong"]
    let shortHead = app.switches["muscleRegion_bicepsShort"]
    XCTAssertTrue(longHead.waitForExistence(timeout: 5))
    XCTAssertTrue(longHead.label.hasPrefix("Бицепс:"))
    reveal(shortHead, in: app)
    shortHead.tap()
    let triceps = app.switches["muscle_triceps"]
    reveal(triceps, in: app)
    XCTAssertEqual(triceps.value as? String, "0")
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Muscle region hierarchy"
    screen.lifetime = .keepAlways
    add(screen)
  }
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
    XCTAssertFalse(app.buttons["closeWorkoutExercise"].exists)
    XCTAssertTrue(app.staticTexts["activeExercisePosition"].exists)
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
    let start = app.buttons["workoutStartAction"]
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
    dismissWorkoutSheet(in: app)
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
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
    let correction = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
    ).firstMatch
    XCTAssertTrue(correction.waitForExistence(timeout: 5))
    correction.tap()
    XCTAssertTrue(app.buttons["numberPadHide"].waitForExistence(timeout: 5))
    app.buttons["numberPadHide"].tap()
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
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
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
  }

  @MainActor func testPreviousWorkoutValuesPrefillTargetsAndFirstDigitReplacesFocusedValue() {
    let app = launch(additionalArguments: ["-appearance", "dark", "-colorTheme", "forest"])
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
    let exercise = app.buttons["openWorkoutExercise"].firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    let overview = XCTAttachment(screenshot: app.screenshot())
    overview.name = "Workout notes spacing"
    overview.lifetime = .keepAlways
    add(overview)
    exercise.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let repetitions = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setRepetitions_"))
    XCTAssertTrue(weights.firstMatch.waitForExistence(timeout: 5))
    assertEmptyWorkoutField(weights.firstMatch)
    assertEmptyWorkoutField(repetitions.firstMatch)
    fillWorkoutSet(in: app, weight: 42, repetitions: 7)
    app.buttons["completeSet"].tap()
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(finish.isEnabled)
    finish.tap()
    let notice = app.alerts["Готово"]
    XCTAssertTrue(notice.waitForExistence(timeout: 5))
    notice.buttons["Хорошо"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
    exercise.tap()
    let weight = weights.firstMatch
    let prefilled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND value == %@", "42"), object: weight)
    XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 5), .completed)
    XCTAssertEqual(repetitions.firstMatch.value as? String, "7")
    XCTAssertFalse(
      app.staticTexts.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "previousSetValues_")
      )
      .firstMatch.exists)
    XCTAssertGreaterThanOrEqual(weight.frame.width, 44)
    XCTAssertLessThanOrEqual(weight.frame.width, 76)
    XCTAssertFalse(app.staticTexts["previousWorkoutValuesHeader"].exists)
    let compactTable = XCTAttachment(screenshot: app.screenshot())
    compactTable.name = "Compact workout table with previous values"
    compactTable.lifetime = .keepAlways
    add(compactTable)

    let setID = String(weight.identifier.dropFirst("setWeight_".count))
    weight.tap()
    XCTAssertTrue(app.buttons["numberPadDigit_4"].waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "42")
    app.buttons["numberPadDigit_4"].tap()
    XCTAssertEqual(weight.value as? String, "4")
    app.buttons["numberPadDigit_5"].tap()
    XCTAssertEqual(weight.value as? String, "45")
    XCTAssertEqual(repetitions.firstMatch.value as? String, "7")
    app.buttons["numberPadHide"].tap()
    XCTAssertEqual(weight.value as? String, "45")
    weight.tap()
    XCTAssertTrue(app.buttons["numberPadDigit_3"].waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "45")
    app.buttons["numberPadDigit_3"].tap()
    XCTAssertEqual(weight.value as? String, "3")
    XCTAssertEqual(repetitions.firstMatch.value as? String, "7")
    app.buttons["numberPadHide"].tap()
    app.buttons["completeSet"].tap()
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    let savedWeight = app.textFields["setWeight_\(setID)"]
    XCTAssertTrue(savedWeight.waitForExistence(timeout: 5))
    XCTAssertEqual(savedWeight.value as? String, "3")
    XCTAssertEqual(app.textFields["setRepetitions_\(setID)"].value as? String, "7")
  }

  @MainActor func testWorkoutTableEditsCompletedRowsWithTheSameNumericPanel() {
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
    XCTAssertEqual(weights.firstMatch.identifier, firstWeightID)
    XCTAssertEqual(app.textFields[firstWeightID].value as? String, "50")
    weights.firstMatch.tap()
    app.buttons["numberPadClear"].tap()
    XCTAssertTrue(app.buttons["numberPadDigit_5"].waitForExistence(timeout: 5))
    app.buttons["numberPadDigit_6"].tap()
    app.buttons["numberPadDigit_0"].tap()
    app.buttons["numberPadNext"].tap()
    app.buttons["numberPadClear"].tap()
    app.buttons["numberPadDigit_1"].tap()
    app.buttons["numberPadDigit_2"].tap()
    app.buttons["numberPadHide"].tap()
    XCTAssertEqual(app.textFields[firstWeightID].value as? String, "60")
    dismissWorkoutSheet(in: app)
    XCTAssertTrue(exercise.waitForExistence(timeout: 5))
    exercise.tap()
    XCTAssertEqual(app.textFields[firstWeightID].value as? String, "60")
    XCTAssertFalse(app.buttons["saveCompletedSetCorrection"].exists)
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
    dismissWorkoutSheet(in: app)
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
    let correction = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_")
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
    dismissWorkoutSheet(in: app)
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
    dismissWorkoutSheet(in: app)
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
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
    dismissWorkoutSheet(in: app)
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

  @MainActor private func addGobletExercise(in app: XCUIApplication) {
    let add = app.buttons["addExercise"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    add.tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
      search.tap()
    }
    search.typeText("Goblet")
    let goblet = app.buttons.containing(.staticText, identifier: "Гоблет-приседания").firstMatch
    XCTAssertTrue(goblet.waitForExistence(timeout: 5))
    goblet.tap()
    let select = app.buttons["selectLibraryExercise"]
    XCTAssertTrue(select.waitForExistence(timeout: 5))
    select.tap()
    XCTAssertTrue(app.buttons["openWorkoutExercise"].firstMatch.waitForExistence(timeout: 5))
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
    let selected = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "setIndex_")
    ).firstMatch
    let selectedID =
      selected.exists ? String(selected.identifier.dropFirst("setIndex_".count)) : nil
    let field =
      selectedID.map { app.textFields["setWeight_\($0)"] }
      ?? app.textFields.matching(
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

  @MainActor func testAppleWatchLivePulseSetupRequiresAnExplicitActiveWorkout() {
    let app = launch()
    app.buttons["openSettings"].tap()
    let tracker = app.buttons["openTracker"]
    reveal(tracker, in: app)
    tracker.tap()
    app.buttons["trackerDevicePicker"].tap()
    app.buttons["Apple Watch"].tap()
    let start = app.buttons["startLiveHeartRate"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(start.isEnabled)
    XCTAssertTrue(
      app.staticTexts["trackerAirPodsSetup"].label.contains("FitnessTracker на Apple Watch"))
    XCTAssertEqual(app.alerts.count, 0)
    let setup = XCTAttachment(screenshot: app.screenshot())
    setup.name = "Apple Watch live pulse setup, explicit start and permission guidance"
    setup.lifetime = .keepAlways
    add(setup)
    app.buttons["trackerModePicker"].tap()
    app.buttons["Bluetooth-пульс"].tap()
    XCTAssertFalse(app.buttons["scanHeartRate"].exists)
    app.buttons["Выбрать Apple «Здоровье»"].tap()
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(start.isEnabled)
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
    dismissWorkoutSheet(in: app)
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
    dismissWorkoutSheet(in: app)
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
    let nutrition = app.segmentedControls["diarySection"].buttons["Питание"]
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

  @MainActor func testDiaryPagesShareDateAndWaterUndoDoesNotChangeWorkouts() {
    let app = launch()
    let section = app.segmentedControls["diarySection"]
    XCTAssertTrue(section.waitForExistence(timeout: 10))
    section.buttons["Питание"].tap()
    let water = app.buttons["addWater_250"]
    XCTAssertTrue(water.waitForExistence(timeout: 5))
    water.tap()
    XCTAssertTrue(app.staticTexts["waterTotal"].label.contains("250"))
    app.buttons["previousDiaryPeriod"].tap()
    XCTAssertFalse(app.buttons["undoWater"].exists)
    app.buttons["diaryToday"].tap()
    XCTAssertTrue(app.buttons["undoWater"].waitForExistence(timeout: 5))
    app.buttons["undoWater"].tap()
    XCTAssertFalse(app.buttons["undoWater"].exists)
    app.swipeRight()
    XCTAssertTrue(section.buttons["Тренировки"].isSelected)
    XCTAssertTrue(app.buttons["workoutStartAction"].exists)
    app.swipeLeft()
    XCTAssertTrue(section.buttons["Питание"].isSelected)
    let add = app.buttons["addFood_breakfast"]
    reveal(add, in: app)
    add.tap()
    app.buttons["addProduct"].tap()
    XCTAssertTrue(app.buttons["scanFoodBarcode"].waitForExistence(timeout: 5))
    app.segmentedControls["foodPickerSource"].buttons["Избранное"].tap()
    XCTAssertTrue(app.staticTexts["Пока нет избранных продуктов"].waitForExistence(timeout: 5))
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
    let start = app.buttons["workoutStartAction"]
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
    dismissWorkoutSheet(in: app)
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    dismissWorkoutSheet(in: app)
    app.buttons["workoutStartAction"].tap()
    XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 5))
    let finish = app.buttons["finishWorkout"]
    XCTAssertTrue(finish.exists)
    XCTAssertTrue(finish.isHittable)
    XCTAssertFalse(finish.isEnabled)
  }

  @MainActor func testPullDownClosesExerciseThenMinimizesWorkoutWithoutLosingSets() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.buttons["workoutStartAction"].isHittable)
    app.buttons["workoutStartAction"].tap()
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
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 5))
    XCTAssertTrue(workoutScroll.waitForNonExistence(timeout: 5))
    XCTAssertFalse(exercise.exists)
    XCTAssertTrue(workout.exists)
  }
  @MainActor func testSetNoteAndContextInsertion() {
    let app = launch()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["workoutStartAction"].tap()
    chooseFreeWorkout(in: app)
    addGobletExercise(in: app)
    app.buttons["openWorkoutExercise"].firstMatch.tap()
    let weights = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "setWeight_"))
    let weight = weights.firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    let weightID = weight.identifier
    let setID = String(weightID.dropFirst("setWeight_".count))
    let note = app.buttons["setNote_\(setID)"]
    XCTAssertFalse(note.exists)
    XCTAssertFalse(app.buttons["Добавить заметку к подходу"].exists)
    let initialWeightWidth = weight.frame.width
    let row = app.cells.containing(.textField, identifier: weightID).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    weight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.05,
        thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
    XCTAssertFalse(app.buttons["numberPadHide"].exists)
    let addNote = app.buttons["noteSwipe_\(setID)"]
    XCTAssertTrue(addNote.waitForExistence(timeout: 5))
    addNote.tap()
    let editor = app.textViews["setNoteEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("Keep elbows close")
    app.buttons["saveSetNote"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    XCTAssertLessThanOrEqual(weight.frame.width, initialWeightWidth)
    XCTAssertGreaterThanOrEqual(weight.frame.width, 44)
    XCTAssertEqual(note.value as? String, "Keep elbows close")
    XCTAssertLessThanOrEqual(note.frame.width, 112)
    note.tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Keep elbows close")
    app.buttons["Закрыть"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    let index = app.descendants(matching: .any).matching(identifier: "setIndex_\(setID)").firstMatch
    index.press(forDuration: 1)
    let contextNote = app.buttons.matching(
      NSPredicate(format: "label == %@", "Заметка к подходу")
    ).firstMatch
    XCTAssertTrue(contextNote.waitForExistence(timeout: 5))
    contextNote.tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Keep elbows close")
    app.buttons["Закрыть"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    let count = weights.count
    index.press(forDuration: 1)
    let addAfter = app.buttons.matching(
      NSPredicate(format: "label == %@", "Добавить подход после")
    ).firstMatch
    XCTAssertTrue(addAfter.waitForExistence(timeout: 5))
    addAfter.tap()
    let insertion = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "count == %d", count + 1), object: weights)
    XCTAssertEqual(XCTWaiter.wait(for: [insertion], timeout: 5), .completed)
    XCTAssertEqual(weights.count, count + 1)
    row.swipeLeft()
    let remove = app.buttons["removeSetTarget_\(setID)"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    remove.tap()
    XCTAssertTrue(app.textFields[weightID].waitForNonExistence(timeout: 5))
    XCTAssertTrue(note.waitForNonExistence(timeout: 5))
    let removal = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "count == %d", count), object: weights)
    XCTAssertEqual(XCTWaiter.wait(for: [removal], timeout: 5), .completed)
    XCTAssertEqual(weights.count, count)
  }

}
