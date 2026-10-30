import FitnessTrackerCore
import Foundation

private struct Failure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw Failure(message: message) }
}
private func rejects(_ action: () throws -> Void) throws {
  do { try action() } catch is TrainingError { return }
  throw Failure(message: "Invalid input or mutation accepted")
}

@main private struct PortableWorkoutExerciseChecks {
  @MainActor static func main() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let first = WorkoutExercise(
      exercise: Exercise(name: "A", muscle: .back),
      sets: [
        WorkoutSet(repetitions: 15, weightKG: 40, loadMultiplier: 2),
        WorkoutSet(repetitions: 12, weightKG: 45),
      ])
    let second = WorkoutExercise(
      exercise: first.exercise, sets: [WorkoutSet(repetitions: 8, weightKG: 50)])
    var workout = Workout(name: "Test", startedAt: date, exercises: [first, second])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    try expect(model.selectedSetID == first.sets[0].id, "Select first pending set")
    model.editWeight("42,5", setID: first.sets[0].id)
    model.editRepetitions("11", setID: first.sets[0].id)
    model.move(-1, in: workout)
    try expect(model.exerciseID == first.id, "Previous cannot leave the first exercise")
    model.move(1, in: workout)
    try expect(
      model.exerciseID == second.id, "Page by workout row identity, even for repeated exercises")
    model.move(1, in: workout)
    try expect(model.exerciseID == second.id, "Next cannot leave the last exercise")
    model.move(-1, in: workout)
    try expect(model.drafts[first.sets[0].id]?.weight == "42,5", "Paging preserves typed drafts")
    let request = try model.completion(in: workout)
    try expect(
      request.exerciseID == first.id && request.set.weightKG == 42.5
        && request.set.repetitions == 11 && request.set.loadMultiplier == 2,
      "Localized input preserves load metadata")
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: request.exerciseID, setID: request.set.id,
      repetitions: request.set.repetitions, weightKG: request.set.weightKG,
      at: date.addingTimeInterval(1))
    model.refresh(workout)
    try expect(
      model.selectedSetID == first.sets[1].id && model.drafts[first.sets[0].id] == nil,
      "Saved completion advances selection and clears its draft")
    try expect(workout.volume == 935, "Completion uses the Core multiplier semantics")
    model.select(first.sets[0].id, in: workout)
    try expect(
      model.selectedSetID == first.sets[1].id,
      "Completed sets cannot be selected for another completion")
    try WorkoutEngine.pause(&workout, at: date.addingTimeInterval(2))
    try rejects { _ = try model.completion(in: workout) }
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(3))
    try rejects { _ = try model.completion(in: workout) }
    var other = workout
    other.id = UUID()
    other.status = .active
    try rejects { _ = try model.completion(in: other) }
    try expect(model.exercise(in: other) == nil, "A different workout cannot reuse this editor")

    var draft = WorkoutSetDraft(
      set: first.sets[0], unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    for input in ["", "-1", "1e2", "NaN", "12kg", "1,2,3", "1501", " 3 0 "] {
      draft.weight = input
      try rejects { _ = try draft.validatedSet(from: first.sets[0], unit: .kilograms) }
    }
    draft.weight = "0"
    draft.repetitions = "8"
    try expect(
      try draft.validatedSet(from: first.sets[0], unit: .kilograms).weightKG == 0,
      "Zero added load remains valid")
    for input in ["", "0", "-1", "1001", "1.5", "1e2", "8 reps"] {
      draft.repetitions = input
      try rejects { _ = try draft.validatedSet(from: first.sets[0], unit: .kilograms) }
    }
    let precise = WorkoutSet(weightKG: 23.456789)
    var pounds = WorkoutSetDraft(set: precise, unit: .pounds, locale: Locale(identifier: "en_US"))
    try expect(
      try pounds.validatedSet(from: precise, unit: .pounds).weightKG == precise.weightKG,
      "Unchanged pounds text preserves original precision")
    pounds.weight = "100.5"
    try expect(
      abs(
        try pounds.validatedSet(from: precise, unit: .pounds).weightKG
          - WeightUnit.pounds.kilograms(from: 100.5)) < 0.000001,
      "Edited pounds convert to stored kilograms")

    var reordered = Workout(name: "Rows", startedAt: date, exercises: [first, second])
    let pages = WorkoutExercisePresentation(
      workout: reordered, exerciseID: second.id, unit: .kilograms,
      locale: Locale(identifier: "en_US"))
    reordered.exercises.swapAt(0, 1)
    pages.refresh(reordered)
    try expect(
      pages.index(in: reordered) == 0 && pages.exerciseID == second.id,
      "Reordering retains selection by row UUID")
    reordered.exercises.removeFirst()
    pages.refresh(reordered)
    try expect(
      pages.exerciseID == first.id, "Removing the selected row selects the surviving exercise")
    reordered.exercises.removeAll()
    pages.refresh(reordered)
    try expect(
      pages.exercise(in: reordered) == nil && pages.selectedSetID == nil,
      "Deleting all exercises has an empty state")

    let summary = WorkoutExerciseSummary.text(
      workout.exercises[0], completedOnly: true, unit: .kilograms,
      locale: Locale(identifier: "ru_RU"), numberLocale: Locale(identifier: "ru_RU"))
    try expect(
      summary.contains("42,5") && summary.contains("11") && !summary.contains("45"),
      "History summary includes completed sets only")
    print(
      "Portable workout exercise presentation: localized/strict input, pounds precision, draft retention, repeated exercise identity, paging/reordering/removal, completion, pause/history guards and summaries passed (no Apple SDK)."
    )
  }
}
