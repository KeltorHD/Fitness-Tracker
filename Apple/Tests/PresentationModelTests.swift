import FitLifeCore
import XCTest

@testable import FitLife

@MainActor private final class ControlledCloudAccount: CloudAccountChecking {
  private(set) var requests: [CheckedContinuation<CloudAccountStatus, any Error>] = []
  private var waiter: CheckedContinuation<Void, Never>?

  func accountStatus() async throws -> CloudAccountStatus {
    try await withCheckedThrowingContinuation { continuation in
      requests.append(continuation)
      waiter?.resume()
      waiter = nil
    }
  }
  func waitForRequest(count: Int) async {
    while requests.count < count {
      await withCheckedContinuation { waiter = $0 }
    }
  }
}

@MainActor private final class NotificationStub: RestNotificationServing {
  var result: Result<Bool, any Error> = .success(true)
  func authorize() async throws -> Bool { try result.get() }
  func schedule(until date: Date?) async throws {}
  func cancel() {}
}

@MainActor final class PresentationModelTests: XCTestCase {
  func testExternalSupersetCompletionSelectsNextMemberAndKeepsUnsavedDrafts() throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs),
      sets: [WorkoutSet(repetitions: 8, weightKG: 40), WorkoutSet(repetitions: 8, weightKG: 40)])
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20), WorkoutSet(repetitions: 12, weightKG: 20)])
    var workout = Workout(name: "External completion", exercises: [first, second])
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    model.editWeight("42", setID: first.sets[1].id)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: first.id, setID: first.sets[0].id,
      repetitions: 8, weightKG: 40)
    model.refresh(workout)
    XCTAssertEqual(model.exerciseID, second.id)
    XCTAssertEqual(model.selectedSetID, second.sets[0].id)
    XCTAssertEqual(model.drafts[first.sets[1].id]?.weight, "42")
    let completion = try model.completion(in: workout)
    XCTAssertEqual(completion.exerciseID, second.id)
    XCTAssertEqual(completion.set.weightKG, 20)
  }

  func testAddingRoundAfterOpeningCompletedSecondMemberSelectsFirstNewMember() throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs), sets: [WorkoutSet(repetitions: 8, weightKG: 40)]
    )
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20)])
    var workout = Workout(name: "Additional round", exercises: [first, second])
    let supersetID = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    for row in [first, second] {
      try WorkoutEngine.completeSet(
        in: &workout, exerciseID: row.id, setID: row.sets[0].id,
        repetitions: row.sets[0].repetitions, weightKG: row.sets[0].weightKG)
    }
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: second.id, unit: .kilograms, locale: Locale(identifier: "en_US")
    )
    XCTAssertNil(model.selectedSetID)
    try WorkoutEngine.addSupersetRound(supersetID: supersetID, to: &workout)
    model.refresh(workout)
    XCTAssertEqual(model.exerciseID, first.id)
    XCTAssertEqual(model.selectedSetID, workout.exercises[0].sets[1].id)
    XCTAssertEqual(model.drafts[workout.exercises[0].sets[1].id]?.weight, "")
    XCTAssertEqual(model.drafts[workout.exercises[1].sets[1].id]?.repetitions, "")
  }

  func testCompletingStandaloneExerciseEntersPartiallyCompletedSupersetInRoundOrder() throws {
    let standalone = WorkoutExercise(
      exercise: Exercise(name: "Standalone", muscle: .back), sets: [WorkoutSet(repetitions: 10)])
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs),
      sets: [WorkoutSet(repetitions: 8, weightKG: 40), WorkoutSet(repetitions: 8, weightKG: 40)])
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20), WorkoutSet(repetitions: 12, weightKG: 20)])
    var workout = Workout(name: "Transition", exercises: [standalone, first, second])
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: first.id, setID: first.sets[0].id,
      repetitions: 8, weightKG: 40)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: standalone.id, unit: .kilograms,
      locale: Locale(identifier: "en_US"))
    let completion = try model.completion(in: workout)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: completion.exerciseID, setID: completion.set.id,
      repetitions: completion.set.repetitions, weightKG: completion.set.weightKG)
    let advance = model.advance(afterSaving: completion, in: workout)
    guard case .moved = advance else { return XCTFail("Expected to enter the next group") }
    XCTAssertEqual(model.exerciseID, second.id)
    XCTAssertEqual(model.selectedSetID, second.sets[0].id)
  }

  func testExplicitSupersetMemberActionConfiguresTheRequestedMembersDropSet() throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs), sets: [WorkoutSet(repetitions: 8, weightKG: 40)]
    )
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20)])
    var workout = Workout(name: "Member action", exercises: [first, second])
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    model.showExercise(second.id, in: workout)
    let configured = try model.configuredDropSet(
      in: workout, adding: true, setID: second.sets[0].id)
    XCTAssertEqual(model.exerciseID, second.id)
    XCTAssertEqual(configured.id, second.sets[0].id)
    XCTAssertEqual(configured.weightKG, 20)
    XCTAssertEqual(configured.dropStages?.first?.weightKG, 16)
    XCTAssertNil(workout.exercises[0].sets[0].dropStages)
  }

  func testSupersetUsesEachMembersHistoryAndKeepsDraftsIsolated() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let earlier = date.addingTimeInterval(-3600)
    let first = Exercise(name: "First member", muscle: .legs)
    let second = Exercise(name: "Second member", muscle: .legs)
    var history = Workout(
      name: "Earlier", startedAt: earlier,
      exercises: [
        WorkoutExercise(
          exercise: first,
          sets: [WorkoutSet(repetitions: 8, weightKG: 40, completedAt: earlier)]),
        WorkoutExercise(
          exercise: second,
          sets: [WorkoutSet(repetitions: 12, weightKG: 20, completedAt: earlier)]),
      ])
    try WorkoutEngine.finish(&history, at: earlier.addingTimeInterval(60))
    let firstRow = WorkoutExercise(exercise: first, sets: [WorkoutSet(repetitions: 0)])
    let secondRow = WorkoutExercise(exercise: second, sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Now", startedAt: date, exercises: [firstRow, secondRow])
    _ = try WorkoutEngine.groupExercises([firstRow.id, secondRow.id], in: &workout)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: secondRow.id, unit: .kilograms,
      locale: Locale(identifier: "en_US"), history: [history])
    XCTAssertEqual(model.exerciseID, firstRow.id)
    XCTAssertEqual(model.drafts[firstRow.sets[0].id]?.weight, "40")
    XCTAssertEqual(model.drafts[secondRow.sets[0].id]?.weight, "20")
    XCTAssertEqual(model.drafts[secondRow.sets[0].id]?.repetitions, "12")
    model.editWeight("45", setID: firstRow.sets[0].id)
    model.select(secondRow.sets[0].id, in: workout)
    model.updateHistory([history], for: workout)
    XCTAssertEqual(model.exerciseID, secondRow.id)
    XCTAssertEqual(model.selectedSetID, secondRow.sets[0].id)
    XCTAssertEqual(model.drafts[firstRow.sets[0].id]?.weight, "45")
    XCTAssertEqual(try model.completion(in: workout).set.weightKG, 20)
  }

  func testSupersetCompletionAdvancesByRoundThenMovesToNextExercise() throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs),
      sets: [WorkoutSet(repetitions: 8, weightKG: 40), WorkoutSet(repetitions: 8, weightKG: 40)])
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20), WorkoutSet(repetitions: 12, weightKG: 20)])
    let final = WorkoutExercise(
      exercise: Exercise(name: "C", muscle: .back), sets: [WorkoutSet(repetitions: 10)])
    var workout = Workout(name: "Rounds", exercises: [first, second, final])
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let order = [
      (first.id, first.sets[0].id), (second.id, second.sets[0].id),
      (first.id, first.sets[1].id), (second.id, second.sets[1].id),
    ]
    for (index, target) in order.enumerated() {
      XCTAssertEqual(model.exerciseID, target.0)
      XCTAssertEqual(model.selectedSetID, target.1)
      let completion = try model.completion(in: workout)
      try WorkoutEngine.completeSet(
        in: &workout, exerciseID: completion.exerciseID, setID: completion.set.id,
        repetitions: completion.set.repetitions, weightKG: completion.set.weightKG)
      let advance = model.advance(afterSaving: completion, in: workout)
      guard case .moved = advance else {
        XCTFail("A completed superset member should select the next member or exercise")
        return
      }
      if index == 0 { XCTAssertNil(workout.restEndsAt) }
      if index == 1 { XCTAssertNotNil(workout.restEndsAt) }
    }
    XCTAssertEqual(model.exerciseID, final.id)
    XCTAssertEqual(workout.status, .active)
  }

  func testSupersetKeyboardAdvancesAcrossMembersButCopiesOnlyWithinOneExercise() throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .legs),
      sets: [WorkoutSet(repetitions: 8, weightKG: 40), WorkoutSet(repetitions: 8, weightKG: 40)])
    let second = WorkoutExercise(
      exercise: Exercise(name: "B", muscle: .legs),
      sets: [WorkoutSet(repetitions: 12, weightKG: 20), WorkoutSet(repetitions: 12, weightKG: 20)])
    var workout = Workout(name: "Fields", exercises: [first, second])
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let keyboard = WorkoutNumberPadModel(editor: model, locale: Locale(identifier: "en_US"))
    keyboard.begin(.weight(first.sets[0].id), in: workout)
    keyboard.digit(5)
    keyboard.copyDown(in: workout)
    XCTAssertEqual(model.drafts[first.sets[1].id]?.weight, "5")
    XCTAssertEqual(model.drafts[second.sets[0].id]?.weight, "20")
    XCTAssertEqual(model.drafts[second.sets[1].id]?.weight, "20")
    keyboard.begin(.repetitions(first.sets[0].id), in: workout)
    keyboard.advance(in: workout)
    XCTAssertEqual(keyboard.field, .weight(second.sets[0].id))
    XCTAssertEqual(model.exerciseID, second.id)
    keyboard.digit(6)
    XCTAssertEqual(model.drafts[second.sets[0].id]?.weight, "6")
    XCTAssertEqual(model.drafts[first.sets[0].id]?.weight, "5")
  }

  func testPreviousValuesPopulateDraftsAndUnchangedCompletionKeepsExactKilograms() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let earlier = date.addingTimeInterval(-3600)
    let exercise = Exercise(name: "Previous", muscle: .back)
    var history = Workout(
      name: "Earlier", startedAt: earlier,
      exercises: [
        WorkoutExercise(
          exercise: exercise,
          sets: [WorkoutSet(repetitions: 8, weightKG: 25.123456, completedAt: earlier)])
      ])
    try WorkoutEngine.finish(&history, at: earlier.addingTimeInterval(60))
    let row = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Now", startedAt: date, exercises: [row])
    let original = workout
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .pounds, locale: Locale(identifier: "en_US"),
      history: [history])
    XCTAssertFalse(try XCTUnwrap(model.drafts[row.sets[0].id]).weight.isEmpty)
    XCTAssertEqual(model.drafts[row.sets[0].id]?.repetitions, "8")
    let completion = try model.completion(in: workout)
    XCTAssertEqual(completion.set.weightKG, 25.123456)
    XCTAssertEqual(completion.set.repetitions, 8)
    XCTAssertEqual(workout, original)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: completion.set.id,
      repetitions: completion.set.repetitions, weightKG: completion.set.weightKG,
      at: date.addingTimeInterval(1))
    model.refresh(workout)
    history.exercises[0].sets[0].weightKG = 30
    model.updateHistory([history], for: workout)
    XCTAssertNil(model.drafts[row.sets[0].id])
    XCTAssertEqual(workout.exercises[0].sets[0].weightKG, 25.123456)
  }

  func testHistoryRefreshPreservesEditedFieldsAndNeverRestoresAnExplicitClear() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let earlier = date.addingTimeInterval(-3600)
    let exercise = Exercise(name: "Previous", muscle: .back)
    var history = Workout(
      name: "Earlier", startedAt: earlier,
      exercises: [
        WorkoutExercise(
          exercise: exercise, sets: [WorkoutSet(repetitions: 8, weightKG: 30, completedAt: earlier)]
        )
      ])
    try WorkoutEngine.finish(&history, at: earlier.addingTimeInterval(60))
    let row = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
    let workout = Workout(name: "Now", startedAt: date, exercises: [row])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"),
      history: [history])
    model.editRepetitions("10", setID: row.sets[0].id)
    history.exercises[0].sets[0].weightKG = 35
    history.exercises[0].sets[0].repetitions = 12
    model.updateHistory([history], for: workout)
    XCTAssertEqual(model.drafts[row.sets[0].id]?.weight, "35")
    XCTAssertEqual(model.drafts[row.sets[0].id]?.repetitions, "10")
    model.editWeight("0", setID: row.sets[0].id)
    model.updateHistory([history], for: workout)
    XCTAssertEqual(try model.completion(in: workout).set.weightKG, 0)
    model.editWeight("", setID: row.sets[0].id)
    model.updateHistory([history], for: workout)
    XCTAssertEqual(model.drafts[row.sets[0].id]?.weight, "")
    XCTAssertThrowsError(try model.completion(in: workout))
    model.editWeight("45", setID: row.sets[0].id)
    model.updateHistory([], for: workout)
    XCTAssertEqual(try model.completion(in: workout).set.weightKG, 45)
    XCTAssertEqual(try model.completion(in: workout).set.repetitions, 10)
    XCTAssertEqual(workout.exercises[0].sets[0].weightKG, 0)
    XCTAssertEqual(workout.exercises[0].sets[0].repetitions, 0)
  }

  func testCloudCancellationClearsLoadingWithoutDisplayingAnError() async {
    let cloud = ControlledCloudAccount()
    let model = SettingsViewModel(cloud: cloud, notifications: NotificationStub())
    let request = Task { await model.checkCloudAccount() }
    await cloud.waitForRequest(count: 1)
    XCTAssertEqual(model.cloudState, .loading)
    request.cancel()
    cloud.requests[0].resume(returning: .available)
    await request.value
    XCTAssertEqual(model.cloudState, .idle)
  }

  func testOlderCloudResponseCannotOverwriteTheLatestRequest() async {
    let cloud = ControlledCloudAccount()
    let model = SettingsViewModel(cloud: cloud, notifications: NotificationStub())
    let first = Task { await model.checkCloudAccount() }
    await cloud.waitForRequest(count: 1)
    let second = Task { await model.checkCloudAccount() }
    await cloud.waitForRequest(count: 2)
    cloud.requests[1].resume(returning: .available)
    await second.value
    cloud.requests[0].resume(returning: .noAccount)
    await first.value
    XCTAssertEqual(model.cloudState, .result(CloudAccountStatus.available.message))
  }

  func testCloudFailureOffersRetryWithoutDisplayingInternalErrorDetails() async {
    let cloud = ControlledCloudAccount()
    let model = SettingsViewModel(cloud: cloud, notifications: NotificationStub())
    let first = Task { await model.checkCloudAccount() }
    await cloud.waitForRequest(count: 1)
    cloud.requests[0].resume(
      throwing: NSError(
        domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private diagnostic"]))
    await first.value
    XCTAssertEqual(model.cloudState, .failed)
    XCTAssertFalse(model.cloudState.message?.contains("private diagnostic") ?? true)
    let retry = Task { await model.checkCloudAccount() }
    await cloud.waitForRequest(count: 2)
    cloud.requests[1].resume(returning: .available)
    await retry.value
    XCTAssertEqual(model.cloudState, .result(CloudAccountStatus.available.message))
  }

  func testNotificationDenialFailureAndRetry() async {
    let notifications = NotificationStub()
    let model = SettingsViewModel(cloud: ControlledCloudAccount(), notifications: notifications)
    notifications.result = .success(false)
    let denied = await model.authorizeNotifications()
    XCTAssertEqual(denied, false)
    XCTAssertNotNil(model.notificationMessage)
    notifications.result = .failure(NSError(domain: "Test", code: 1))
    let failed = await model.authorizeNotifications()
    XCTAssertEqual(failed, false)
    XCTAssertFalse(model.requestingNotifications)
    notifications.result = .success(true)
    let accepted = await model.authorizeNotifications()
    XCTAssertEqual(accepted, true)
    XCTAssertNil(model.notificationMessage)
  }

  func testProgressSelectionFallsBackWhenSelectedExerciseIsDeleted() throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var workout = try ExerciseCatalog.starterTemplates[0].start(at: date)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
      repetitions: 8, weightKG: 40, at: date)
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
    let model = ProgressViewModel(now: { date.addingTimeInterval(120) })
    model.refresh(workouts: [workout], calendar: .current)
    model.exerciseProgress.selectedExerciseID = workout.exercises[0].exercise.id
    XCTAssertNotNil(model.exerciseProgress.history)
    XCTAssertEqual(model.exerciseProgress.points.count, 1)
    model.refresh(workouts: [], calendar: .current)
    XCTAssertNil(model.exerciseProgress.history)
    XCTAssertTrue(model.exerciseProgress.points.isEmpty)
  }
}
