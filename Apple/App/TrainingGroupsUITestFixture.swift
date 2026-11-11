import FitLifeCore
import Foundation

/// Used only by the isolated in-memory UI test runtime, never by the personal workspace.
@MainActor enum TrainingGroupsUITestFixture {
  static func seed(into repository: any WorkoutRepository) throws {
    guard let templateID = UUID(uuidString: "90000000-0000-0000-0000-000000000001"),
      let variationID = UUID(uuidString: "90000000-0000-0000-0000-000000000002"),
      let historyID = UUID(uuidString: "90000000-0000-0000-0000-000000000003")
    else { throw TrainingError.invalidState }
    let barbell = Exercise(name: "Тест: жим штанги", muscle: .chest)
    let incline = Exercise(name: "Тест: жим в наклоне", muscle: .chest)
    let dumbbell = Exercise(name: "Тест: жим гантелей", muscle: .chest)
    let template = WorkoutTemplate(
      id: templateID, name: "Тест: жим на грудь",
      exercises: [
        TemplateExercise(exercise: barbell, setCount: 2),
        TemplateExercise(exercise: incline, setCount: 2),
      ], restSeconds: 90,
      variations: [
        WorkoutTemplateVariation(
          id: variationID, name: "Гантели",
          exercises: [
            TemplateExercise(exercise: dumbbell, setCount: 2),
            TemplateExercise(exercise: incline, setCount: 2),
          ])
      ])
    try repository.saveTemplate(template)
    let date = Date().addingTimeInterval(-3600)
    var history = Workout(
      id: historyID, name: "Тест: прошлая тренировка", startedAt: date,
      exercises: [
        WorkoutExercise(
          exercise: barbell, sets: [WorkoutSet(repetitions: 8), WorkoutSet(repetitions: 8)]),
        WorkoutExercise(
          exercise: incline, sets: [WorkoutSet(repetitions: 10), WorkoutSet(repetitions: 10)]),
      ])
    var completedIndex = 0
    for row in history.exercises {
      for set in row.sets {
        completedIndex += 1
        try WorkoutEngine.completeSet(
          in: &history, exerciseID: row.id, setID: set.id,
          repetitions: set.repetitions, weightKG: 40,
          at: date.addingTimeInterval(Double(completedIndex) * 60))
      }
    }
    try WorkoutEngine.finish(&history, at: date.addingTimeInterval(600))
    try repository.save(history)
  }
}
