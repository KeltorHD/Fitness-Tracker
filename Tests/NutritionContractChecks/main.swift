import FitLifeCore
import Foundation

@main struct NutritionContractChecks {
  static func values() throws -> [TrainingValue] {
    let date = Date(timeIntervalSince1970: 1_700_000_000.125)
    func id(_ number: Int) -> UUID {
      UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, UInt8(number)))
    }
    let product = FoodProduct(
      id: "off:12345678", name: "Продукт", brand: "Бренд",
      per100Units: Nutrients(calories: 240, protein: 20, fat: 10, carbohydrates: 12),
      imageURL: URL(string: "https://example.com/product.jpg"),
      sourceURL: URL(string: "https://example.com/product"), barcode: "12345678")
    let food = FoodEntry(
      id: id(1), date: date, meal: .lunch, title: "Обед",
      portions: [FoodPortion(id: id(2), product: product, amount: 123.456789)], note: "Заметка",
      photo: Data([255, 216, 255, 0, 1, 2, 3]), isSavedMeal: true)
    let protein = SupplementEntry(
      id: id(3), date: date, kind: .protein, name: "Протеин", amount: 30.123456789,
      nutritionPerBasis: Nutrients(calories: 380, protein: 75, fat: 5, carbohydrates: 9),
      note: "Состав с упаковки")
    let plan = SupplementPlan(
      prototype: protein, recurrence: .weekdays, weekdays: [2, 4, 6], times: [540, 1200],
      startDate: date, endDate: date.addingTimeInterval(86400 * 21), timeZoneID: "Europe/Moscow",
      remindersEnabled: true)
    var result: [TrainingValue] = [
      .foodEntry(food), .waterEntry(WaterEntry(id: id(4), date: date, milliliters: 250.25)),
      .supplementPlan(plan),
      .supplementEntry(plan.intake(scheduledFor: date, takenAt: date.addingTimeInterval(300))),
      .nutritionProfile(
        NutritionProfile(
          goal: NutritionGoal(
            calories: 2350, protein: 120, fat: 80, carbohydrates: 250, waterMilliliters: 2000),
          favorites: [product])),
    ]
    for (index, unit) in SupplementUnit.allCases.enumerated() {
      result.append(
        .supplementEntry(
          SupplementEntry(
            id: id(10 + index), date: date, kind: .other, name: "Добавка", amount: 1.25, unit: unit,
            includesNutrition: true,
            nutritionPerBasis: Nutrients(calories: 1, protein: 0.5, fat: 0, carbohydrates: 0))))
    }
    for value in result { try value.validate() }
    return result
  }
  static func main() throws {
    let values = try values()
    let arguments = CommandLine.arguments
    if arguments.count == 3, arguments[1] == "--write" {
      try TrainingCoding.encoder().encode(values).write(to: URL(fileURLWithPath: arguments[2]))
    } else if arguments.count == 3, arguments[1] == "--server-page" {
      let page = try TrainingCoding.decoder().decode(
        TrainingPage.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
      guard page.changes.map(\.value) == values.map(Optional.some) else {
        throw TrainingSyncError.invalidData
      }
    } else {
      let data = try Data(
        contentsOf: URL(fileURLWithPath: "Tests/Server/Fixtures/nutrition-contract.json"))
      guard try TrainingCoding.decoder().decode([TrainingValue].self, from: data) == values else {
        throw TrainingSyncError.invalidData
      }
    }
    print("Nutrition contract verified using Swift Core.")
  }
}
