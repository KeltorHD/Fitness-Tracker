import Foundation
import Testing

@testable import FitSessionCore

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
