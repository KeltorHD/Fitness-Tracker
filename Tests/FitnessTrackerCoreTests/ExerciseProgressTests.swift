import Foundation
import Testing

@testable import FitnessTrackerCore

private func progressDate(_ month: Int, _ day: Int) throws -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  return try #require(
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
}

private func progressWorkout(_ date: Date, sets: [WorkoutSet], exercise: Exercise? = nil) throws
  -> Workout
{
  var workout = Workout(
    name: "Progress fixture", startedAt: date,
    exercises: [WorkoutExercise(exercise: exercise ?? ExerciseCatalog.all[0], sets: sets)])
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  try Validation.workout(workout)
  return workout
}

@Test func exerciseProgressAggregatesAllFiveMetricsAcrossRepeatedRows() throws {
  let date = try progressDate(10, 1)
  var workout = try progressWorkout(
    date,
    sets: [
      WorkoutSet(repetitions: 8, weightKG: 40, completedAt: date),
      WorkoutSet(repetitions: 2, weightKG: 200, isWarmup: true, completedAt: date),
      WorkoutSet(repetitions: 10, weightKG: 150),
    ])
  workout.exercises.append(
    WorkoutExercise(
      exercise: ExerciseCatalog.all[0],
      sets: [WorkoutSet(repetitions: 5, weightKG: 50, completedAt: date)]))
  let report = ExerciseProgressReport(workouts: [workout], now: date.addingTimeInterval(120))
  let history = try #require(report.exercises.first)
  let point = try #require(history.points.first)
  #expect(history.points.count == 1)
  #expect(point.id == workout.id)
  #expect(point.maximumWeightKG == 50)
  #expect(point.volume == 570)
  #expect(point.repetitions == 13)
  #expect(point.setCount == 2)
  let actualOneRepMaxKG: Double = try #require(point.estimatedOneRepMaxKG)
  let expectedOneRepMaxKG: Double = 50.0 * (1.0 + 5.0 / 30.0)
  let oneRepMaxDifference: Double = abs(actualOneRepMaxKG - expectedOneRepMaxKG)
  #expect(oneRepMaxDifference < 0.0001)
}

@Test func exerciseProgressKeepsBodyweightAndOmitsUnsupportedOneRepMaxEstimates() throws {
  let date = try progressDate(10, 1)
  let bodyweight = try progressWorkout(
    date, sets: [WorkoutSet(repetitions: 15, weightKG: 0, completedAt: date)])
  let highReps = try progressWorkout(
    date.addingTimeInterval(3600),
    sets: [WorkoutSet(repetitions: 20, weightKG: 40, completedAt: date.addingTimeInterval(3600))])
  let report = try ExerciseProgressReport(
    workouts: [highReps, bodyweight], now: progressDate(10, 2))
  let points = try #require(report.exercises.first?.points)
  #expect(points.map(\.repetitions) == [15, 20])
  #expect(points.map(\.volume) == [0, 800])
  #expect(points.map(\.maximumWeightKG) == [0, 40])
  #expect(points.allSatisfy { $0.estimatedOneRepMaxKG == nil })
}

@Test func exerciseProgressExcludesUnfinishedCancelledFutureAndWarmupOnlyRows() throws {
  let date = try progressDate(10, 1)
  let valid = try progressWorkout(
    date, sets: [WorkoutSet(repetitions: 1, weightKG: 60, completedAt: date)])
  var active = valid
  active.id = UUID()
  active.status = .active
  var paused = active
  paused.id = UUID()
  paused.status = .paused
  var cancelled = valid
  cancelled.id = UUID()
  cancelled.status = .cancelled
  let futureDate = try progressDate(10, 3)
  let future = try progressWorkout(
    futureDate, sets: [WorkoutSet(weightKG: 900, completedAt: futureDate)])
  let warmup = try progressWorkout(
    date, sets: [WorkoutSet(weightKG: 100, isWarmup: true, completedAt: date)],
    exercise: ExerciseCatalog.all[1])
  let report = try ExerciseProgressReport(
    workouts: [active, future, paused, cancelled, warmup, valid], now: progressDate(10, 2))
  #expect(report.exercises.count == 1)
  #expect(report.exercises.first?.points.map(\.id) == [valid.id])
  #expect(report.exercises.first?.points.first?.estimatedOneRepMaxKG == 60)
}

@Test func exerciseProgressUsesExerciseIdentityAndLatestStoredName() throws {
  let date = try progressDate(10, 1)
  let original = ExerciseCatalog.all[0]
  var renamed = original
  renamed.name = "Renamed squat"
  let first = try progressWorkout(
    date, sets: [WorkoutSet(weightKG: 40, completedAt: date)], exercise: original)
  let later = date.addingTimeInterval(3600)
  let second = try progressWorkout(
    later, sets: [WorkoutSet(weightKG: 50, completedAt: later)], exercise: renamed)
  let other = Exercise(name: renamed.name, muscle: renamed.muscle)
  let third = try progressWorkout(
    later, sets: [WorkoutSet(weightKG: 10, completedAt: later)], exercise: other)
  let histories = ExerciseProgressReport(
    workouts: [third, second, first], now: date.addingTimeInterval(7200)
  ).exercises
  #expect(histories.count == 2)
  let same = try #require(histories.first { $0.id == original.id })
  #expect(same.exercise.name == renamed.name)
  #expect(same.points.map(\.id) == [first.id, second.id])
  #expect(histories.first { $0.id == other.id }?.points.count == 1)
}

@Test func exerciseProgressSortingIsStableForSessionsWithTheSameTimestamp() throws {
  let date = try progressDate(10, 1)
  var first = try progressWorkout(date, sets: [WorkoutSet(weightKG: 40, completedAt: date)])
  var second = first
  first.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
  second.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
  let a = ExerciseProgressReport(workouts: [second, first], now: date)
  let b = ExerciseProgressReport(workouts: [first, second], now: date)
  #expect(a == b)
  #expect(a.exercises.first?.points.map(\.id) == [first.id, second.id])
}

@Test func exerciseProgressPeriodsUseCalendarWeeksAndIncludeBoundaryAcrossDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let now = try progressDate(3, 30)
  let start = try #require(
    ExerciseProgressPeriod.fourWeeks.startDate(relativeTo: now, calendar: calendar))
  #expect(start == (try progressDate(3, 2)))
  #expect(now.timeIntervalSince(start) == 28 * 86400 - 3600)
  let dates = [start.addingTimeInterval(-1), start, now]
  let workouts = try dates.map { date in
    try progressWorkout(date, sets: [WorkoutSet(weightKG: 40, completedAt: date)])
  }
  let history = try #require(ExerciseProgressReport(workouts: workouts, now: now).exercises.first)
  #expect(
    history.points(in: .fourWeeks, relativeTo: now, calendar: calendar).map(\.id)
      == Array(workouts.dropFirst()).map(\.id))
  #expect(history.points(in: .allTime, relativeTo: now, calendar: calendar).count == 3)
  #expect(ExerciseProgressPeriod.allTime.startDate(relativeTo: now, calendar: calendar) == nil)
  #expect(
    ExerciseProgressPeriod.twelveWeeks.startDate(relativeTo: now, calendar: calendar)
      == calendar.date(byAdding: .weekOfYear, value: -12, to: now))
  #expect(
    ExerciseProgressPeriod.twentySixWeeks.startDate(relativeTo: now, calendar: calendar)
      == calendar.date(byAdding: .weekOfYear, value: -26, to: now))
}

@Test func exerciseProgressHandlesEmptyAndOutOfRangeHistoryWithoutFakePoints() throws {
  #expect(ExerciseProgressReport(workouts: []).exercises.isEmpty)
  let date = try progressDate(1, 1)
  let workout = try progressWorkout(date, sets: [WorkoutSet(weightKG: 40, completedAt: date)])
  let now = try progressDate(10, 1)
  let history = try #require(ExerciseProgressReport(workouts: [workout], now: now).exercises.first)
  #expect(history.points(in: .fourWeeks, relativeTo: now).isEmpty)
  #expect(history.points(in: .allTime, relativeTo: now).count == 1)
}
