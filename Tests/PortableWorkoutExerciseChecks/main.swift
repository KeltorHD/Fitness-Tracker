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
    try checkPreviousDraftRefreshAndPrecision(at: date)
    try checkPreviousDropDrafts(at: date)
    try checkAutomaticExerciseAdvance(at: date)
    try checkAdvanceGuards(at: date)
    try checkAdvanceWrapsToEarlierPendingExercise(at: date)
    try checkReopenedInputs(at: date)
    try checkInheritedInputs(at: date)
    print(
      "Portable workout exercise presentation: localized/strict input, pounds precision, draft retention, repeated exercise identity, paging/reordering/removal, completion, pause/history guards and summaries passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkInheritedInputs(at date: Date) throws {
    let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Add draft", startedAt: date, exercises: [row])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    model.editWeight("42,", setID: row.sets[0].id)
    try WorkoutEngine.addSet(exerciseID: row.id, to: &workout)
    let added = workout.exercises[0].sets[1].id
    model.inheritInput(from: row.sets[0].id, for: added, in: workout)
    try expect(
      model.drafts[added]?.weight == "42," && model.drafts[added]?.repetitions == "",
      "Adding preserves displayed partial input without inventing repetitions")
    model.editWeight("42,5", setID: added)
    model.editRepetitions("11", setID: added)
    try WorkoutEngine.addSet(exerciseID: row.id, to: &workout)
    let last = workout.exercises[0].sets[2].id
    model.inheritInput(from: added, for: last, in: workout)
    model.select(last, in: workout)
    let request = try model.completion(in: workout)
    try expect(
      request.set.weightKG == 42.5 && request.set.repetitions == 11,
      "The added target uses the last displayed values, including unsaved drafts")
    try expect(
      workout.completedSets == 0 && workout.volume == 0,
      "Copying input never completes a set")
    let precise = WorkoutSet(repetitions: 12, weightKG: 45.123456)
    let preciseRow = WorkoutExercise(exercise: row.exercise, sets: [precise])
    var poundsWorkout = Workout(name: "Pounds", exercises: [preciseRow])
    let poundsModel = WorkoutExercisePresentation(
      workout: poundsWorkout, exerciseID: preciseRow.id, unit: .pounds,
      locale: Locale(identifier: "en_US"))
    try WorkoutEngine.addSet(exerciseID: preciseRow.id, to: &poundsWorkout)
    let copied = poundsWorkout.exercises[0].sets[1].id
    poundsModel.inheritInput(from: precise.id, for: copied, in: poundsWorkout)
    poundsModel.select(copied, in: poundsWorkout)
    try expect(
      try poundsModel.completion(in: poundsWorkout).set.weightKG == precise.weightKG,
      "Copied unedited pounds preserve exact stored kilograms behind rounded display")
  }

  @MainActor private static func checkReopenedInputs(at date: Date) throws {
    let row = WorkoutExercise(
      exercise: Exercise(name: "Drafts", muscle: .chest),
      sets: [WorkoutSet(repetitions: 0), WorkoutSet(repetitions: 0), WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Shared drafts", startedAt: date, exercises: [row])
    let shared = WorkoutExerciseDraftStore(workoutID: workout.id, unit: .kilograms)
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"),
      draftStore: shared)
    model.editWeight("42,5", setID: row.sets[0].id)
    model.editRepetitions("11", setID: row.sets[0].id)
    model.editWeight("", setID: row.sets[1].id)
    model.editRepetitions("8", setID: row.sets[1].id)
    model.editRepetitions("12", setID: row.sets[2].id)
    try WorkoutEngine.updatePendingValues(model.pendingValues(in: workout), in: &workout)
    let reopened = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"),
      draftStore: shared)
    try expect(
      reopened.drafts[row.sets[0].id]?.weight == "42,5"
        && reopened.drafts[row.sets[0].id]?.repetitions == "11"
        && reopened.drafts[row.sets[1].id]?.weight == ""
        && reopened.drafts[row.sets[2].id]?.weight == ""
        && reopened.drafts[row.sets[2].id]?.repetitions == "12"
        && workout.exercises[0].sets[2].repetitions == 0,
      "Recreating the screen preserves entered text and explicit clears")
    try expect(reopened.pendingValues(in: workout).isEmpty, "Unchanged input does not write again")
    let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
    let relaunched = WorkoutExercisePresentation(
      workout: restored, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    try expect(
      relaunched.drafts[row.sets[0].id]?.weight == "42.5"
        && relaunched.drafts[row.sets[0].id]?.repetitions == "11"
        && restored.completedSets == 0 && restored.restEndsAt == nil,
      "Saved valid input survives restoring a session without completing a set")
    var unrelated = workout
    unrelated.id = UUID()
    let isolated = WorkoutExercisePresentation(
      workout: unrelated, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "en_US"),
      draftStore: shared)
    try expect(
      isolated.drafts[row.sets[0].id]?.weight == "42.5",
      "A different session never reuses another workout's raw drafts")
    let original = workout
    model.editWeight("invalid", setID: row.sets[0].id)
    try expect(
      model.pendingValues(in: workout).isEmpty, "Invalid text does not corrupt numeric data")
    let invalidReopened = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"),
      draftStore: shared)
    try expect(
      invalidReopened.drafts[row.sets[0].id]?.weight == "invalid" && workout == original,
      "Invalid input remains editable after reopening")
  }

  @MainActor private static func checkAutomaticExerciseAdvance(at date: Date) throws {
    let first = WorkoutExercise(
      exercise: Exercise(name: "First", muscle: .back),
      sets: [WorkoutSet(weightKG: 40), WorkoutSet(weightKG: 20, isWarmup: true)])
    let alreadyComplete = WorkoutExercise(
      exercise: first.exercise, sets: [WorkoutSet(weightKG: 30, completedAt: date)])
    let next = WorkoutExercise(
      exercise: Exercise(name: "Next", muscle: .legs), sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(
      name: "Advance", startedAt: date, exercises: [first, alreadyComplete, next])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    model.editWeight("17.5", setID: next.sets[0].id)
    model.editRepetitions("11", setID: next.sets[0].id)
    let initial = try model.completion(in: workout)
    try expect(
      model.advance(afterSaving: initial, in: workout) == .stay
        && model.exerciseID == first.id && model.selectedSetID == first.sets[0].id,
      "Preparing a completion or failing to save cannot move the exercise page")
    try persist(initial, in: &workout, at: date.addingTimeInterval(1))
    // SwiftUI may already refresh its snapshot before the save handler advances the page.
    model.refresh(workout)
    try expect(
      model.advance(afterSaving: initial, in: workout) == .stay
        && model.exerciseID == first.id && model.selectedSetID == first.sets[1].id,
      "Completing a set stays in the exercise until its warmup and all other sets are performed")
    let final = try model.completion(in: workout)
    try persist(final, in: &workout, at: date.addingTimeInterval(2))
    try expect(
      model.advance(afterSaving: final, in: workout) == .moved && model.exerciseID == next.id,
      "Saving the last set skips fully completed exercise rows and selects the next pending row")
    try expect(
      model.selectedSetID == next.sets[0].id && model.selectedStageID == nil
        && model.drafts[next.sets[0].id]?.weight == "17.5"
        && model.drafts[next.sets[0].id]?.repetitions == "11",
      "Automatic paging keeps unsaved drafts and focuses the next actual target")
    try expect(
      model.advance(afterSaving: final, in: workout) == .stay && model.exerciseID == next.id,
      "Delivering the same save again cannot advance a second exercise")
    let last = try model.completion(in: workout)
    try persist(last, in: &workout, at: date.addingTimeInterval(3))
    try expect(
      model.advance(afterSaving: last, in: workout) == .finished
        && model.selectedSetID == nil && workout.status == .active && workout.endedAt == nil,
      "All stages performed return to the overview while workout finishing remains explicit")
    try expect(
      model.advance(afterSaving: last, in: workout) == .stay,
      "A consumed final request cannot signal another automatic return")
  }

  @MainActor private static func checkAdvanceGuards(at date: Date) throws {
    let first = WorkoutExercise(exercise: Exercise(name: "First", muscle: .back))
    let second = WorkoutExercise(exercise: Exercise(name: "Second", muscle: .arms))
    let initial = Workout(name: "Guards", startedAt: date, exercises: [first, second])
    let model = WorkoutExercisePresentation(
      workout: initial, exerciseID: first.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    let stale = try model.completion(in: initial)
    let request = try model.completion(in: initial)
    var saved = initial
    try persist(request, in: &saved, at: date.addingTimeInterval(1))
    try expect(
      model.advance(afterSaving: stale, in: saved) == .stay,
      "Only the latest prepared completion can drive automatic paging")
    var foreign = saved
    foreign.id = UUID()
    var wrongRow = saved
    wrongRow.exercises[0].id = UUID()
    var wrongSet = saved
    wrongSet.exercises[0].sets[0].id = UUID()
    var changedValues = saved
    changedValues.exercises[0].sets[0].repetitions += 1
    var paused = saved
    try WorkoutEngine.pause(&paused, at: date.addingTimeInterval(2))
    var finished = saved
    try WorkoutEngine.finish(&finished, at: date.addingTimeInterval(2))
    for invalid in [foreign, wrongRow, wrongSet, changedValues, paused, finished] {
      try expect(
        model.advance(afterSaving: request, in: invalid) == .stay
          && model.exerciseID == first.id && model.selectedSetID == first.sets[0].id
          && model.drafts[first.sets[0].id] != nil,
        "Foreign, missing, changed, paused and finished snapshots cannot consume selection or drafts"
      )
    }
    model.move(1, in: saved)
    try expect(
      model.advance(afterSaving: request, in: saved) == .stay && model.exerciseID == second.id,
      "A late save cannot replace a manually chosen page")
    model.move(-1, in: saved)
    try expect(
      model.advance(afterSaving: request, in: saved) == .stay && model.exerciseID == first.id,
      "Returning to the page does not revive a stale completion")
  }

  @MainActor private static func checkAdvanceWrapsToEarlierPendingExercise(at date: Date) throws {
    let first = WorkoutExercise(exercise: Exercise(name: "Earlier", muscle: .arms))
    let last = WorkoutExercise(exercise: Exercise(name: "Last", muscle: .legs))
    var workout = Workout(name: "Wrap", startedAt: date, exercises: [first, last])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: last.id, unit: .kilograms, locale: Locale(identifier: "en_US"))
    model.editWeight("10", setID: first.sets[0].id)
    model.editRepetitions("13", setID: first.sets[0].id)
    let request = try model.completion(in: workout)
    try persist(request, in: &workout, at: date.addingTimeInterval(1))
    try expect(
      model.advance(afterSaving: request, in: workout) == .moved && model.exerciseID == first.id
        && model.drafts[first.sets[0].id]?.repetitions == "13",
      "The last exercise wraps to earlier pending work while preserving its drafts")
    let final = try model.completion(in: workout)
    try persist(final, in: &workout, at: date.addingTimeInterval(2))
    try expect(
      model.advance(afterSaving: final, in: workout) == .finished
        && WorkoutCompletionProgress(workout: workout).isComplete
        && workout.status == .active && workout.endedAt == nil,
      "Completing the wrapped target leaves a ready ongoing workout for explicit finishing")
  }

  private static func persist(
    _ request: WorkoutSetCompletion, in workout: inout Workout, at date: Date
  ) throws {
    if let stageID = request.stageID {
      guard let stage = request.set.dropStages?.first(where: { $0.id == stageID }) else {
        throw Failure(message: "Missing requested drop stage")
      }
      try WorkoutEngine.completeDropStage(
        in: &workout, exerciseID: request.exerciseID, setID: request.set.id, stageID: stageID,
        repetitions: stage.repetitions, weightKG: stage.weightKG,
        dropStages: request.set.dropStages, at: date)
    } else {
      try WorkoutEngine.completeSet(
        in: &workout, exerciseID: request.exerciseID, setID: request.set.id,
        repetitions: request.set.repetitions, weightKG: request.set.weightKG, at: date)
    }
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
      model.drafts[first.sets[0].id]?.weight == "30"
        && model.drafts[first.sets[0].id]?.repetitions == "10"
        && model.drafts[first.sets[1].id]?.weight == "40"
        && workout == snapshot,
      "Previous values appear in input drafts while the saved workout remains unchanged")
    let unchanged = try model.completion(in: workout)
    try expect(
      unchanged.set.weightKG == 30 && unchanged.set.repetitions == 10 && workout == snapshot,
      "Completing unchanged input uses the displayed historical values")
    model.editRepetitions("8", setID: first.sets[0].id)
    try expect(
      try model.completion(in: workout).set.weightKG == 30,
      "Editing repetitions independently keeps the previous weight available")
    model.editWeight("0", setID: first.sets[0].id)
    let explicitBodyweight = try model.completion(in: workout)
    try expect(
      explicitBodyweight.set.weightKG == 0 && explicitBodyweight.set.repetitions == 8
        && workout == snapshot,
      "Explicit zero added load and positive repetitions prepare a valid completion")
    model.move(1, in: workout)
    try expect(
      model.previousValues?.stages[second.sets[0].id]?.repetitions == 15
        && model.previousValues?.stages[first.sets[0].id] == nil
        && model.drafts[second.sets[0].id]?.weight == "0"
        && model.drafts[second.sets[0].id]?.repetitions == "15",
      "Paging replaces suggestions with the selected exercise's own history")
    model.move(-1, in: workout)
    workout.exercises[0].sets.swapAt(0, 1)
    model.refresh(workout)
    try expect(
      model.previousValues?.stages[first.sets[1].id]?.weightKG == 30
        && model.previousValues?.stages[first.sets[0].id]?.weightKG == 40
        && model.drafts[first.sets[0].id]?.weight == "0"
        && model.drafts[first.sets[1].id]?.weight == "30",
      "Refreshing reordered targets remaps historical positions while retaining typed drafts")
    model.updateHistory([], for: workout)
    try expect(
      model.previousValues == nil && model.drafts[first.sets[0].id]?.repetitions == "8"
        && model.drafts[first.sets[1].id]?.weight == "",
      "Deleting history removes untouched fallbacks without losing entered data")
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
      "Portable previous workout values: editable draft fallback, unchanged completion, explicit zero load, paging, refresh, history deletion and replacement passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkPreviousDraftRefreshAndPrecision(at date: Date) throws {
    let exercise = Exercise(name: "History draft", muscle: .back)
    let earlier = date.addingTimeInterval(-3600)
    var history = Workout(
      name: "Earlier", startedAt: earlier,
      exercises: [
        WorkoutExercise(
          exercise: exercise,
          sets: [
            WorkoutSet(repetitions: 12, weightKG: 20, isWarmup: true, completedAt: earlier),
            WorkoutSet(repetitions: 8, weightKG: 50.123456, completedAt: earlier),
          ]),
        WorkoutExercise(
          exercise: exercise, sets: [WorkoutSet(repetitions: 15, weightKG: 0, completedAt: earlier)]
        ),
      ])
    try WorkoutEngine.finish(&history, at: earlier.addingTimeInterval(60))
    let first = WorkoutExercise(
      exercise: exercise,
      sets: [WorkoutSet(repetitions: 0, isWarmup: true), WorkoutSet(repetitions: 0)])
    let repeated = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Now", startedAt: date, exercises: [first, repeated])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: first.id, unit: .pounds, locale: Locale(identifier: "en_US"),
      history: [history])
    let warmup = try model.completion(in: workout)
    try expect(
      warmup.set.isWarmup && warmup.set.weightKG == 20 && warmup.set.repetitions == 12,
      "Warmup fallback uses its own ordinal and preserves exact kilograms behind pounds display")
    model.select(first.sets[1].id, in: workout)
    try expect(
      try model.completion(in: workout).set.weightKG == 50.123456,
      "Unchanged historical pounds retain the original precise stored kilograms")
    model.editRepetitions("9", setID: first.sets[1].id)
    history.exercises[0].sets[1].weightKG = 55.777777
    history.exercises[0].sets[1].repetitions = 6
    model.updateHistory([history], for: workout)
    let refreshed = try model.completion(in: workout)
    try expect(
      refreshed.set.weightKG == 55.777777 && refreshed.set.repetitions == 9,
      "History refresh updates only the untouched field, preserving independent repetition edits")
    model.editWeight("0", setID: first.sets[1].id)
    history.exercises[0].sets[1].weightKG = 60
    model.updateHistory([history], for: workout)
    try expect(
      try model.completion(in: workout).set.weightKG == 0,
      "Explicit zero added load overrides a positive historical weight after refresh")
    model.editWeight("", setID: first.sets[1].id)
    model.updateHistory([history], for: workout)
    try rejects { _ = try model.completion(in: workout) }
    try expect(
      model.drafts[first.sets[1].id]?.weight == "",
      "An intentionally cleared field cannot silently regain its historical fallback")
    model.editWeight("1", setID: first.sets[1].id)
    model.move(1, in: workout)
    let second = try model.completion(in: workout)
    try expect(
      second.set.weightKG == 0 && second.set.repetitions == 15,
      "Repeated exercise rows use their own occurrence, including zero-load history")
    model.move(-1, in: workout)
    try expect(
      model.drafts[first.sets[1].id]?.weight == "1"
        && model.drafts[first.sets[1].id]?.repetitions == "9",
      "Paging does not replace entered current values with another history occurrence")
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: first.id, setID: warmup.set.id, repetitions: warmup.set.repetitions,
      weightKG: warmup.set.weightKG, at: date.addingTimeInterval(1))
    model.refresh(workout)
    history.exercises[0].sets[0].weightKG = 30
    model.updateHistory([history], for: workout)
    try expect(
      model.drafts[warmup.set.id] == nil && workout.exercises[0].sets[0].weightKG == 20,
      "Completed fields remain frozen even when their history source changes")
    let existing = WorkoutExercise(
      exercise: exercise, sets: [WorkoutSet(repetitions: 6, weightKG: 0)])
    let existingWorkout = Workout(name: "Already entered", startedAt: date, exercises: [existing])
    let existingModel = WorkoutExercisePresentation(
      workout: existingWorkout, exerciseID: existing.id, unit: .kilograms,
      locale: Locale(identifier: "en_US"), history: [history])
    let existingCompletion = try existingModel.completion(in: existingWorkout)
    try expect(
      existingCompletion.set.weightKG == 0 && existingCompletion.set.repetitions == 6,
      "An existing current zero-load target is recorded data and is never replaced by positive history"
    )
  }

  @MainActor private static func checkPreviousDropDrafts(at date: Date) throws {
    let exercise = Exercise(name: "Drop history", muscle: .back)
    let earlier = date.addingTimeInterval(-3600)
    let recorded = WorkoutSet(
      repetitions: 10, weightKG: 50, completedAt: earlier,
      dropStages: [
        DropSetStage(repetitions: 8, weightKG: 40, completedAt: earlier.addingTimeInterval(1))
      ])
    var history = Workout(
      name: "Earlier", startedAt: earlier,
      exercises: [WorkoutExercise(exercise: exercise, sets: [recorded])])
    try WorkoutEngine.finish(&history, at: earlier.addingTimeInterval(60))
    let row = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
    var workout = Workout(name: "Drop fallback", startedAt: date, exercises: [row])
    let model = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "en_US"),
      history: [history])
    let configured = try model.configuredDropSet(in: workout, adding: true)
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: configured.id, repetitions: configured.repetitions,
      weightKG: configured.weightKG, stages: configured.dropStages ?? [])
    model.refresh(workout)
    let stage = try requireStage(configured)
    try expect(
      model.previousValues?.stages[stage.id]?.repetitions == 8
        && model.drafts[stage.id]?.repetitions == "10",
      "Historical drops map to their own stage while explicit current drop configuration wins")
    model.editRepetitions("7", setID: stage.id)
    let base = try model.completion(in: workout)
    try expect(
      base.set.weightKG == 50 && base.set.dropStages?.first?.repetitions == 7,
      "Base completion combines unchanged historical base values and entered current drop values")
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: base.set.id, repetitions: base.set.repetitions,
      weightKG: base.set.weightKG, stages: base.set.dropStages ?? [])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: base.set.id, repetitions: base.set.repetitions,
      weightKG: base.set.weightKG, at: date.addingTimeInterval(1))
    model.refresh(workout)
    history.exercises[0].sets[0].dropStages?[0].repetitions = 12
    model.updateHistory([history], for: workout)
    let child = try model.completion(in: workout)
    try expect(
      child.stageID == stage.id && child.set.completedAt != nil
        && child.set.dropStages?.first?.repetitions == 7 && model.drafts[base.set.id] == nil,
      "Completed drop base is frozen and edited pending stage survives a history refresh")
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
    try expect(
      model.advance(afterSaving: base, in: workout) == .stay, "Base stage cannot page away")
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
    try expect(
      model.advance(afterSaving: first, in: workout) == .stay,
      "An intermediate drop cannot advance the exercise")
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
    try expect(
      model.advance(afterSaving: last, in: workout) == .finished && workout.status == .active,
      "The final drop returns to the overview and leaves the workout unfinished")
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
