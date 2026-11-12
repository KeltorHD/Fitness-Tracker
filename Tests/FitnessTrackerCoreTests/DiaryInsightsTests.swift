import Foundation
import Testing

@testable import FitnessTrackerCore

private func diaryCalendar() -> Calendar {
  var calendar = Calendar(identifier: .iso8601)
  calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
  return calendar
}

private func diaryDate(_ day: Int, month: Int = 3) throws -> Date {
  try #require(
    diaryCalendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
}

private func diaryWorkout(at date: Date) throws -> Workout {
  var workout = Workout(
    name: "Fixture", startedAt: date,
    exercises: [WorkoutExercise(exercise: ExerciseCatalog.all[0])])
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 10, weightKG: 20, at: date)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(600))
  return workout
}

@Test func diaryWeekUsesCalendarBoundariesAcrossDSTAndExcludesUnfinishedAndFuture() throws {
  let day = try diaryDate(29)
  let finished = try diaryWorkout(at: day)
  let previous = try diaryWorkout(at: diaryDate(22))
  let next = try diaryWorkout(at: diaryDate(30))
  let future = try diaryWorkout(at: day.addingTimeInterval(3600))
  var active = Workout(name: "Active", startedAt: day)
  var paused = active
  paused.status = .paused
  active.status = .cancelled
  let summary = DiaryTrainingSummary(
    workouts: [finished, previous, next, future, active, paused], day: day,
    now: day.addingTimeInterval(600), calendar: diaryCalendar())
  #expect(summary.workouts == 1)
  #expect(summary.workingSets == 1)
  #expect(summary.volumeKG == 200)
  #expect(summary.duration == 600)
  #expect(summary.end.timeIntervalSince(summary.start) == 167 * 3600)
  #expect(summary.trainedDays == [diaryCalendar().startOfDay(for: day)])
  #expect(summary.progress(goal: 3) == 1.0 / 3)
}

@Test func diarySummaryKeepsActualTotalsAboveGoalAndDoesNotInventImportDuration() throws {
  let date = try diaryDate(29)
  var imported = try diaryWorkout(at: date)
  imported.durationIsKnown = false
  imported.exercises[0].sets.append(
    WorkoutSet(repetitions: 10, weightKG: 100, isWarmup: true, completedAt: date))
  imported.exercises[0].sets.append(WorkoutSet(repetitions: 10, weightKG: 100))
  let other = try diaryWorkout(at: date)
  let onlyImported = DiaryTrainingSummary(
    workouts: [imported], day: date, now: date.addingTimeInterval(1000), calendar: diaryCalendar())
  #expect(onlyImported.duration == nil)
  #expect(onlyImported.workingSets == 1)
  #expect(onlyImported.volumeKG == 200)
  let summary = DiaryTrainingSummary(
    workouts: [imported, other], day: date, now: date.addingTimeInterval(1000),
    calendar: diaryCalendar())
  #expect(summary.workouts == 2)
  #expect(summary.progress(goal: 1) == 1)
  #expect(summary.progress(goal: 0) == 0)
  #expect(summary.trainedDays.count == 1)
  #expect(summary.duration == 600)
}

@Test func emptyDiarySummaryHasNoFabricatedTimeOrActivity() throws {
  let day = try diaryDate(29)
  let summary = DiaryTrainingSummary(workouts: [], day: day, now: day, calendar: diaryCalendar())
  #expect(summary.workouts == 0)
  #expect(summary.workingSets == 0)
  #expect(summary.volumeKG == 0)
  #expect(summary.duration == nil)
  #expect(summary.progress(goal: 3) == 0)
}

@Test func diaryRingSelectionHandlesTinySlicesEmptyValuesAndExactBoundaries() {
  let values = [0.0, 20, 0.01, 80, 0]
  #expect(DiaryRingSelection.index(at: 0, weights: values) == 1)
  #expect(DiaryRingSelection.index(at: 20, weights: values) == 2)
  #expect(DiaryRingSelection.index(at: 20.005, weights: values) == 2)
  #expect(DiaryRingSelection.index(at: values.reduce(0, +), weights: values) == 3)
  #expect(DiaryRingSelection.index(at: -1, weights: values) == nil)
  #expect(DiaryRingSelection.index(at: .nan, weights: values) == nil)
  #expect(DiaryRingSelection.index(at: 0, weights: [0, 0]) == nil)
  #expect(DiaryRingSelection.index(at: 1, weights: [.infinity]) == nil)
  #expect(DiaryRingSelection.index(at: 1, weights: [-1, 2]) == nil)
}

@Test func diaryComparisonUsesThePreviousCalendarWeekAndPreservesRatiosAboveOne() throws {
  let date = try diaryDate(29)
  let previous = try diaryWorkout(at: diaryDate(22))
  var current = try diaryWorkout(at: date)
  current.exercises[0].sets.append(WorkoutSet(repetitions: 10, weightKG: 40, completedAt: date))
  let summary = DiaryTrainingSummary(
    workouts: [current, previous], day: date, now: date.addingTimeInterval(600),
    calendar: diaryCalendar())
  #expect(summary.previousWorkingSets == 1)
  #expect(summary.previousVolumeKG == 200)
  #expect(summary.setComparison == 2)
  #expect(summary.volumeComparison == 3)
  let missing = DiaryTrainingSummary(
    workouts: [current], day: date, now: date.addingTimeInterval(600), calendar: diaryCalendar())
  #expect(missing.previousWorkingSets == nil)
  #expect(missing.previousVolumeKG == nil)
  #expect(missing.setComparison == nil)
  #expect(missing.volumeComparison == nil)
  var bodyweight = previous
  bodyweight.exercises[0].sets[0].weightKG = 0
  let zeroBaseline = DiaryTrainingSummary(
    workouts: [current, bodyweight], day: date, now: date.addingTimeInterval(600),
    calendar: diaryCalendar())
  #expect(zeroBaseline.previousVolumeKG == 0)
  #expect(zeroBaseline.volumeComparison == nil)
  #expect(zeroBaseline.setComparison == 2)
}
