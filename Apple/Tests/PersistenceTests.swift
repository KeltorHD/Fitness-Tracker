import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

@MainActor final class PersistenceTests: XCTestCase {
  func testDropStagesAndMixedTemplateTargetsRoundTrip() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let row = WorkoutExercise(
      exercise: Exercise(name: "Drop", muscle: .back),
      sets: [WorkoutSet(repetitions: 10, weightKG: 50, dropStages: [DropSetStage(weightKG: 40)])])
    var workout = Workout(name: "Drop", startedAt: date, exercises: [row])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id, repetitions: 10, weightKG: 50,
      at: date.addingTimeInterval(1))
    let stage = try XCTUnwrap(row.sets[0].dropStages?.first)
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id, stageID: stage.id, repetitions: 8,
      weightKG: 40, at: date.addingTimeInterval(2))
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(3))
    let template = try WorkoutEngine.makeTemplate(from: workout)
    try repository.save(workout)
    try repository.saveTemplate(template)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(try repository.templates(), [template])
    let archive = try WorkoutArchiveCodec.decode(
      WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [workout], templates: [template])))
    XCTAssertEqual(archive.workouts, [workout])
    XCTAssertEqual(archive.templates, [template])
  }
  func testBodyWeightRoundTripDeleteAndCombinedArchiveImport() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var entry = BodyWeightEntry(measuredAt: Date(timeIntervalSince1970: 100), weightKG: 72.5)
    try repository.saveBodyWeight(entry)
    entry.weightKG = 71.5
    try repository.saveBodyWeight(entry)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    var invalid = entry
    invalid.weightKG = 0
    XCTAssertThrowsError(try repository.saveBodyWeight(invalid))
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    try repository.deleteBodyWeight(id: entry.id)
    let workout = Workout(name: "Weight fixture", bodyWeightKG: 72)
    let archive = WorkoutArchive(workouts: [workout], templates: [], bodyWeights: [entry])
    XCTAssertEqual(try repository.importArchive(archive).addedBodyWeights, 1)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    XCTAssertEqual(try repository.workouts().first?.bodyWeightKG, 72)
    XCTAssertFalse(try repository.importArchive(archive).hasChanges)
  }
  func testSwiftDataUpsertRoundTripAndDelete() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = try ExerciseCatalog.starterTemplates[0].start()
    try repository.save(workout)
    workout.notes = "После восстановления"
    try repository.save(workout)
    let restored = try repository.workouts()
    XCTAssertEqual(restored, [workout])
    try repository.deleteWorkout(id: workout.id)
    XCTAssertTrue(try repository.workouts().isEmpty)
  }
  func testTemplateRoundTrip() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let template = ExerciseCatalog.starterTemplates[0]
    try repository.saveTemplate(template)
    XCTAssertEqual(try repository.templates(), [template])
    try repository.deleteTemplate(id: template.id)
    XCTAssertTrue(try repository.templates().isEmpty)
  }
  func testFailedValidationLeavesStoredValueUnchanged() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = Workout(name: "A")
    try repository.save(workout)
    workout.name = ""
    XCTAssertThrowsError(try repository.save(workout))
    XCTAssertEqual(try repository.workouts().first?.name, "A")
  }
  func testArchiveImportIsAtomicAndIdempotentAcrossBothRecordKinds() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let original = Workout(name: "Текущая тренировка", startedAt: Date(timeIntervalSince1970: 100))
    try repository.save(original)
    let template = ExerciseCatalog.starterTemplates[0]
    var malformed = original
    malformed.id = UUID()
    malformed.name = ""
    XCTAssertThrowsError(
      try repository.importArchive(WorkoutArchive(workouts: [malformed], templates: [template])))
    XCTAssertTrue(try repository.templates().isEmpty)
    XCTAssertEqual(try repository.workouts(), [original])
    var modified = original
    modified.notes = "Не заменяет оригинал"
    let archive = WorkoutArchive(workouts: [modified], templates: [template])
    let first = try repository.importArchive(archive)
    XCTAssertEqual(first.addedTemplates, 1)
    XCTAssertEqual(first.skippedExisting, 1)
    XCTAssertEqual(try repository.workouts(), [original])
    let again = try repository.importArchive(archive)
    XCTAssertFalse(again.hasChanges)
    XCTAssertEqual(try repository.templates(), [template])
  }
}
