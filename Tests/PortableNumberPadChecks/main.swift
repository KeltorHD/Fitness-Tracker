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
    try expect(pad.field == .weight(second.id), "Next skips completed rows")
    pad.advance(in: workout)
    try expect(pad.field == .repetitions(second.id), "Weight advances to repetitions")
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
        && editor.drafts[completed.id] == nil,
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
    try expect(pad.field == nil, "Completed fields cannot open the panel")
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
      pad.field == nil && editor.drafts[first.id] == nil,
      "External completion cannot leave an editable stale field")
    pad.begin(.weight(second.id), in: workout)
    pad.reconcile(nil)
    try expect(pad.field == nil, "Workout removal dismisses the panel")
    var foreign = workout
    foreign.id = UUID()
    pad.begin(.weight(second.id), in: foreign)
    try expect(pad.field == nil, "Another workout cannot reuse the editor")
    try checkLegacyAndPounds(date: date)
    try checkCursor(date: date)
    print(
      "Portable number pad: native caret, range replacement, C/backspace, decimal/bounds, field traversal, copy isolation, draft-only changes, immutable completions, pause/removal, legacy zero reps and pounds precision passed (no Apple SDK)."
    )
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
