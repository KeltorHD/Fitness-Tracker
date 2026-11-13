import Foundation

public enum SupplementKind: String, Codable, CaseIterable, Sendable {
  case creatine, protein, massGainer, other

  public var title: String {
    switch self {
    case .creatine: "Креатин"
    case .protein: "Протеин"
    case .massGainer: "Гейнер"
    case .other: "Другая добавка"
    }
  }
  public var normallyTracksNutrition: Bool { self == .protein || self == .massGainer }
}

public enum SupplementUnit: String, Codable, CaseIterable, Sendable {
  case grams, milligrams, milliliters, servings, capsules, tablets

  public var symbol: String {
    switch self {
    case .grams: "г"
    case .milligrams: "мг"
    case .milliliters: "мл"
    case .servings: "порц."
    case .capsules: "капс."
    case .tablets: "табл."
    }
  }
  public var nutritionBasis: Double {
    switch self {
    case .grams, .milliliters: 100
    case .milligrams: 1000
    case .servings, .capsules, .tablets: 1
    }
  }
  public var nutritionTitle: String {
    switch self {
    case .grams: "КБЖУ на 100 г"
    case .milligrams: "КБЖУ на 1000 мг"
    case .milliliters: "КБЖУ на 100 мл"
    case .servings: "КБЖУ на 1 порцию"
    case .capsules: "КБЖУ на 1 капсулу"
    case .tablets: "КБЖУ на 1 таблетку"
    }
  }
  public var maximumAmount: Double { self == .milligrams ? 10_000_000 : 10_000 }
}

/// One actual intake, independent of food portions. Nutrition is optional and never invented.
public struct SupplementEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public let schemaVersion: Int
  public var date: Date
  public var kind: SupplementKind
  public var name: String
  public var amount: Double
  public var unit: SupplementUnit
  public var includesNutrition: Bool
  public var nutritionPerBasis: Nutrients?
  public var note: String

  public init(
    id: UUID = UUID(), date: Date = Date(), kind: SupplementKind, name: String = "",
    amount: Double, unit: SupplementUnit = .grams, includesNutrition: Bool? = nil,
    nutritionPerBasis: Nutrients? = nil, note: String = ""
  ) {
    self.id = id
    schemaVersion = 1
    self.date = date
    self.kind = kind
    self.name = name
    self.amount = amount
    self.unit = unit
    self.includesNutrition = includesNutrition ?? kind.normallyTracksNutrition
    self.nutritionPerBasis = nutritionPerBasis
    self.note = note
  }

  public var nutrients: Nutrients? {
    includesNutrition ? nutritionPerBasis?.scaled(by: amount / unit.nutritionBasis) : nil
  }
  public var needsNutrition: Bool { includesNutrition && nutritionPerBasis == nil }

  public func validate() throws {
    guard schemaVersion == 1, date.timeIntervalSince1970.isFinite,
      name.count <= 300, note.count <= 2000,
      kind != .other || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      amount.isFinite, amount > 0, amount <= unit.maximumAmount,
      includesNutrition || nutritionPerBasis == nil
    else { throw NutritionError.invalidSupplement }
    if let value = nutritionPerBasis {
      do {
        switch unit {
        case .grams: try value.validate()
        case .milligrams: try value.scaled(by: 100).validate()
        case .milliliters: try value.validate(unit: .milliliters)
        case .servings, .capsules, .tablets:
          // An actual serving has no assumed mass or density; only bounded values are accepted.
          guard
            [value.calories, value.protein, value.fat, value.carbohydrates].allSatisfy({
              $0.isFinite && $0 >= 0
            }), value.calories <= 10_000,
            value.protein + value.fat + value.carbohydrates <= 1000
          else { throw NutritionError.invalidSupplementNutrition }
        }
      } catch { throw NutritionError.invalidSupplementNutrition }
    }
  }

  public func repeated(on date: Date) -> Self {
    var copy = self
    copy.id = UUID()
    copy.date = date
    return copy
  }
}
