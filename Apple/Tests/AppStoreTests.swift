import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

@MainActor private final class RecordingHealthExporter: HealthWorkoutExporting {
  var authorized = false
  var exported: [Workout] = []
  func requestAuthorization() async throws { authorized = true }
  func export(_ workout: Workout) async throws { exported.append(workout) }
}

@MainActor private final class FailingWorkoutRepository: WorkoutRepository {
  let memory = MemoryWorkoutRepository()
  var failSaves = false
  var failTemplateReads = false
  var failBodyWeightReads = false
  private var failure: NSError {
    NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private diagnostic"])
  }
  func workouts() throws -> [Workout] { try memory.workouts() }
  func templates() throws -> [WorkoutTemplate] {
    if failTemplateReads { throw failure }
    return try memory.templates()
  }
  func save(_ workout: Workout) throws {
    if failSaves { throw failure }
    try memory.save(workout)
  }
  func saveTemplate(_ template: WorkoutTemplate) throws { try memory.saveTemplate(template) }
  func deleteWorkout(id: UUID) throws { try memory.deleteWorkout(id: id) }
  func deleteTemplate(id: UUID) throws { try memory.deleteTemplate(id: id) }
  func bodyWeights() throws -> [BodyWeightEntry] {
    if failBodyWeightReads { throw failure }
    return try memory.bodyWeights()
  }
  func saveBodyWeight(_ entry: BodyWeightEntry) throws {
    if failSaves { throw failure }
    try memory.saveBodyWeight(entry)
  }
  func deleteBodyWeight(id: UUID) throws {
    if failSaves { throw failure }
    try memory.deleteBodyWeight(id: id)
  }
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    if failSaves { throw failure }
    return try memory.importArchive(archive)
  }
}

@MainActor final class AppStoreTests: XCTestCase {
  func testFailedWeightReadPreservesTheEntirePreviousSnapshot() throws {
    let repository = FailingWorkoutRepository()
    let original = BodyWeightEntry(weightKG: 72)
    try repository.saveBodyWeight(original)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    let workout = Workout(name: "Weight fixture")
    try repository.save(workout)
    try repository.saveBodyWeight(BodyWeightEntry(weightKG: 73))
    repository.failBodyWeightReads = true
    store.reload()
    XCTAssertTrue(store.workouts.isEmpty)
    XCTAssertEqual(store.bodyWeights, [original])
    XCTAssertNotNil(store.error)
    repository.failBodyWeightReads = false
    store.reload()
    XCTAssertEqual(store.workouts, [workout])
    XCTAssertEqual(store.bodyWeights.count, 2)
  }
  func testWorkoutBodyWeightSaveFailurePreservesPreviousValue() throws {
    let repository = FailingWorkoutRepository()
    let workout = Workout(name: "Weight fixture")
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    XCTAssertTrue(store.setBodyWeight(72.5, for: workout.id))
    repository.failSaves = true
    XCTAssertFalse(store.setBodyWeight(71, for: workout.id))
    XCTAssertEqual(store.active?.bodyWeightKG, 72.5)
    XCTAssertEqual(try repository.workouts().first?.bodyWeightKG, 72.5)
    XCTAssertNotNil(store.error)
  }
  func testDemoWeightsNeverChangePersonalWeightHistory() async throws {
    let repository = MemoryWorkoutRepository()
    let original = BodyWeightEntry(weightKG: 72.5)
    try repository.saveBodyWeight(original)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    await store.loadDemoData()
    XCTAssertTrue(store.bodyWeights.isEmpty)
    var demo = original
    demo.weightKG = 90
    XCTAssertTrue(store.saveBodyWeight(demo))
    await store.leaveDemoMode()
    XCTAssertEqual(store.bodyWeights, [original])
    XCTAssertEqual(try repository.bodyWeights(), [original])
  }
  func testDemoProfileIsIsolatedReloadableAndNeverExportsToHealth() async throws {
    let personal = MemoryWorkoutRepository()
    let fixture = try DemoWorkoutData.archive(relativeTo: Date().addingTimeInterval(-3600))
    var own = try XCTUnwrap(fixture.workouts.first)
    own.name = "Личная тренировка"
    try personal.save(own)
    let health = RecordingHealthExporter()
    let store = AppStore(repository: personal, health: health, platformServicesEnabled: false)
    await store.loadDemoData()
    XCTAssertTrue(store.isDemoMode)
    XCTAssertEqual(store.completed.count, 24)
    XCTAssertEqual(store.templates.count, 3)
    store.delete(workout: try XCTUnwrap(store.completed.first))
    XCTAssertEqual(try personal.workouts(), [own])
    await store.loadDemoData()
    XCTAssertEqual(store.completed.count, 24)
    await store.exportHealth(try XCTUnwrap(store.completed.first))
    XCTAssertFalse(health.authorized)
    XCTAssertTrue(health.exported.isEmpty)
    await store.leaveDemoMode()
    XCTAssertFalse(store.isDemoMode)
    XCTAssertEqual(store.workouts, [own])
  }
  func testFailedPersonalReadKeepsTheDemoProfileAndItsData() async throws {
    let personal = FailingWorkoutRepository()
    let store = AppStore(
      repository: personal, health: RecordingHealthExporter(), platformServicesEnabled: false)
    await store.loadDemoData()
    let demo = store.workouts
    personal.failTemplateReads = true
    await store.leaveDemoMode()
    XCTAssertTrue(store.isDemoMode)
    XCTAssertEqual(store.workouts, demo)
    XCTAssertNotNil(store.error)
    personal.failTemplateReads = false
    await store.leaveDemoMode()
    XCTAssertFalse(store.isDemoMode)
  }
  func testFailedSavePreservesActiveSessionAndDoesNotAnnounceSuccess() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.finish()
    XCTAssertNil(store.notice)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let workout = try XCTUnwrap(store.active)
    repository.failSaves = true
    let saved = store.mutate {
      try WorkoutEngine.completeSet(
        in: &$0, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
        repetitions: 8, weightKG: 40)
    }
    XCTAssertFalse(saved)
    XCTAssertEqual(store.active, workout)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertNotNil(store.error)
    XCTAssertFalse(store.error?.contains("private diagnostic") ?? true)
    XCTAssertNil(store.notice)
  }

  func testFailedReloadKeepsTheEntirePreviousSnapshot() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let original = store.workouts
    try repository.save(ExerciseCatalog.starterTemplates[1].start())
    repository.failTemplateReads = true
    store.reload()
    XCTAssertEqual(store.workouts, original)
    XCTAssertEqual(store.active?.id, original.first?.id)
    XCTAssertNotNil(store.error)
    repository.failTemplateReads = false
    store.reload()
    XCTAssertEqual(store.workouts.count, 2)
  }
  func testCompletedWorkoutIsPersistedAndExportRequiresExplicitAction() async throws {
    let repository = MemoryWorkoutRepository()
    let health = RecordingHealthExporter()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "FitnessTracker.UnitTests"))
    defer { defaults.removePersistentDomain(forName: "FitnessTracker.UnitTests") }
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

  func testLiveActionPersistsAndCanResumeAfterProcessRecreation() async throws {
    let repository = MemoryWorkoutRepository()
    let workout = try ExerciseCatalog.starterTemplates[0].start(at: Date().addingTimeInterval(-300))
    try repository.save(workout)
    let first = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    try await first.performLiveAction(.pause, workoutID: workout.id)
    XCTAssertEqual(try repository.workouts().first?.status, .paused)
    let pausedAt = try XCTUnwrap(first.active?.pausedAt)
    try await first.performLiveAction(.pause, workoutID: workout.id)
    XCTAssertEqual(first.active?.pausedAt, pausedAt)

    let restored = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    try await restored.performLiveAction(.resume, workoutID: workout.id)
    XCTAssertEqual(restored.active?.status, .active)
    XCTAssertEqual(restored.active?.pauses.count, 1)
    XCTAssertFalse(restored.showSession)
  }

  func testStaleLiveActionDoesNotChangeAnotherSession() async throws {
    let repository = MemoryWorkoutRepository()
    let workout = try ExerciseCatalog.starterTemplates[0].start()
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    do {
      try await store.performLiveAction(.pause, workoutID: UUID())
      XCTFail("An unknown Live Activity ID must fail")
    } catch { XCTAssertEqual(error as? TrainingError, .invalidState) }
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(store.active, workout)
  }

  func testDeepLinkOpensSpecifiedUnfinishedSession() throws {
    let repository = MemoryWorkoutRepository()
    let older = try ExerciseCatalog.starterTemplates[0].start(at: Date().addingTimeInterval(-60))
    let newer = try ExerciseCatalog.starterTemplates[1].start()
    try repository.save(older)
    try repository.save(newer)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.openWorkout(id: older.id)
    store.reload()
    XCTAssertEqual(store.active?.id, older.id)
    XCTAssertTrue(store.showSession)
  }
  func testRepeatCreatesANewSessionWithoutChangingTheOriginal() throws {
    let repository = MemoryWorkoutRepository()
    var source = try ExerciseCatalog.starterTemplates[0].start(at: Date().addingTimeInterval(-120))
    try WorkoutEngine.completeSet(
      in: &source, exerciseID: source.exercises[0].id,
      setID: source.exercises[0].sets[0].id, repetitions: 8, weightKG: 40, at: source.startedAt)
    try WorkoutEngine.finish(&source, at: source.startedAt.addingTimeInterval(60))
    try repository.save(source)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.repeatWorkout(source)
    XCTAssertNotEqual(store.active?.id, source.id)
    XCTAssertEqual(store.active?.completedSets, 0)
    XCTAssertEqual(store.completed, [source])
  }

  func testCompletedWorkoutEditsPreserveHistoryAndRejectEmptyTraining() throws {
    let repository = MemoryWorkoutRepository()
    var source = try ExerciseCatalog.starterTemplates[0].start(at: Date().addingTimeInterval(-120))
    try WorkoutEngine.completeSet(
      in: &source, exerciseID: source.exercises[0].id,
      setID: source.exercises[0].sets[0].id, repetitions: 8, weightKG: 40, at: source.startedAt)
    try WorkoutEngine.finish(&source, at: source.startedAt.addingTimeInterval(60))
    try repository.save(source)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    var draft = source
    draft.name = "Грудь и бицепс"
    draft.notes = "После изменения"
    XCTAssertTrue(store.updateCompleted(draft))
    XCTAssertEqual(try repository.workouts().first?.name, draft.name)
    draft.exercises = []
    XCTAssertFalse(store.updateCompleted(draft))
    XCTAssertEqual(try repository.workouts().first?.completedSets, 1)
  }

}
