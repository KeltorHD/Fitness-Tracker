import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func pendingInputsPersistIndependentlyWithoutCompletingOrStartingRest() throws {
  let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 0)])
  var workout = Workout(name: "Ввод", exercises: [row], restSeconds: 90)
  try WorkoutEngine.updatePendingValues([row.sets[0].id: .init(weightKG: 42.5)], in: &workout)
  #expect(workout.exercises[0].sets[0].weightKG == 42.5)
  #expect(workout.exercises[0].sets[0].repetitions == 0)
  try WorkoutEngine.pause(&workout)
  try WorkoutEngine.updatePendingValues([row.sets[0].id: .init(repetitions: 11)], in: &workout)
  let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
  #expect(restored.exercises[0].sets[0].repetitions == 11)
  #expect(restored.exercises[0].sets[0].weightKG == 42.5)
  #expect(restored.completedSets == 0 && restored.volume == 0 && restored.restEndsAt == nil)
}

@Test func pendingInputUpdatesRejectRecordedTargetsAndInvalidBatchesAtomically() throws {
  let row = WorkoutExercise(
    exercise: ExerciseCatalog.all[0],
    sets: [WorkoutSet(weightKG: 50, dropStages: [DropSetStage(weightKG: 40)])])
  var workout = Workout(name: "Дропсет", exercises: [row])
  let target = row.sets[0].id
  let drop = try #require(row.sets[0].dropStages?.first?.id)
  try WorkoutEngine.updatePendingValues(
    [target: .init(weightKG: 30), drop: .init(weightKG: 20)], in: &workout)
  let original = workout
  #expect(throws: TrainingError.invalidDropSet) {
    try WorkoutEngine.updatePendingValues([target: .init(weightKG: 10)], in: &workout)
  }
  #expect(workout == original)
  #expect(throws: TrainingError.missingSet) {
    try WorkoutEngine.updatePendingValues(
      [target: .init(repetitions: 12), UUID(): .init(weightKG: 10)], in: &workout)
  }
  #expect(workout == original)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: target, repetitions: 8, weightKG: 30)
  let recorded = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.updatePendingValues([target: .init(weightKG: 35)], in: &workout)
  }
  #expect(workout == recorded)
  try WorkoutEngine.finish(&workout)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.updatePendingValues([drop: .init(weightKG: 15)], in: &workout)
  }
}

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
@Test func addSetStartsBlankAndPreservesLoadMultiplierWithoutChangingRecordedWork() throws {
  var workout = try finished()
  workout.status = .active
  workout.endedAt = nil
  workout.exercises[0].sets[0].loadMultiplier = 2
  let original = workout.exercises[0].sets[0]
  try WorkoutEngine.addSet(exerciseID: workout.exercises[0].id, to: &workout)
  #expect(workout.exercises[0].sets.last?.completedAt == nil)
  #expect(workout.exercises[0].sets.last?.weightKG == 0)
  #expect(workout.exercises[0].sets.last?.repetitions == 0)
  #expect(workout.exercises[0].sets.last?.loadMultiplier == 2)
  #expect(workout.exercises[0].sets.last?.id != original.id)
  #expect(workout.exercises[0].sets[0] == original)
  try Validation.workout(workout)
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
  let added = workout.exercises.filter { $0.id != first.id && $0.id != second.id }
  #expect(added.flatMap(\.sets).allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
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

@Test func setNoteCompatibilityAndRoundTrip() throws {
  let original = WorkoutSet(repetitions: 8, weightKG: 40)
  let data = try JSONEncoder().encode(original)
  let legacy = try JSONDecoder().decode(WorkoutSet.self, from: data)
  #expect(legacy.note == nil)
  var workout = session()
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  try WorkoutEngine.setNote("  Keep elbows close \n", exerciseID: row, setID: set, in: &workout)
  #expect(workout.exercises[0].sets[0].note == "Keep elbows close")
  let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
  #expect(restored == workout)
  try WorkoutEngine.setNote(" \n", exerciseID: row, setID: set, in: &workout)
  #expect(workout.exercises[0].sets[0].note == nil)
  #expect(throws: TrainingError.invalidSetNote) {
    try WorkoutEngine.setNote(
      String(repeating: "x", count: 2001), exerciseID: row, setID: set, in: &workout)
  }
  #expect(throws: TrainingError.invalidSetNote) {
    try Validation.set(WorkoutSet(note: String(repeating: "x", count: 2001)))
  }
}

@Test func setNotesPreservePerformanceAndFollowRepeatAndTemplate() throws {
  var workout = try finished()
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.setNote("readonly", exerciseID: row, setID: set, in: &workout)
  }
  workout.status = .active
  workout.endedAt = nil
  let volume = workout.volume
  try WorkoutEngine.setNote("Technique", exerciseID: row, setID: set, in: &workout)
  #expect(workout.volume == volume)
  try WorkoutEngine.pause(&workout, at: epoch.addingTimeInterval(61))
  try WorkoutEngine.setNote("Technique updated", exerciseID: row, setID: set, in: &workout)
  try WorkoutEngine.finish(&workout, at: epoch.addingTimeInterval(62))
  let repeated = try WorkoutEngine.repeatWorkout(workout, at: epoch.addingTimeInterval(100))
  #expect(repeated.exercises[0].sets[0].note == "Technique updated")
  #expect(repeated.exercises[0].sets[0].completedAt == nil)
  #expect(repeated.exercises[0].sets[0].id != set)
  let template = try WorkoutEngine.makeTemplate(from: workout)
  #expect(template.exercises[0].plannedSets?.first?.note == "Technique updated")
}

@Test func insertingSetStartsBlankWithAnchorMultiplierWithoutCopyingNoteOrCompletion() throws {
  var workout = session()
  let row = workout.exercises[0].id
  let anchor = workout.exercises[0].sets[0].id
  workout.exercises[0].sets[0].note = "Only this set"
  workout.exercises[0].sets[0].loadMultiplier = 3
  workout.exercises[0].sets.append(WorkoutSet(repetitions: 12, weightKG: 20))
  let last = workout.exercises[0].sets[1].id
  try WorkoutEngine.addSet(exerciseID: row, to: &workout, after: anchor)
  let added = workout.exercises[0].sets[1]
  #expect(added.repetitions == 0 && added.weightKG == 0 && added.loadMultiplier == 3)
  #expect(added.note == nil && added.completedAt == nil && added.id != anchor)
  #expect(workout.exercises[0].sets[2].id == last)
  let snapshot = workout
  #expect(throws: TrainingError.missingSet) {
    try WorkoutEngine.addSet(exerciseID: row, to: &workout, after: UUID())
  }
  #expect(workout == snapshot)
}

@Test func removingCompletedSetUpdatesVolumeAndRestAndProtectsLastSet() throws {
  var workout = session()
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  try WorkoutEngine.addSet(exerciseID: row, to: &workout)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row, setID: set, repetitions: 5, weightKG: 100, at: epoch)
  #expect(workout.restEndsAt != nil && workout.volume == 500)
  try WorkoutEngine.removeSet(exerciseID: row, setID: set, from: &workout)
  #expect(workout.restEndsAt == nil && workout.volume == 0)
  let last = workout.exercises[0].sets[0].id
  #expect(throws: TrainingError.invalidSetCount) {
    try WorkoutEngine.removeSet(exerciseID: row, setID: last, from: &workout)
  }
  try WorkoutEngine.pause(&workout, at: epoch)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.addSet(exerciseID: row, to: &workout)
  }
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.removeSet(exerciseID: row, setID: last, from: &workout)
  }
}

@Test func removingSetPreservesRestSharedByAnotherRow() throws {
  var workout = session()
  workout.exercises.append(WorkoutExercise(exercise: ExerciseCatalog.all[1], sets: [WorkoutSet()]))
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  try WorkoutEngine.addSet(exerciseID: row, to: &workout)
  for exercise in workout.exercises {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: exercise.id, setID: exercise.sets[0].id, repetitions: 5,
      weightKG: 40, at: epoch)
  }
  let deadline = workout.restEndsAt
  try WorkoutEngine.removeSet(exerciseID: row, setID: set, from: &workout)
  #expect(workout.restEndsAt == deadline)
}

@Test func setLimitAndDropSetRemovalAreAtomic() throws {
  var workout = session()
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  workout.exercises[0].sets[0].dropStages = [DropSetStage(repetitions: 8, weightKG: 60)]
  for _ in 1..<30 { try WorkoutEngine.addSet(exerciseID: row, to: &workout) }
  let original = workout
  #expect(throws: TrainingError.invalidSetCount) {
    try WorkoutEngine.addSet(exerciseID: row, to: &workout)
  }
  #expect(workout == original)
  try WorkoutEngine.removeSet(exerciseID: row, setID: set, from: &workout)
  #expect(workout.exercises[0].sets.count == 29)
  #expect(!workout.exercises[0].sets.contains { $0.id == set })
  let snapshot = workout
  #expect(throws: TrainingError.missingSet) {
    try WorkoutEngine.removeSet(exerciseID: row, setID: set, from: &workout)
  }
  #expect(workout == snapshot)
}

@Test func exerciseReorderingPreservesRowsAndRejectsStaleOrders() throws {
  var workout = session()
  let first = workout.exercises[0]
  // Two occurrences of one exercise must keep independent set IDs and notes.
  var second = WorkoutExercise(exercise: first.exercise, sets: [WorkoutSet(note: "Second row")])
  second.sets[0].completedAt = epoch
  workout.exercises.append(second)
  workout.restEndsAt = epoch.addingTimeInterval(90)
  let original = workout
  try WorkoutEngine.reorderExercises([second.id, first.id], in: &workout)
  #expect(workout.exercises == [second, first])
  #expect(workout.restEndsAt == original.restEndsAt && workout.volume == original.volume)
  try WorkoutEngine.reorderExercises([first.id, second.id], in: &workout)
  #expect(workout == original)
  #expect(throws: TrainingError.duplicateID) {
    try WorkoutEngine.reorderExercises([first.id, first.id], in: &workout)
  }
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.reorderExercises([first.id], in: &workout)
  }
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.reorderExercises([first.id, UUID()], in: &workout)
  }
  #expect(workout == original)
}

@Test(arguments: [WorkoutStatus.paused, .completed, .cancelled])
func exerciseReorderingRejectsNonActiveSessions(_ status: WorkoutStatus) {
  var workout = session()
  workout.status = status
  let original = workout
  let ids = workout.exercises.map(\.id)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.reorderExercises(ids, in: &workout)
  }
  #expect(workout == original)
}

@Test func appendingTemplatesPreservesRecordedWorkAndSessionSettings() throws {
  var workout = session()
  let row = workout.exercises[0].id
  let set = workout.exercises[0].sets[0].id
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row, setID: set, repetitions: 5, weightKG: 100, at: epoch)
  workout.notes = "Session note"
  workout.exercises[0].sets[0].note = "Recorded note"
  workout.restSeconds = 120
  workout.restEndsAt = epoch.addingTimeInterval(120)
  let original = workout
  let template = WorkoutTemplate(
    name: "Additional",
    exercises: [
      TemplateExercise(
        exercise: workout.exercises[0].exercise, setCount: 2, repetitions: 12, weightKG: 20)
    ], restSeconds: 30)
  try WorkoutEngine.addTemplates([template], to: &workout)
  #expect(workout.exercises.count == 2)
  #expect(workout.exercises[0] == original.exercises[0])
  #expect(workout.exercises[1].exercise == original.exercises[0].exercise)
  #expect(workout.exercises[1].id != row)
  #expect(
    workout.exercises[1].sets.allSatisfy {
      $0.id != set && $0.completedAt == nil && $0.repetitions == 12
    })
  #expect(workout.volume == original.volume)
  workout.exercises.removeLast()
  #expect(workout == original)
}

@Test func invalidTemplateAdditionDoesNotPartiallyAppend() throws {
  var workout = session()
  let original = workout
  let valid = WorkoutTemplate(
    name: "Valid", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[1])])
  let invalid = WorkoutTemplate(name: "Invalid", exercises: [])
  #expect(throws: TrainingError.emptyWorkout) {
    try WorkoutEngine.addTemplates([valid, invalid], to: &workout)
  }
  #expect(workout == original)
  #expect(throws: TrainingError.emptyWorkout) { try WorkoutEngine.addTemplates([], to: &workout) }
  #expect(workout == original)
}

@Test(arguments: [WorkoutStatus.paused, .completed, .cancelled])
func templateAdditionRejectsNonActiveSessions(_ status: WorkoutStatus) {
  var workout = session()
  workout.status = status
  let original = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.addTemplates(ExerciseCatalog.starterTemplates, to: &workout)
  }
  #expect(workout == original)
}

@Test func replacingUnusedExerciseKeepsPositionAndStartsFreshTargets() throws {
  var workout = session()
  let original = workout
  let row = workout.exercises[0]
  let replacement = ExerciseCatalog.all[1]
  let id = try WorkoutEngine.replaceExercise(id: row.id, with: replacement, in: &workout)
  #expect(
    id == row.id && workout.exercises.count == 1 && workout.exercises[0].exercise == replacement)
  #expect(workout.exercises[0].sets[0].id != row.sets[0].id)
  #expect(
    workout.exercises[0].sets[0].weightKG == 0 && workout.exercises[0].sets[0].repetitions == 0
      && workout.exercises[0].sets[0].completedAt == nil)
  #expect(
    workout.id == original.id && workout.startedAt == original.startedAt
      && workout.restSeconds == original.restSeconds)
  let unchanged = workout
  try WorkoutEngine.replaceExercise(id: id, with: replacement, in: &workout)
  #expect(workout == unchanged)
}

@Test func replacingRecordedExerciseKeepsItsAttributionAndRest() throws {
  var workout = session()
  let row = workout.exercises[0]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: row.sets[0].id, repetitions: 5, weightKG: 100,
    at: epoch)
  workout.exercises[0].sets[0].note = "Original exercise note"
  let original = workout
  let replacement = ExerciseCatalog.all[1]
  let id = try WorkoutEngine.replaceExercise(id: row.id, with: replacement, in: &workout)
  #expect(workout.exercises.count == 2 && workout.exercises[0] == original.exercises[0])
  #expect(
    workout.exercises[1].id == id && id != row.id && workout.exercises[1].exercise == replacement)
  #expect(workout.exercises[1].sets.allSatisfy { $0.completedAt == nil && $0.note == nil })
  #expect(workout.exercises[1].sets.allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
  #expect(workout.volume == original.volume && workout.restEndsAt == original.restEndsAt)
  #expect(workout.name == original.name && workout.startedAt == original.startedAt)
}

@Test func replacementRejectsStaleTargetAndInvalidExerciseAtomically() throws {
  var workout = session()
  let original = workout
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.replaceExercise(id: UUID(), with: ExerciseCatalog.all[1], in: &workout)
  }
  #expect(throws: TrainingError.invalidName) {
    try WorkoutEngine.replaceExercise(
      id: original.exercises[0].id, with: Exercise(name: "", muscle: .back), in: &workout)
  }
  #expect(workout == original)
}

@Test(arguments: [WorkoutStatus.paused, .completed, .cancelled])
func replacementRequiresActiveSession(_ status: WorkoutStatus) {
  var workout = session()
  workout.status = status
  let original = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.replaceExercise(
      id: original.exercises[0].id, with: ExerciseCatalog.all[1], in: &workout)
  }
  #expect(workout == original)
}
