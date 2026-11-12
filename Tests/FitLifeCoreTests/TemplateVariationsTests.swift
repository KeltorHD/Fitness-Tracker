import Foundation
import Testing

@testable import FitLifeCore

private let variationDate = Date(timeIntervalSince1970: 1_700_000_000)

private func variationTemplate() -> WorkoutTemplate {
  WorkoutTemplate(
    name: "Жим на грудь",
    exercises: [TemplateExercise(exercise: Exercise(name: "Жим штанги лёжа", muscle: .chest))],
    restSeconds: 120, muscleGroups: [.chest], preferredWeekdays: [.monday],
    variations: [
      WorkoutTemplateVariation(
        name: "С гантелями",
        exercises: [
          TemplateExercise(exercise: Exercise(name: "Жим гантелей лёжа", muscle: .chest)),
          TemplateExercise(exercise: Exercise(name: "Жим в наклоне", muscle: .chest)),
        ])
    ])
}

@Test func selectedVariationUsesOnlyItsExercisesAndKeepsCommonTemplateSettings() throws {
  let template = variationTemplate()
  let alternate = template.variations[0]
  let selected = try template.resolvedVariation(id: alternate.id)
  #expect(selected.id == template.id && selected.name == template.name)
  #expect(selected.exercises == alternate.exercises)
  #expect(selected.variations.isEmpty)
  #expect(selected.restSeconds == template.restSeconds)
  #expect(selected.muscleSelection == template.muscleSelection)
  #expect(selected.preferredWeekdays == template.preferredWeekdays)
  #expect(try template.resolvedVariation(id: nil).exercises == template.exercises)
  #expect(try template.resolvedVariation(id: template.id).exercises == template.exercises)
  #expect(template.variations.count == 1)
  #expect(throws: TrainingError.missingTemplateVariation) {
    try template.resolvedVariation(id: UUID())
  }
  let workout = try selected.start(at: variationDate, prefillTargets: false)
  #expect(workout.exercises.map(\.exercise) == alternate.exercises.map(\.exercise))
  #expect(
    workout.exercises.allSatisfy { $0.sets.allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 } })
}

@Test func variationCopiesKeepPlansButCreateIndependentRowsStagesAndSupersets() throws {
  let groupID = UUID()
  let plan = WorkoutSet(repetitions: 12, weightKG: 30, note: "Контроль движения")
  let original = WorkoutTemplate(
    name: "Пара",
    exercises: [
      TemplateExercise(
        exercise: Exercise(name: "Первое", muscle: .legs), setCount: 1,
        plannedSets: [plan], supersetID: groupID),
      TemplateExercise(exercise: Exercise(name: "Второе", muscle: .legs), supersetID: groupID),
    ])
  let copied = try original.makeVariation(name: "Другой вариант")
  #expect(copied.exercises.map(\.exercise) == original.exercises.map(\.exercise))
  #expect(Set(copied.exercises.map(\.id)).isDisjoint(with: original.exercises.map(\.id)))
  #expect(copied.exercises[0].plannedSets?[0].note == plan.note)
  #expect(copied.exercises[0].plannedSets?[0].id != plan.id)
  #expect(copied.exercises[0].supersetID != groupID)
  #expect(copied.exercises[0].supersetID == copied.exercises[1].supersetID)
  var saved = original
  saved.variations = [copied]
  try Validation.template(saved)
  #expect(
    try saved.makeVariation(name: "Третий", copying: copied.id).exercises[0].id
      != copied.exercises[0].id)
  #expect(
    try WorkoutTemplate(name: "Черновик", exercises: []).makeVariation(name: "Новый").exercises
      .isEmpty)
}

@Test func templateValidationIncludesUnselectedVariations() throws {
  var template = variationTemplate()
  template.variations[0].exercises[0].setCount = 0
  #expect(throws: TrainingError.invalidSetCount) { try Validation.template(template) }
  template = variationTemplate()
  template.variations[0].name = " "
  #expect(throws: TrainingError.invalidName) { try Validation.template(template) }
  template = variationTemplate()
  template.variations[0].exercises = []
  #expect(throws: TrainingError.emptyWorkout) { try Validation.template(template) }
  template = variationTemplate()
  template.variations.append(template.variations[0])
  #expect(throws: TrainingError.duplicateID) { try Validation.template(template) }
}

@Test func templatesRequireCurrentVariationsMetadata() throws {
  let template = WorkoutTemplate(
    name: "Шаблон", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])])
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
  object.removeValue(forKey: "variations")
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(
      WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object))
  }
}

@Test func archiveRoundTripPreservesTemplateVariationsAndSupersets() throws {
  var template = variationTemplate()
  let groupID = UUID()
  template.variations[0].exercises[0].supersetID = groupID
  template.variations[0].exercises[1].supersetID = groupID
  var workout = try template.resolvedVariation(id: template.variations[0].id).start(
    at: variationDate)
  let first = workout.exercises[0]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: first.id, setID: first.sets[0].id,
    repetitions: 10, weightKG: 20, at: workout.startedAt)
  try WorkoutEngine.finish(&workout, at: workout.startedAt.addingTimeInterval(10))
  let archive = WorkoutArchive(
    workouts: [workout], templates: [template], exportedAt: variationDate.addingTimeInterval(20))
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive))
  #expect(restored.workouts == archive.workouts)
  #expect(restored.templates == archive.templates)
  #expect(restored.version == 4)
}

@Test func draftChangesDissolveBrokenSupersetsAndRetainValidPairs() {
  let id = UUID()
  let rows = [
    TemplateExercise(exercise: ExerciseCatalog.all[0], supersetID: id),
    TemplateExercise(exercise: ExerciseCatalog.all[1], supersetID: id),
    TemplateExercise(exercise: ExerciseCatalog.all[2]),
  ]
  #expect(TemplateExercise.normalizingSupersets(rows) == rows)
  #expect(TemplateExercise.normalizingSupersets([rows[0], rows[2]])[0].supersetID == nil)
  #expect(
    TemplateExercise.normalizingSupersets([rows[0], rows[2], rows[1]]).allSatisfy {
      $0.supersetID == nil
    })
}

@Test func variantExercisesRemainDiscoverableInTemplateSearchAndMuscleFilters() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  var template = variationTemplate()
  template.variations[0].exercises[0].exercise = Exercise(name: "Гантели на ноги", muscle: .legs)
  var filter = WorkoutTemplateFilter()
  filter.query = "Гантели на ноги"
  #expect(filter.apply(to: [template], date: variationDate, calendar: calendar).others.count == 1)
  template.muscleSelection = ExerciseMuscleSelection()
  filter.query = ""
  filter.muscles = ExerciseMuscleSelection(groups: [.legs])
  #expect(filter.apply(to: [template], date: variationDate, calendar: calendar).others.count == 1)
}
