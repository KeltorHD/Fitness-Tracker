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
  var failTemplateSaves = false
  var failTemplateReads = false
  var failBodyWeightReads = false
  var failBodyWeightReadsAfterWrite = false
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
  func saveTemplate(_ template: WorkoutTemplate) throws {
    if failTemplateSaves { throw failure }
    try memory.saveTemplate(template)
  }
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
  func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws {
    if failSaves { throw failure }
    try memory.saveBodyWeight(entry, updating: workout)
    if failBodyWeightReadsAfterWrite { failBodyWeightReads = true }
  }
  func deleteBodyWeight(id: UUID) throws {
    if failSaves { throw failure }
    try memory.deleteBodyWeight(id: id)
  }
  func deleteBodyWeight(id: UUID, updating workout: Workout?) throws {
    if failSaves { throw failure }
    try memory.deleteBodyWeight(id: id, updating: workout)
    if failBodyWeightReadsAfterWrite { failBodyWeightReads = true }
  }
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    if failSaves { throw failure }
    return try memory.importArchive(archive)
  }
}

@MainActor final class AppStoreTests: XCTestCase {
  func testSelectedVariationStartsWithItsSupersetWithoutChangingSavedTemplate() throws {
    let repository = MemoryWorkoutRepository()
    let groupID = UUID()
    let variation = WorkoutTemplateVariation(
      name: "Гантели",
      exercises: [
        TemplateExercise(exercise: ExerciseCatalog.all[1], setCount: 2, supersetID: groupID),
        TemplateExercise(exercise: ExerciseCatalog.all[2], setCount: 2, supersetID: groupID),
      ])
    let template = WorkoutTemplate(
      name: "Грудь", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
      restSeconds: 90, variations: [variation])
    try repository.saveTemplate(template)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: try template.resolvedVariation(id: variation.id))
    let workout = try XCTUnwrap(store.active)
    XCTAssertEqual(workout.exercises.map(\.exercise.id), variation.exercises.map(\.exercise.id))
    XCTAssertEqual(workout.exercises.map { $0.sets.count }, [2, 2])
    XCTAssertTrue(
      workout.exercises.flatMap(\.sets).allSatisfy {
        $0.repetitions == 0 && $0.weightKG == 0 && $0.completedAt == nil
      })
    let newGroupID = try XCTUnwrap(workout.exercises.first?.supersetID)
    XCTAssertNotEqual(newGroupID, groupID)
    XCTAssertTrue(workout.exercises.allSatisfy { $0.supersetID == newGroupID })
    store.reload()
    XCTAssertEqual(store.active, workout)
    XCTAssertEqual(try repository.templates(), [template])
    XCTAssertEqual(store.templates, [template])
  }

  func testSupersetSaveFailureDoesNotChangeGroupOrStartRest() throws {
    let repository = FailingWorkoutRepository()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let first = WorkoutExercise(
      exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 0)])
    let second = WorkoutExercise(
      exercise: ExerciseCatalog.all[1], sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(
      name: "Суперсет", startedAt: date, exercises: [first, second], restSeconds: 90)
    _ = try WorkoutEngine.groupExercises([first.id, second.id], in: &workout)
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: first.id, setID: first.sets[0].id,
          repetitions: 8, weightKG: 40, at: date.addingTimeInterval(1))
      })
    XCTAssertEqual(store.active, workout)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertNil(store.active?.restEndsAt)
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: first.id, setID: first.sets[0].id,
          repetitions: 8, weightKG: 40, at: date.addingTimeInterval(1))
      })
    XCTAssertNil(store.active?.restEndsAt)
    XCTAssertEqual(store.active?.nextPendingSet?.exerciseID, second.id)
    store.reload()
    XCTAssertEqual(store.active?.nextPendingSet?.exerciseID, second.id)
  }

  func testEditedTemplateFromHistoryIsSavedWithoutChangingHistoryAndCanRetryFailure() throws {
    let repository = FailingWorkoutRepository()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    var history = Workout(
      name: "Прошлая тренировка", startedAt: date,
      exercises: [
        WorkoutExercise(
          exercise: ExerciseCatalog.all[0],
          sets: [WorkoutSet(repetitions: 8, weightKG: 40, completedAt: date)]),
        WorkoutExercise(
          exercise: ExerciseCatalog.all[1],
          sets: [WorkoutSet(repetitions: 10, weightKG: 30, completedAt: date)]),
      ])
    try WorkoutEngine.finish(&history, at: date.addingTimeInterval(600))
    try repository.save(history)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    var draft = try WorkoutEngine.makeTemplate(from: history)
    XCTAssertTrue(store.templates.isEmpty)
    draft.name = "Новый план"
    draft.exercises.removeFirst()
    draft.exercises.append(TemplateExercise(exercise: ExerciseCatalog.all[2], setCount: 2))
    repository.failTemplateSaves = true
    XCTAssertFalse(store.save(template: draft))
    XCTAssertTrue(store.templates.isEmpty)
    XCTAssertNotNil(store.error)
    XCTAssertEqual(try repository.workouts(), [history])
    repository.failTemplateSaves = false
    XCTAssertTrue(store.save(template: draft))
    XCTAssertEqual(store.templates, [draft])
    XCTAssertEqual(store.completed, [history])
    XCTAssertEqual(try repository.workouts(), [history])
    XCTAssertNil(store.active)
  }

  func testAllStagesRequireExplicitFinishAndFailedFinishCanBeRetried() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let warmup = WorkoutSet(repetitions: 12, weightKG: 10, isWarmup: true)
    let drop = WorkoutSet(
      repetitions: 8, weightKG: 40, dropStages: [DropSetStage(repetitions: 6, weightKG: 30)])
    let last = WorkoutSet(repetitions: 10, weightKG: 0)
    let firstRow = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [warmup, drop])
    let lastRow = WorkoutExercise(exercise: ExerciseCatalog.all[1], sets: [last])
    let workout = Workout(name: "План", startedAt: date, exercises: [firstRow, lastRow])
    let repository = FailingWorkoutRepository()
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.presentWorkoutStart()
    XCTAssertTrue(store.showSession)
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: firstRow.id, setID: warmup.id,
          repetitions: 12, weightKG: 10, at: date)
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: firstRow.id, setID: drop.id,
          repetitions: 8, weightKG: 40, at: date.addingTimeInterval(1))
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: lastRow.id, setID: last.id,
          repetitions: 10, weightKG: 0, at: date.addingTimeInterval(2))
      })
    let pending = try XCTUnwrap(store.active)
    XCTAssertFalse(WorkoutCompletionProgress(workout: pending).isComplete)
    let stage = try XCTUnwrap(drop.dropStages?.first)
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.completeDropStage(
          in: &$0, exerciseID: firstRow.id, setID: drop.id, stageID: stage.id,
          repetitions: 6, weightKG: 30, at: date.addingTimeInterval(3))
      })
    let ready = try XCTUnwrap(store.active)
    XCTAssertTrue(WorkoutCompletionProgress(workout: ready).isComplete)
    XCTAssertEqual(ready.status, .active)
    XCTAssertNil(ready.endedAt)
    XCTAssertTrue(store.completed.isEmpty)
    XCTAssertTrue(store.showSession)
    XCTAssertEqual(try repository.workouts(), [ready])
    repository.failSaves = true
    store.finish()
    XCTAssertEqual(store.active, ready)
    XCTAssertTrue(store.completed.isEmpty)
    XCTAssertTrue(store.showSession)
    XCTAssertNil(store.notice)
    XCTAssertNotNil(store.error)
    XCTAssertEqual(try repository.workouts(), [ready])
    repository.failSaves = false
    store.error = nil
    store.finish()
    XCTAssertNil(store.active)
    XCTAssertFalse(store.showSession)
    XCTAssertEqual(store.completed.count, 1)
    let saved = try XCTUnwrap(store.completed.first)
    XCTAssertEqual(saved.id, ready.id)
    XCTAssertEqual(saved.exercises, ready.exercises)
    XCTAssertEqual(saved.status, .completed)
    XCTAssertNotNil(saved.endedAt)
    XCTAssertNotNil(store.notice)
    XCTAssertEqual(try repository.workouts(), [saved])
  }

  func testOrdinaryTemplateStartPersistsEmptyTargetsAndRetainsTheSavedTemplate() throws {
    let repository = MemoryWorkoutRepository()
    let template = WorkoutTemplate(
      name: "План",
      exercises: [
        TemplateExercise(exercise: ExerciseCatalog.all[0], repetitions: 12, weightKG: 60)
      ], restSeconds: 120)
    try repository.saveTemplate(template)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: template)
    let workout = try XCTUnwrap(store.active)
    XCTAssertEqual(workout.exercises[0].sets.count, 3)
    XCTAssertTrue(workout.exercises[0].sets.allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
    XCTAssertEqual(workout.restSeconds, 120)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(try repository.templates(), [template])
  }

  func testFailedExerciseInsertionAndRemovalKeepPersistedSessionIntact() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let original = try XCTUnwrap(store.active)
    let anchor = original.exercises[0].id
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.addExercise(ExerciseCatalog.all[7], to: &$0, position: .before(anchor))
      })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts(), [original])
    XCTAssertFalse(store.mutate { try WorkoutEngine.removeExercise(id: anchor, from: &$0) })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts(), [original])
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.addExercise(ExerciseCatalog.all[7], to: &$0, position: .before(anchor))
      })
    XCTAssertEqual(store.active?.exercises[1].id, anchor)
    let inserted = try XCTUnwrap(store.active?.exercises.first?.id)
    XCTAssertTrue(store.mutate { try WorkoutEngine.removeExercise(id: inserted, from: &$0) })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts(), [original])
  }

  func testExerciseOrderRollsBackWhenSaveFails() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let original = try XCTUnwrap(store.active)
    let order = original.exercises.reversed().map(\.id)
    repository.failSaves = true
    XCTAssertFalse(store.mutate { try WorkoutEngine.reorderExercises(order, in: &$0) })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts(), [original])
    repository.failSaves = false
    XCTAssertTrue(store.mutate { try WorkoutEngine.reorderExercises(order, in: &$0) })
    XCTAssertEqual(store.active?.exercises.map(\.id), order)
    XCTAssertEqual(try repository.workouts().first?.exercises.map(\.id), order)
  }

  func testAddingTemplatesPreservesSessionAndCanRetryAfterSaveFailure() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start()
    let original = try XCTUnwrap(store.active)
    XCTAssertTrue(original.exercises.isEmpty)
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.addTemplates([ExerciseCatalog.starterTemplates[0]], to: &$0)
      })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts(), [original])
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.addTemplates([ExerciseCatalog.starterTemplates[0]], to: &$0)
      })
    XCTAssertEqual(store.active?.id, original.id)
    XCTAssertEqual(store.active?.startedAt, original.startedAt)
    XCTAssertEqual(store.active?.restSeconds, original.restSeconds)
    XCTAssertEqual(store.active?.exercises.count, 3)
    XCTAssertEqual(try repository.workouts().first, store.active)
  }

  func testCompletedCorrectionAndChildDeletionRollbackOnSaveFailure() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let initial = try XCTUnwrap(store.active)
    let row = initial.exercises[0]
    let set = row.sets[0]
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.configureDropSet(
          in: &$0, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50,
          stages: [DropSetStage(weightKG: 40)])
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50)
      })
    let original = try XCTUnwrap(store.active)
    let stage = try XCTUnwrap(original.exercises[0].sets[0].dropStages?.first)
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.correctCompletedTarget(
          in: &$0, exerciseID: row.id, targetID: set.id, repetitions: 12, weightKG: 50)
      })
    XCTAssertEqual(store.active, original)
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.removeDropStage(
          in: &$0, exerciseID: row.id, setID: set.id, stageID: stage.id)
      })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts().first, original)
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.correctCompletedTarget(
          in: &$0, exerciseID: row.id, targetID: set.id, repetitions: 12, weightKG: 50)
      })
    XCTAssertEqual(
      store.active?.exercises[0].sets[0].completedAt, original.exercises[0].sets[0].completedAt)
  }

  func testExerciseReplacementRollsBackOnSaveFailure() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let original = try XCTUnwrap(store.active)
    let rowID = original.exercises[0].id
    let exercise = ExerciseCatalog.all.first { $0.id != original.exercises[0].exercise.id }
    let replacement = try XCTUnwrap(exercise)
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate { _ = try WorkoutEngine.replaceExercise(id: rowID, with: replacement, in: &$0) })
    XCTAssertEqual(store.active, original)
    XCTAssertEqual(try repository.workouts().first, original)
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate { _ = try WorkoutEngine.replaceExercise(id: rowID, with: replacement, in: &$0) })
    XCTAssertEqual(store.active?.exercises[0].exercise, replacement)
    XCTAssertEqual(store.active?.id, original.id)
  }

  func testGeneralStartPresentsPickerWithoutSavingAndResumesExistingSession() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    repository.failSaves = true
    store.presentWorkoutStart()
    store.presentWorkoutStart()
    XCTAssertTrue(store.showingWorkoutStart)
    XCTAssertFalse(store.showSession)
    XCTAssertNil(store.active)
    XCTAssertNil(store.error)
    XCTAssertTrue(try repository.workouts().isEmpty)
    store.showingWorkoutStart = false
    repository.failSaves = false
    store.start()
    let active = try XCTUnwrap(store.active)
    store.showSession = false
    store.presentWorkoutStart()
    XCTAssertTrue(store.showSession)
    XCTAssertFalse(store.showingWorkoutStart)
    XCTAssertEqual(store.active, active)
    XCTAssertEqual(try repository.workouts(), [active])
  }

  func testCombinedTemplateStartPersistsOneSessionAndResumesWithoutReplacement() throws {
    let repository = MemoryWorkoutRepository()
    let first = ExerciseCatalog.starterTemplates[0]
    var second = ExerciseCatalog.starterTemplates[1]
    second.exercises.insert(first.exercises[0], at: 0)
    try repository.saveTemplate(first)
    try repository.saveTemplate(second)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(templates: [first, second])
    let active = try XCTUnwrap(store.active)
    XCTAssertEqual(active.exercises.count, 6)
    XCTAssertEqual(Set(active.exercises.map(\.exercise.id)).count, 6)
    XCTAssertEqual(try repository.workouts(), [active])
    XCTAssertEqual(try repository.templates().count, 2)
    XCTAssertTrue(store.showSession)
    store.showSession = false
    store.start(templates: [second, first])
    XCTAssertEqual(store.active, active)
    XCTAssertEqual(try repository.workouts(), [active])
    XCTAssertTrue(store.showSession)
  }

  func testCombinedTemplateSaveFailureDoesNotLeaveAPartialSession() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    repository.failSaves = true
    store.start(templates: ExerciseCatalog.starterTemplates)
    XCTAssertNil(store.active)
    XCTAssertFalse(store.showSession)
    XCTAssertTrue(try repository.workouts().isEmpty)
    XCTAssertNotNil(store.error)
    repository.failSaves = false
    store.start(templates: ExerciseCatalog.starterTemplates)
    XCTAssertEqual(store.active?.exercises.count, 6)
    XCTAssertEqual(try repository.workouts().count, 1)
    XCTAssertTrue(store.showSession)
  }

  func testFailedWorkoutStartDoesNotPresentOrCreateSession() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    repository.failSaves = true
    store.start()
    XCTAssertNil(store.active)
    XCTAssertFalse(store.showSession)
    XCTAssertTrue(try repository.workouts().isEmpty)
    XCTAssertNotNil(store.error)
    repository.failSaves = false
    store.start()
    XCTAssertNotNil(store.active)
    XCTAssertTrue(store.showSession)
    XCTAssertEqual(try repository.workouts().count, 1)
  }

  func testStartingAnotherTemplateResumesExistingSessionWithoutReplacingIt() throws {
    let repository = MemoryWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let original = try XCTUnwrap(store.active)
    store.showSession = false
    store.start(template: ExerciseCatalog.starterTemplates[1])
    XCTAssertEqual(store.active, original)
    XCTAssertTrue(store.showSession)
    XCTAssertEqual(try repository.workouts(), [original])
  }

  func testUnknownImportedDurationNeverRequestsHealthWritePermission() async throws {
    let repository = MemoryWorkoutRepository()
    var workout = Workout(name: "CSV fixture", startedAt: Date(timeIntervalSince1970: 100))
    workout.exercises = [
      WorkoutExercise(
        exercise: ExerciseCatalog.all[0],
        sets: [WorkoutSet(weightKG: 40, completedAt: workout.startedAt)])
    ]
    try WorkoutEngine.finish(&workout, at: workout.startedAt)
    workout.durationIsKnown = false
    try repository.save(workout)
    let health = RecordingHealthExporter()
    let store = AppStore(repository: repository, health: health, platformServicesEnabled: false)
    await store.exportHealth(workout)
    XCTAssertFalse(health.authorized)
    XCTAssertTrue(health.exported.isEmpty)
    XCTAssertNotNil(store.error)
  }
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
  func testCurrentWeightStartsFreeTemplateAndRepeatedWorkoutsWithoutChangingHistory() throws {
    let repository = MemoryWorkoutRepository()
    var instant = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { instant })
    XCTAssertNil(store.currentBodyWeightKG)
    XCTAssertTrue(store.setCurrentBodyWeight(72.5))
    store.start()
    XCTAssertEqual(store.active?.bodyWeightKG, 72.5)
    store.cancel()
    instant = instant.addingTimeInterval(1)
    XCTAssertTrue(store.setCurrentBodyWeight(73))
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let active = try XCTUnwrap(store.active)
    XCTAssertEqual(active.bodyWeightKG, 73)
    XCTAssertTrue(
      store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: active.exercises[0].id, setID: active.exercises[0].sets[0].id,
          repetitions: 8, weightKG: 20)
      })
    store.finish()
    let completed = try XCTUnwrap(store.completed.first)
    instant = instant.addingTimeInterval(1)
    XCTAssertTrue(store.setCurrentBodyWeight(74))
    store.repeatWorkout(completed)
    XCTAssertEqual(store.active?.bodyWeightKG, 74)
    XCTAssertEqual(store.completed.first?.bodyWeightKG, 73)
    XCTAssertEqual(
      try repository.workouts().first(where: { $0.id == completed.id })?.bodyWeightKG, 73)
    let restored = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { instant })
    XCTAssertEqual(restored.currentBodyWeightKG, 74)
    XCTAssertEqual(restored.active?.bodyWeightKG, 74)
  }
  func testActiveWeightEditsUpdateGlobalStateOnceAndSurviveCancellation() throws {
    let repository = MemoryWorkoutRepository()
    var instant = Date(timeIntervalSince1970: 1_700_000_000)
    let workout = Workout(name: "Current weight", startedAt: instant)
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { instant })
    XCTAssertTrue(store.setBodyWeight(72.5, for: workout.id))
    let first = try XCTUnwrap(store.bodyWeights.first)
    XCTAssertEqual(first.workoutID, workout.id)
    XCTAssertEqual(store.currentBodyWeightKG, 72.5)
    XCTAssertEqual(store.active?.bodyWeightKG, 72.5)
    instant = instant.addingTimeInterval(1)
    XCTAssertTrue(store.setBodyWeight(73, for: workout.id))
    XCTAssertEqual(store.bodyWeights.count, 1)
    XCTAssertEqual(store.bodyWeights.first?.id, first.id)
    XCTAssertEqual(store.bodyWeights.first?.weightKG, 73)
    XCTAssertEqual(store.currentBodyWeightKG, 73)
    XCTAssertTrue(store.mutate { try WorkoutEngine.pause(&$0) })
    instant = instant.addingTimeInterval(1)
    XCTAssertTrue(store.setCurrentBodyWeight(74))
    XCTAssertEqual(store.active?.bodyWeightKG, 74)
    store.cancel()
    XCTAssertNil(store.active)
    XCTAssertEqual(store.currentBodyWeightKG, 74)
    XCTAssertEqual(store.bodyWeights.count, 1)
    XCTAssertEqual(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts, now: instant).points
        .count, 1)
  }
  func testNewReadingUpdatesActiveWeightButDatedRecordEditsDoNot() throws {
    let repository = MemoryWorkoutRepository()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let historical = BodyWeightEntry(measuredAt: date.addingTimeInterval(-3600), weightKG: 72)
    try repository.saveBodyWeight(historical)
    let workout = Workout(name: "Current weight", startedAt: date, bodyWeightKG: 72)
    try repository.save(workout)
    let now = date.addingTimeInterval(3600)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { now })
    var correction = historical
    correction.weightKG = 71
    XCTAssertTrue(store.saveBodyWeight(correction))
    XCTAssertEqual(store.active?.bodyWeightKG, 72)
    let reading = BodyWeightEntry(measuredAt: now, weightKG: 73)
    XCTAssertTrue(store.saveBodyWeight(reading))
    XCTAssertEqual(store.active?.bodyWeightKG, 73)
    XCTAssertEqual(store.currentBodyWeightKG, 73)
    XCTAssertEqual(store.bodyWeights.first(where: { $0.id == reading.id })?.workoutID, workout.id)
    correction.weightKG = 70
    XCTAssertTrue(store.saveBodyWeight(correction))
    XCTAssertEqual(store.active?.bodyWeightKG, 73)
    XCTAssertEqual(store.currentBodyWeightKG, 73)
  }
  func testCurrentWeightAtomicFailurePreservesReadingAndWorkoutAndReadFailureCannotUndoCommit()
    throws
  {
    let repository = FailingWorkoutRepository()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let workout = Workout(name: "Current weight", startedAt: date)
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date })
    XCTAssertTrue(store.setCurrentBodyWeight(72.5))
    let savedWeights = try repository.bodyWeights()
    let savedWorkout = try XCTUnwrap(repository.workouts().first)
    repository.failSaves = true
    XCTAssertFalse(store.setCurrentBodyWeight(73))
    XCTAssertEqual(store.currentBodyWeightKG, 72.5)
    XCTAssertEqual(store.active, savedWorkout)
    XCTAssertEqual(try repository.bodyWeights(), savedWeights)
    XCTAssertEqual(try repository.workouts(), [savedWorkout])
    repository.failSaves = false
    repository.failBodyWeightReads = true
    XCTAssertFalse(store.setCurrentBodyWeight(73))
    XCTAssertEqual(store.currentBodyWeightKG, 72.5)
    XCTAssertEqual(try repository.memory.bodyWeights(), savedWeights)
    XCTAssertEqual(try repository.memory.workouts(), [savedWorkout])
    repository.failBodyWeightReads = false
    repository.failBodyWeightReadsAfterWrite = true
    XCTAssertTrue(store.setCurrentBodyWeight(74))
    XCTAssertEqual(store.currentBodyWeightKG, 74)
    XCTAssertEqual(store.active?.bodyWeightKG, 74)
    XCTAssertEqual(try repository.memory.bodyWeights().first?.weightKG, 74)
    XCTAssertEqual(try repository.memory.workouts().first?.bodyWeightKG, 74)
  }
  func testCurrentWeightEditsValidateAndDoNotChangeCompletedWorkoutSnapshots() throws {
    let repository = MemoryWorkoutRepository()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    var workout = try ExerciseCatalog.starterTemplates[0].start(at: date)
    try WorkoutEngine.setBodyWeight(72, in: &workout)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
      repetitions: 8, weightKG: 20, at: date)
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
    try repository.save(workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    for invalid in [0.0, -1, .nan, .infinity, 1001] {
      XCTAssertFalse(store.setCurrentBodyWeight(invalid))
    }
    XCTAssertTrue(try repository.bodyWeights().isEmpty)
    XCTAssertTrue(store.setCurrentBodyWeight(73))
    XCTAssertEqual(store.currentBodyWeightKG, 73)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertTrue(store.setBodyWeight(71, for: workout.id))
    XCTAssertEqual(store.currentBodyWeightKG, 73)
    XCTAssertEqual(try repository.workouts().first?.bodyWeightKG, 71)
  }
  private func sharedWeightFixture(status: WorkoutStatus, at date: Date) throws
    -> (Workout, BodyWeightEntry)
  {
    let row = WorkoutExercise(
      exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(weightKG: 20, completedAt: date)])
    var workout = Workout(
      name: "Shared weight", startedAt: date, exercises: [row], bodyWeightKG: 72)
    switch status {
    case .completed: try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
    case .cancelled: try WorkoutEngine.cancel(&workout, at: date.addingTimeInterval(60))
    case .paused: try WorkoutEngine.pause(&workout, at: date.addingTimeInterval(60))
    case .active: break
    }
    let entry = BodyWeightEntry(
      measuredAt: date.addingTimeInterval(30), weightKG: 72, workoutID: workout.id)
    return (workout, entry)
  }
  func testDeletingSharedCompletedWeightDoesNotRestoreTheWorkoutSnapshot() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let (workout, entry) = try sharedWeightFixture(status: .completed, at: date)
    let repository = MemoryWorkoutRepository()
    try repository.saveBodyWeight(entry, updating: workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    let summary = BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts)
    XCTAssertEqual(summary.points.count, 1)
    let point = try XCTUnwrap(summary.latest)
    XCTAssertTrue(store.deleteBodyWeight(point))
    XCTAssertTrue(store.bodyWeights.isEmpty)
    XCTAssertNil(store.currentBodyWeightKG)
    XCTAssertTrue(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).points.isEmpty)
    var expected = workout
    expected.bodyWeightKG = nil
    XCTAssertEqual(try repository.workouts(), [expected])
    store.reload()
    XCTAssertNil(store.currentBodyWeightKG)
    XCTAssertTrue(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).points.isEmpty)
  }
  func testSharedWeightDeleteFailurePreservesBothRecordsUntilRetry() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let (workout, entry) = try sharedWeightFixture(status: .completed, at: date)
    let repository = FailingWorkoutRepository()
    try repository.saveBodyWeight(entry, updating: workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    let point = try XCTUnwrap(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).latest)
    repository.failSaves = true
    XCTAssertFalse(store.deleteBodyWeight(point))
    XCTAssertEqual(store.bodyWeights, [entry])
    XCTAssertEqual(store.completed, [workout])
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    repository.failSaves = false
    repository.failBodyWeightReadsAfterWrite = true
    XCTAssertTrue(store.deleteBodyWeight(point))
    XCTAssertTrue(store.bodyWeights.isEmpty)
    XCTAssertNil(store.completed.first?.bodyWeightKG)
    XCTAssertNil(store.currentBodyWeightKG)
    XCTAssertTrue(try repository.memory.bodyWeights().isEmpty)
    XCTAssertNil(try repository.memory.workouts().first?.bodyWeightKG)
  }
  func testDeletingSharedCancelledWeightRemovesItsGlobalReading() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let (workout, entry) = try sharedWeightFixture(status: .cancelled, at: date)
    let repository = MemoryWorkoutRepository()
    try repository.saveBodyWeight(entry, updating: workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    let point = try XCTUnwrap(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).latest)
    XCTAssertTrue(store.deleteBodyWeight(point))
    XCTAssertNil(store.currentBodyWeightKG)
    XCTAssertTrue(store.bodyWeights.isEmpty)
    XCTAssertNil(try repository.workouts().first?.bodyWeightKG)
    XCTAssertEqual(try repository.workouts().first?.status, .cancelled)
  }
  func testDeletingSharedActiveWeightRevealsPreviousReadingAndClearsOnlyItsSnapshot() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let (workout, entry) = try sharedWeightFixture(status: .active, at: date)
    let previous = BodyWeightEntry(measuredAt: date.addingTimeInterval(-3600), weightKG: 70)
    let repository = MemoryWorkoutRepository()
    try repository.saveBodyWeight(previous)
    try repository.saveBodyWeight(entry, updating: workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    let point = try XCTUnwrap(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).latest)
    XCTAssertTrue(store.deleteBodyWeight(point))
    XCTAssertNil(store.active?.bodyWeightKG)
    XCTAssertEqual(store.currentBodyWeightKG, 70)
    XCTAssertEqual(store.bodyWeights, [previous])
    XCTAssertEqual(store.active?.exercises, workout.exercises)
    XCTAssertEqual(store.active?.status, .active)
  }
  func testDeletingUnlinkedOrDifferentSharedWeightPreservesTheCompletedSnapshot() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let (workout, originalEntry) = try sharedWeightFixture(status: .completed, at: date)
    var different = originalEntry
    different.weightKG = 71
    let repository = MemoryWorkoutRepository()
    try repository.saveBodyWeight(different, updating: workout)
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false,
      now: { date.addingTimeInterval(3600) })
    let point = try XCTUnwrap(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).points.first {
        $0.source == .measurement(different.id)
      })
    XCTAssertTrue(store.deleteBodyWeight(point))
    XCTAssertEqual(try repository.workouts(), [workout])
    let unrelated = BodyWeightEntry(measuredAt: date.addingTimeInterval(120), weightKG: 72)
    XCTAssertTrue(store.saveBodyWeight(unrelated))
    let unrelatedPoint = try XCTUnwrap(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).points.first {
        $0.source == .measurement(unrelated.id)
      })
    XCTAssertTrue(store.deleteBodyWeight(unrelatedPoint))
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(store.currentBodyWeightKG, 72)
    XCTAssertEqual(
      BodyWeightSummary(entries: store.bodyWeights, workouts: store.workouts).points.count, 1)
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

  func testFailedSetChangesPreserveSavedSession() throws {
    let repository = FailingWorkoutRepository()
    let store = AppStore(
      repository: repository, health: RecordingHealthExporter(), platformServicesEnabled: false)
    store.start(template: ExerciseCatalog.starterTemplates[0])
    let workout = try XCTUnwrap(store.active)
    let row = workout.exercises[0].id
    let set = workout.exercises[0].sets[0].id
    repository.failSaves = true
    XCTAssertFalse(
      store.mutate {
        try WorkoutEngine.setNote("private note", exerciseID: row, setID: set, in: &$0)
      })
    XCTAssertEqual(store.active, workout)
    XCTAssertFalse(store.mutate { try WorkoutEngine.addSet(exerciseID: row, to: &$0, after: set) })
    XCTAssertEqual(store.active, workout)
    XCTAssertFalse(
      store.mutate { try WorkoutEngine.removeSet(exerciseID: row, setID: set, from: &$0) })
    XCTAssertEqual(store.active, workout)
    XCTAssertEqual(try repository.workouts(), [workout])
    repository.failSaves = false
    XCTAssertTrue(
      store.mutate { try WorkoutEngine.setNote("saved note", exerciseID: row, setID: set, in: &$0) }
    )
    XCTAssertEqual(store.active?.exercises[0].sets[0].note, "saved note")
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
