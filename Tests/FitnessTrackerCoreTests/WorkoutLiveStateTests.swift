import Foundation
import Testing

@testable import FitnessTrackerCore

private let start = Date(timeIntervalSince1970: 1_700_000_000)
private func liveWorkout() throws -> Workout {
  try ExerciseCatalog.starterTemplates[0].start(at: start)
}

@Test func liveStateFindsNextSetAndRestDeadline() throws {
  var workout = try liveWorkout()
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id,
    setID: workout.exercises[0].sets[0].id, repetitions: 8, weightKG: 20, at: start)
  let state = WorkoutLiveState(workout: workout, at: start.addingTimeInterval(30))
  #expect(state.completedSets == 1)
  #expect(state.totalSets == 9)
  #expect(state.nextSetNumber == 2)
  #expect(state.nextExerciseName == workout.exercises[0].exercise.name)
  #expect(state.restStartsAt == start)
  #expect(state.restEndsAt == start.addingTimeInterval(90))
  #expect(state.progress == 1.0 / 9)
}

@Test func systemTimerAnchorSurvivesSuspensionAndExcludesPauses() throws {
  var workout = try liveWorkout()
  try WorkoutEngine.pause(&workout, at: start.addingTimeInterval(60))
  let paused = WorkoutLiveState(workout: workout, at: start.addingTimeInterval(600))
  #expect(paused.timerPausedAt == start.addingTimeInterval(60))
  #expect(paused.paused)
  try WorkoutEngine.resume(&workout, at: start.addingTimeInterval(120))
  let active = WorkoutLiveState(workout: workout)
  #expect(active.timerPausedAt == nil)
  #expect(
    start.addingTimeInterval(7200).timeIntervalSince(active.timerStart)
      == workout.duration(at: start.addingTimeInterval(7200)))
  #expect(active.timerStart == start.addingTimeInterval(60))
}

@Test func expiredRestIsOmittedOnNextSnapshot() throws {
  var workout = try liveWorkout()
  workout.restEndsAt = start.addingTimeInterval(90)
  #expect(WorkoutLiveState(workout: workout, at: start.addingTimeInterval(90)).restEndsAt == nil)
}

@Test func liveActionsAreIdempotentAndPersistValidPauseIntervals() throws {
  var workout = try liveWorkout()
  #expect(
    try WorkoutLiveAction.pause.apply(
      to: &workout, expectedWorkoutID: workout.id, at: start.addingTimeInterval(10)))
  let paused = workout
  #expect(
    try !WorkoutLiveAction.pause.apply(
      to: &workout, expectedWorkoutID: workout.id, at: start.addingTimeInterval(20)))
  #expect(workout == paused)
  #expect(
    try WorkoutLiveAction.resume.apply(
      to: &workout, expectedWorkoutID: workout.id, at: start.addingTimeInterval(30)))
  let resumed = workout
  #expect(
    try !WorkoutLiveAction.resume.apply(
      to: &workout, expectedWorkoutID: workout.id, at: start.addingTimeInterval(40)))
  #expect(workout == resumed)
  #expect(workout.pausedSeconds == 20)
  try Validation.workout(workout)
}

@Test func staleRestButtonCannotClearNewRest() throws {
  var workout = try liveWorkout()
  let oldEnd = start.addingTimeInterval(90)
  let newEnd = start.addingTimeInterval(180)
  workout.restEndsAt = newEnd
  #expect(
    try !WorkoutLiveAction.skipRest(expectedEnd: oldEnd).apply(
      to: &workout, expectedWorkoutID: workout.id))
  #expect(workout.restEndsAt == newEnd)
  #expect(
    try WorkoutLiveAction.skipRest(expectedEnd: newEnd).apply(
      to: &workout, expectedWorkoutID: workout.id))
  #expect(workout.restEndsAt == nil)
}

@Test func staleActivityCannotMutateAnotherOrFinishedWorkout() throws {
  var workout = try liveWorkout()
  let original = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutLiveAction.pause.apply(to: &workout, expectedWorkoutID: UUID(), at: start)
  }
  #expect(workout == original)
  try WorkoutEngine.cancel(&workout, at: start)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutLiveAction.resume.apply(to: &workout, expectedWorkoutID: workout.id, at: start)
  }
}

@Test func liveStateRoundTripIsSmallEnoughForActivityKit() throws {
  var workout = try liveWorkout()
  workout.notes = String(repeating: "private notes", count: 10_000)
  let state = WorkoutLiveState(workout: workout, at: start)
  let data = try JSONEncoder().encode(state)
  #expect(data.count < 4096)
  #expect(try JSONDecoder().decode(WorkoutLiveState.self, from: data) == state)
  #expect(!String(decoding: data, as: UTF8.self).contains("private notes"))
}

@Test func liveStateLanguageRemainsCompatibleWithExistingActivities() throws {
  let workout = try liveWorkout()
  let state = WorkoutLiveState(workout: workout, at: start, languageCode: "en")
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(WorkoutLiveState.self, from: data) == state)
  var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  legacy.removeValue(forKey: "languageCode")
  let restored = try JSONDecoder().decode(
    WorkoutLiveState.self, from: JSONSerialization.data(withJSONObject: legacy))
  #expect(restored.languageCode == nil)
  #expect(restored == WorkoutLiveState(workout: workout, at: start))
}

@Test func emptyAndFullyCompletedSessionsHaveNoNextExercise() throws {
  let empty = WorkoutLiveState(workout: Workout(name: "Empty", startedAt: start), at: start)
  #expect(empty.progress == 0)
  #expect(empty.nextExerciseName == nil)
  var workout = try liveWorkout()
  for e in workout.exercises.indices {
    for s in workout.exercises[e].sets.indices { workout.exercises[e].sets[s].completedAt = start }
  }
  let state = WorkoutLiveState(workout: workout, at: start)
  #expect(state.progress == 1)
  #expect(state.nextSetNumber == nil)
}
