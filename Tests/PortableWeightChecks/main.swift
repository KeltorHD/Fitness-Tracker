import FitnessTrackerCore
import Foundation

private struct WeightCheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw WeightCheckFailure(message: message) }
}

@main struct PortableWeightChecks {
  @MainActor static func main() throws {
    let date = Date(timeIntervalSince1970: 1_793_000_000)
    let editor = BodyWeightEditorModel(unit: .kilograms, locale: Locale(identifier: "ru_RU"))
    editor.text = "72,5"
    try expect(try editor.valueInKG() == 72.5, "Comma decimals must be accepted")
    editor.text = "72.5"
    try expect(try editor.valueInKG() == 72.5, "Dot decimals must also be accepted")
    for value in ["", "72kg", "1,2,3", "0", "-1", "2e2", "nan", "inf", "72 5"] {
      editor.text = value
      var rejected = false
      do { _ = try editor.valueInKG() } catch TrainingError.invalidBodyWeight { rejected = true }
      try expect(rejected, "Malformed input must not be partially parsed: \(value)")
    }
    let pounds = BodyWeightEditorModel(unit: .pounds)
    pounds.text = "160"
    try expect(
      abs(try pounds.valueInKG() - 72.5747792) < 0.000001, "Pounds must be converted on input")
    let precise = BodyWeightEditorModel(weightKG: 72.345678, unit: .pounds)
    try expect(
      try precise.valueInKG() == 72.345678, "Editing just the date must preserve stored precision")
    let arabic = BodyWeightEditorModel(unit: .kilograms, locale: Locale(identifier: "ar_EG"))
    arabic.text = "٧٢٫٥"
    try expect(try arabic.valueInKG() == 72.5, "Localized decimal digits must be supported")

    let measurement = BodyWeightEntry(measuredAt: date.addingTimeInterval(-3600), weightKG: 73)
    var workout = try ExerciseCatalog.starterTemplates[0].start(at: date)
    try WorkoutEngine.setBodyWeight(72.5, in: &workout)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
      repetitions: 8, weightKG: 40, at: date)
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
    let model = BodyWeightViewModel(now: { date.addingTimeInterval(120) })
    model.refresh(entries: [measurement], workouts: [workout])
    try expect(
      model.summary.latest?.source == .workout(workout.id),
      "A completed workout weight must appear in the card")
    try expect(model.summary.changeKG == -0.5, "Card delta must use real preceding values")
    try expect(
      model.items.first?.workoutName == workout.name, "History must retain the workout source")
    workout.bodyWeightKG = 71
    model.refresh(entries: [measurement], workouts: [workout])
    try expect(
      model.items.count == 2 && model.summary.latest?.weightKG == 71,
      "Editing a workout must update, not duplicate, its weight")
    model.refresh(entries: [], workouts: [])
    try expect(
      model.summary.latest == nil && model.items.isEmpty,
      "Changing workspace must clear previous body weights")
    print(
      "Portable body weight: localized input, strict validation, pounds, precision, sources, editing and workspace refresh passed (no Apple SDK)."
    )
  }
}
