import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class FoodEntryEditorModel {
  var entry: FoodEntry
  var error: String?
  private(set) var isLoadingPhoto = false
  @ObservationIgnored private let photos = MealPhotoProcessor()
  init(entry: FoodEntry) { self.entry = entry }
  func importPhoto(_ data: Data) async {
    isLoadingPhoto = true
    defer { isLoadingPhoto = false }
    do {
      let jpeg = try await photos.jpeg(from: data)
      try Task.checkCancellation()
      entry.photo = jpeg
      error = nil
    } catch {
      guard !Task.isCancelled else { return }
      self.error = "Не удалось обработать фото. Выберите другое изображение."
    }
  }
  func add(_ product: FoodProduct, amount: Double) throws {
    let portion = FoodPortion(product: product, amount: amount)
    try portion.validate()
    guard entry.portions.count < 100 else { throw NutritionError.invalidEntry }
    entry.portions.append(portion)
    if entry.title.isEmpty { entry.title = product.name }
  }
  func validatedEntry() throws -> FoodEntry {
    var result = entry
    if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result.title = result.portions.first?.product.name ?? L10n.text(result.meal.title)
    }
    try result.validate()
    return result
  }
}
