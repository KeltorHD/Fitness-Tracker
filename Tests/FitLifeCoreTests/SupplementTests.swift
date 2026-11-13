import Foundation
import Testing

@testable import FitLifeCore

private let supplementDate = Date(timeIntervalSince1970: 1_700_000_000)

@Test(arguments: SupplementUnit.allCases)
func supplementNutritionUsesTheDeclaredBasis(_ unit: SupplementUnit) throws {
  let values = Nutrients(calories: 4, protein: 1)
  let entry = SupplementEntry(
    date: supplementDate, kind: .protein, amount: unit.nutritionBasis * 2, unit: unit,
    nutritionPerBasis: values)
  try entry.validate()
  #expect(entry.nutrients == Nutrients(calories: 8, protein: 2))
  #expect(!entry.needsNutrition)
  #expect(
    try JSONDecoder().decode(SupplementEntry.self, from: JSONEncoder().encode(entry)) == entry)
}

@Test(arguments: [0, -1, 10_001, Double.nan, .infinity, -.infinity])
func supplementRejectsInvalidAmounts(_ amount: Double) {
  #expect(throws: NutritionError.self) {
    try SupplementEntry(kind: .creatine, amount: amount).validate()
  }
}

@Test func supplementRequiresCustomNameAndValidVersionWithoutDefaultingBadValues() throws {
  #expect(throws: NutritionError.self) {
    try SupplementEntry(kind: .other, name: " \n ", amount: 1, unit: .capsules).validate()
  }
  let value = SupplementEntry(
    date: supplementDate, kind: .other, name: "Custom", amount: 1, unit: .capsules, note: "Note")
  try value.validate()
  var json = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  json["schemaVersion"] = 2
  let decoded = try JSONDecoder().decode(
    SupplementEntry.self, from: JSONSerialization.data(withJSONObject: json))
  #expect(throws: NutritionError.self) { try decoded.validate() }
  var invalid = value
  invalid.date = Date(timeIntervalSince1970: .nan)
  #expect(throws: NutritionError.self) { try invalid.validate() }
  invalid = value
  invalid.note = String(repeating: "x", count: 2001)
  #expect(throws: NutritionError.self) { try invalid.validate() }
}

@Test func unknownSupplementNutritionIsDistinctFromExplicitZeroAndExcludedIntake() throws {
  let creatine = SupplementEntry(date: supplementDate, kind: .creatine, amount: 5)
  let unknown = SupplementEntry(date: supplementDate, kind: .protein, amount: 30)
  let zero = SupplementEntry(
    date: supplementDate, kind: .protein, amount: 30, nutritionPerBasis: Nutrients())
  try creatine.validate()
  try unknown.validate()
  try zero.validate()
  #expect(creatine.nutrients == nil && !creatine.needsNutrition)
  #expect(unknown.nutrients == nil && unknown.needsNutrition)
  #expect(zero.nutrients == Nutrients() && !zero.needsNutrition)
  let day = NutritionDay(entries: [], date: supplementDate, supplements: [creatine, unknown, zero])
  #expect(day.entries.isEmpty && day.supplements.count == 3)
  #expect(day.nutritionEntryCount == 2 && day.incompleteCount == 1)
}

@Test func supplementValidatesNutritionAgainstMassAndServingUnits() throws {
  for value in [Double.nan, .infinity, -1] {
    #expect(throws: NutritionError.self) {
      try SupplementEntry(kind: .protein, amount: 30, nutritionPerBasis: Nutrients(calories: value))
        .validate()
    }
  }
  #expect(throws: NutritionError.self) {
    try SupplementEntry(
      kind: .protein, amount: 30,
      nutritionPerBasis: Nutrients(protein: 80, fat: 80)
    ).validate()
  }
  #expect(throws: NutritionError.self) {
    try SupplementEntry(
      kind: .protein, amount: 30, includesNutrition: false,
      nutritionPerBasis: Nutrients(calories: 400)
    ).validate()
  }
  #expect(throws: NutritionError.self) {
    try SupplementEntry(
      kind: .other, name: "Custom", amount: 1, unit: .capsules,
      includesNutrition: true, nutritionPerBasis: Nutrients(calories: 10_001)
    ).validate()
  }
}

@Test func supplementsAddKnownMacrosOnceWithoutBecomingFoodEntries() throws {
  let product = FoodProduct(name: "Food", per100Units: Nutrients(calories: 200, protein: 10))
  let food = FoodEntry(
    date: supplementDate, title: "Food", portions: [FoodPortion(product: product)])
  let protein = SupplementEntry(
    date: supplementDate, kind: .protein, amount: 30,
    nutritionPerBasis: Nutrients(calories: 400, protein: 80, fat: 5, carbohydrates: 10))
  let gainer = SupplementEntry(
    date: supplementDate, kind: .massGainer, amount: 50,
    nutritionPerBasis: Nutrients(calories: 380, protein: 20, fat: 5, carbohydrates: 65))
  let day = NutritionDay(entries: [food], date: supplementDate, supplements: [protein, gainer])
  #expect(day.entries == [food])
  #expect(day.nutritionEntryCount == 3 && day.incompleteCount == 0)
  #expect(day.total == Nutrients(calories: 510, protein: 44, fat: 4, carbohydrates: 35.5))
}

@Test func supplementCalendarAndWeekUseLocalDaysAcrossDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
  let next = try #require(calendar.date(byAdding: .day, value: 1, to: date))
  #expect(next.timeIntervalSince(date) == 23 * 3600)
  let first = SupplementEntry(
    date: date, kind: .protein, amount: 100,
    nutritionPerBasis: Nutrients(calories: 400, protein: 80))
  let last = SupplementEntry(date: next.addingTimeInterval(-1), kind: .creatine, amount: 5)
  let tomorrow = first.repeated(on: next)
  let day = NutritionDay(
    entries: [], date: date, calendar: calendar, supplements: [tomorrow, last, first])
  #expect(day.supplements == [first, last])
  #expect(day.total.calories == 400)
  let week = NutritionDaySummary.week(
    ending: date, entries: [], water: [], calendar: calendar,
    supplements: [first, last, tomorrow])
  #expect(week.count == 7 && week.last?.entryCount == 1)
  #expect(week.last?.total.calories == 400)
}

@Test @MainActor func supplementRepositoryKeepsPreviousValuesAfterInvalidUpdate() throws {
  let repository = MemoryNutritionRepository()
  var entry = SupplementEntry(date: supplementDate, kind: .creatine, amount: 5)
  try repository.saveSupplementEntry(entry)
  try repository.saveSupplementEntry(entry)
  #expect(try repository.supplementEntries() == [entry])
  entry.amount = -1
  #expect(throws: NutritionError.self) { try repository.saveSupplementEntry(entry) }
  #expect(try repository.supplementEntries().first?.amount == 5)
  let original = try #require(try repository.supplementEntries().first)
  let copy = original.repeated(on: supplementDate.addingTimeInterval(3600))
  #expect(copy.id != original.id && copy.kind == original.kind && copy.amount == original.amount)
  try repository.saveSupplementEntry(copy)
  try repository.deleteSupplementEntry(id: original.id)
  #expect(try repository.supplementEntries() == [copy])
}
