import Foundation
import Testing

@testable import FitLifeCore

@Test func completionProgressKeepsEmptyWorkoutAndExerciseUnready() {
  let exercise = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [])
  let values = [
    WorkoutCompletionProgress(),
    WorkoutCompletionProgress(workout: Workout(name: "Пусто")),
    WorkoutCompletionProgress(exercise: exercise),
    WorkoutCompletionProgress(workout: Workout(name: "Пусто", exercises: [exercise])),
  ]
  for value in values {
    #expect(value.completed == 0 && value.total == 0 && value.fraction == 0)
    #expect(!value.isComplete)
  }
}

@Test func completionProgressCountsWarmupsAndEveryDropStageAcrossRepeatedRows() {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let warmup = WorkoutSet(repetitions: 12, weightKG: 20, isWarmup: true, completedAt: date)
  let drop = WorkoutSet(
    repetitions: 8, weightKG: 50, completedAt: date,
    dropStages: [
      DropSetStage(weightKG: 40, completedAt: date), DropSetStage(weightKG: 30),
    ])
  let first = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [warmup, drop])
  let second = WorkoutExercise(
    exercise: first.exercise, sets: [WorkoutSet(repetitions: 0), WorkoutSet(repetitions: 0)])
  let workout = Workout(name: "Прогресс", startedAt: date, exercises: [first, second])
  let row = WorkoutCompletionProgress(exercise: first)
  #expect(row.completed == 3 && row.total == 4 && row.fraction == 0.75)
  #expect(!row.isComplete)
  let overall = WorkoutCompletionProgress(workout: workout)
  #expect(overall.completed == 3 && overall.total == 6 && overall.fraction == 0.5)
  #expect(!overall.isComplete)
}

@Test func completionProgressWaitsForFinalDropAndNeverFinishesWorkout() throws {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let stage = DropSetStage(repetitions: 8, weightKG: 20)
  let set = WorkoutSet(repetitions: 10, weightKG: 40, dropStages: [stage])
  let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [set])
  var workout = Workout(name: "Дропсет", startedAt: date, exercises: [row])
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 40, at: date)
  let partial = WorkoutCompletionProgress(workout: workout)
  #expect(partial.completed == 1 && partial.total == 2 && partial.fraction == 0.5)
  #expect(!partial.isComplete)
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: stage.id,
    repetitions: 8, weightKG: 20, at: date.addingTimeInterval(1))
  let snapshot = workout
  let ready = WorkoutCompletionProgress(workout: workout)
  #expect(ready.isComplete && ready.fraction == 1 && ready.completed == 2 && ready.total == 2)
  #expect(workout == snapshot && workout.status == .active && workout.endedAt == nil)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(2))
  #expect(WorkoutCompletionProgress(workout: workout) == ready)
  #expect(workout.status == .completed && workout.endedAt != nil)
}

@Test func completionProgressTracksAddingAndRemovingPendingTargetsWithoutInventingWork() throws {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let set = WorkoutSet(repetitions: 15, weightKG: 0)
  let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [set])
  var workout = Workout(name: "Свой вес", startedAt: date, exercises: [row])
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 15, weightKG: 0, at: date)
  #expect(WorkoutCompletionProgress(workout: workout).isComplete)
  #expect(workout.volume == 0)
  try WorkoutEngine.addSet(exerciseID: row.id, to: &workout)
  let expanded = WorkoutCompletionProgress(workout: workout)
  #expect(expanded.completed == 1 && expanded.total == 2 && expanded.fraction == 0.5)
  #expect(!expanded.isComplete)
  let added = try #require(workout.exercises[0].sets.last)
  try WorkoutEngine.removeSet(exerciseID: row.id, setID: added.id, from: &workout)
  #expect(WorkoutCompletionProgress(workout: workout).isComplete)
  try WorkoutEngine.removeExercise(id: row.id, from: &workout)
  #expect(!WorkoutCompletionProgress(workout: workout).isComplete)
}
