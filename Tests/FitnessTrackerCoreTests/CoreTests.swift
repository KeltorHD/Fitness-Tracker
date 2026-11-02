import Foundation
import Testing

@testable import FitnessTrackerCore

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
private func session() -> Workout {
  Workout(
    name: "Силовая", startedAt: epoch,
    exercises: [
      WorkoutExercise(
        exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 5, weightKG: 100)])
    ])
}
private func finished(at date: Date = epoch) throws -> Workout {
  var workout = session()
  workout.startedAt = date
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id,
    setID: workout.exercises[0].sets[0].id, repetitions: 5, weightKG: 100, at: date)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  return workout
}

@Test func completedWorkingSetsDetermineVolume() throws {
  var workout = try finished()
  workout.exercises[0].sets.append(WorkoutSet(repetitions: 10, weightKG: 100))
  workout.exercises[0].sets.append(
    WorkoutSet(repetitions: 10, weightKG: 100, isWarmup: true, completedAt: epoch))
  #expect(workout.volume == 500)
  #expect(workout.completedSets == 2)
  #expect(workout.totalSets == 3)
}
@Test func invalidSetDoesNotMutateSession() {
  var workout = session()
  let original = workout
  #expect(throws: TrainingError.invalidRepetitions) {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: workout.exercises[0].id,
      setID: workout.exercises[0].sets[0].id, repetitions: 0, weightKG: 20, at: epoch)
  }
  #expect(workout == original)
}
@Test(arguments: [Double.nan, .infinity, -.infinity, -1, 1501])
func invalidWeightsAreRejected(_ weight: Double) {
  #expect(throws: TrainingError.invalidWeight) { try Validation.set(WorkoutSet(weightKG: weight)) }
}
@Test(arguments: [0, -1, 1001]) func invalidRepetitionsAreRejected(_ reps: Int) {
  #expect(throws: TrainingError.invalidRepetitions) {
    try Validation.set(WorkoutSet(repetitions: reps))
  }
}
@Test func bodyweightAndWarmupAreSupported() throws {
  try Validation.set(WorkoutSet(repetitions: 10, weightKG: 0, isWarmup: true))
}
@Test func pauseResumeAndFinishExcludePausedTime() throws {
  var workout = session()
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id,
    setID: workout.exercises[0].sets[0].id, repetitions: 5, weightKG: 50, at: epoch)
  #expect(workout.remainingRest(at: epoch.addingTimeInterval(30)) == 60)
  try WorkoutEngine.pause(&workout, at: epoch.addingTimeInterval(20))
  #expect(workout.duration(at: epoch.addingTimeInterval(100)) == 20)
  #expect(workout.restEndsAt == nil)
  try WorkoutEngine.resume(&workout, at: epoch.addingTimeInterval(80))
  try WorkoutEngine.finish(&workout, at: epoch.addingTimeInterval(120))
  #expect(workout.duration(at: epoch.addingTimeInterval(200)) == 60)
  try Validation.workout(workout)
}
@Test func finishDuringPauseAccountsForPause() throws {
  var workout = try finished()
  workout.status = .active
  workout.endedAt = nil
  try WorkoutEngine.pause(&workout, at: epoch.addingTimeInterval(10))
  try WorkoutEngine.finish(&workout, at: epoch.addingTimeInterval(50))
  #expect(workout.duration() == 10)
}
@Test func emptyWorkoutCannotFinish() {
  var workout = session()
  #expect(throws: TrainingError.emptyWorkout) { try WorkoutEngine.finish(&workout, at: epoch) }
  #expect(workout.status == .active)
}
@Test func completedWorkoutCannotBeResumedOrCompletedAgain() throws {
  var workout = try finished()
  #expect(throws: TrainingError.invalidState) { try WorkoutEngine.resume(&workout) }
  #expect(throws: TrainingError.invalidState) { try WorkoutEngine.finish(&workout) }
}
@Test func sameSetCannotBeCompletedTwice() throws {
  var workout = session()
  let e = workout.exercises[0].id
  let s = workout.exercises[0].sets[0].id
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: e, setID: s, repetitions: 5, weightKG: 20, at: epoch)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: e, setID: s, repetitions: 5, weightKG: 20, at: epoch)
  }
}
@Test func invalidClockDoesNotMutate() throws {
  var workout = session()
  let initial = workout
  #expect(throws: TrainingError.invalidDate) {
    try WorkoutEngine.pause(&workout, at: epoch.addingTimeInterval(-1))
  }
  #expect(workout == initial)
  try WorkoutEngine.pause(&workout, at: epoch)
  #expect(throws: TrainingError.invalidDate) {
    try WorkoutEngine.resume(&workout, at: epoch.addingTimeInterval(-1))
  }
}
@Test func cancelledWorkoutsAreNotStatistics() throws {
  var workout = session()
  try WorkoutEngine.cancel(&workout, at: epoch)
  #expect(workout.status == .cancelled)
  #expect(TrainingStatistics.records(in: [workout]).isEmpty)
  #expect(TrainingStatistics.weeks(in: [workout], now: epoch).allSatisfy { $0.workouts == 0 })
}
@Test func templatesProduceIndependentIDs() throws {
  let template = ExerciseCatalog.starterTemplates[0]
  let a = try template.start(at: epoch)
  let b = try template.start(at: epoch)
  #expect(a.id != b.id)
  #expect(a.exercises[0].id != b.exercises[0].id)
  #expect(a.exercises[0].sets[0].id != b.exercises[0].sets[0].id)
  #expect(a.exercises[0].exercise.id == b.exercises[0].exercise.id)
  #expect(a.totalSets == 9)
}
@Test(arguments: [-1, 0, 31]) func invalidTemplateCounts(_ count: Int) {
  let template = WorkoutTemplate(
    name: "A", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0], setCount: count)])
  #expect(throws: TrainingError.invalidSetCount) { try template.start() }
}
@Test func catalogAndTemplatesAreValid() throws {
  #expect(Set(ExerciseCatalog.all.map(\.id)).count == ExerciseCatalog.all.count)
  for template in ExerciseCatalog.starterTemplates { try Validation.template(template) }
}
@Test func oneRepMaxBoundaries() {
  #expect(TrainingStatistics.estimatedOneRepMax(weightKG: 100, repetitions: 1) == 100)
  #expect(TrainingStatistics.estimatedOneRepMax(weightKG: 100, repetitions: 6) == 120)
  #expect(TrainingStatistics.estimatedOneRepMax(weightKG: 100, repetitions: 13) == nil)
  #expect(TrainingStatistics.estimatedOneRepMax(weightKG: .nan, repetitions: 1) == nil)
  #expect(TrainingStatistics.estimatedOneRepMax(weightKG: 0, repetitions: 10) == nil)
}
@Test func recordsIgnoreUnfinishedSets() throws {
  var workout = try finished()
  workout.exercises[0].sets.append(WorkoutSet(repetitions: 1, weightKG: 400))
  let records = TrainingStatistics.records(in: [workout])
  #expect(records.count == 1)
  #expect(records[0].weightKG == 100)
}
@Test func weekBoundariesAndMissingWeeks() throws {
  var calendar = Calendar(identifier: .iso8601)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
  let workouts = try [finished(at: monday.addingTimeInterval(-60)), finished(at: monday)]
  let weeks = TrainingStatistics.weeks(
    in: workouts, count: 3, now: monday.addingTimeInterval(100), calendar: calendar)
  #expect(weeks.map(\.workouts) == [0, 1, 1])
  #expect(
    TrainingStatistics.weeklyStreak(
      in: workouts, now: monday.addingTimeInterval(100), calendar: calendar) == 2)
  #expect(TrainingStatistics.weeklyStreak(in: [workouts[0]], now: monday, calendar: calendar) == 1)
  #expect(TrainingStatistics.weeks(in: [], count: -1).isEmpty)
}
@Test func futureWorkoutsAreExcluded() throws {
  #expect(
    TrainingStatistics.weeks(in: [try finished(at: epoch.addingTimeInterval(60))], now: epoch)
      .allSatisfy { $0.workouts == 0 })
}
@Test func weightConversionRoundTrip() {
  let pounds = WeightUnit.pounds.display(100)
  #expect(abs(WeightUnit.pounds.kilograms(from: pounds) - 100) < 0.00001)
}
@Test func codableRoundTripPreservesSession() throws {
  let workout = try finished()
  let data = try JSONEncoder().encode(workout)
  #expect(try JSONDecoder().decode(Workout.self, from: data) == workout)
}
@Test func duplicateIDsRejected() {
  var workout = session()
  workout.exercises.append(workout.exercises[0])
  #expect(throws: TrainingError.duplicateID) { try Validation.workout(workout) }
}
@Test func addSetCopiesTargetsButResetsCompletion() throws {
  var workout = try finished()
  workout.status = .active
  workout.endedAt = nil
  try WorkoutEngine.addSet(exerciseID: workout.exercises[0].id, to: &workout)
  #expect(workout.exercises[0].sets.last?.completedAt == nil)
  #expect(workout.exercises[0].sets.last?.weightKG == 100)
}
@Test @MainActor func repositoryUpsertDeleteAndValidation() throws {
  let repo = MemoryWorkoutRepository()
  var workout = try finished()
  try repo.save(workout)
  workout.notes = "Обновлено"
  try repo.save(workout)
  #expect(try repo.workouts().count == 1)
  #expect(try repo.workouts()[0].notes == "Обновлено")
  workout.name = " "
  #expect(throws: TrainingError.invalidName) { try repo.save(workout) }
  try repo.deleteWorkout(id: workout.id)
  #expect(try repo.workouts().isEmpty)
  let template = ExerciseCatalog.starterTemplates[0]
  try repo.saveTemplate(template)
  try repo.saveTemplate(template)
  #expect(try repo.templates().count == 1)
  try repo.deleteTemplate(id: template.id)
  #expect(try repo.templates().isEmpty)
}

@Test func exerciseInsertionUsesRowIdentityAndPreservesExistingTargets() throws {
  let shared = ExerciseCatalog.all[0]
  let first = WorkoutExercise(exercise: shared, sets: [WorkoutSet(repetitions: 5, weightKG: 80)])
  let second = WorkoutExercise(exercise: shared, sets: [WorkoutSet(repetitions: 10, weightKG: 40)])
  var workout = Workout(name: "План", startedAt: epoch, exercises: [first, second])
  try WorkoutEngine.addExercise(ExerciseCatalog.all[1], to: &workout, position: .before(second.id))
  let beforeID = workout.exercises[1].id
  try WorkoutEngine.addExercise(ExerciseCatalog.all[2], to: &workout, position: .after(second.id))
  let afterID = workout.exercises[3].id
  #expect(workout.exercises.map(\.id) == [first.id, beforeID, second.id, afterID])
  #expect(workout.exercises[0] == first && workout.exercises[2] == second)
  try WorkoutEngine.addExercise(shared, to: &workout, position: .before(first.id))
  #expect(workout.exercises[0].exercise.id == shared.id)
  try WorkoutEngine.addExercise(shared, to: &workout)
  #expect(workout.exercises.last?.exercise.id == shared.id)
  #expect(Set(workout.exercises.map(\.id)).count == 6)
  #expect(Set(workout.exercises.flatMap(\.sets).map(\.id)).count == 6)
  try Validation.workout(workout)
}

@Test func staleExerciseAnchorAndRepeatedRemovalDoNotMutateWorkout() throws {
  var workout = session()
  let removedID = workout.exercises[0].id
  try WorkoutEngine.removeExercise(id: removedID, from: &workout)
  let original = workout
  for position in [WorkoutExerciseInsertion.before(removedID), .after(removedID)] {
    #expect(throws: TrainingError.missingExercise) {
      try WorkoutEngine.addExercise(ExerciseCatalog.all[1], to: &workout, position: position)
    }
    #expect(workout == original)
  }
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.removeExercise(id: removedID, from: &workout)
  }
  #expect(workout == original)
  try WorkoutEngine.addExercise(ExerciseCatalog.all[1], to: &workout)
  #expect(workout.exercises.count == 1)
}

@Test(arguments: [WorkoutStatus.paused, .completed, .cancelled])
func exerciseStructureChangesRejectNonActiveWorkouts(_ status: WorkoutStatus) throws {
  var workout = session()
  switch status {
  case .paused: try WorkoutEngine.pause(&workout, at: epoch)
  case .completed: workout = try finished()
  case .cancelled: try WorkoutEngine.cancel(&workout, at: epoch)
  case .active: return
  }
  let original = workout
  let id = workout.exercises[0].id
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.addExercise(ExerciseCatalog.all[1], to: &workout, position: .before(id))
  }
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.removeExercise(id: id, from: &workout)
  }
  #expect(workout == original)
}

@Test func removingExercisePreservesOtherRowsAndTheirRestTimer() throws {
  var workout = session()
  let first = workout.exercises[0]
  try WorkoutEngine.addExercise(first.exercise, to: &workout)
  let second = workout.exercises[1]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: first.id, setID: first.sets[0].id,
    repetitions: 5, weightKG: 80, at: epoch)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: second.id, setID: second.sets[0].id,
    repetitions: 4, weightKG: 20, at: epoch.addingTimeInterval(20))
  let retained = workout.exercises[1]
  let restEnd = workout.restEndsAt
  try WorkoutEngine.removeExercise(id: first.id, from: &workout)
  #expect(workout.exercises == [retained])
  #expect(workout.volume == 80 && workout.completedSets == 1)
  #expect(workout.restEndsAt == restEnd)
  try Validation.workout(workout)
}

@Test func removingLastExerciseClearsItsRestAndReturnsToValidEmptySession() throws {
  var workout = session()
  let row = workout.exercises[0]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: row.sets[0].id,
    repetitions: 5, weightKG: 80, at: epoch)
  #expect(workout.restEndsAt != nil)
  try WorkoutEngine.removeExercise(id: row.id, from: &workout)
  #expect(workout.exercises.isEmpty && workout.volume == 0 && workout.completedSets == 0)
  #expect(workout.restEndsAt == nil && workout.status == .active)
  try Validation.workout(workout)
  #expect(throws: TrainingError.emptyWorkout) { try WorkoutEngine.finish(&workout, at: epoch) }
}

@Test func removingCompletedDropExerciseClearsRestFromItsFinalStage() throws {
  let stage = DropSetStage(repetitions: 8, weightKG: 20)
  let set = WorkoutSet(repetitions: 8, weightKG: 40, dropStages: [stage])
  let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [set])
  var workout = Workout(name: "Дропсет", startedAt: epoch, exercises: [row])
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 8, weightKG: 40, at: epoch)
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: stage.id,
    repetitions: 8, weightKG: 20, at: epoch.addingTimeInterval(10))
  #expect(workout.restEndsAt == epoch.addingTimeInterval(100))
  try WorkoutEngine.removeExercise(id: row.id, from: &workout)
  #expect(workout.restEndsAt == nil)
  try Validation.workout(workout)
}

@Test func insertingInvalidExerciseDoesNotChangeRowOrder() {
  var workout = session()
  let original = workout
  #expect(throws: TrainingError.invalidName) {
    try WorkoutEngine.addExercise(
      Exercise(name: " ", muscle: .chest), to: &workout,
      position: .after(original.exercises[0].id))
  }
  #expect(workout == original)
}

@Test func removalPreservesRestSharedByAnotherCompletionAtTheSameInstant() throws {
  var workout = session()
  try WorkoutEngine.addExercise(ExerciseCatalog.all[1], to: &workout)
  let rows = workout.exercises
  for row in rows {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id,
      repetitions: 5, weightKG: 20, at: epoch)
  }
  let deadline = workout.restEndsAt
  try WorkoutEngine.removeExercise(id: rows[0].id, from: &workout)
  #expect(workout.restEndsAt == deadline)
  try WorkoutEngine.removeExercise(id: rows[1].id, from: &workout)
  #expect(workout.restEndsAt == nil)
}
