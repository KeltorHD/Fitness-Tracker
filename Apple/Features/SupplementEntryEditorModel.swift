import FitLifeCore
import Foundation
import Observation

@MainActor @Observable final class SupplementEntryEditorModel {
  var kind: SupplementKind
  var name: String
  var date: Date
  var amount: String
  var unit: SupplementUnit
  var includesNutrition: Bool
  var calories: String
  var protein: String
  var fat: String
  var carbohydrates: String
  var note: String
  var error: String?
  @ObservationIgnored private let original: SupplementEntry

  init(entry: SupplementEntry) {
    original = entry
    kind = entry.kind
    name = entry.name
    date = entry.date
    amount = entry.amount > 0 ? Self.text(entry.amount) : ""
    unit = entry.unit
    includesNutrition = entry.includesNutrition
    calories = entry.nutritionPerBasis.map { Self.text($0.calories) } ?? ""
    protein = entry.nutritionPerBasis.map { Self.text($0.protein) } ?? ""
    fat = entry.nutritionPerBasis.map { Self.text($0.fat) } ?? ""
    carbohydrates = entry.nutritionPerBasis.map { Self.text($0.carbohydrates) } ?? ""
    note = entry.note
  }

  func changeKind(_ kind: SupplementKind) {
    guard self.kind != kind else { return }
    self.kind = kind
    if nutritionIsEmpty { includesNutrition = kind.normallyTracksNutrition }
  }
  func changeUnit(_ unit: SupplementUnit) {
    guard self.unit != unit else { return }
    self.unit = unit
    // Values for 100 grams cannot silently become values for one capsule or one serving.
    calories = ""
    protein = ""
    fat = ""
    carbohydrates = ""
  }

  func validatedEntry() throws -> SupplementEntry {
    let nutrition: Nutrients?
    if includesNutrition && !nutritionIsEmpty {
      guard
        [calories, protein, fat, carbohydrates].allSatisfy({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
      else { throw NutritionError.invalidSupplementNutrition }
      let previous = unit == original.unit ? original.nutritionPerBasis : nil
      do {
        nutrition = try Nutrients(
          calories: Self.number(calories, original: previous?.calories),
          protein: Self.number(protein, original: previous?.protein),
          fat: Self.number(fat, original: previous?.fat),
          carbohydrates: Self.number(carbohydrates, original: previous?.carbohydrates))
      } catch { throw NutritionError.invalidSupplementNutrition }
    } else {
      nutrition = nil
    }
    let quantity: Double
    do { quantity = try Self.number(amount, original: original.amount) } catch {
      throw NutritionError.invalidSupplement
    }
    let result = SupplementEntry(
      id: original.id, date: date, kind: kind,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      amount: quantity, unit: unit,
      includesNutrition: includesNutrition, nutritionPerBasis: nutrition,
      note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    try result.validate()
    return result
  }

  private var nutritionIsEmpty: Bool {
    [calories, protein, fat, carbohydrates].allSatisfy {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
  private static func text(_ value: Double) -> String { String(value) }
  private static func number(_ text: String, original: Double?) throws -> Double {
    if let original, text == Self.text(original) { return original }
    return try NutritionInput.number(text)
  }
}
