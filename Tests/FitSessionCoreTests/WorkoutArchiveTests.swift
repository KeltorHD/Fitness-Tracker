import Foundation
import Testing

@testable import FitSessionCore

private let archiveDate = Date(timeIntervalSince1970: 1_790_000_000)

private func archivedWorkout(at date: Date = archiveDate) throws -> Workout {
  var workout = try ExerciseCatalog.starterTemplates[0].start(at: date)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 8, weightKG: 42.5, at: date)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  workout.notes = "Техника и заметка по-русски"
  return workout
}

@Test func archiveRoundTripPreservesRecordsTemplatesAndExerciseIdentities() throws {
  let workout = try archivedWorkout()
  let archive = WorkoutArchive(
    workouts: [workout], templates: ExerciseCatalog.starterTemplates, exportedAt: archiveDate)
  let data = try WorkoutArchiveCodec.encode(archive)
  #expect(try WorkoutArchiveCodec.decode(data) == archive)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["format"] as? String == WorkoutArchive.formatIdentifier)
  #expect(object["exportedAt"] as? Double == archiveDate.timeIntervalSince1970)
  #expect(String(decoding: data, as: UTF8.self).contains("Техника"))
}

@Test func archiveRetainsFractionalPauseIntervalsAcrossManyPauses() throws {
  var workout = try ExerciseCatalog.starterTemplates[0].start(at: archiveDate)
  for index in 0..<100 {
    let date = archiveDate.addingTimeInterval(Double(index) + 0.123456)
    try WorkoutEngine.pause(&workout, at: date)
    try WorkoutEngine.resume(&workout, at: date.addingTimeInterval(0.378912))
  }
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 8, weightKG: 40, at: archiveDate.addingTimeInterval(101))
  try WorkoutEngine.finish(&workout, at: archiveDate.addingTimeInterval(120))
  let data = try WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [workout], templates: []))
  let restored = try #require(WorkoutArchiveCodec.decode(data).workouts.first)
  try Validation.workout(restored)
  #expect(restored.id == workout.id)
  #expect(abs(restored.pausedSeconds - workout.pausedSeconds) < 0.0001)
  #expect(abs(restored.duration() - workout.duration()) < 0.0001)
}

@Test func archiveAcceptsTheOriginalSingleWorkoutISO8601JSON() throws {
  let workout = try archivedWorkout()
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  let restored = try WorkoutArchiveCodec.decode(encoder.encode(workout))
  #expect(restored.workouts == [workout])
  #expect(restored.templates.isEmpty)
}

@Test(arguments: ["not JSON", "[]", "{}", "{\"name\":\"Not a workout\"}"])
func invalidArchiveInputIsRejected(_ input: String) {
  #expect(throws: WorkoutArchiveError.invalidFile) {
    try WorkoutArchiveCodec.decode(Data(input.utf8))
  }
}

@Test func archiveRejectsWrongFormatVersionAndIncompleteEnvelope() throws {
  let data = try WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [], templates: []))
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  object["version"] = 99
  #expect(throws: WorkoutArchiveError.unsupportedVersion) {
    try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  }
  object["version"] = 1
  object["format"] = "some.other.app"
  #expect(throws: WorkoutArchiveError.invalidFile) {
    try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  }
  object["format"] = WorkoutArchive.formatIdentifier
  object.removeValue(forKey: "templates")
  #expect(throws: WorkoutArchiveError.invalidFile) {
    try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  }
}

@Test func archiveRejectsOversizedDataBeforeDecoding() {
  #expect(throws: WorkoutArchiveError.tooLarge) {
    try WorkoutArchiveCodec.decode(Data(repeating: 0, count: WorkoutArchiveCodec.maximumBytes + 1))
  }
}

@Test func archiveRejectsDuplicateIDsInBothRecordKinds() throws {
  let workout = try archivedWorkout()
  #expect(throws: WorkoutArchiveError.duplicateID) {
    try WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [workout, workout], templates: []))
  }
  let template = ExerciseCatalog.starterTemplates[0]
  #expect(throws: WorkoutArchiveError.duplicateID) {
    try WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [], templates: [template, template]))
  }
}

@Test func archiveRejectsExcessiveRecordCounts() throws {
  let workout = try archivedWorkout()
  #expect(throws: WorkoutArchiveError.tooManyRecords) {
    try WorkoutArchiveCodec.validate(
      WorkoutArchive(
        workouts: Array(repeating: workout, count: 10_001), templates: []))
  }
}

@MainActor @Test func archiveImportIsIdempotentAndDoesNotOverwriteExistingIDs() throws {
  let repository = MemoryWorkoutRepository()
  let workout = try archivedWorkout()
  let template = ExerciseCatalog.starterTemplates[0]
  try repository.save(workout)
  try repository.saveTemplate(template)
  var changed = workout
  changed.notes = "Не должно перезаписать заметку"
  var changedTemplate = template
  changedTemplate.name = "Не должно перезаписать план"
  let newWorkout = try archivedWorkout(at: archiveDate.addingTimeInterval(3600))
  let archive = WorkoutArchive(workouts: [changed, newWorkout], templates: [changedTemplate])
  let first = try repository.importArchive(archive)
  #expect(first.addedWorkouts == 1 && first.addedTemplates == 0 && first.skippedExisting == 2)
  #expect(try repository.workouts().first { $0.id == workout.id } == workout)
  #expect(try repository.templates() == [template])
  let second = try repository.importArchive(archive)
  #expect(!second.hasChanges && second.skippedExisting == 3)
  #expect(try repository.workouts().count == 2)
}

@MainActor @Test func invalidRecordPreventsTheEntireImportFromChangingRepository() throws {
  let repository = MemoryWorkoutRepository()
  let existing = try archivedWorkout()
  try repository.save(existing)
  let good = try archivedWorkout(at: archiveDate.addingTimeInterval(3600))
  var bad = try archivedWorkout(at: archiveDate.addingTimeInterval(7200))
  bad.exercises[0].sets[0].weightKG = -1
  #expect(throws: TrainingError.invalidWeight) {
    try repository.importArchive(
      WorkoutArchive(
        workouts: [good, bad], templates: ExerciseCatalog.starterTemplates))
  }
  #expect(try repository.workouts() == [existing])
  #expect(try repository.templates().isEmpty)
}

@MainActor @Test
func importRestoresOnlyTheLatestUnfinishedSessionAndPreservesExistingActiveSession() throws {
  let repository = MemoryWorkoutRepository()
  let older = try ExerciseCatalog.starterTemplates[0].start(at: archiveDate)
  var latest = try ExerciseCatalog.starterTemplates[1].start(at: archiveDate.addingTimeInterval(60))
  try WorkoutEngine.pause(&latest, at: latest.startedAt)
  let completed = try archivedWorkout(at: archiveDate.addingTimeInterval(-3600))
  let archive = WorkoutArchive(workouts: [older, latest, completed], templates: [])
  let first = try repository.importArchive(archive)
  #expect(first.addedWorkouts == 2 && first.skippedUnfinished == 1)
  #expect(try repository.workouts().contains { $0.id == latest.id })
  #expect(try !repository.workouts().contains { $0.id == older.id })
  let again = try repository.importArchive(archive)
  #expect(again.skippedExisting == 2 && again.skippedUnfinished == 1)
}

@Test func emptyArchiveIsAValidNoOp() throws {
  let archive = WorkoutArchive(workouts: [], templates: [], exportedAt: archiveDate)
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive))
  let plan = try ArchiveImportPlan(archive: restored, existingWorkouts: [], existingTemplates: [])
  #expect(!plan.summary.hasChanges)
}
