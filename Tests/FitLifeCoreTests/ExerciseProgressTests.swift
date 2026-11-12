import Foundation
import Testing

@testable import FitLifeCore

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

@Test func exerciseWorkoutHistoryPreservesSnapshotsPositionsAndRepeatedRows() throws {
  let date = try progressDate(10, 1)
  let exercise = ExerciseCatalog.all[0]
  let warmup = WorkoutSet(
    repetitions: 6, weightKG: 20, isWarmup: true, completedAt: date,
    note: "Разминка перед рабочими")
  let pending = WorkoutSet(repetitions: 12, weightKG: 99)
  let working = WorkoutSet(
    repetitions: 8, weightKG: 40, completedAt: date.addingTimeInterval(20),
    loadMultiplier: 2, note: "С паузой")
  let repeated = WorkoutSet(
    repetitions: 5, weightKG: 45, completedAt: date.addingTimeInterval(10))
  let sameName = Exercise(name: exercise.name, muscle: exercise.muscle)
  var workout = Workout(
    name: "Сохранённая тренировка", startedAt: date,
    exercises: [
      WorkoutExercise(exercise: sameName, sets: [warmup]),
      WorkoutExercise(exercise: exercise, sets: [warmup, pending, working]),
      WorkoutExercise(exercise: exercise, sets: [repeated]),
    ])
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  let archived = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: exercise.id, workouts: [archived], now: date)
  let entry = try #require(entries.first)
  #expect(entry.id == workout.id && entry.date == date && entry.name == workout.name)
  #expect(entry.rows.map(\.id) == Array(workout.exercises.dropFirst()).map(\.id))
  #expect(entry.rows.map(\.position) == [2, 3])
  #expect(entry.rows[0].sets.map(\.position) == [1, 3])
  #expect(entry.rows[0].sets.map(\.set) == [warmup, working])
  #expect(entry.rows[1].sets.map(\.set) == [repeated])
  #expect(entry.rows[0].sets[1].set.loadMultiplier == 2)
  #expect(entry.rows[0].sets[1].set.note == "С паузой")
  #expect(workout.exercises[1].sets == [warmup, pending, working])
}

@Test func exerciseWorkoutHistoryRetainsOnlyPerformedDropStagesAndZeroLoad() throws {
  let date = try progressDate(10, 1)
  let completed = DropSetStage(repetitions: 12, weightKG: 30, completedAt: date)
  let pending = DropSetStage(repetitions: 15, weightKG: 20)
  let set = WorkoutSet(
    repetitions: 8, weightKG: 40, completedAt: date, dropStages: [completed, pending],
    note: "Последнее снижение пропущено")
  let bodyweight = WorkoutSet(repetitions: 15, weightKG: 0, completedAt: date)
  let workout = try progressWorkout(date, sets: [set, bodyweight])
  let entry = try #require(
    ExerciseWorkoutHistoryEntry.entries(
      for: ExerciseCatalog.all[0].id, workouts: [workout], now: date
    ).first)
  let recorded = try #require(entry.rows.first?.sets.first?.set)
  #expect(recorded.id == set.id && recorded.isDropSet)
  #expect(recorded.performedStages.map(\.id) == [set.id, completed.id])
  #expect(recorded.performedStages.map(\.repetitions) == [8, 12])
  #expect(recorded.performedStages.map(\.weightKG) == [40, 30])
  #expect(entry.rows.first?.sets.last?.set.weightKG == 0)
  #expect(entry.rows.first?.sets.last?.set.note == nil)
}

@Test func exerciseWorkoutHistoryIncludesWarmupsButExcludesUnfinishedAndOtherExercises() throws {
  let date = try progressDate(10, 1)
  let exercise = ExerciseCatalog.all[0]
  let warmup = try progressWorkout(
    date, sets: [WorkoutSet(weightKG: 20, isWarmup: true, completedAt: date)])
  var active = warmup
  active.id = UUID()
  active.status = .active
  var paused = active
  paused.id = UUID()
  paused.status = .paused
  var cancelled = active
  cancelled.id = UUID()
  cancelled.status = .cancelled
  var future = warmup
  future.id = UUID()
  future.startedAt = date.addingTimeInterval(100)
  let other = try progressWorkout(
    date, sets: [WorkoutSet(weightKG: 50, completedAt: date)], exercise: ExerciseCatalog.all[1])
  var unperformed = warmup
  unperformed.id = UUID()
  unperformed.exercises[0].sets = [WorkoutSet(weightKG: 90)]
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: exercise.id, workouts: [active, other, paused, future, cancelled, unperformed, warmup],
    now: date)
  #expect(entries.map(\.id) == [warmup.id])
  #expect(entries.first?.rows.first?.sets.first?.set.isWarmup == true)
  #expect(ExerciseWorkoutHistoryEntry.entries(for: exercise.id, workouts: []).isEmpty)
}

@Test func exerciseWorkoutHistoryUsesNewestFirstAndKeepsStoredNamesAcrossSessions() throws {
  let date = try progressDate(10, 1)
  let exercise = Exercise(name: "Название в старой тренировке", muscle: .legs)
  let old = try progressWorkout(
    date, sets: [WorkoutSet(weightKG: 40, completedAt: date)], exercise: exercise)
  var renamed = exercise
  renamed.name = "Новое название"
  let later = date.addingTimeInterval(3600)
  var recent = try progressWorkout(
    later, sets: [WorkoutSet(weightKG: 50, completedAt: later)], exercise: renamed)
  recent.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
  var sameTime = recent
  sameTime.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: exercise.id, workouts: [old, recent, sameTime], now: later)
  #expect(entries.map(\.id) == [sameTime.id, recent.id, old.id])
  #expect(entries.last?.rows.first?.name == "Название в старой тренировке")
  #expect(entries.first?.rows.first?.name == "Новое название")
  #expect(
    entries
      == ExerciseWorkoutHistoryEntry.entries(
        for: exercise.id, workouts: [sameTime, recent, old], now: later))
}

@Test func exerciseHistoryFiltersComposeAndKeepOriginalRowsSetsAndStages() throws {
  let date = try progressDate(10, 1)
  let warmup = WorkoutSet(weightKG: 20, isWarmup: true, completedAt: date)
  let working = WorkoutSet(weightKG: 40, completedAt: date)
  let drop = WorkoutSet(
    weightKG: 50, completedAt: date,
    dropStages: [DropSetStage(weightKG: 30, completedAt: date)])
  var workout = try progressWorkout(date, sets: [warmup, working, drop])
  workout.name = "Тяжёлая тренировка — НОГИ"
  var other = workout
  other.id = UUID()
  other.name = "Верх тела"
  var old = workout
  old.id = UUID()
  old.startedAt = try progressDate(1, 1)
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: ExerciseCatalog.all[0].id, workouts: [old, workout, other], now: date)
  var filter = ExerciseWorkoutHistoryFilter()
  filter.query = "  ноги ТЯЖЕЛАЯ\n"
  filter.period = .fourWeeks
  filter.setKind = .working
  let result = filter.apply(to: entries, now: date, calendar: Calendar(identifier: .gregorian))
  #expect(result.map(\.id) == [workout.id])
  #expect(result.first?.rows.first?.id == workout.exercises.first?.id)
  #expect(result.first?.rows.first?.sets.map(\.position) == [2, 3])
  #expect(result.first?.rows.first?.sets.map(\.set) == [working, drop])
  filter.setKind = .dropSet
  #expect(
    filter.apply(to: entries, now: date, calendar: .current).first?.rows.first?.sets.map(\.set)
      == [drop])
  filter.setKind = .warmup
  #expect(
    filter.apply(to: entries, now: date, calendar: .current).first?.rows.first?.sets.map(\.set)
      == [warmup])
  #expect(
    entries.first { $0.id == workout.id }?.rows.first?.sets.map(\.set) == [warmup, working, drop])
  filter.query = "Неизвестное занятие"
  #expect(filter.apply(to: entries, now: date, calendar: .current).isEmpty)
}

@Test func exerciseHistorySortingKeepsSessionsSeparateAndTiesStable() throws {
  let date = try progressDate(10, 1)
  var first = try progressWorkout(date, sets: [WorkoutSet(weightKG: 40, completedAt: date)])
  first.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
  var sameDate = first
  sameDate.id = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
  var later = first
  later.id = UUID()
  later.startedAt = date.addingTimeInterval(60)
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: ExerciseCatalog.all[0].id, workouts: [sameDate, later, first], now: later.startedAt)
  var filter = ExerciseWorkoutHistoryFilter()
  #expect(
    filter.apply(to: Array(entries.reversed()), now: later.startedAt, calendar: .current).map(\.id)
      == [later.id, first.id, sameDate.id])
  filter.sortOrder = .oldest
  #expect(filter.isModified && !filter.isActive)
  #expect(
    filter.apply(to: entries, now: later.startedAt, calendar: .current).map(\.id)
      == [first.id, sameDate.id, later.id])
}

@Test func exerciseHistoryPeriodUsesCalendarBoundaryAcrossDSTAndEmptyRowsAreRemoved() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let now = try progressDate(3, 30)
  let boundary = try #require(
    ExerciseProgressPeriod.fourWeeks.startDate(relativeTo: now, calendar: calendar))
  let workouts = try [boundary.addingTimeInterval(-1), boundary, now].map {
    try progressWorkout($0, sets: [WorkoutSet(weightKG: 20, isWarmup: true, completedAt: $0)])
  }
  let entries = ExerciseWorkoutHistoryEntry.entries(
    for: ExerciseCatalog.all[0].id, workouts: workouts, now: now)
  var filter = ExerciseWorkoutHistoryFilter()
  filter.period = .fourWeeks
  #expect(
    filter.apply(to: entries, now: now, calendar: calendar).map(\.id) == [
      workouts[2].id, workouts[1].id,
    ])
  filter.setKind = .working
  #expect(filter.apply(to: entries, now: now, calendar: calendar).isEmpty)
  filter = ExerciseWorkoutHistoryFilter()
  filter.query = " \n "
  #expect(!filter.isModified)
  #expect(filter.apply(to: entries, now: now, calendar: calendar).count == 3)
}
