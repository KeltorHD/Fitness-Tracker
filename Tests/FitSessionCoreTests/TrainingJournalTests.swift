import Foundation
import Testing

@testable import FitSessionCore

private var journalCalendar: Calendar {
  var value = Calendar(identifier: .iso8601)
  value.timeZone = TimeZone(identifier: "Europe/Berlin")!
  return value
}
private func journalDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
  journalCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}
private func logged(_ date: Date, weight: Double = 40) throws -> Workout {
  var workout = Workout(
    name: "Жим лёжа", startedAt: date,
    exercises: [WorkoutExercise(exercise: ExerciseCatalog.all[1])])
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id,
    setID: workout.exercises[0].sets[0].id, repetitions: 8, weightKG: weight, at: date)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  return workout
}
@Test func journalGroupsWeeksAcrossYearBoundaryAndIgnoresFuture() throws {
  let a = try logged(journalDate(2025, 12, 31))
  let b = try logged(journalDate(2026, 1, 2), weight: 45)
  let future = try logged(journalDate(2026, 2, 2))
  let groups = TrainingJournal.weeks(
    in: [future, b, a], now: journalDate(2026, 1, 3), calendar: journalCalendar)
  #expect(groups.count == 1)
  #expect(groups[0].workouts.map(\.id) == [b.id, a.id])
  #expect(groups[0].personalRecords == 2)
}
@Test func journalMonthHandlesLeapYearAndWeekAlignment() {
  let days = TrainingJournal.monthDays(
    containing: journalDate(2024, 2, 12), workouts: [], calendar: journalCalendar)
  #expect(days.filter(\.isInMonth).count == 29)
  #expect(days.count % 7 == 0)
  #expect(journalCalendar.component(.weekday, from: days[0].date) == journalCalendar.firstWeekday)
}
@Test func calendarDeduplicatesTrainingDaysAndExcludesCancelled() throws {
  let date = journalDate(2026, 10, 20)
  let a = try logged(date)
  let b = try logged(date.addingTimeInterval(3600))
  var cancelled = Workout(name: "Отменена", startedAt: journalDate(2026, 10, 21))
  try WorkoutEngine.cancel(&cancelled, at: cancelled.startedAt)
  let days = TrainingJournal.monthDays(
    containing: date, workouts: [a, b, cancelled], now: journalDate(2026, 10, 29),
    calendar: journalCalendar)
  #expect(days.filter(\.hasWorkout).count == 1)
}
@Test func weekStripUsesCalendarDaysAcrossDaylightSaving() {
  let days = TrainingJournal.weekDays(
    containing: journalDate(2026, 3, 29), calendar: journalCalendar)
  #expect(days.count == 7)
  #expect(Set(days.map { journalCalendar.component(.day, from: $0) }).count == 7)
  #expect(journalCalendar.component(.weekday, from: days[0]) == journalCalendar.firstWeekday)
}
@Test func recordCountsRequireHigherWeightAndIgnoreWarmups() throws {
  let first = try logged(journalDate(2026, 10, 1))
  var equal = try logged(journalDate(2026, 10, 2))
  equal.exercises[0].sets.append(
    WorkoutSet(weightKG: 200, isWarmup: true, completedAt: equal.startedAt))
  let higher = try logged(journalDate(2026, 10, 3), weight: 45)
  let counts = TrainingJournal.recordCounts(in: [higher, equal, first])
  #expect(counts[first.id] == 1)
  #expect(counts[equal.id] == 0)
  #expect(counts[higher.id] == 1)
}
@Test func repeatWorkoutCopiesPerformedTargetsWithFreshIdentityAndNoHistory() throws {
  var source = try logged(journalDate(2026, 10, 20))
  source.exercises[0].sets.append(WorkoutSet(repetitions: 10, weightKG: 50))
  source.notes = "Историческая заметка"
  let result = try WorkoutEngine.repeatWorkout(source, at: journalDate(2026, 10, 29))
  #expect(result.id != source.id)
  #expect(result.exercises[0].id != source.exercises[0].id)
  #expect(result.exercises[0].exercise.id == source.exercises[0].exercise.id)
  #expect(result.exercises[0].sets[0].id != source.exercises[0].sets[0].id)
  #expect(result.totalSets == 1)
  #expect(result.completedSets == 0)
  #expect(result.exercises[0].sets[0].weightKG == 40)
  #expect(result.notes.isEmpty && result.pauses.isEmpty && result.status == .active)
  try Validation.workout(result)
}
@Test func repeatRejectsAnUnfinishedSession() {
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.repeatWorkout(Workout(name: "A"))
  }
}
