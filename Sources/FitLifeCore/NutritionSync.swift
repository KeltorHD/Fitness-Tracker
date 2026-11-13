import Foundation

/// One account-level aggregate: concurrent edits are resolved with the same explicit CAS as workouts.
public struct NutritionProfile: Codable, Equatable, Sendable {
  public static let recordID = StableIdentifier.uuid("com.fitlife.nutrition-profile")
  public var id: UUID
  public var goal: NutritionGoal?
  public var favorites: [FoodProduct]
  public init(goal: NutritionGoal?, favorites: [FoodProduct]) {
    id = Self.recordID
    self.goal = goal
    self.favorites = favorites.sorted { $0.id < $1.id }
  }
  public func validate() throws {
    guard id == Self.recordID, favorites.count <= 500,
      Set(favorites.map(\.id)).count == favorites.count,
      favorites.map(\.id) == favorites.map(\.id).sorted()
    else { throw NutritionError.invalidEntry }
    try goal?.validate()
    for product in favorites { try product.validate() }
  }
}

public struct NutritionSnapshot: Sendable {
  public var entries: [FoodEntry]
  public var water: [WaterEntry]
  public var supplements: [SupplementEntry]
  public var plans: [SupplementPlan]
  public var profile: NutritionProfile?
  public init(
    entries: [FoodEntry] = [], water: [WaterEntry] = [], supplements: [SupplementEntry] = [],
    plans: [SupplementPlan] = [], profile: NutritionProfile? = nil
  ) {
    self.entries = entries
    self.water = water
    self.supplements = supplements
    self.plans = plans
    self.profile = profile
  }
  public var values: [TrainingValue] {
    entries.map(TrainingValue.foodEntry) + water.map(TrainingValue.waterEntry)
      + supplements.map(TrainingValue.supplementEntry) + plans.map(TrainingValue.supplementPlan)
      + (profile.map { [TrainingValue.nutritionProfile($0)] } ?? [])
  }
}

extension NutritionRepository {
  public func currentNutritionValue(_ key: TrainingRecordKey) throws -> TrainingValue? {
    switch key.kind {
    case .foodEntry: return try foodEntries().first { $0.id == key.id }.map(TrainingValue.foodEntry)
    case .waterEntry:
      return try waterEntries().first { $0.id == key.id }.map(TrainingValue.waterEntry)
    case .supplementEntry:
      return try supplementEntries().first { $0.id == key.id }.map(TrainingValue.supplementEntry)
    case .supplementPlan:
      return try supplementPlans().first { $0.id == key.id }.map(TrainingValue.supplementPlan)
    case .nutritionProfile:
      guard key.id == NutritionProfile.recordID else { throw TrainingSyncError.invalidData }
      let goal = try nutritionGoal()
      let favorites = try favoriteFoodProducts()
      return goal == nil && favorites.isEmpty
        ? nil : .nutritionProfile(NutritionProfile(goal: goal, favorites: favorites))
    default: throw TrainingSyncError.invalidData
    }
  }
  public func nutritionSnapshot() throws -> NutritionSnapshot {
    let goal = try nutritionGoal()
    let favorites = try favoriteFoodProducts()
    return try NutritionSnapshot(
      entries: foodEntries(), water: waterEntries(), supplements: supplementEntries(),
      plans: supplementPlans(),
      profile: goal == nil && favorites.isEmpty
        ? nil : NutritionProfile(goal: goal, favorites: favorites))
  }
}
