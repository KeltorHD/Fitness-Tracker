import FitnessTrackerCore
import Foundation

/// Synthetic nutrition is confined to the explicitly requested, in-memory Debug UI runtime.
@MainActor enum DiaryInsightsUITestFixture {
  #if DEBUG
    static func seed(into repository: any WorkoutRepository) throws {
      guard let nutrition = repository as? any NutritionRepository else {
        throw NutritionError.invalidEntry
      }
      let product = FoodProduct(
        id: "ui-diary-insights", name: "UI fixture: nutrition",
        per100Units: Nutrients(calories: 240, protein: 12, fat: 8, carbohydrates: 30))
      try nutrition.saveFoodEntry(
        FoodEntry(
          date: .now, meal: .breakfast, title: "UI fixture: breakfast",
          portions: [FoodPortion(product: product, amount: 300)]))
      try nutrition.saveNutritionGoal(
        NutritionGoal(calories: 2000, protein: 100, fat: 70, carbohydrates: 250))
      let now = Date()
      for (offset, weight) in [(-1, 40.0), (0, 20.0)] {
        guard let date = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: now) else {
          throw TrainingError.invalidState
        }
        let row = WorkoutExercise(
          exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(), WorkoutSet()])
        var workout = Workout(name: "UI fixture: rings", startedAt: date, exercises: [row])
        for set in row.sets {
          try WorkoutEngine.completeSet(
            in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: weight,
            at: date)
        }
        try WorkoutEngine.finish(&workout, at: date)
        try repository.save(workout)
      }
    }
  #endif
}
