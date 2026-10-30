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
    try checkDrops(at: date)
    print(
      "Portable workout exercise presentation: localized/strict input, pounds precision, draft retention, repeated exercise identity, paging/reordering/removal, completion, pause/history guards and summaries passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkDrops(at date: Date) throws {
    let row = WorkoutExercise(
      exercise: Exercise(name: "Drop", muscle: .back),
      sets: [WorkoutSet(repetitions: 10, weightKG: 50)])
    var workout = Workout(name: "Drop", startedAt: date, exercises: [row])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    for _ in 0..<2 {
      let config = try model.configuredDropSet(in: workout, adding: true)
      try WorkoutEngine.configureDropSet(
        in: &workout, exerciseID: row.id, setID: config.id, repetitions: config.repetitions,
        weightKG: config.weightKG, stages: config.dropStages ?? [])
      model.refresh(workout)
    }
    let stages = workout.exercises[0].sets[0].dropStages ?? []
    try expect(
      stages.count == 2 && stages[0].weightKG == 40 && stages[1].weightKG == 32,
      "Adding drops creates editable decreasing targets, never performed values")
    model.editWeight("60", setID: row.sets[0].id)
    model.editWeight("45", setID: stages[0].id)
    model.editWeight("30", setID: stages[1].id)
    let base = try model.completion(in: workout)
    try expect(
      base.stageID == nil && base.set.weightKG == 60 && base.set.dropStages?[0].weightKG == 45,
      "Base completion validates all edited targets together")
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: base.set.id, repetitions: base.set.repetitions,
      weightKG: base.set.weightKG, stages: base.set.dropStages ?? [])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: base.set.id, repetitions: base.set.repetitions,
      weightKG: base.set.weightKG, at: date.addingTimeInterval(1))
    model.refresh(workout)
    try expect(
      model.selectedSetID == base.set.id && model.selectedStageID == stages[0].id
        && workout.restEndsAt == nil,
      "Selection stays in the same group and advances to its first drop")
    model.select(stages[1].id, in: workout)
    try rejects { _ = try model.completion(in: workout) }
    model.select(stages[0].id, in: workout)
    model.editWeight("25,5", setID: stages[0].id)
    try rejects { _ = try model.completion(in: workout) }
    model.editWeight("20", setID: stages[1].id)
    let first = try model.completion(in: workout)
    let value = first.set.dropStages?[0]
    guard let value else { throw Failure(message: "Missing drop request") }
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: first.set.id, stageID: value.id,
      repetitions: value.repetitions, weightKG: value.weightKG, dropStages: first.set.dropStages,
      at: date.addingTimeInterval(2))
    model.refresh(workout)
    try expect(
      model.selectedStageID == stages[1].id && model.drafts[stages[0].id] == nil
        && workout.restEndsAt == nil,
      "Completed drop fields freeze; future draft remains ready without rest")
    let last = try model.completion(in: workout)
    guard let final = last.set.dropStages?.last else {
      throw Failure(message: "Missing final drop")
    }
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: last.set.id, stageID: final.id,
      repetitions: final.repetitions, weightKG: final.weightKG, dropStages: last.set.dropStages,
      at: date.addingTimeInterval(3))
    model.refresh(workout)
    try expect(
      model.selectedSetID == nil && workout.fullyCompletedSets == 1 && workout.totalSets == 1
        && workout.restEndsAt != nil, "One complete group starts exactly one rest interval")
    let summary = WorkoutExerciseSummary.text(
      workout.exercises[0], completedOnly: true, unit: .kilograms,
      locale: Locale(identifier: "ru_RU"), numberLocale: Locale(identifier: "ru_RU"))
    try expect(
      summary.contains("Дропсет") && summary.contains("25,5") && summary.contains("→"),
      "History renders the actual linked stages")

    var editable = Workout(name: "Editable", startedAt: date, exercises: [row])
    let edit = WorkoutExercisePresentation(
      workout: editable, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let config = try edit.configuredDropSet(in: editable, adding: true)
    try WorkoutEngine.configureDropSet(
      in: &editable, exerciseID: row.id, setID: config.id, repetitions: config.repetitions,
      weightKG: config.weightKG, stages: config.dropStages ?? [])
    edit.refresh(editable)
    edit.editWeight("10", setID: config.id)
    try rejects { _ = try edit.completion(in: editable) }
    let plain = try edit.configuredDropSet(in: editable, adding: false)
    try expect(
      !plain.isDropSet && plain.weightKG == 10,
      "Removing a drop group can recover from inconsistent pending stage targets")
    try WorkoutEngine.configureDropSet(
      in: &editable, exerciseID: row.id, setID: plain.id, repetitions: plain.repetitions,
      weightKG: plain.weightKG, stages: [])
    try WorkoutEngine.setWarmup(true, in: &editable, exerciseID: row.id, setID: plain.id)
    edit.refresh(editable)
    try rejects { _ = try edit.configuredDropSet(in: editable, adding: true) }
    let warmup = WorkoutExerciseSummary.text(
      editable.exercises[0], completedOnly: false, unit: .kilograms,
      locale: Locale(identifier: "ru_RU"), numberLocale: Locale(identifier: "ru_RU"))
    try expect(warmup.contains("Разминка"), "Warmup remains explicitly identified")
    print(
      "Portable drop-set presentation: configuration, mixed target editing, ordered selection, strict decrease, draft freezing, one-group count/rest, history and warmup separation passed (no Apple SDK)."
    )
  }
}
