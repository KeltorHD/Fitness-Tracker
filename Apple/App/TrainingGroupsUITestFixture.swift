import FitnessTrackerCore
import Foundation

/// Used only by the isolated in-memory UI test runtime, never by the personal workspace.
@MainActor enum TrainingGroupsUITestFixture {
  static func seedPreviousSets(into repository: any WorkoutRepository) throws {
    guard
      let exercise = ExerciseLibrary.entries.first(where: { $0.sourceID == "Goblet_Squat" })?
        .exercise
    else {
      throw TrainingError.missingExercise
    }
    let date = Date().addingTimeInterval(-3600)
    let values = [(30.0, 12), (35.0, 10), (40.0, 8)]
    let notes: [String?] = ["Рабочий подход", nil, "Заметка"]
    let row = WorkoutExercise(
      exercise: exercise,
      sets: values.enumerated().map { index, value in
        WorkoutSet(repetitions: value.1, weightKG: value.0, note: notes[index])
      })
    var workout = Workout(name: "Тест: три предыдущих подхода", startedAt: date, exercises: [row])
    for (index, set) in row.sets.enumerated() {
      try WorkoutEngine.completeSet(
        in: &workout, exerciseID: row.id, setID: set.id,
        repetitions: set.repetitions, weightKG: set.weightKG,
        at: date.addingTimeInterval(Double(index + 1) * 30))
    }
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(300))
    try repository.save(workout)
  }

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
