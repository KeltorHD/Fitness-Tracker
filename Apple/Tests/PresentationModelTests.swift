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
    model.selectedExerciseID = workout.exercises[0].exercise.id
    XCTAssertNotNil(model.selectedRecord)
    XCTAssertEqual(model.points.count, 1)
    model.refresh(workouts: [], calendar: .current)
    XCTAssertNil(model.selectedRecord)
    XCTAssertTrue(model.points.isEmpty)
  }
}
