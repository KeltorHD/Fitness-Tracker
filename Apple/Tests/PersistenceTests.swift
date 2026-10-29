import FitSessionCore
import XCTest

@testable import FitSession

@MainActor final class PersistenceTests: XCTestCase {
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
