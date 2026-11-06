import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

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
