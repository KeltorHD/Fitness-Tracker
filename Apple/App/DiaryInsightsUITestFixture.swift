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
    }
  #endif
}
