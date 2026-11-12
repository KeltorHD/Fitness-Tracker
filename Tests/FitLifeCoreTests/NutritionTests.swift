import Foundation
import Testing

@testable import FitLifeCore

private func food() -> FoodProduct {
  FoodProduct(
    id: "test", name: "Продукт",
    per100Units: Nutrients(calories: 200, protein: 10, fat: 8, carbohydrates: 22))
}

@Test func foodPortionsScaleAllNutrients() throws {
  let portion = FoodPortion(product: food(), amount: 150)
  try portion.validate()
  #expect(portion.nutrients == Nutrients(calories: 300, protein: 15, fat: 12, carbohydrates: 33))
  for amount in [0, -1, Double.nan, Double.infinity, 10_001] {
    #expect(throws: NutritionError.self) {
      try FoodPortion(product: food(), amount: amount).validate()
    }
  }
}

@Test func nutritionRejectsInvalidDataWithoutInventingValues() throws {
  for value in [Double.nan, Double.infinity, -1, 1001] {
    #expect(throws: NutritionError.self) { try Nutrients(calories: value).validate() }
  }
  #expect(throws: NutritionError.self) {
    try Nutrients(calories: 500, protein: 80, fat: 80, carbohydrates: 10).validate()
  }
  let zero = FoodProduct(name: "Вода", per100Units: Nutrients())
  try zero.validate()
  #expect(throws: NutritionError.self) { try FoodEntry(title: "Пустая запись").validate() }
  let photo = Data([0xFF, 0xD8, 0xFF, 0])
  let entry = FoodEntry(title: "Перекус", photo: photo)
  try entry.validate()
  #expect(entry.needsNutrition)
  #expect(throws: NutritionError.self) {
    try FoodEntry(title: "Фото", photo: Data(repeating: 0, count: 600_001)).validate()
  }
}

@Test func nutritionCalendarUsesLocalDaysAcrossDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let date = try #require(ISO8601DateFormatter().date(from: "2026-03-08T07:30:00Z"))
  let start = calendar.startOfDay(for: date)
  let next = try #require(calendar.date(byAdding: .day, value: 1, to: start))
  #expect(next.timeIntervalSince(start) == 23 * 3600)
  let a = FoodEntry(date: start, title: "A", portions: [FoodPortion(product: food())])
  let b = FoodEntry(date: next.addingTimeInterval(-1), title: "B", photo: Data([0xFF, 0xD8, 0xFF]))
  let c = FoodEntry(date: next, title: "C", portions: [FoodPortion(product: food())])
  let day = NutritionDay(entries: [c, b, a], date: date, calendar: calendar)
  #expect(day.entries.map(\.id) == [a.id, b.id])
  #expect(day.total.calories == 200)
  #expect(day.incompleteCount == 1)
}

@Test func repeatingFoodPreservesProductIdentityButCreatesNewRows() throws {
  let entry = FoodEntry(
    title: "Блюдо", portions: [FoodPortion(product: food(), amount: 75)], isSavedMeal: true)
  let date = Date(timeIntervalSince1970: 1500)
  let copy = entry.repeated(on: date)
  #expect(copy.id != entry.id)
  #expect(copy.portions.first?.id != entry.portions.first?.id)
  #expect(copy.portions.first?.product.id == entry.portions.first?.product.id)
  #expect(copy.nutrients == entry.nutrients)
  #expect(copy.date == date)
  #expect(!copy.isSavedMeal)
  #expect(try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(copy)) == copy)
}

@Test @MainActor func nutritionRepositoryValidatesBeforeChangingData() throws {
  let repository = MemoryNutritionRepository()
  var entry = FoodEntry(title: "Еда", portions: [FoodPortion(product: food())])
  try repository.saveFoodEntry(entry)
  entry.portions[0].amount = -10
  #expect(throws: NutritionError.self) { try repository.saveFoodEntry(entry) }
  #expect(try repository.foodEntries().first?.portions.first?.amount == 100)
  let goal = NutritionGoal(calories: 2100, protein: 110)
  try repository.saveNutritionGoal(goal)
  #expect(throws: NutritionError.self) {
    try repository.saveNutritionGoal(NutritionGoal(calories: .nan))
  }
  #expect(try repository.nutritionGoal() == goal)
  try repository.saveNutritionGoal(nil)
  #expect(try repository.nutritionGoal() == nil)
  try repository.deleteFoodEntry(id: entry.id)
  #expect(try repository.foodEntries().isEmpty)
}

@Test func openFoodFactsRequiresCompleteNutritionAndPreservesQuantityBasis() throws {
  let json =
    #"{"code":"12345678","product_name":"Food","product_name_ru":"Продукт","image_front_small_url":"https://images.openfoodfacts.org/test.jpg","nutriments":{"energy_100g":836.8,"proteins_100g":10,"fat_100g":8,"carbohydrates_100g":22}}"#
  func decode(_ input: String) throws -> FoodProduct? {
    try JSONDecoder().decode(OpenFoodFactsProduct.self, from: Data(input.utf8)).product()
  }
  let product = try #require(try decode(json))
  #expect(abs(product.per100Units.calories - 200) < 0.0001)
  #expect(product.name == "Продукт")
  #expect(product.imageURL?.scheme == "https")
  #expect(try decode(json.replacingOccurrences(of: "\"proteins_100g\":10,", with: "")) == nil)
  #expect(
    try decode(
      json.replacingOccurrences(of: "\"code\":", with: "\"product_quantity_unit\":\"ml\",\"code\":")
    )?.unit == .milliliters)
  #expect(
    try decode(
      json.replacingOccurrences(of: "\"code\":", with: "\"nutrition_data_per\":\"100ml\",\"code\":")
    )?.unit == .milliliters)
  #expect(
    try decode(
      json.replacingOccurrences(
        of: "https://images.openfoodfacts.org", with: "http://other.example"))?.imageURL == nil)
  #expect(try decode(json.replacingOccurrences(of: "12345678", with: "../test")) == nil)
}

@Test func volumeNutritionDoesNotAssumeTheDensityOfWater() throws {
  let syrup = FoodProduct(
    name: "Syrup", per100Units: Nutrients(calories: 500, carbohydrates: 125), unit: .milliliters)
  let portion = FoodPortion(product: syrup, amount: 20)
  try portion.validate()
  #expect(portion.nutrients.calories == 100)
  #expect(portion.nutrients.carbohydrates == 25)
  #expect(throws: NutritionError.self) { try syrup.per100Units.validate(unit: .grams) }
  let powder =
    #"{"code":"12345678","product_name":"Powder","product_quantity_unit":"g","serving_size":"5 g in 200 ml water","nutriments":{"energy-kcal_100g":100,"proteins_100g":10,"fat_100g":2,"carbohydrates_100g":10}}"#
  let product = try JSONDecoder().decode(OpenFoodFactsProduct.self, from: Data(powder.utf8))
    .product()
  #expect(product?.unit == .grams)
}

@Test func nutritionWaterGoalIsAnAdditivePayloadAndWaterValidatesBeforeSaving() throws {
  let legacy = Data(#"{"calories":2200,"protein":100}"#.utf8)
  let goal = try JSONDecoder().decode(NutritionGoal.self, from: legacy)
  #expect(goal.waterMilliliters == nil)
  let updated = NutritionGoal(calories: 2200, waterMilliliters: 1800)
  #expect(
    try JSONDecoder().decode(NutritionGoal.self, from: JSONEncoder().encode(updated)) == updated)
  for amount in [0, -1, Double.nan, Double.infinity, 10_001] {
    #expect(throws: NutritionError.self) { try WaterEntry(milliliters: amount).validate() }
    #expect(throws: NutritionError.self) {
      try NutritionGoal(calories: 2200, waterMilliliters: amount).validate()
    }
  }
}

@Test @MainActor func nutritionBatchCopyRejectsWholeBatchWithoutPartialData() throws {
  let repository = MemoryNutritionRepository()
  let original = FoodEntry(title: "Original", portions: [FoodPortion(product: food())])
  try repository.saveFoodEntry(original)
  let first = original.repeated(on: original.date)
  var invalid = first.repeated(on: original.date)
  invalid.portions[0].amount = -1
  #expect(throws: NutritionError.self) { try repository.saveFoodEntries([first, invalid]) }
  #expect(try repository.foodEntries() == [original])
  #expect(throws: NutritionError.self) { try repository.saveFoodEntries([first, first]) }
  #expect(try repository.foodEntries() == [original])
  let second = original.repeated(on: original.date)
  try repository.saveFoodEntries([first, second])
  #expect(Set(try repository.foodEntries().map(\.id)) == [original.id, first.id, second.id])
}

@Test @MainActor func nutritionFavoritesAreIndependentFromEntriesAndDoNotMutateProductSnapshots()
  throws
{
  let repository = MemoryNutritionRepository()
  let product = food()
  let entry = FoodEntry(title: "Food", portions: [FoodPortion(product: product)])
  try repository.saveFoodEntry(entry)
  try repository.setFavoriteFoodProduct(product, isFavorite: true)
  var updated = product
  updated.name = "Updated food"
  try repository.setFavoriteFoodProduct(updated, isFavorite: true)
  #expect(try repository.favoriteFoodProducts() == [updated])
  #expect(try repository.foodEntries().first?.portions.first?.product == product)
  try repository.deleteFoodEntry(id: entry.id)
  #expect(try repository.favoriteFoodProducts() == [updated])
  try repository.setFavoriteFoodProduct(updated, isFavorite: false)
  #expect(try repository.favoriteFoodProducts().isEmpty)
}

@Test func nutritionWeekKeepsMissingDaysAndPhotoOnlyDaysDistinctAcrossDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let end = try #require(ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z"))
  let source = try #require(calendar.date(byAdding: .day, value: -2, to: end))
  let entries = [
    FoodEntry(date: source, title: "Photo", photo: Data([0xFF, 0xD8, 0xFF])),
    FoodEntry(date: end, title: "Food", portions: [FoodPortion(product: food())]),
  ]
  let water = [WaterEntry(date: source, milliliters: 250)]
  let week = NutritionDaySummary.week(
    ending: end, entries: entries, water: water, calendar: calendar)
  #expect(week.count == 7)
  #expect(Set(week.map { calendar.startOfDay(for: $0.date) }).count == 7)
  #expect(week.map(\.entryCount) == [0, 0, 0, 0, 1, 0, 1])
  #expect(week[4].incompleteCount == 1 && week[4].waterMilliliters == 250)
  #expect(week[6].total.calories == 200)
  let copied = NutritionCalendar.date(
    on: end, timeOf: source.addingTimeInterval(0.75), calendar: calendar)
  #expect(calendar.isDate(copied, inSameDayAs: end))
  #expect(calendar.component(.hour, from: copied) == calendar.component(.hour, from: source))
  #expect(abs(copied.timeIntervalSince1970 - floor(copied.timeIntervalSince1970) - 0.75) < 0.0001)
}

@Test func foodBarcodesKeepLeadingZeroAndRejectURLsAndOtherPayloads() {
  #expect(FoodBarcode.normalized(" 0123456789012\n") == "0123456789012")
  for code in [
    "", "123", "123456789012345", "１２３４５６７８", "https://example.com", "1234 5678", "1234567x",
  ] {
    #expect(FoodBarcode.normalized(code) == nil)
  }
}
