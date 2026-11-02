import Foundation
import Testing

@testable import FitnessTrackerCore

private let combinationDate = Date(timeIntervalSince1970: 1_700_000_000)

@Test func combinedTemplatesPreserveOrderAndFirstTargetsByExerciseIdentity() throws {
  let chest = Exercise(name: "Грудь", muscle: .chest)
  let arms = Exercise(name: "Бицепс", muscle: .arms)
  let legs = Exercise(name: "Ноги", muscle: .legs)
  var renamedChest = chest
  renamedChest.name = "Другое название того же упражнения"
  let first = WorkoutTemplate(
    name: "Грудь", exercises: [TemplateExercise(exercise: chest, weightKG: 40)], restSeconds: 120)
  let second = WorkoutTemplate(
    name: "Руки",
    exercises: [
      TemplateExercise(exercise: arms, setCount: 4, repetitions: 12, weightKG: 15),
      TemplateExercise(exercise: renamedChest, weightKG: 60),
      TemplateExercise(exercise: legs), TemplateExercise(exercise: arms),
    ], restSeconds: 60)
  let workout = try WorkoutTemplate.start(combining: [first, second], at: combinationDate)
  #expect(workout.exercises.map(\.exercise.id) == [chest.id, arms.id, legs.id])
  #expect(workout.exercises[0].exercise.name == chest.name)
  #expect(workout.exercises[0].sets.allSatisfy { $0.weightKG == 40 })
  #expect(workout.exercises[1].sets.count == 4)
  #expect(workout.exercises[1].sets.allSatisfy { $0.repetitions == 12 && $0.weightKG == 15 })
  #expect(workout.name == "Грудь + Руки" && workout.restSeconds == 120)
  #expect(workout.startedAt == combinationDate && workout.status == .active)
  try Validation.workout(workout)
  let reverse = try WorkoutTemplate.start(combining: [second, first], at: combinationDate)
  #expect(reverse.exercises.map(\.exercise.id) == [arms.id, chest.id, legs.id])
  #expect(reverse.exercises[1].sets.allSatisfy { $0.weightKG == 60 })
  #expect(reverse.restSeconds == 60)
}

@Test func combinationDoesNotMergeDifferentExercisesWithIdenticalNamesOrSharedRowIDs() throws {
  let row = TemplateExercise(
    exercise: Exercise(name: "Жим", muscle: .chest), setCount: 1,
    plannedSets: [
      WorkoutSet(
        weightKG: 30, dropStages: [DropSetStage(repetitions: 8, weightKG: 20)])
    ])
  var another = row
  another.exercise = Exercise(name: "Жим", muscle: .shoulders)
  let workout = try WorkoutTemplate.start(
    combining: [
      WorkoutTemplate(name: "A", exercises: [row]),
      WorkoutTemplate(name: "B", exercises: [another]),
    ], at: combinationDate)
  #expect(workout.exercises.map(\.exercise.id) == [row.exercise.id, another.exercise.id])
  #expect(Set(workout.exercises.map(\.id)).count == 2)
  #expect(Set(workout.exercises.flatMap(\.sets).flatMap(\.stages).map(\.id)).count == 4)
  try Validation.workout(workout)
}

@Test func combinedPlansKeepWarmupDropSetsAndFreshIndependentIDs() throws {
  let warmup = WorkoutSet(
    repetitions: 15, weightKG: 10, isWarmup: true)
  let drop = WorkoutSet(
    repetitions: 10, weightKG: 30, loadMultiplier: 2,
    dropStages: [DropSetStage(repetitions: 8, weightKG: 20)])
  let template = WorkoutTemplate(
    name: "План",
    exercises: [
      TemplateExercise(
        exercise: Exercise(name: "Бицепс", muscle: .arms), setCount: 2, plannedSets: [warmup, drop])
    ])
  let before = template
  let first = try WorkoutTemplate.start(combining: [template, template], at: combinationDate)
  let second = try WorkoutTemplate.start(combining: [template, template], at: combinationDate)
  #expect(first.exercises.count == 1 && first.exercises[0].sets.count == 2)
  #expect(first.exercises[0].sets[0].isWarmup)
  #expect(first.exercises[0].sets[1].loadMultiplier == 2)
  #expect(first.exercises[0].sets[1].dropStages?.first?.weightKG == 20)
  let stages = first.exercises.flatMap(\.sets).flatMap(\.stages)
  #expect(stages.allSatisfy { $0.completedAt == nil })
  let sourceIDs = Set([warmup.id] + drop.stages.map(\.id))
  let firstIDs = Set(stages.map(\.id))
  #expect(firstIDs.isDisjoint(with: sourceIDs))
  #expect(firstIDs.isDisjoint(with: second.exercises.flatMap(\.sets).flatMap(\.stages).map(\.id)))
  #expect(first.id != second.id && first.exercises[0].id != second.exercises[0].id)
  #expect(first.exercises[0].id != template.exercises[0].id)
  #expect(first.volume == 0 && first.pauses.isEmpty && first.restEndsAt == nil)
  #expect(template == before)
  try Validation.workout(first)
}

@Test func combinationValidatesAllPlansBeforeDiscardingDuplicateExercises() {
  let row = TemplateExercise(exercise: Exercise(name: "Грудь", muscle: .chest))
  let valid = WorkoutTemplate(name: "A", exercises: [row])
  var invalid = valid
  invalid.exercises[0].weightKG = -1
  #expect(throws: TrainingError.invalidWeight) {
    try WorkoutTemplate.start(combining: [valid, invalid], at: combinationDate)
  }
  #expect(throws: TrainingError.emptyWorkout) {
    try WorkoutTemplate.start(combining: [], at: combinationDate)
  }
  #expect(throws: TrainingError.emptyWorkout) {
    try WorkoutTemplate.start(
      combining: [valid, WorkoutTemplate(name: "Пустой", exercises: [])], at: combinationDate)
  }
}

@Test func combinedNamesStayWithinTheExistingValidationLimit() throws {
  let template = WorkoutTemplate(
    name: String(repeating: "Я", count: 80),
    exercises: [TemplateExercise(exercise: Exercise(name: "Грудь", muscle: .chest))])
  let workout = try WorkoutTemplate.start(combining: [template, template], at: combinationDate)
  #expect(workout.name.count == 80)
  try Validation.workout(workout)
  var padded = template
  padded.name = String(repeating: " ", count: 100) + "Грудь "
  let trimmed = try WorkoutTemplate.start(combining: [padded, padded], at: combinationDate)
  #expect(trimmed.name == "Грудь + Грудь")
  try Validation.workout(trimmed)
}
