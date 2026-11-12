import XCTest

final class SupersetUITests: XCTestCase {
  @MainActor func testAddingSupersetRoundAddsOneSetToEveryMember() {
    let app = launchFixture()
    startTemplate(in: app)
    app.buttons["activeWorkoutActions"].tap()
    app.buttons["groupWorkoutExercises"].tap()
    let save = app.buttons["saveWorkoutSuperset"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    let candidates = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "supersetCandidate_"))
    XCTAssertEqual(candidates.count, 2)
    candidates.element(boundBy: 0).tap()
    candidates.element(boundBy: 1).tap()
    save.tap()
    let group = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "openWorkoutSuperset_")
    ).firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    XCTAssertEqual(group.value as? String, "0 из 2")
    group.tap()
    XCTAssertTrue(app.staticTexts["activeSupersetHeading"].waitForExistence(timeout: 5))
    let addRound = app.buttons["addWorkoutSet"]
    XCTAssertEqual(addRound.label, "Добавить круг")
    XCTAssertTrue(addRound.isEnabled)
    addRound.tap()
    let screen = app.descendants(matching: .any)
      .matching(identifier: "workoutExerciseScreen").firstMatch
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
      .press(
        forDuration: 0.1,
        thenDragTo:
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    XCTAssertEqual(group.value as? String, "0 из 3")
    let overview = app.descendants(matching: .any)
      .matching(identifier: "activeWorkoutScroll").firstMatch
    let members = overview.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertEqual(members.count, 2)
    for index in 0..<members.count {
      XCTAssertTrue(members.element(boundBy: index).label.contains("3 подхода"))
    }
    attach("Superset with an added full round", app: app)
  }

  @MainActor func testGroupingAlternatesMembersAndRestsAfterTheWholeRound() async throws {
    let app = launchFixture()
    startTemplate(in: app)
    app.buttons["activeWorkoutActions"].tap()
    app.buttons["groupWorkoutExercises"].tap()
    let save = app.buttons["saveWorkoutSuperset"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    XCTAssertFalse(save.isEnabled)
    let candidates = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "supersetCandidate_"))
    XCTAssertEqual(candidates.count, 2)
    candidates.element(boundBy: 0).tap()
    XCTAssertFalse(save.isEnabled)
    candidates.element(boundBy: 1).tap()
    XCTAssertTrue(save.isEnabled)
    save.tap()
    let group = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "openWorkoutSuperset_")
    ).firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    XCTAssertEqual(group.value as? String, "0 из 2")
    attach("Superset in active workout", app: app)
    group.tap()
    XCTAssertTrue(app.staticTexts["activeSupersetHeading"].waitForExistence(timeout: 5))
    let title = app.staticTexts["activeExerciseTitle"]
    XCTAssertEqual(title.label, "Тест: жим штанги")
    let round = app.descendants(matching: .any).matching(identifier: "supersetRound_0").firstMatch
    XCTAssertTrue(round.exists)
    let members = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "supersetMember_"))
    XCTAssertGreaterThanOrEqual(members.count, 2)
    attach("Superset round with separate exercise inputs", app: app)
    let complete = app.buttons["completeSet"]
    let screen = app.descendants(matching: .any)
      .matching(identifier: "workoutExerciseScreen").firstMatch
    let skipRest = screen.buttons["Пропустить отдых"]
    XCTAssertTrue(complete.isHittable)
    complete.tap()
    XCTAssertEqual(title.label, "Тест: жим в наклоне")
    XCTAssertFalse(skipRest.exists)
    complete.tap()
    XCTAssertEqual(title.label, "Тест: жим штанги")
    XCTAssertTrue(skipRest.waitForExistence(timeout: 5))
    attach("Superset rest after a completed round", app: app)
    skipRest.tap()
    complete.tap()
    XCTAssertEqual(title.label, "Тест: жим в наклоне")
    XCTAssertFalse(skipRest.exists)
    complete.tap()
    XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
    XCTAssertEqual(group.value as? String, "2 из 2")
    XCTAssertTrue(app.buttons["finishWorkout"].isEnabled)
    XCTAssertEqual(app.buttons["finishWorkout"].label, "Завершить и сохранить тренировку")
    app.buttons["finishWorkout"].tap()
    let saved = app.alerts["Готово"]
    XCTAssertTrue(saved.waitForExistence(timeout: 10))
    saved.buttons["Хорошо"].tap()
    XCTAssertTrue(app.buttons["workoutStartAction"].waitForExistence(timeout: 10))
    app.buttons["navigationTab_0"].tap()
    let history = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "historyWorkout_", "Тест: жим на грудь")
    ).firstMatch
    for _ in 0..<8 {
      if history.exists && history.isHittable { break }
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    XCTAssertTrue(history.isHittable)
    history.tap()
    let savedMembers = app.buttons.matching(identifier: "openWorkoutExercise")
    XCTAssertTrue(savedMembers.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(savedMembers.count, 2)
    XCTAssertTrue(savedMembers.element(boundBy: 0).label.contains("Тест: жим штанги"))
    XCTAssertTrue(savedMembers.element(boundBy: 1).label.contains("Тест: жим в наклоне"))
    attach("Saved superset in workout history", app: app)
    savedMembers.firstMatch.tap()
    XCTAssertTrue(app.staticTexts["activeSupersetHeading"].waitForExistence(timeout: 5))
    try await assertSavedColumnsAlign(in: app)
    attach("Saved superset rounds remain grouped", app: app)
  }

  @MainActor private func assertSavedColumnsAlign(in app: XCUIApplication) async throws {
    let screen = app.descendants(matching: .any)
      .matching(identifier: "workoutExerciseScreen").firstMatch
    let weights = screen.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Вес:"))
    let repetitions = screen.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Повторения:"))
    XCTAssertTrue(weights.element(boundBy: 1).waitForExistence(timeout: 5))
    XCTAssertTrue(repetitions.element(boundBy: 1).waitForExistence(timeout: 5))
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    var frames: [CGRect] = []
    repeat {
      frames = [
        weights.element(boundBy: 0).frame, weights.element(boundBy: 1).frame,
        repetitions.element(boundBy: 0).frame, repetitions.element(boundBy: 1).frame,
      ]
      if frames.allSatisfy({ $0.width > 0 && $0.height > 0 }),
        abs(frames[0].midX - frames[1].midX) <= 2,
        abs(frames[2].midX - frames[3].midX) <= 2
      {
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    } while clock.now < deadline
    XCTAssertTrue(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    XCTAssertEqual(frames[0].midX, frames[1].midX, accuracy: 2)
    XCTAssertEqual(frames[2].midX, frames[3].midX, accuracy: 2)
    XCTAssertLessThan(frames[0].midX, frames[2].midX)
    XCTAssertLessThan(frames[1].midX, frames[3].midX)
  }

  @MainActor private func launchFixture() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-testing", "--ui-testing-training-groups", "-AppleLanguages", "(ru)",
      "-AppleLocale", "ru_RU", "-appearance", "dark", "-colorTheme", "forest",
    ]
    app.launch()
    return app
  }

  @MainActor private func startTemplate(in app: XCUIApplication) {
    let start = app.buttons["workoutStartAction"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("Тест: жим на грудь")
    let template = app.buttons["startWorkoutTemplate_90000000-0000-0000-0000-000000000001"]
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.tap()
    app.buttons["startSelectedTemplates"].tap()
    XCTAssertTrue(app.buttons["activeWorkoutActions"].waitForExistence(timeout: 5))
  }

  @MainActor private func attach(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
