import Foundation
import Testing

@testable import FitLifeCore

@Test func newTemplateUsesRestWithoutTimerAndKeepsSetTargets() throws {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let item = TemplateExercise(
    exercise: ExerciseCatalog.all[0], setCount: 4, repetitions: 10, weightKG: 25)
  let template = WorkoutTemplate(name: "План", exercises: [item])
  var workout = try template.start(at: date)
  #expect(workout.restSeconds == 0)
  #expect(workout.exercises[0].sets.count == 4)
  #expect(workout.exercises[0].sets.allSatisfy { $0.repetitions == 10 && $0.weightKG == 25 })
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 10, weightKG: 25, at: date)
  #expect(workout.restEndsAt == nil)
}

@Test func storedTemplateRetainsTimedRestWhenDefaultChanges() throws {
  let template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])], restSeconds: 120)
  let restored = try JSONDecoder().decode(
    WorkoutTemplate.self, from: JSONEncoder().encode(template))
  #expect(restored == template)
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  var workout = try restored.start(at: date)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 8, weightKG: 0, at: date)
  #expect(workout.restEndsAt == date.addingTimeInterval(120))
}

@Test func interactiveTemplateStartOmitsTargetsAndKeepsPlanMetadataAndIndependentIDs() throws {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let warmup = WorkoutSet(
    repetitions: 12, weightKG: 20, isWarmup: true, note: "Медленно")
  let drop = WorkoutSet(
    repetitions: 6, weightKG: 80, loadMultiplier: 2,
    dropStages: [DropSetStage(repetitions: 8, weightKG: 60)], note: "Контроль движения")
  let plain = WorkoutSet(repetitions: 8, weightKG: 40)
  let template = WorkoutTemplate(
    name: "Старый план",
    exercises: [
      TemplateExercise(
        exercise: ExerciseCatalog.all[0], setCount: 3, repetitions: 6, weightKG: 80,
        loadMultiplier: 2, plannedSets: [warmup, drop, plain])
    ], restSeconds: 90)
  let original = try JSONEncoder().encode(template)
  let restored = try JSONDecoder().decode(WorkoutTemplate.self, from: original)
  var workout = try restored.start(at: date, prefillTargets: false)
  let sets = workout.exercises[0].sets
  #expect(sets.count == 3 && sets.allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
  #expect(sets[0].isWarmup && sets[0].note == warmup.note && sets[0].loadMultiplier == nil)
  #expect(sets[1].loadMultiplier == 2 && sets[1].note == drop.note)
  #expect(sets[2].loadMultiplier == nil)
  #expect(sets.allSatisfy { $0.dropStages == nil && $0.completedAt == nil })
  #expect(workout.restSeconds == 90 && workout.volume == 0 && workout.restEndsAt == nil)
  let sourceIDs = Set([warmup.id, plain.id] + drop.stages.map(\.id))
  #expect(sourceIDs.isDisjoint(with: sets.map(\.id)))
  #expect(workout.exercises[0].id != template.exercises[0].id)
  #expect(restored == template)
  let legacyStart = try restored.start(at: date)
  #expect(legacyStart.exercises[0].sets[0].weightKG == 20)
  #expect(legacyStart.exercises[0].sets[1].dropStages?.first?.weightKG == 60)
  try Validation.workout(workout)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: sets[2].id,
    repetitions: 8, weightKG: 10, at: date)
  #expect(workout.volume == 80)
}

@Test func legacyUniformTemplatePayloadKeepsRecordedTargetsAndCanStartWithoutPrefill() throws {
  let legacy = """
    {
      "id": "00000000-0000-4000-8000-000000000001", "name": "План", "restSeconds": 120,
      "exercises": [{
        "id": "00000000-0000-4000-8000-000000000002", "setCount": 3,
        "repetitions": 7, "weightKG": 45, "loadMultiplier": 2,
        "exercise": {
          "id": "00000000-0000-4000-8000-000000000003", "name": "Жим",
          "muscle": "chest", "instructions": ""
        }
      }]
    }
    """
  let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: Data(legacy.utf8))
  let restored = try JSONDecoder().decode(
    WorkoutTemplate.self, from: JSONEncoder().encode(decoded))
  #expect(restored == decoded)
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let legacyStart = try restored.start(at: date)
  #expect(legacyStart.exercises[0].sets.allSatisfy { $0.repetitions == 7 && $0.weightKG == 45 })
  let blank = try restored.start(at: date, prefillTargets: false)
  #expect(blank.exercises[0].sets.count == 3)
  #expect(
    blank.exercises[0].sets.allSatisfy {
      $0.repetitions == 0 && $0.weightKG == 0 && $0.loadMultiplier == 2
    })
  #expect(restored.exercises[0].repetitions == 7 && restored.exercises[0].weightKG == 45)
  try Validation.workout(blank)
}

@Test @MainActor func blankPendingTargetsSurviveSaveAndRejectEmptyCompletionAtomically() throws {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0], setCount: 2)])
  var workout = try template.start(at: date, prefillTargets: false)
  let repository = MemoryWorkoutRepository()
  try repository.save(workout)
  let restored = try #require(repository.workouts().first)
  #expect(restored == workout)
  #expect(try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(restored)) == workout)
  let rowID = workout.exercises[0].id
  let setID = workout.exercises[0].sets[0].id
  let blank = workout
  #expect(throws: TrainingError.invalidRepetitions) {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: rowID, setID: setID, repetitions: 0, weightKG: 0, at: date)
  }
  #expect(workout == blank)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: rowID, setID: setID, repetitions: 8, weightKG: 0, at: date)
  #expect(workout.completedSets == 1 && workout.volume == 0)
  #expect(workout.exercises[0].sets[1].repetitions == 0)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(60))
  try repository.save(workout)
  #expect(try repository.workouts().first == workout)
}

@Test func combiningAndAppendingWithoutPrefillKeepOrderingCountsAndRecordedWork() throws {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let firstExercise = ExerciseCatalog.all[0]
  let secondExercise = ExerciseCatalog.all[1]
  let first = WorkoutTemplate(
    name: "Первый",
    exercises: [TemplateExercise(exercise: firstExercise, setCount: 2, weightKG: 50)],
    restSeconds: 120)
  let second = WorkoutTemplate(
    name: "Второй",
    exercises: [
      TemplateExercise(exercise: firstExercise, setCount: 4, repetitions: 12, weightKG: 70),
      TemplateExercise(exercise: secondExercise, setCount: 3, repetitions: 10, weightKG: 40),
    ], restSeconds: 60)
  let combined = try WorkoutTemplate.start(
    combining: [first, second], at: date, prefillTargets: false)
  #expect(combined.exercises.map(\.exercise.id) == [firstExercise.id, secondExercise.id])
  #expect(combined.exercises.map { $0.sets.count } == [2, 3])
  #expect(combined.exercises.flatMap(\.sets).allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
  #expect(combined.restSeconds == 120)
  var workout = try first.start(at: date)
  let row = workout.exercises[0]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: row.sets[0].id,
    repetitions: 5, weightKG: 50, at: date)
  let recorded = workout
  try WorkoutEngine.addTemplates([first, second], to: &workout, prefillTargets: false)
  #expect(workout.exercises[0] == recorded.exercises[0])
  #expect(
    workout.exercises.dropFirst().map(\.exercise.id) == [firstExercise.id, secondExercise.id])
  #expect(workout.exercises.dropFirst().map { $0.sets.count } == [2, 3])
  #expect(
    workout.exercises.dropFirst().flatMap(\.sets).allSatisfy {
      $0.repetitions == 0 && $0.weightKG == 0 && $0.completedAt == nil
    })
  #expect(workout.restEndsAt == recorded.restEndsAt && workout.volume == recorded.volume)
  let saved = workout
  #expect(throws: TrainingError.emptyWorkout) {
    try WorkoutEngine.addTemplates(
      [first, WorkoutTemplate(name: "Пусто", exercises: [])], to: &workout,
      prefillTargets: false)
  }
  #expect(workout == saved)
  try Validation.workout(workout)
}
