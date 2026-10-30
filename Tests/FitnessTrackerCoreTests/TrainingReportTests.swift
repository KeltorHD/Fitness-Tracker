import Foundation
import Testing

@testable import FitnessTrackerCore

private func reportCalendar() throws -> Calendar {
  var calendar = Calendar(identifier: .iso8601)
  calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
  return calendar
}
private func reportDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
  try #require(
    reportCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
}
private func reportWorkout(_ date: Date, weight: Double = 40) throws -> Workout {
  var workout = Workout(
    name: "Тренировка", startedAt: date,
    exercises: [
      WorkoutExercise(
        exercise: ExerciseCatalog.all[1],
        sets: [
          WorkoutSet(repetitions: 8, weightKG: weight, completedAt: date),
          WorkoutSet(weightKG: 200, isWarmup: true, completedAt: date),
          WorkoutSet(weightKG: 150),
        ])
    ])
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  try Validation.workout(workout)
  return workout
}

@Test func dayFilterComparesRecordsAgainstEarlierWorkouts() throws {
  let first = try reportWorkout(reportDate(2026, 10, 1), weight: 100)
  let next = try reportWorkout(reportDate(2026, 10, 2), weight: 80)
  let weeks = try TrainingJournal.weeks(
    in: [first, next], on: next.startedAt, now: reportDate(2026, 10, 29),
    calendar: reportCalendar())
  #expect(weeks.flatMap(\.workouts).map(\.id) == [next.id])
  #expect(weeks.first?.personalRecords == 0)
}

@Test func reportAggregatesRepeatedExerciseRowsAndUsesOnlyPerformedWorkingSets() throws {
  let date = try reportDate(2026, 10, 20)
  var workout = try reportWorkout(date)
  workout.exercises.append(
    WorkoutExercise(
      exercise: ExerciseCatalog.all[1],
      sets: [
        WorkoutSet(repetitions: 5, weightKG: 50, completedAt: date)
      ]))
  let report = try TrainingReport(
    workouts: [workout], month: date, now: reportDate(2026, 10, 29), calendar: reportCalendar())
  let points = try #require(report.exerciseVolumes[ExerciseCatalog.all[1].id])
  #expect(points.count == 1)
  #expect(points[0].volume == 570)
  #expect(report.records.first?.weightKG == 50)
  #expect(report.weeks.count == 26)
  #expect(report.weeks.reduce(0) { $0 + $1.volume } == 570)
}

@Test func reportFiltersFutureAndUnfinishedSessionsAndSelectsCalendarYear() throws {
  let old = try reportWorkout(reportDate(2025, 12, 31))
  let current = try reportWorkout(reportDate(2026, 10, 20))
  let future = try reportWorkout(reportDate(2027, 1, 1), weight: 900)
  let active = Workout(name: "Не закончена", startedAt: current.startedAt)
  let report = try TrainingReport(
    workouts: [future, active, current, old], month: old.startedAt,
    now: reportDate(2026, 10, 29), calendar: reportCalendar())
  #expect(report.years == [2026, 2025])
  #expect(report.records.first?.weightKG == 40)
  #expect(report.exerciseVolumes[ExerciseCatalog.all[1].id]?.map(\.id) == [old.id])
  #expect(report.month.workoutCount == 1)
}

@Test func monthCountsSessionsAndDistinctTrainingDaysAcrossDaylightSaving() throws {
  let first = try reportWorkout(reportDate(2026, 3, 29))
  let sameDay = try reportWorkout(first.startedAt.addingTimeInterval(3600))
  let outside = try reportWorkout(reportDate(2026, 4, 1))
  let summary = try TrainingMonthSummary(
    workouts: [first, sameDay, outside], month: first.startedAt,
    now: reportDate(2026, 4, 2), calendar: reportCalendar())
  #expect(summary.workoutCount == 2)
  #expect(summary.trainingDayFraction == 1.0 / 31)
  #expect(summary.days.filter(\.isInMonth).count == 31)
}

@Test func templateProjectionUsesCompletedTargetsAndFreshRowIdentities() throws {
  var workout = try reportWorkout(reportDate(2026, 10, 20))
  workout.exercises.append(WorkoutExercise(exercise: ExerciseCatalog.all[0]))
  let first = try WorkoutEngine.makeTemplate(from: workout)
  let second = try WorkoutEngine.makeTemplate(from: workout)
  #expect(first.id != second.id)
  #expect(first.exercises.count == 1)
  #expect(first.exercises[0].id != workout.exercises[0].id)
  #expect(first.exercises[0].id != second.exercises[0].id)
  #expect(first.exercises[0].exercise.id == workout.exercises[0].exercise.id)
  #expect(first.exercises[0].setCount == 2)
  #expect(first.exercises[0].repetitions == 8)
  #expect(first.exercises[0].weightKG == 40)
  #expect(first.restSeconds == workout.restSeconds)
  try Validation.template(first)
}

@Test func templateProjectionRejectsUnfinishedAndCorruptHistory() throws {
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.makeTemplate(from: Workout(name: "Активная"))
  }
  var workout = try reportWorkout(reportDate(2026, 10, 20))
  workout.exercises[0].sets[0].weightKG = .nan
  #expect(throws: TrainingError.invalidWeight) { try WorkoutEngine.makeTemplate(from: workout) }
}

@Test func warmupClassificationIsValidatedBeforeChangingAnActiveSet() throws {
  let date = try reportDate(2026, 10, 20)
  var workout = try ExerciseCatalog.starterTemplates[0].start(at: date)
  let exerciseID = workout.exercises[0].id
  let setID = workout.exercises[0].sets[0].id
  try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: exerciseID, setID: setID)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: exerciseID, setID: setID, repetitions: 8, weightKG: 40, at: date)
  #expect(workout.volume == 0)
  let completed = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.setWarmup(false, in: &workout, exerciseID: exerciseID, setID: setID)
  }
  #expect(workout == completed)
}

@Test func warmupChangesRejectPausedSessionsAndMissingSets() throws {
  var workout = try ExerciseCatalog.starterTemplates[0].start(at: reportDate(2026, 10, 20))
  let exerciseID = workout.exercises[0].id
  let setID = workout.exercises[0].sets[0].id
  #expect(throws: TrainingError.missingSet) {
    try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: exerciseID, setID: UUID())
  }
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: UUID(), setID: setID)
  }
  try WorkoutEngine.pause(&workout, at: workout.startedAt)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: exerciseID, setID: setID)
  }
  #expect(!workout.exercises[0].sets[0].isWarmup)
}
