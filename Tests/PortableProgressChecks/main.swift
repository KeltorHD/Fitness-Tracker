import FitnessTrackerCore
import Foundation

private struct ProgressCheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw ProgressCheckFailure(message: message) }
}

@main struct PortableProgressChecks {
  @MainActor static func main() throws {
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    func workout(daysAgo: Int, weight: Double, reps: Int = 8, exercise: Exercise) throws -> Workout
    {
      guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
        throw ProgressCheckFailure(message: "Invalid fixture date")
      }
      var value = Workout(
        name: "Progress fixture", startedAt: date,
        exercises: [
          WorkoutExercise(
            exercise: exercise,
            sets: [WorkoutSet(repetitions: reps, weightKG: weight, completedAt: date)])
        ])
      try WorkoutEngine.finish(&value, at: date.addingTimeInterval(60))
      return value
    }
    let exercise = ExerciseCatalog.all[0]
    let old = try workout(daysAgo: 100, weight: 30, exercise: exercise)
    let recent = try workout(daysAgo: 2, weight: 50, exercise: exercise)
    let bodyweight = try workout(daysAgo: 1, weight: 0, reps: 20, exercise: ExerciseCatalog.all[5])
    let model = ExerciseProgressViewModel(now: { now })
    model.refresh(workouts: [recent, bodyweight, old], calendar: calendar)
    model.selectedExerciseID = exercise.id
    try expect(model.points.map(\.id) == [recent.id], "Default period must filter old points")
    try expect(model.series.count == 5, "All five metrics must be prepared")
    model.period = .allTime
    try expect(
      model.points.map(\.id) == [old.id, recent.id], "All-time period must retain all history")
    model.selectedDate = old.startedAt.addingTimeInterval(10)
    try expect(
      model.selectedPoint?.id == old.id, "Chart selection must resolve the nearest workout")
    model.period = .fourWeeks
    try expect(
      model.selectedPoint == nil && model.displayedPoint?.id == recent.id,
      "Period changes must reset selection")
    model.selectedExerciseID = bodyweight.exercises[0].exercise.id
    try expect(model.points.count == 1, "Bodyweight must be selectable without a weighted record")
    try expect(
      model.series[.oneRepMax]?.isEmpty == true, "Missing one-rep max must not become zero")
    try expect(
      model.series[.repetitions]?.first?.value == 20, "Bodyweight repetitions must be charted")
    model.refresh(workouts: [recent, old], calendar: calendar)
    try expect(
      model.selectedExerciseID == exercise.id, "Deletion must fall back to a remaining exercise")
    model.refresh(workouts: [], calendar: calendar)
    try expect(
      model.history == nil && model.points.isEmpty && model.displayedPoint == nil,
      "Empty history must clear old chart data")

    let fixed = ExerciseProgressViewModel(
      exerciseID: exercise.id, workoutID: old.id, period: .allTime, now: { now })
    fixed.refresh(workouts: [recent, bodyweight, old], calendar: calendar)
    try expect(
      fixed.selectedPoint?.id == old.id, "Opening from a workout must highlight that workout")
    fixed.refresh(workouts: [bodyweight], calendar: calendar)
    try expect(
      fixed.history == nil && fixed.points.isEmpty,
      "A fixed exercise must never show another exercise's data")

    var sameTime = recent
    sameTime.id = UUID()
    let exact = ExerciseProgressViewModel(
      exerciseID: exercise.id, workoutID: sameTime.id, period: .allTime, now: { now })
    exact.refresh(workouts: [recent, sameTime], calendar: calendar)
    try expect(
      exact.selectedPoint?.id == sameTime.id,
      "Equal dates must preserve the linked workout identity")
    exact.refresh(workouts: [recent, sameTime], calendar: calendar)
    try expect(
      exact.selectedPoint?.id == sameTime.id, "Refreshing equal dates must preserve selection")

    let results = ProgressViewModel(now: { now })
    results.refresh(workouts: [old, recent], calendar: calendar)
    results.exerciseProgress.period = .allTime
    results.moveMonth(by: -1)
    try expect(
      results.exerciseProgress.points.count == 2,
      "Calendar navigation must not silently change the chart period")
    print(
      "Portable exercise progress: selection, periods, bodyweight, deletion, linked workout identity and refresh passed (no Apple SDK)."
    )
  }
}
