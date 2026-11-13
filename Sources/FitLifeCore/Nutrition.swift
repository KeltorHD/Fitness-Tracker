import Foundation

public enum NutritionError: Error, LocalizedError, Sendable {
  case invalidValues, invalidPortion, invalidEntry, invalidPhoto, invalidGoal, invalidWater
  case invalidSupplement, invalidSupplementNutrition, invalidSupplementPlan
  public var errorDescription: String? {
    switch self {
    case .invalidValues:
      "Проверьте КБЖУ: нужны конечные неотрицательные значения на 100 г или 100 мл."
    case .invalidPortion: "Укажите размер порции больше нуля и не больше 10 000."
    case .invalidEntry: "Добавьте продукт или фотографию и проверьте название записи."
    case .invalidPhoto: "Не удалось обработать фото. Выберите другое изображение."
    case .invalidGoal:
      "Укажите положительную цель калорий. Необязательные цели БЖУ тоже должны быть больше нуля."
    case .invalidWater: "Укажите объём воды больше нуля и не больше 10 000 мл."
    case .invalidSupplementPlan: "Проверьте периодичность, время и даты расписания добавки."
    case .invalidSupplement:
      "Проверьте название добавки, дату и положительное количество в выбранных единицах."
    case .invalidSupplementNutrition:
      "Введите все значения КБЖУ с упаковки или оставьте все поля пустыми. Проверьте единицы и значения."
    }
  }
}

/// Energy in kcal, macros in grams. Missing nutrition is never treated as zero.
public struct Nutrients: Codable, Equatable, Sendable {
  public var calories: Double
  public var protein: Double
  public var fat: Double
  public var carbohydrates: Double
  public init(calories: Double = 0, protein: Double = 0, fat: Double = 0, carbohydrates: Double = 0)
  {
    self.calories = calories
    self.protein = protein
    self.fat = fat
    self.carbohydrates = carbohydrates
  }
  public func validate(unit: FoodQuantityUnit = .grams) throws {
    // Values per 100 ml may exceed 100 g, e.g. a dense sugar syrup.
    let massLimit: Double = unit == .grams ? 100 : 1000
    let energyLimit: Double = unit == .grams ? 1000 : 10_000
    guard [calories, protein, fat, carbohydrates].allSatisfy({ $0.isFinite && $0 >= 0 }),
      calories <= energyLimit, protein <= massLimit, fat <= massLimit, carbohydrates <= massLimit,
      protein + fat + carbohydrates <= massLimit * 1.05
    else { throw NutritionError.invalidValues }
  }
  public func scaled(by factor: Double) -> Self {
    Self(
      calories: calories * factor, protein: protein * factor, fat: fat * factor,
      carbohydrates: carbohydrates * factor)
  }
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self(
      calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
      fat: lhs.fat + rhs.fat, carbohydrates: lhs.carbohydrates + rhs.carbohydrates)
  }
}

public enum FoodQuantityUnit: String, CaseIterable, Codable, Sendable {
  case grams, milliliters
  public var symbol: String { self == .grams ? "г" : "мл" }
}

public struct FoodProduct: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var name: String
  public var brand: String
  public var unit: FoodQuantityUnit
  public var per100Units: Nutrients
  public var imageURL: URL?
  public var sourceURL: URL?
  public var barcode: String?
  public init(
    id: String = UUID().uuidString, name: String, brand: String = "",
    per100Units: Nutrients, unit: FoodQuantityUnit = .grams, imageURL: URL? = nil,
    sourceURL: URL? = nil, barcode: String? = nil
  ) {
    self.id = id
    self.name = name
    self.brand = brand
    self.unit = unit
    self.per100Units = per100Units
    self.imageURL = imageURL
    self.sourceURL = sourceURL
    self.barcode = barcode
  }
  public func validate() throws {
    guard !id.isEmpty, id.count <= 100,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 300,
      brand.count <= 300
    else { throw NutritionError.invalidEntry }
    try per100Units.validate(unit: unit)
  }
}

/// Quantity uses the product's basis: grams or milliliters, without assuming a density.
public struct FoodPortion: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var product: FoodProduct
  public var amount: Double
  public init(id: UUID = UUID(), product: FoodProduct, amount: Double = 100) {
    self.id = id
    self.product = product
    self.amount = amount
  }
  public var nutrients: Nutrients { product.per100Units.scaled(by: amount / 100) }
  public func validate() throws {
    try product.validate()
    guard amount.isFinite, amount > 0, amount <= 10_000 else { throw NutritionError.invalidPortion }
  }
}

public enum MealKind: String, CaseIterable, Codable, Sendable {
  case breakfast, lunch, dinner, snack
  public var title: String {
    switch self {
    case .breakfast: "Завтрак"
    case .lunch: "Обед"
    case .dinner: "Ужин"
    case .snack: "Перекус"
    }
  }
}

public struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var date: Date
  public var meal: MealKind
  public var title: String
  public var portions: [FoodPortion]
  public var note: String
  /// Sanitized JPEG, limited to 600 KB. Kept with the aggregate for atomic persistence/CloudKit.
  public var photo: Data?
  public var isSavedMeal: Bool
  public init(
    id: UUID = UUID(), date: Date = Date(), meal: MealKind = .snack,
    title: String = "", portions: [FoodPortion] = [], note: String = "",
    photo: Data? = nil, isSavedMeal: Bool = false
  ) {
    self.id = id
    self.date = date
    self.meal = meal
    self.title = title
    self.portions = portions
    self.note = note
    self.photo = photo
    self.isSavedMeal = isSavedMeal
  }
  public var nutrients: Nutrients { portions.reduce(Nutrients()) { $0 + $1.nutrients } }
  public var needsNutrition: Bool { portions.isEmpty }
  public func validate() throws {
    guard date.timeIntervalSince1970.isFinite,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      title.count <= 300, note.count <= 2000, portions.count <= 100,
      Set(portions.map(\.id)).count == portions.count, !portions.isEmpty || photo != nil
    else { throw NutritionError.invalidEntry }
    for portion in portions { try portion.validate() }
    if let photo {
      guard !photo.isEmpty, photo.count <= 600_000,
        photo.starts(with: [0xFF, 0xD8, 0xFF])
      else { throw NutritionError.invalidPhoto }
    }
  }
  public func repeated(on date: Date) -> Self {
    var copy = self
    copy.id = UUID()
    copy.date = date
    copy.portions = portions.map { FoodPortion(product: $0.product, amount: $0.amount) }
    copy.isSavedMeal = false
    return copy
  }
}

public struct NutritionGoal: Codable, Equatable, Sendable {
  public var calories: Double
  public var protein: Double?
  public var fat: Double?
  public var carbohydrates: Double?
  public var waterMilliliters: Double?
  public init(
    calories: Double, protein: Double? = nil, fat: Double? = nil, carbohydrates: Double? = nil,
    waterMilliliters: Double? = nil
  ) {
    self.calories = calories
    self.protein = protein
    self.fat = fat
    self.carbohydrates = carbohydrates
    self.waterMilliliters = waterMilliliters
  }
  public func validate() throws {
    guard calories.isFinite, calories > 0, calories <= 20_000,
      [protein, fat, carbohydrates].compactMap({ $0 }).allSatisfy({
        $0.isFinite && $0 > 0 && $0 <= 2000
      })
    else { throw NutritionError.invalidGoal }
    if let waterMilliliters {
      guard waterMilliliters.isFinite, waterMilliliters > 0, waterMilliliters <= 10_000 else {
        throw NutritionError.invalidWater
      }
    }
  }
}

public struct WaterEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var date: Date
  public var milliliters: Double
  public init(id: UUID = UUID(), date: Date = Date(), milliliters: Double) {
    self.id = id
    self.date = date
    self.milliliters = milliliters
  }
  public func validate() throws {
    guard date.timeIntervalSince1970.isFinite, milliliters.isFinite,
      milliliters > 0, milliliters <= 10_000
    else { throw NutritionError.invalidWater }
  }
}

public enum NutritionCalendar {
  public static func date(on day: Date, timeOf source: Date, calendar: Calendar) -> Date {
    let time = calendar.dateComponents([.hour, .minute, .second], from: source)
    let resolved =
      calendar.date(
        bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
      ?? calendar.startOfDay(for: day)
    let fraction = source.timeIntervalSince1970 - floor(source.timeIntervalSince1970)
    return resolved.addingTimeInterval(fraction)
  }
}

public struct NutritionDaySummary: Identifiable, Equatable, Sendable {
  public var id: Date { date }
  public let date: Date
  public let total: Nutrients
  public let incompleteCount: Int
  public let waterMilliliters: Double
  public let entryCount: Int

  public static func week(
    ending date: Date, entries: [FoodEntry], water: [WaterEntry], calendar: Calendar,
    supplements: [SupplementEntry] = []
  ) -> [Self] {
    (-6...0).compactMap { offset in
      guard
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))
      else { return nil }
      let nutrition = NutritionDay(
        entries: entries, date: day, calendar: calendar, supplements: supplements)
      return Self(
        date: day, total: nutrition.total, incompleteCount: nutrition.incompleteCount,
        waterMilliliters: water.filter { calendar.isDate($0.date, inSameDayAs: day) }
          .reduce(0) { $0 + $1.milliliters }, entryCount: nutrition.nutritionEntryCount)
    }
  }
}

public enum FoodBarcode {
  public static func normalized(_ value: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (8...14).contains(value.count), value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      return nil
    }
    return value
  }
}

public struct NutritionDay: Equatable, Sendable {
  public let entries: [FoodEntry]
  public let supplements: [SupplementEntry]
  public let total: Nutrients
  public let incompleteCount: Int
  public var nutritionEntryCount: Int {
    entries.count + supplements.filter(\.includesNutrition).count
  }
  public init(
    entries: [FoodEntry], date: Date, calendar: Calendar = .current,
    supplements: [SupplementEntry] = []
  ) {
    self.entries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
      .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    self.supplements = supplements.filter { calendar.isDate($0.date, inSameDayAs: date) }
      .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    total =
      self.entries.reduce(Nutrients()) { $0 + $1.nutrients }
      + self.supplements.compactMap(\.nutrients).reduce(Nutrients(), +)
    incompleteCount =
      self.entries.filter(\.needsNutrition).count
      + self.supplements.filter(\.needsNutrition).count
  }
}

@MainActor public protocol NutritionRepository {
  func foodEntries() throws -> [FoodEntry]
  func saveFoodEntry(_ entry: FoodEntry) throws
  func saveFoodEntries(_ entries: [FoodEntry]) throws
  func deleteFoodEntry(id: UUID) throws
  func nutritionGoal() throws -> NutritionGoal?
  func saveNutritionGoal(_ goal: NutritionGoal?) throws
  func waterEntries() throws -> [WaterEntry]
  func saveWaterEntry(_ entry: WaterEntry) throws
  func deleteWaterEntry(id: UUID) throws
  func supplementEntries() throws -> [SupplementEntry]
  func saveSupplementEntry(_ entry: SupplementEntry) throws
  func deleteSupplementEntry(id: UUID) throws
  func supplementPlans() throws -> [SupplementPlan]
  func saveSupplementPlan(_ plan: SupplementPlan) throws
  func deleteSupplementPlan(id: UUID) throws
  func favoriteFoodProducts() throws -> [FoodProduct]
  func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws
}

@MainActor public final class MemoryNutritionRepository: NutritionRepository {
  private var entries: [UUID: FoodEntry] = [:]
  private var goal: NutritionGoal?
  private var water: [UUID: WaterEntry] = [:]
  private var supplements: [UUID: SupplementEntry] = [:]
  private var plans: [UUID: SupplementPlan] = [:]
  private var favorites: [String: FoodProduct] = [:]
  public init() {}
  public func foodEntries() throws -> [FoodEntry] { Array(entries.values) }
  public func saveFoodEntry(_ entry: FoodEntry) throws {
    try saveFoodEntries([entry])
  }
  public func saveFoodEntries(_ values: [FoodEntry]) throws {
    guard Set(values.map(\.id)).count == values.count else { throw NutritionError.invalidEntry }
    for entry in values { try entry.validate() }
    for entry in values { entries[entry.id] = entry }
  }
  public func deleteFoodEntry(id: UUID) throws { entries[id] = nil }
  public func nutritionGoal() throws -> NutritionGoal? { goal }
  public func saveNutritionGoal(_ goal: NutritionGoal?) throws {
    try goal?.validate()
    self.goal = goal
  }
  public func waterEntries() throws -> [WaterEntry] { Array(water.values) }
  public func saveWaterEntry(_ entry: WaterEntry) throws {
    try entry.validate()
    water[entry.id] = entry
  }
  public func deleteWaterEntry(id: UUID) throws { water[id] = nil }
  public func supplementEntries() throws -> [SupplementEntry] { Array(supplements.values) }
  public func saveSupplementEntry(_ entry: SupplementEntry) throws {
    try entry.validate()
    supplements[entry.id] = entry
  }
  public func deleteSupplementEntry(id: UUID) throws { supplements[id] = nil }
  public func supplementPlans() throws -> [SupplementPlan] { Array(plans.values) }
  public func saveSupplementPlan(_ plan: SupplementPlan) throws {
    try plan.validate()
    plans[plan.id] = plan
  }
  public func deleteSupplementPlan(id: UUID) throws { plans[id] = nil }
  public func favoriteFoodProducts() throws -> [FoodProduct] { Array(favorites.values) }
  public func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws {
    try product.validate()
    guard !isFavorite || favorites[product.id] != nil || favorites.count < 500 else {
      throw NutritionError.invalidEntry
    }
    favorites[product.id] = isFavorite ? product : nil
  }
  public func applyTrainingChanges(_ changes: [TrainingChange]) throws {
    for change in changes { try change.value?.validate() }
    for change in changes {
      switch change.value {
      case .foodEntry(let entry): entries[entry.id] = entry
      case .waterEntry(let entry): water[entry.id] = entry
      case .supplementEntry(let entry): supplements[entry.id] = entry
      case .supplementPlan(let plan): plans[plan.id] = plan
      case .nutritionProfile(let profile):
        goal = profile.goal
        favorites = Dictionary(uniqueKeysWithValues: profile.favorites.map { ($0.id, $0) })
      case nil:
        switch change.key.kind {
        case .foodEntry: entries[change.key.id] = nil
        case .waterEntry: water[change.key.id] = nil
        case .supplementEntry: supplements[change.key.id] = nil
        case .supplementPlan: plans[change.key.id] = nil
        case .nutritionProfile:
          goal = nil
          favorites = [:]
        default: break
        }
      default: break
      }
    }
  }

}
