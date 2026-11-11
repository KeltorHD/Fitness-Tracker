import Foundation
import Testing

@testable import FitLifeCore

private let refinementDate = Date(timeIntervalSince1970: 1_700_000_000)

@Test @MainActor func renamedFirstVariationAndRegionalPreferencesSurviveCurrentArchiveRoundTrips()
  throws
{
  let row = TemplateExercise(exercise: Exercise(name: "Жим", muscle: .chest))
  var template = WorkoutTemplate(name: "Грудь", exercises: [row], baseVariationName: "Штанга")
  template.variations = [try template.makeVariation(name: "Гантели")]
  template.muscleSelection = ExerciseMuscleSelection(regions: [.chestUpper, .deltoidAnterior])
  let data = try JSONEncoder().encode(template)
  #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: data) == template)
  let archive = WorkoutArchive(workouts: [], templates: [template])
  #expect(
    try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive)).templates == [template])
  let repository = MemoryWorkoutRepository()
  try repository.saveTemplate(template)
  #expect(try repository.templates().first == template)
  #expect(try template.resolvedVariation(id: nil).baseVariationName == "Штанга")
  #expect(
    try template.resolvedVariation(id: template.variations[0].id).baseVariationName == "Гантели")
  var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  legacy.removeValue(forKey: "baseVariationName")
  legacy.removeValue(forKey: "muscleRegions")
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(
      WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: legacy))
  }
  template.baseVariationName = "  "
  #expect(throws: TrainingError.invalidName) { try Validation.template(template) }
}

@Test func templateReplacementClearsOtherExercisesTargetsAndDragKeepsSupersetsWhole() throws {
  let groupID = UUID()
  let first = TemplateExercise(
    exercise: Exercise(name: "A", muscle: .chest), setCount: 1,
    plannedSets: [WorkoutSet(repetitions: 8, weightKG: 80, note: "Старое упражнение")],
    supersetID: groupID)
  let second = TemplateExercise(exercise: Exercise(name: "B", muscle: .back), supersetID: groupID)
  let third = TemplateExercise(exercise: Exercise(name: "C", muscle: .legs))
  let rows = [first, second, third]
  let dragged = try TemplateExercise.moving(first.id, to: 3, in: rows)
  #expect(dragged == [third, first, second])
  #expect(try TemplateExercise.moving(second.id, to: 3, in: rows) == dragged)
  #expect(try TemplateExercise.moving(third.id, to: 1, in: rows) == dragged)
  #expect(try TemplateExercise.moving(first.id, to: 1, in: rows) == rows)
  let replacement = first.replacing(with: third.exercise)
  #expect(replacement.id != first.id && replacement.exercise == third.exercise)
  #expect(replacement.supersetID == groupID && replacement.setCount == first.setCount)
  #expect(replacement.plannedSets == nil && replacement.weightKG == 0)
  #expect(first.plannedSets?[0].weightKG == 80)
  #expect(throws: TrainingError.invalidState) {
    try TemplateExercise.moving(first.id, to: rows.count + 1, in: rows)
  }
}

@Test func templateResultsMatchOccurrencesAndIgnoreUnperformedOrUnfinishedSessions() throws {
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let rows = [TemplateExercise(exercise: exercise), TemplateExercise(exercise: exercise)]
  var recorded = Workout(
    name: "Записано", startedAt: refinementDate,
    exercises: [
      WorkoutExercise(
        exercise: exercise,
        sets: [WorkoutSet(repetitions: 8, weightKG: 40, completedAt: refinementDate)]),
      WorkoutExercise(
        exercise: exercise,
        sets: [WorkoutSet(repetitions: 12, weightKG: 30, completedAt: refinementDate)]),
    ])
  try WorkoutEngine.finish(&recorded, at: refinementDate.addingTimeInterval(60))
  var latest = recorded
  latest.id = UUID()
  latest.startedAt = refinementDate.addingTimeInterval(100)
  latest.endedAt = refinementDate.addingTimeInterval(160)
  latest.exercises[0].sets[0].weightKG = 50
  latest.exercises[0].sets[0].completedAt = latest.startedAt
  latest.exercises[1].sets[0].completedAt = nil
  let unfinished = Workout(
    name: "Ещё не сохранено", startedAt: refinementDate.addingTimeInterval(200),
    exercises: latest.exercises)
  let results = TemplateExercise.previousResults(
    for: rows, history: [unfinished, recorded, latest],
    before: refinementDate.addingTimeInterval(300))
  #expect(results[rows[0].id]?.sets[0].weightKG == 50)
  #expect(results[rows[1].id]?.sets[0].weightKG == 30)
  #expect(
    TemplateExercise.previousResults(for: rows, history: [unfinished], before: refinementDate)
      .isEmpty)
  #expect(
    TemplateExercise.previousResults(
      for: rows, history: [latest], before: refinementDate.addingTimeInterval(90)
    ).isEmpty)
}

@Test func regionalSelectionCanNarrowWholeGroupsWithoutLosingSiblingMuscles() {
  var selection = ExerciseMuscleSelection(groups: [.shoulders, .arms])
  selection.set(.deltoidAnterior, selected: false)
  #expect(!selection.contains(.deltoidAnterior))
  #expect(selection.contains(.deltoidLateral) && selection.contains(.deltoidPosterior))
  #expect(selection.contains(.neck) && selection.contains(.biceps))
  #expect(selection.state(of: MuscleGroup.shoulders) == .partial)
  #expect(selection.state(ofMuscle: .shoulders) == .partial)
  selection.set(ExerciseMuscle.shoulders, selected: true)
  #expect(selection.regions.isEmpty && selection.contains(.deltoidAnterior))
  selection.set(MuscleGroup.shoulders, selected: false)
  #expect(selection.groups == [.arms] && selection.regions.isEmpty)
  #expect(ExerciseMuscle(libraryName: "Дельтовидные мышцы") == .shoulders)
  #expect(ExerciseMuscle(libraryName: "Икроножные мышцы") == .calves)
}

@Test func reviewedRegionsFilterBothLanguagesWithoutInventingAnInnerChestMuscle() throws {
  let russian = try ExerciseLibrary.entries(language: .russian)
  let english = try ExerciseLibrary.entries(language: .english)
  #expect(Set(russian.flatMap(\.muscleRegions)) == Set(ExerciseMuscleRegion.allCases))
  #expect(russian.map(\.muscleRegions) == english.map(\.muscleRegions))
  let expectations: [(ExerciseMuscleRegion, String, String)] = [
    (.chestUpper, "Barbell_Incline_Bench_Press_-_Medium_Grip", "Decline_Barbell_Bench_Press"),
    (.chestLower, "Decline_Barbell_Bench_Press", "Barbell_Incline_Bench_Press_-_Medium_Grip"),
    (.deltoidAnterior, "Front_Dumbbell_Raise", "Cable_Rear_Delt_Fly"),
    (.deltoidPosterior, "Cable_Rear_Delt_Fly", "Front_Dumbbell_Raise"),
    (.deltoidLateral, "Side_Lateral_Raise", "Front_Dumbbell_Raise"),
    (.transversusAbdominis, "Stomach_Vacuum", "Decline_Barbell_Bench_Press"),
  ]
  for (region, included, excluded) in expectations {
    let selection = ExerciseMuscleSelection(regions: [region])
    let result = ExerciseLibrary.search(muscleSelection: selection)
    #expect(result.contains { $0.sourceID == included })
    #expect(!result.contains { $0.sourceID == excluded })
    #expect(result.allSatisfy { $0.muscleRegions.contains(region) })
  }
  #expect(
    ExerciseMuscleRegion.allCases.allSatisfy { !$0.rawValue.lowercased().contains("innerchest") })
}

@Test func templateFiltersFindNamedFirstVariationAndRespectNarrowRegions() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Incline_Bench_Press_-_Medium_Grip" })
  var template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: entry.exercise)],
    baseVariationName: "Верх со штангой")
  template.muscleSelection = ExerciseMuscleSelection(regions: [.chestUpper])
  var filter = WorkoutTemplateFilter()
  filter.query = "Верх со штангой"
  filter.muscles = ExerciseMuscleSelection(groups: [.chest])
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  #expect(
    filter.apply(to: [template], date: refinementDate, calendar: calendar).others == [template])
  filter.muscles = ExerciseMuscleSelection(regions: [.chestLower])
  #expect(filter.apply(to: [template], date: refinementDate, calendar: calendar).others.isEmpty)
}
