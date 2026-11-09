import FitnessTrackerCore
import Foundation

private struct Failure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw Failure(message: message) }
}

@main private struct PortableNumberPadChecks {
  @MainActor static func main() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let first = WorkoutSet(repetitions: 12, weightKG: 50)
    let completed = WorkoutSet(
      repetitions: 8, weightKG: 80, completedAt: date.addingTimeInterval(1))
    let second = WorkoutSet(repetitions: 10, weightKG: 55)
    let drop = WorkoutSet(
      repetitions: 10, weightKG: 60,
      dropStages: [DropSetStage(weightKG: 40), DropSetStage(weightKG: 30)])
    let last = WorkoutSet(repetitions: 8, weightKG: 70)
    let row = WorkoutExercise(
      exercise: Exercise(name: "Pad", muscle: .back), sets: [first, completed, second, drop, last])
    let other = WorkoutExercise(exercise: row.exercise, sets: [WorkoutSet(weightKG: 90)])
    var workout = Workout(name: "Pad", startedAt: date, exercises: [row, other])
    let original = workout
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let pad = WorkoutNumberPadModel(editor: editor, locale: Locale(identifier: "ru_RU"))
    pad.begin(.repetitions(first.id), in: workout)
    try expect(
      pad.text == "12" && pad.selection.length == 0
        && pad.selection == NSRange(location: 2, length: 0),
      "Opening leaves an insertion caret at the end")
    pad.clear()
    pad.digit(3)
    pad.digit(0)
    try expect(
      pad.text == "30" && pad.selection.length == 0, "C clears before entering a new value")
    pad.delete()
    try expect(pad.text == "3", "Delete removes one entered digit")
    pad.decimal()
    try expect(pad.text == "3", "Repetitions reject decimal separators")
    pad.advance(in: workout)
    try expect(
      pad.field == .weight(completed.id), "Next visits recorded cells using the same editor")
    pad.advance(in: workout)
    try expect(pad.field == .repetitions(completed.id), "Weight advances to repetitions")
    pad.begin(.weight(first.id), in: workout)
    pad.clear()
    pad.digit(4)
    pad.digit(5)
    pad.decimal()
    pad.digit(5)
    pad.decimal()
    try expect(pad.text == "45,5", "Locale separator is inserted once")
    pad.copyDown(in: workout)
    try expect(
      pad.copiedRows == 2 && editor.drafts[second.id]?.weight == "45,5"
        && editor.drafts[last.id]?.weight == "45,5",
      "Copy down updates following ordinary weight targets")
    try expect(
      editor.drafts[drop.id]?.weight == "60" && editor.drafts[other.sets[0].id]?.weight == "90"
        && editor.drafts[completed.id]?.weight == "80",
      "Copy cannot change drop weights, another exercise or completed rows")
    pad.begin(.repetitions(first.id), in: workout)
    pad.clear()
    pad.digit(2)
    pad.digit(0)
    pad.copyDown(in: workout)
    try expect(
      pad.copiedRows == 5 && editor.drafts[second.id]?.repetitions == "20"
        && editor.drafts[last.id]?.repetitions == "20",
      "Repetitions propagate to following pending rows")
    for stage in drop.dropStages ?? [] {
      try expect(
        editor.drafts[stage.id]?.repetitions == "20",
        "Repetitions may update future drop stages without changing their weights")
    }
    try expect(
      workout == original && workout.volume == original.volume,
      "Numeric entry changes drafts, never actual work or persistence")
    pad.begin(.weight(last.id), in: workout)
    try expect(!pad.canCopy(in: workout), "The last target cannot copy beyond its exercise")
    pad.advance(in: workout)
    pad.advance(in: workout)
    try expect(pad.field == nil, "Next closes the panel after the last field")
    pad.begin(.weight(first.id), in: workout)
    let beforeDelete = pad.text
    pad.delete()
    try expect(
      pad.text == String(beforeDelete.dropLast()),
      "Backspace deletes only the character before the initial caret")
    pad.clear()
    pad.advance(in: workout)
    try expect(
      pad.field == .weight(first.id) && pad.error != nil, "Invalid empty input cannot advance")
    pad.digit(0)
    pad.advance(in: workout)
    try expect(
      pad.field == .repetitions(first.id) && pad.error == nil, "Zero added weight is valid")
    pad.clear()
    pad.digit(1)
    pad.digit(0)
    pad.digit(0)
    pad.digit(0)
    pad.digit(1)
    try expect(pad.text == "1000" && pad.error != nil, "Repetitions have a bounded input buffer")
    pad.delete()
    try expect(pad.text == "100" && pad.error == nil, "Editing clears validation feedback")
    pad.begin(.weight(first.id), in: workout)
    pad.clear()
    pad.digit(1)
    pad.digit(5)
    pad.digit(0)
    pad.digit(1)
    let previous = editor.drafts[second.id]?.weight
    pad.copyDown(in: workout)
    try expect(
      pad.error != nil && editor.drafts[second.id]?.weight == previous,
      "Invalid copied values leave all other drafts untouched")
    pad.dismiss()
    try expect(editor.drafts[first.id]?.weight == "1501", "Hiding retains the draft for correction")
    pad.begin(.weight(completed.id), in: workout)
    try expect(pad.field == .weight(completed.id), "Completed fields open the same panel")
    let recordedDate = workout.exercises[0].sets[1].completedAt
    pad.digit(7)
    pad.digit(5)
    try expect(pad.text == "75", "First insertion replaces the recorded weight")
    let edits = editor.pendingValues(in: workout, includingCompleted: true)
    try WorkoutEngine.updateEditableValues(
      [completed.id: edits[completed.id] ?? .init()], in: &workout)
    try expect(
      workout.exercises[0].sets[1].weightKG == 75
        && workout.exercises[0].sets[1].completedAt == recordedDate,
      "Recorded input saves without completing again")
    pad.begin(.weight(first.id), in: workout)
    try WorkoutEngine.pause(&workout, at: date.addingTimeInterval(2))
    editor.refresh(workout)
    pad.reconcile(workout)
    try expect(pad.field == nil, "Pause dismisses the panel")
    pad.begin(.weight(first.id), in: workout)
    try expect(pad.field == nil, "Paused fields cannot be edited")
    try WorkoutEngine.resume(&workout, at: date.addingTimeInterval(3))
    editor.refresh(workout)
    pad.begin(.weight(first.id), in: workout)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: first.id, repetitions: 12, weightKG: 50,
      at: date.addingTimeInterval(4))
    editor.refresh(workout)
    pad.reconcile(workout)
    try expect(
      pad.field == .weight(first.id) && editor.drafts[first.id]?.weight == "50",
      "External completion refreshes recorded values without losing the numeric editor")
    pad.begin(.weight(second.id), in: workout)
    pad.reconcile(nil)
    try expect(pad.field == nil, "Workout removal dismisses the panel")
    var foreign = workout
    foreign.id = UUID()
    pad.begin(.weight(second.id), in: foreign)
    try expect(pad.field == nil, "Another workout cannot reuse the editor")
    try checkLegacyAndPounds(date: date)
    try checkCursor(date: date)
    try checkFirstInsertionReplacement(date: date)
    try checkNativeSelectionCallbacks(date: date)
    print(
      "Portable number pad: first insertion replacement, native caret, range replacement, C/backspace, decimal/bounds, field traversal, copy isolation, draft-only changes, inline recorded edits, pause/removal, legacy zero reps and pounds precision passed (no Apple SDK)."
    )
  }

  @MainActor private static func checkNativeSelectionCallbacks(date: Date) throws {
    let set = WorkoutSet(repetitions: 8, weightKG: 45)
    let row = WorkoutExercise(exercise: Exercise(name: "Native focus", muscle: .back), sets: [set])
    let workout = Workout(name: "Native focus", startedAt: date, exercises: [row])
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let pad = WorkoutNumberPadModel(editor: editor, locale: Locale(identifier: "ru_RU"))
    pad.begin(.weight(set.id), in: workout)
    pad.selectText(NSRange(location: 0, length: 0), userInitiated: false)
    try expect(
      pad.selection == NSRange(location: 2, length: 0),
      "Automatic caret placement preserves the initial model caret")
    pad.digit(3)
    try expect(pad.text == "3", "Automatic UIKit caret placement does not cancel replacement")
    pad.dismiss()
    editor.editWeight("45", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.selectText(NSRange(location: 0, length: 0), userInitiated: false)
    pad.digit(6)
    try expect(pad.text == "6", "Refocus replacement survives a delayed native selection callback")
    pad.dismiss()
    editor.editWeight("45", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.selectText(NSRange(location: 0, length: 0), userInitiated: false)
    pad.delete()
    try expect(pad.text == "4", "Initial backspace uses the preserved caret after native focus")
    pad.dismiss()
    editor.editWeight("45", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.beginSelectionInteraction()
    pad.selectText(NSRange(location: 2, length: 0), userInitiated: false)
    pad.digit(3)
    try expect(pad.text == "453", "An explicit tap at the existing caret permits appending")
    pad.dismiss()
    editor.editWeight("45", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.beginSelectionInteraction()
    pad.selectText(NSRange(location: 0, length: 0), userInitiated: false)
    pad.digit(3)
    try expect(pad.text == "345", "A deliberate caret move permits insertion at the start")
    pad.dismiss()
    pad.selectText(NSRange(location: 0, length: 0), userInitiated: false)
    try expect(pad.field == nil, "A late selection callback cannot reopen the hidden panel")
  }

  @MainActor private static func checkFirstInsertionReplacement(date: Date) throws {
    let set = WorkoutSet(repetitions: 12, weightKG: 123.5)
    let row = WorkoutExercise(exercise: Exercise(name: "Replace", muscle: .back), sets: [set])
    let workout = Workout(name: "Replace", startedAt: date, exercises: [row])
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let pad = WorkoutNumberPadModel(editor: editor, locale: Locale(identifier: "ru_RU"))
    pad.begin(.weight(set.id), in: workout)
    try expect(
      pad.text == "123,5" && pad.selection == NSRange(location: 5, length: 0),
      "Focusing preserves the visible value with an insertion caret")
    pad.dismiss()
    try expect(
      pad.field == nil && editor.drafts[set.id]?.weight == "123,5",
      "Closing without typing preserves the initial value")
    pad.begin(.weight(set.id), in: workout)
    pad.reconcile(workout)
    pad.digit(8)
    pad.digit(0)
    try expect(pad.text == "80", "The first digit replaces the whole value; later digits append")
    pad.dismiss()
    try expect(editor.drafts[set.id]?.weight == "80", "Hiding keeps the entered draft")
    pad.begin(.weight(set.id), in: workout)
    try expect(pad.text == "80", "Refocusing does not change the existing draft")
    pad.digit(4)
    pad.digit(2)
    try expect(pad.text == "42", "Refocusing re-arms replacement for the next insertion")
    pad.begin(.repetitions(set.id), in: workout)
    try expect(pad.text == "12", "Changing fields preserves its displayed value until typing")
    pad.replaceCharacters(in: pad.selection, with: "٩")
    pad.digit(1)
    try expect(pad.text == "91", "A first pasted digit replaces and normalizes repetitions")

    editor.editWeight("123,5", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.decimal()
    pad.digit(5)
    try expect(pad.text == "0,5", "A first decimal replaces an existing decimal value")
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    pad.replaceCharacters(in: pad.selection, with: "42.75")
    pad.digit(0)
    try expect(pad.text == "42,750", "The first paste replaces; subsequent digits edit normally")
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    let beforeInvalidPaste = pad.text
    pad.replaceCharacters(in: pad.selection, with: "invalid")
    try expect(
      pad.text == beforeInvalidPaste && pad.error != nil,
      "Rejected first input preserves the displayed value")
    pad.digit(7)
    try expect(pad.text == "7" && pad.error == nil, "Rejected input does not consume replacement")

    pad.dismiss()
    editor.editWeight("123,5", setID: set.id)
    pad.begin(.weight(set.id), in: workout)
    pad.selectText(NSRange(location: 1, length: 2))
    pad.replaceCharacters(in: pad.selection, with: "88")
    try expect(pad.text == "188,5", "An explicit selected range overrides first-input replacement")
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    pad.delete()
    pad.digit(9)
    try expect(pad.text == "188,9", "Initial backspace edits one character and ends replacement")
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    pad.clear()
    try expect(pad.text.isEmpty, "C explicitly clears the existing value")
    pad.digit(0)
    try expect(pad.text == "0", "Zero is an explicit entered value")
    pad.digit(5)
    try expect(pad.text == "5", "Typing after zero does not retain an unwanted leading zero")
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    pad.digit(0)
    pad.dismiss()
    pad.begin(.weight(set.id), in: workout)
    try expect(pad.text == "0", "Refocusing preserves explicit bodyweight zero")
    pad.digit(6)
    try expect(pad.text == "6", "A first digit replaces a previously entered zero")
    pad.dismiss()
    try expect(
      workout.exercises == [row] && workout.completedSets == 0,
      "Replacement, hiding and refocusing never complete or persist a set")
  }

  @MainActor private static func checkCursor(date: Date) throws {
    let row = WorkoutExercise(
      exercise: Exercise(name: "Caret", muscle: .legs),
      sets: [WorkoutSet(weightKG: 123.5), WorkoutSet(weightKG: 20)])
    let workout = Workout(name: "Caret", startedAt: date, exercises: [row])
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let pad = WorkoutNumberPadModel(editor: editor, locale: Locale(identifier: "ru_RU"))
    pad.begin(.weight(row.sets[0].id), in: workout)
    pad.selectText(NSRange(location: 1, length: 0))
    pad.digit(9)
    try expect(
      pad.text == "1923,5" && pad.selection.location == 2, "Digits insert at the native caret")
    pad.delete()
    try expect(
      pad.text == "123,5" && pad.selection.location == 1,
      "Backspace removes only the preceding character")
    pad.selectText(NSRange(location: 0, length: 0))
    pad.delete()
    try expect(pad.text == "123,5", "Backspace at the start leaves the value intact")
    pad.selectText(NSRange(location: 1, length: 2))
    pad.digit(8)
    try expect(
      pad.text == "18,5" && pad.selection.location == 2 && pad.selection.length == 0,
      "Typing replaces an explicitly selected range")
    pad.selectText(NSRange(location: 0, length: 0))
    pad.begin(.weight(row.sets[0].id), in: workout)
    try expect(pad.selection.location == 0, "Refocusing the same cell preserves its caret")
    pad.selectText(NSRange(location: 1, length: 1))
    pad.delete()
    try expect(pad.text == "1,5", "Backspace removes an explicitly selected range")
    let before = pad.text
    pad.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
    try expect(
      pad.text == before && pad.error != nil, "Invalid pasted text does not overwrite the draft")
    pad.clear()
    try expect(
      pad.text.isEmpty && pad.selection.location == 0 && pad.error == nil,
      "C clears the entire value and resets the caret")
    pad.replaceCharacters(in: NSRange(location: 0, length: 0), with: "42.5")
    try expect(pad.text == "42,5", "Hardware and pasted separators normalize to the current locale")
    pad.selectText(NSRange(location: 100, length: 100))
    try expect(
      pad.selection == NSRange(location: 4, length: 0), "Stale native selections clamp safely")
    let selected = editor.selectedSetID
    pad.begin(.weight(row.sets[1].id), in: workout)
    pad.delete()
    try expect(
      pad.text == "2" && editor.selectedSetID == selected,
      "Editing another row never switches the completion target")
    try expect(
      workout.exercises == [row],
      "Cursor editing never persists or performs a set")
  }

  @MainActor private static func checkLegacyAndPounds(date: Date) throws {
    let zero = WorkoutSet(repetitions: 0)
    let row = WorkoutExercise(exercise: Exercise(name: "Legacy", muscle: .legs), sets: [zero])
    let workout = Workout(name: "Legacy", startedAt: date, exercises: [row])
    let editor = WorkoutExercisePresentation(
      workout: workout, exerciseID: row.id, unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    let pad = WorkoutNumberPadModel(editor: editor, locale: Locale(identifier: "ru_RU"))
    pad.begin(.weight(zero.id), in: workout)
    pad.advance(in: workout)
    try expect(
      pad.field == .weight(zero.id) && pad.text.isEmpty && pad.error != nil,
      "An unfilled target requires an explicit weight, including zero for bodyweight")
    pad.digit(0)
    pad.advance(in: workout)
    try expect(
      pad.field == .repetitions(zero.id) && pad.text.isEmpty,
      "An explicit zero weight advances to empty repetitions")
    pad.advance(in: workout)
    try expect(pad.field != nil && pad.error != nil, "Zero repetitions still require correction")
    pad.digit(8)
    pad.advance(in: workout)
    try expect(
      pad.field == nil,
      "Correcting legacy repetitions completes navigation without performing a set")
    let precise = WorkoutSet(repetitions: 8, weightKG: 23.456789)
    let poundsRow = WorkoutExercise(exercise: row.exercise, sets: [precise])
    let poundsWorkout = Workout(name: "Pounds", startedAt: date, exercises: [poundsRow])
    let poundsEditor = WorkoutExercisePresentation(
      workout: poundsWorkout, exerciseID: poundsRow.id, unit: .pounds,
      locale: Locale(identifier: "en_US"))
    let poundsPad = WorkoutNumberPadModel(editor: poundsEditor, locale: Locale(identifier: "en_US"))
    poundsPad.begin(.weight(precise.id), in: poundsWorkout)
    poundsPad.advance(in: poundsWorkout)
    try expect(
      try poundsEditor.completion(in: poundsWorkout).set.weightKG == precise.weightKG,
      "Opening and advancing unchanged pounds preserves exact kilograms")
    poundsPad.begin(.weight(precise.id), in: poundsWorkout)
    poundsPad.clear()
    poundsPad.digit(1)
    poundsPad.digit(0)
    poundsPad.digit(0)
    poundsPad.decimal()
    poundsPad.digit(5)
    try expect(poundsPad.text == "100.5", "English region uses a dot")
    try expect(
      abs(
        try poundsEditor.completion(in: poundsWorkout).set.weightKG
          - WeightUnit.pounds.kilograms(from: 100.5)) < 0.000001,
      "Edited pounds convert only at the validation boundary")
  }
}
