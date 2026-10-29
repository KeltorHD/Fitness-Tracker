import FitSessionCore
import XCTest

@testable import FitSession

@MainActor private final class RecordingHealthExporter: HealthWorkoutExporting {
  var authorized = false
  var exported: [Workout] = []
  func requestAuthorization() async throws { authorized = true }
  func export(_ workout: Workout) async throws { exported.append(workout) }
}

@MainActor final class AppStoreTests: XCTestCase {
  func testCompletedWorkoutIsPersistedAndExportRequiresExplicitAction() async throws {
    let repository = MemoryWorkoutRepository()
    let health = RecordingHealthExporter()
    let defaults = UserDefaults(suiteName: "FitSession.UnitTests")!
    defer { defaults.removePersistentDomain(forName: "FitSession.UnitTests") }
    let store = AppStore(
      repository: repository, health: health, defaults: defaults, platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let workout = try XCTUnwrap(store.active)
    store.mutate {
      try WorkoutEngine.completeSet(
        in: &$0, exerciseID: workout.exercises[0].id,
        setID: workout.exercises[0].sets[0].id, repetitions: 8, weightKG: 20)
    }
    store.finish()
    XCTAssertNil(store.active)
    XCTAssertEqual(store.completed.count, 1)
    XCTAssertFalse(health.authorized)
    await store.exportHealth(try XCTUnwrap(store.completed.first))
    XCTAssertTrue(health.authorized)
    XCTAssertEqual(health.exported.count, 1)
  }
  func testRestoringRepositoryResumesSameWorkout() throws {
    let repository = MemoryWorkoutRepository()
    let workout = try ExerciseCatalog.starterTemplates[0].start()
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    XCTAssertEqual(store.active?.id, workout.id)
    store.start()
    XCTAssertEqual(try repository.workouts().count, 1)
  }
}
