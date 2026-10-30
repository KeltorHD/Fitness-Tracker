import Foundation
import Testing

@testable import FitnessTrackerCore

private let weightDate = Date(timeIntervalSince1970: 1_793_000_000)
private func weightedWorkout(weight: Double = 72.5) throws -> Workout {
  var workout = Workout(
    name: "Weight fixture", startedAt: weightDate, bodyWeightKG: weight)
  workout.exercises = [
    WorkoutExercise(
      exercise: ExerciseCatalog.all[0],
      sets: [WorkoutSet(weightKG: 40, completedAt: weightDate)])
  ]
  try WorkoutEngine.finish(&workout, at: weightDate.addingTimeInterval(60))
  return workout
}

@Test(arguments: [0.0, -1, .infinity, .nan, 1000.01])
func bodyWeightRejectsInvalidValuesWithoutChangingAWorkout(_ value: Double) throws {
  var workout = Workout(name: "Weight fixture", bodyWeightKG: 72.5)
  let before = workout
  #expect(throws: TrainingError.invalidBodyWeight) {
    try WorkoutEngine.setBodyWeight(value, in: &workout)
  }
  #expect(workout == before)
  #expect(throws: TrainingError.invalidBodyWeight) {
    try Validation.bodyWeightEntry(BodyWeightEntry(weightKG: value))
  }
}

@Test func bodyWeightUpdatesPausedSessionsButNeverCopiesIntoRepeatedWorkouts() throws {
  var workout = Workout(name: "Weight fixture", startedAt: weightDate)
  try WorkoutEngine.pause(&workout, at: weightDate)
  try WorkoutEngine.setBodyWeight(72.5, in: &workout)
  #expect(workout.bodyWeightKG == 72.5)
  try WorkoutEngine.setBodyWeight(nil, in: &workout)
  #expect(workout.bodyWeightKG == nil)
  var completed = try weightedWorkout()
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.setBodyWeight(70, in: &completed)
  }
  let repeated = try WorkoutEngine.repeatWorkout(completed, at: weightDate.addingTimeInterval(3600))
  #expect(repeated.bodyWeightKG == nil)
  #expect(completed.bodyWeightKG == 72.5)
  #expect(completed.volume == 320)
}

@Test func bodyWeightSummaryCombinesSourcesWithoutDuplicatingOrInventingValues() throws {
  let workout = try weightedWorkout()
  let first = BodyWeightEntry(measuredAt: weightDate.addingTimeInterval(-3600), weightKG: 73)
  let future = BodyWeightEntry(measuredAt: weightDate.addingTimeInterval(86400), weightKG: 99)
  var unfinished = workout
  unfinished.id = UUID()
  unfinished.status = .active
  var cancelled = workout
  cancelled.id = UUID()
  cancelled.status = .cancelled
  let summary = BodyWeightSummary(
    entries: [future, first], workouts: [cancelled, unfinished, workout],
    now: weightDate.addingTimeInterval(120))
  #expect(summary.points.count == 2)
  #expect(summary.latest?.source == .workout(workout.id))
  #expect(summary.latest?.weightKG == 72.5)
  #expect(summary.changeKG == -0.5)
  #expect(BodyWeightSummary(entries: [], workouts: []).latest == nil)
  #expect(BodyWeightSummary(entries: [first], workouts: [], now: weightDate).changeKG == nil)
  let sameID = BodyWeightEntry(id: workout.id, measuredAt: weightDate, weightKG: 73)
  let tied = BodyWeightSummary(entries: [sameID], workouts: [workout], now: weightDate)
  #expect(Set(tied.points.map(\.id)).count == 2)
}

@Test func bodyWeightArchiveVersionTwoRoundTripsAndRejectsMissingRecords() throws {
  let entry = BodyWeightEntry(measuredAt: weightDate, weightKG: 72.345)
  let workout = try weightedWorkout()
  let archive = WorkoutArchive(
    workouts: [workout], templates: [], bodyWeights: [entry], exportedAt: weightDate)
  let data = try WorkoutArchiveCodec.encode(archive)
  #expect(try WorkoutArchiveCodec.decode(data) == archive)
  #expect(archive.version == 2)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  object.removeValue(forKey: "bodyWeights")
  #expect(throws: WorkoutArchiveError.invalidFile) {
    try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  }
}

@Test func bodyWeightMigrationReadsVersionOneAndOriginalWorkoutPayloads() throws {
  let archive = WorkoutArchive(
    workouts: [try weightedWorkout()], templates: [], exportedAt: weightDate)
  var object = try #require(
    JSONSerialization.jsonObject(with: WorkoutArchiveCodec.encode(archive)) as? [String: Any])
  object["version"] = 1
  object.removeValue(forKey: "bodyWeights")
  var workouts = try #require(object["workouts"] as? [[String: Any]])
  workouts[0].removeValue(forKey: "bodyWeightKG")
  object["workouts"] = workouts
  let restored = try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  #expect(restored.bodyWeights.isEmpty)
  #expect(restored.workouts.first?.bodyWeightKG == nil)
  #expect(restored.version == 2)
  let original = try #require(workouts.first)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  let legacyWorkout = try decoder.decode(
    Workout.self, from: JSONSerialization.data(withJSONObject: original))
  #expect(legacyWorkout.bodyWeightKG == nil)
}

@Test @MainActor func bodyWeightImportIsAdditiveAtomicAndIdempotent() throws {
  let repository = MemoryWorkoutRepository()
  let own = BodyWeightEntry(measuredAt: weightDate, weightKG: 70)
  try repository.saveBodyWeight(own)
  var conflict = own
  conflict.weightKG = 90
  let extra = BodyWeightEntry(measuredAt: weightDate.addingTimeInterval(3600), weightKG: 71)
  let archive = WorkoutArchive(workouts: [], templates: [], bodyWeights: [conflict, extra])
  let first = try repository.importArchive(archive)
  #expect(first.addedBodyWeights == 1 && first.hasChanges && first.skippedExisting == 1)
  #expect(try repository.bodyWeights() == [extra, own])
  #expect(try !repository.importArchive(archive).hasChanges)
  let before = try repository.bodyWeights()
  let invalid = BodyWeightEntry(measuredAt: weightDate, weightKG: -1)
  #expect(throws: TrainingError.invalidBodyWeight) {
    try repository.importArchive(
      WorkoutArchive(workouts: [weightedWorkout()], templates: [], bodyWeights: [invalid]))
  }
  #expect(try repository.bodyWeights() == before)
  #expect(try repository.workouts().isEmpty)
  #expect(throws: WorkoutArchiveError.duplicateID) {
    try WorkoutArchiveCodec.encode(
      WorkoutArchive(workouts: [], templates: [], bodyWeights: [own, own]))
  }
}

@Test @MainActor func bodyWeightRepositoryCRUDAndDemoIsolationPreservePersonalRecords() throws {
  let personal = MemoryWorkoutRepository()
  var entry = BodyWeightEntry(measuredAt: weightDate, weightKG: 72)
  try personal.saveBodyWeight(entry)
  entry.weightKG = 71
  try personal.saveBodyWeight(entry)
  #expect(try personal.bodyWeights() == [entry])
  let workspace = WorkoutWorkspaceRepository(personal: personal)
  try workspace.openDemo(WorkoutArchive(workouts: [], templates: []))
  #expect(try workspace.bodyWeights().isEmpty)
  var demoEntry = entry
  demoEntry.weightKG = 99
  try workspace.saveBodyWeight(demoEntry)
  try workspace.deleteBodyWeight(id: entry.id)
  #expect(try personal.bodyWeights() == [entry])
  let restored = try workspace.closeDemo()
  #expect(restored.bodyWeights == [entry])
  try workspace.deleteBodyWeight(id: entry.id)
  #expect(try personal.bodyWeights().isEmpty)
}

@Test func bodyWeightDatesAndPoundsAreValidatedWithoutChangingKilogramStorage() throws {
  let weight = WeightUnit.pounds.kilograms(from: 160)
  let entry = BodyWeightEntry(measuredAt: weightDate, weightKG: weight)
  try Validation.bodyWeightEntry(entry)
  #expect(abs(WeightUnit.pounds.display(entry.weightKG) - 160) < 0.000001)
  let invalid = BodyWeightEntry(measuredAt: Date(timeIntervalSince1970: .nan), weightKG: 72)
  #expect(throws: TrainingError.invalidMeasurementDate) { try Validation.bodyWeightEntry(invalid) }
}
