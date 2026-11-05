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
    try checkContextTarget(at: date)
    try checkStartedGroupAppend(at: date)
    try checkReplacementFocus(at: date)
    try checkPreviousValuesAndBlankDrafts(at: date)
    print(
      "Portable workout exercise presentation: localized/strict input, pounds precision, draft retention, repeated exercise identity, paging/reordering/removal, completion, pause/history guards and summaries passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkPreviousValuesAndBlankDrafts(at date: Date) throws {
    let exercise = Exercise(name: "Previous values", muscle: .back)
    let otherExercise = Exercise(name: "Bodyweight", muscle: .arms)
    let recordedDate = date.addingTimeInterval(-3600)
    var history = Workout(
      name: "Earlier", startedAt: recordedDate,
      exercises: [
        WorkoutExercise(
          exercise: exercise,
          sets: [
            WorkoutSet(repetitions: 10, weightKG: 30, completedAt: recordedDate),
            WorkoutSet(repetitions: 6, weightKG: 40, completedAt: recordedDate),
          ]),
        WorkoutExercise(
          exercise: otherExercise,
          sets: [WorkoutSet(repetitions: 15, weightKG: 0, completedAt: recordedDate)]),
      ])
    try WorkoutEngine.finish(&history, at: recordedDate.addingTimeInterval(60))
    let first = WorkoutExercise(
      exercise: exercise, sets: [WorkoutSet(repetitions: 0), WorkoutSet(repetitions: 0)])
    let second = WorkoutExercise(exercise: otherExercise, sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Now", startedAt: date, exercises: [first, second])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let snapshot = workout
    model.updateHistory([history], for: workout)
    try expect(
      model.previousValues?.stages[first.sets[0].id]?.weightKG == 30
        && model.previousValues?.stages[first.sets[1].id]?.repetitions == 6,
      "History values map to current target IDs")
    try expect(
      model.drafts.values.allSatisfy { $0.weight.isEmpty && $0.repetitions.isEmpty }
        && workout == snapshot,
      "Displaying history leaves all pending numeric fields blank and never changes the workout")
    try rejects { _ = try model.completion(in: workout) }
    model.editRepetitions("8", setID: first.sets[0].id)
    try rejects { _ = try model.completion(in: workout) }
    model.editWeight("0", setID: first.sets[0].id)
    let explicitBodyweight = try model.completion(in: workout)
    try expect(
      explicitBodyweight.set.weightKG == 0 && explicitBodyweight.set.repetitions == 8
        && workout == snapshot,
      "Explicit zero added load and positive repetitions prepare a valid completion")
    model.move(1, in: workout)
    try expect(
      model.previousValues?.stages[second.sets[0].id]?.repetitions == 15
        && model.previousValues?.stages[first.sets[0].id] == nil,
      "Paging replaces suggestions with the selected exercise's own history")
    model.move(-1, in: workout)
    workout.exercises[0].sets.swapAt(0, 1)
    model.refresh(workout)
    try expect(
      model.previousValues?.stages[first.sets[1].id]?.weightKG == 30
        && model.previousValues?.stages[first.sets[0].id]?.weightKG == 40
        && model.drafts[first.sets[0].id]?.weight == "0",
      "Refreshing reordered targets remaps historical positions while retaining typed drafts")
    model.updateHistory([], for: workout)
    try expect(
      model.previousValues == nil && model.drafts[first.sets[0].id]?.repetitions == "8",
      "Deleting history removes previous values without losing entered data")
    model.updateHistory([history], for: workout)
    let replacementID = try WorkoutEngine.replaceExercise(
      id: first.id, with: Exercise(name: "No history", muscle: .legs), in: &workout)
    model.showExercise(replacementID, in: workout)
    try expect(
      model.previousValues == nil && model.drafts[first.sets[0].id] == nil
        && model.drafts[workout.exercises[0].sets[0].id]?.weight == ""
        && model.drafts[workout.exercises[0].sets[0].id]?.repetitions == "",
      "Replacement clears unrelated history and starts new empty fields")
    print(
      "Portable previous workout values: display without prefill, explicit zero load, paging, refresh, history deletion and replacement passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkReplacementFocus(at date: Date) throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "Old", muscle: .back), sets: [WorkoutSet(weightKG: 40)])
    var workout = Workout(name: "Focus", startedAt: date, exercises: [first])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let id = try WorkoutEngine.replaceExercise(
      id: first.id, with: Exercise(name: "New", muscle: .legs), in: &workout)
    model.showExercise(id, in: workout)
    try expect(
      model.exerciseID == id && model.exercise(in: workout)?.exercise.name == "New",
      "Replacement focuses the actual new exercise")
    try expect(
      model.drafts[first.sets[0].id] == nil
        && model.selectedSetID == workout.exercises[0].sets[0].id,
      "Fresh replacement cannot reuse old numeric drafts or targets")
    var foreign = workout
    foreign.id = UUID()
    model.showExercise(UUID(), in: foreign)
    try expect(model.exerciseID == id, "A foreign or missing row cannot steal selection")
  }

  @MainActor private static func checkStartedGroupAppend(at date: Date) throws {
    let set = WorkoutSet(repetitions: 10, weightKG: 50, dropStages: [DropSetStage(weightKG: 40)])
    let row = WorkoutExercise(exercise: Exercise(name: "Append", muscle: .back), sets: [set])
    var workout = Workout(name: "Append", startedAt: date, exercises: [row])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50, at: date)
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let stage = try requireStage(set)
    editor.editWeight("35", setID: stage.id)
    let configured = try editor.configuredDropSet(in: workout, adding: true, setID: set.id)
    try expect(
      configured.dropStages?.last?.weightKG == 28 && configured.completedAt == date,
      "Appending a started group uses pending drafts and preserves the performed base")
    try rejects { _ = try editor.configuredDropSet(in: workout, adding: false, setID: set.id) }
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: set.id, repetitions: configured.repetitions,
      weightKG: configured.weightKG, stages: configured.dropStages ?? [])
    try expect(
      workout.exercises[0].sets[0].dropStages?.count == 2 && workout.volume == 500
        && workout.restEndsAt == nil, "A new pending drop does not perform work or start rest")
  }
  private static func requireStage(_ set: WorkoutSet) throws -> DropSetStage {
    guard let stage = set.dropStages?.first else { throw Failure(message: "Missing drop") }
    return stage
  }

  @MainActor private static func checkContextTarget(at date: Date) throws {
    let first = WorkoutSet(weightKG: 40)
    let second = WorkoutSet(weightKG: 80, note: "Target note")
    let row = WorkoutExercise(
      exercise: Exercise(name: "Context target", muscle: .back), sets: [first, second])
    var workout = Workout(name: "Context", startedAt: date, exercises: [row])
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    editor.editWeight("60", setID: second.id)
    let configured = try editor.configuredDropSet(in: workout, adding: true, setID: second.id)
    try expect(
      configured.id == second.id && configured.weightKG == 60
        && configured.dropStages?.first?.weightKG == 48,
      "Context action uses the pressed set and its own draft")
    try expect(
      configured.note == second.note && editor.selectedSetID == first.id
        && workout.exercises[0].sets == [first, second],
      "Preparing another set preserves note, selection and persisted values")
    let stale = UUID()
    try rejects { _ = try editor.configuredDropSet(in: workout, adding: true, setID: stale) }
    workout.exercises[0].sets[1].completedAt = date
    try rejects { _ = try editor.configuredDropSet(in: workout, adding: true, setID: second.id) }
    workout.status = .paused
    try rejects { _ = try editor.configuredDropSet(in: workout, adding: true, setID: first.id) }
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
