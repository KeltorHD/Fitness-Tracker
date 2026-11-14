import FitLifeCore
import Foundation
import SwiftData

/// CloudKit-compatible schema: defaults on every nonoptional property, no unique constraints.
/// A record holds one versioned aggregate; concurrent edits use last-writer-wins per aggregate.
@Model final class StoredRecord {
  var recordID: UUID = UUID()
  var kind: String = "workout"
  var payload: Data = Data()
  var modifiedAt: Date = Date()
  var schemaVersion: Int = 1
  init(id: UUID, kind: String, payload: Data) {
    self.recordID = id
    self.kind = kind
    self.payload = payload
  }
}

@MainActor final class SwiftDataWorkoutRepository: TrainingAccountRepository {
  let container: ModelContainer
  private let context: ModelContext
  private(set) var trainingAccountSelection = TrainingAccountSelection()
  private static let scopeRecordID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
  init(inMemory: Bool = false, cloudEnabled: Bool = false) throws {
    let schema = Schema([StoredRecord.self])
    let cloudID =
      Bundle.main.object(forInfoDictionaryKey: "FitLifeCloudContainer") as? String ?? ""
    let configuration = ModelConfiguration(
      AppIdentifiers.storeConfiguration, schema: schema, isStoredInMemoryOnly: inMemory,
      groupContainer: .none,
      cloudKitDatabase: cloudEnabled && !inMemory && AppCapabilities.current.supportsCloudSync
        ? .private(cloudID) : .none)
    container = try ModelContainer(for: schema, configurations: [configuration])
    context = ModelContext(container)
    context.autosaveEnabled = false
    let scopeRecords = try allRecords(kind: "trainingScope")
    guard scopeRecords.count <= 1 else { throw TrainingSyncError.invalidData }
    if let metadata = scopeRecords.first {
      guard metadata.recordID == Self.scopeRecordID else { throw TrainingSyncError.invalidData }
      trainingAccountSelection = try JSONDecoder().decode(
        TrainingAccountSelection.self, from: metadata.payload)
      guard trainingAccountSelection.firstAccountID != nil,
        trainingAccountSelection.currentAccountID != nil
      else { throw TrainingSyncError.invalidData }
      try trainingAccountSelection.validate()
    }
    try migrateNutrition()
  }
  func workouts() throws -> [Workout] {
    try records(kind: "workout").map {
      let value = try JSONDecoder().decode(Workout.self, from: $0.payload)
      try Validation.workout(value)
      return value
    }.sorted { $0.startedAt > $1.startedAt }
  }
  func templates() throws -> [WorkoutTemplate] {
    try records(kind: "template").map {
      let value = try JSONDecoder().decode(WorkoutTemplate.self, from: $0.payload)
      try Validation.template(value)
      return value
    }.sorted { $0.name < $1.name }
  }
  func save(_ workout: Workout) throws {
    try Validation.workout(workout)
    try upsert(id: workout.id, kind: "workout", data: JSONEncoder().encode(workout))
  }
  func saveTemplate(_ template: WorkoutTemplate) throws {
    try Validation.template(template)
    try upsert(id: template.id, kind: "template", data: JSONEncoder().encode(template))
  }
  func deleteWorkout(id: UUID) throws { try remove(id: id, kind: "workout") }
  func deleteTemplate(id: UUID) throws { try remove(id: id, kind: "template") }
  func exerciseLinks() throws -> [ExerciseLink] {
    try records(kind: "exerciseLink").map {
      let link = try JSONDecoder().decode(ExerciseLink.self, from: $0.payload)
      guard link.id == $0.recordID else { throw TrainingSyncError.invalidData }
      try link.validate()
      return link
    }.sorted { $0.id.uuidString < $1.id.uuidString }
  }
  func saveExerciseLink(_ link: ExerciseLink) throws {
    try link.validate()
    try upsert(id: link.id, kind: "exerciseLink", data: JSONEncoder().encode(link))
  }
  func deleteExerciseLink(id: UUID) throws { try remove(id: id, kind: "exerciseLink") }
  func bodyWeights() throws -> [BodyWeightEntry] {
    try records(kind: "bodyWeight").map {
      let entry = try JSONDecoder().decode(BodyWeightEntry.self, from: $0.payload)
      try Validation.bodyWeightEntry(entry)
      return entry
    }.sorted {
      $0.measuredAt == $1.measuredAt
        ? $0.id.uuidString < $1.id.uuidString : $0.measuredAt > $1.measuredAt
    }
  }
  func saveBodyWeight(_ entry: BodyWeightEntry) throws {
    try Validation.bodyWeightEntry(entry)
    try upsert(id: entry.id, kind: "bodyWeight", data: JSONEncoder().encode(entry))
  }
  func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws {
    try Validation.bodyWeightEntry(entry)
    if let workout { try Validation.workout(workout) }
    let entryData = try JSONEncoder().encode(entry)
    let workoutData = try workout.map { try JSONEncoder().encode($0) }
    do {
      try stageUpsert(id: entry.id, kind: "bodyWeight", data: entryData)
      if let workout, let workoutData {
        try stageUpsert(id: workout.id, kind: "workout", data: workoutData)
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  func deleteBodyWeight(id: UUID) throws { try remove(id: id, kind: "bodyWeight") }
  func deleteBodyWeight(id: UUID, updating workout: Workout?) throws {
    if let workout { try Validation.workout(workout) }
    let workoutData = try workout.map { try JSONEncoder().encode($0) }
    do {
      for record in try allRecords(kind: "bodyWeight") where record.recordID == id {
        context.delete(record)
      }
      if let workout, let workoutData {
        try stageUpsert(id: workout.id, kind: "workout", data: workoutData)
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    let plan = try ArchiveImportPlan(
      archive: archive, existingWorkouts: self.workouts(), existingTemplates: self.templates(),
      existingBodyWeights: self.bodyWeights())
    // Encode everything before changing the context. One save commits the entire import.
    let workouts = try plan.workouts.map { ($0.id, try JSONEncoder().encode($0)) }
    let templates = try plan.templates.map { ($0.id, try JSONEncoder().encode($0)) }
    let bodyWeights = try plan.bodyWeights.map { ($0.id, try JSONEncoder().encode($0)) }
    guard plan.summary.hasChanges else { return plan.summary }
    do {
      for (id, data) in workouts {
        context.insert(StoredRecord(id: id, kind: storageKind("workout"), payload: data))
      }
      for (id, data) in templates {
        context.insert(StoredRecord(id: id, kind: storageKind("template"), payload: data))
      }
      for (id, data) in bodyWeights {
        context.insert(StoredRecord(id: id, kind: storageKind("bodyWeight"), payload: data))
      }
      try context.save()
      return plan.summary
    } catch {
      context.rollback()
      throw error
    }
  }
  private func allRecords(kind: String) throws -> [StoredRecord] {
    try rawRecords(kind: storageKind(kind))
  }
  private func rawRecords(kind: String) throws -> [StoredRecord] {
    try context.fetch(
      FetchDescriptor<StoredRecord>(
        predicate: #Predicate { $0.kind == kind },
        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]))
  }
  private func records(kind: String) throws -> [StoredRecord] {
    var seen = Set<UUID>()
    return try allRecords(kind: kind).filter { seen.insert($0.recordID).inserted }
  }
  private func upsert(id: UUID, kind: String, data: Data) throws {
    do {
      try stageUpsert(id: id, kind: kind, data: data)
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  private func stageUpsert(id: UUID, kind: String, data: Data) throws {
    let matches = try allRecords(kind: kind).filter { $0.recordID == id }
    if let record = matches.first {
      record.payload = data
      record.modifiedAt = Date()
      for duplicate in matches.dropFirst() { context.delete(duplicate) }
    } else {
      context.insert(StoredRecord(id: id, kind: storageKind(kind), payload: data))
    }
  }
  private func remove(id: UUID, kind: String) throws {
    do {
      for item in try allRecords(kind: kind) where item.recordID == id { context.delete(item) }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }

  private func storageKind(_ kind: String, account: String? = nil) -> String {
    guard
      (["workout", "template", "bodyWeight", "exerciseLink"] + Self.nutritionKinds).contains(kind),
      let account = account ?? trainingAccountSelection.currentAccountID
    else { return kind }
    return kind + "@" + account
  }

  func activateTrainingAccount(_ namespace: String) throws {
    try TrainingAccountSelection(firstAccountID: namespace, currentAccountID: namespace).validate()
    guard trainingAccountSelection.currentAccountID != namespace else { return }
    if trainingAccountSelection.firstAccountID != nil,
      try workouts().contains(where: { [.active, .paused].contains($0.status) })
    {
      throw TrainingSyncError.activeWorkout
    }
    var selection = trainingAccountSelection
    do {
      try migrateNutrition(adopting: namespace, commit: false)
      if selection.firstAccountID == nil {
        for kind in ["workout", "template", "bodyWeight", "exerciseLink"] {
          for record in try rawRecords(kind: kind) {
            record.kind = storageKind(kind, account: namespace)
          }
        }
        selection.firstAccountID = namespace
      }
      // Validate the destination before committing the switch; every previous namespace remains.
      for record in try rawRecords(kind: storageKind("workout", account: namespace)) {
        try Validation.workout(JSONDecoder().decode(Workout.self, from: record.payload))
      }
      for record in try rawRecords(kind: storageKind("template", account: namespace)) {
        try Validation.template(JSONDecoder().decode(WorkoutTemplate.self, from: record.payload))
      }
      for record in try rawRecords(kind: storageKind("bodyWeight", account: namespace)) {
        try Validation.bodyWeightEntry(
          JSONDecoder().decode(BodyWeightEntry.self, from: record.payload))
      }
      for record in try rawRecords(kind: storageKind("exerciseLink", account: namespace)) {
        let link = try JSONDecoder().decode(ExerciseLink.self, from: record.payload)
        guard link.id == record.recordID else { throw TrainingSyncError.invalidData }
        try link.validate()
      }
      try validateNutrition(account: namespace)
      selection.currentAccountID = namespace
      try stageUpsert(
        id: Self.scopeRecordID, kind: "trainingScope", data: JSONEncoder().encode(selection))
      try context.save()
      trainingAccountSelection = selection
    } catch {
      context.rollback()
      throw error
    }
  }

  func applyTrainingChanges(_ changes: [TrainingChange]) throws {
    _ = try TrainingJournalSnapshot(
      workouts: workouts(), templates: templates(), bodyWeights: bodyWeights(),
      exerciseLinks: exerciseLinks()
    ).applying(changes)
    do {
      for change in changes {
        switch change.value {
        case .workout(let value):
          try stageUpsert(id: value.id, kind: "workout", data: JSONEncoder().encode(value))
        case .template(let value):
          try stageUpsert(id: value.id, kind: "template", data: JSONEncoder().encode(value))
        case .bodyWeight(let value):
          try stageUpsert(id: value.id, kind: "bodyWeight", data: JSONEncoder().encode(value))
        case .foodEntry(let value):
          try stageUpsert(id: value.id, kind: "foodEntry", data: JSONEncoder().encode(value))
        case .waterEntry(let value):
          try stageUpsert(id: value.id, kind: "waterEntry", data: JSONEncoder().encode(value))
        case .supplementEntry(let value):
          try stageUpsert(id: value.id, kind: "supplementEntry", data: JSONEncoder().encode(value))
        case .supplementPlan(let value):
          try stageUpsert(id: value.id, kind: "supplementPlan", data: JSONEncoder().encode(value))
        case .nutritionProfile(let value):
          try stageUpsert(id: value.id, kind: "nutritionProfile", data: JSONEncoder().encode(value))
        case .exerciseLink(let value):
          try stageUpsert(id: value.id, kind: "exerciseLink", data: JSONEncoder().encode(value))
        case .heartRate: throw TrainingSyncError.invalidData
        case nil:
          for record in try allRecords(kind: change.key.kind.rawValue)
          where record.recordID == change.key.id {
            context.delete(record)
          }
        }
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}

extension SwiftDataWorkoutRepository: NutritionRepository {
  func supplementEntries() throws -> [SupplementEntry] {
    try records(kind: "supplementEntry").map {
      let entry = try JSONDecoder().decode(SupplementEntry.self, from: $0.payload)
      guard entry.id == $0.recordID else { throw NutritionError.invalidSupplement }
      try entry.validate()
      return entry
    }
  }
  func saveSupplementEntry(_ entry: SupplementEntry) throws {
    try entry.validate()
    try upsert(id: entry.id, kind: "supplementEntry", data: JSONEncoder().encode(entry))
  }
  func deleteSupplementEntry(id: UUID) throws { try remove(id: id, kind: "supplementEntry") }
  func foodEntries() throws -> [FoodEntry] {
    try records(kind: "foodEntry").map {
      let entry = try JSONDecoder().decode(FoodEntry.self, from: $0.payload)
      guard entry.id == $0.recordID else { throw NutritionError.invalidEntry }
      try entry.validate()
      return entry
    }
  }
  func saveFoodEntry(_ entry: FoodEntry) throws {
    try entry.validate()
    try upsert(id: entry.id, kind: "foodEntry", data: JSONEncoder().encode(entry))
  }
  func saveFoodEntries(_ entries: [FoodEntry]) throws {
    guard Set(entries.map(\.id)).count == entries.count else { throw NutritionError.invalidEntry }
    let encoded = try entries.map { entry in
      try entry.validate()
      return (entry.id, try JSONEncoder().encode(entry))
    }
    do {
      let existing = try allRecords(kind: "foodEntry")
      for (id, data) in encoded {
        let matches = existing.filter { $0.recordID == id }
        if let record = matches.first {
          record.payload = data
          record.modifiedAt = .now
          for duplicate in matches.dropFirst() { context.delete(duplicate) }
        } else {
          context.insert(StoredRecord(id: id, kind: storageKind("foodEntry"), payload: data))
        }
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  func waterEntries() throws -> [WaterEntry] {
    try records(kind: "waterEntry").map {
      let entry = try JSONDecoder().decode(WaterEntry.self, from: $0.payload)
      guard entry.id == $0.recordID else { throw NutritionError.invalidWater }
      try entry.validate()
      return entry
    }
  }
  func saveWaterEntry(_ entry: WaterEntry) throws {
    try entry.validate()
    try upsert(id: entry.id, kind: "waterEntry", data: JSONEncoder().encode(entry))
  }
  func deleteWaterEntry(id: UUID) throws { try remove(id: id, kind: "waterEntry") }
  func supplementPlans() throws -> [SupplementPlan] {
    try records(kind: "supplementPlan").map {
      let value = try JSONDecoder().decode(SupplementPlan.self, from: $0.payload)
      guard value.id == $0.recordID else { throw NutritionError.invalidSupplementPlan }
      try value.validate()
      return value
    }
  }
  func saveSupplementPlan(_ plan: SupplementPlan) throws {
    try plan.validate()
    try upsert(id: plan.id, kind: "supplementPlan", data: JSONEncoder().encode(plan))
  }
  func deleteSupplementPlan(id: UUID) throws { try remove(id: id, kind: "supplementPlan") }
  private func nutritionProfile() throws -> NutritionProfile? {
    let values = try records(kind: "nutritionProfile")
    guard values.count <= 1 else { throw NutritionError.invalidEntry }
    guard let record = values.first else { return nil }
    let value = try JSONDecoder().decode(NutritionProfile.self, from: record.payload)
    guard value.id == record.recordID else { throw NutritionError.invalidEntry }
    try value.validate()
    return value
  }
  private func saveProfile(_ profile: NutritionProfile) throws {
    try profile.validate()
    if profile.goal == nil && profile.favorites.isEmpty {
      try remove(id: profile.id, kind: "nutritionProfile")
    } else {
      try upsert(id: profile.id, kind: "nutritionProfile", data: JSONEncoder().encode(profile))
    }
  }
  func favoriteFoodProducts() throws -> [FoodProduct] { try nutritionProfile()?.favorites ?? [] }
  func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws {
    try product.validate()
    let profile = try nutritionProfile()
    var favorites = profile?.favorites.filter { $0.id != product.id } ?? []
    if isFavorite { favorites.append(product) }
    try saveProfile(NutritionProfile(goal: profile?.goal, favorites: favorites))
  }
  func deleteFoodEntry(id: UUID) throws { try remove(id: id, kind: "foodEntry") }
  func nutritionGoal() throws -> NutritionGoal? { try nutritionProfile()?.goal }
  func saveNutritionGoal(_ goal: NutritionGoal?) throws {
    try saveProfile(NutritionProfile(goal: goal, favorites: favoriteFoodProducts()))
  }

  private static let nutritionKinds = [
    "foodEntry", "waterEntry", "supplementEntry", "supplementPlan", "nutritionProfile",
  ]

  /// Adopts pre-sync nutrition once into the first account, including stores already signed in.
  /// Legacy goal/favorite rows are consolidated and removed only in the same successful save.
  private func migrateNutrition(adopting namespace: String? = nil, commit: Bool = true) throws {
    let first = trainingAccountSelection.firstAccountID ?? namespace
    func target(_ kind: String) -> String { first.map { kind + "@" + $0 } ?? kind }
    do {
      let goals = try rawRecords(kind: "nutritionGoal")
      let favorites = try rawRecords(kind: "favoriteFoodProduct")
      if !goals.isEmpty || !favorites.isEmpty {
        guard Set(goals.map(\.recordID)).count <= 1 else { throw NutritionError.invalidGoal }
        let profiles = try rawRecords(kind: target("nutritionProfile"))
        guard profiles.allSatisfy({ $0.recordID == NutritionProfile.recordID }) else {
          throw NutritionError.invalidEntry
        }
        let existing = try profiles.first.map {
          try JSONDecoder().decode(NutritionProfile.self, from: $0.payload)
        }
        try existing?.validate()
        let oldGoal = try goals.first.map {
          try JSONDecoder().decode(NutritionGoal.self, from: $0.payload)
        }
        try oldGoal?.validate()
        guard oldGoal == nil || existing?.goal == nil || oldGoal == existing?.goal else {
          throw NutritionError.invalidGoal
        }
        var products = Dictionary(
          uniqueKeysWithValues: (existing?.favorites ?? []).map { ($0.id, $0) })
        for record in favorites.reversed() {
          let product = try JSONDecoder().decode(FoodProduct.self, from: record.payload)
          try product.validate()
          products[product.id] = product
        }
        let profile = NutritionProfile(
          goal: oldGoal ?? existing?.goal, favorites: Array(products.values))
        try profile.validate()
        let payload = try JSONEncoder().encode(profile)
        if let row = profiles.first {
          row.payload = payload
        } else {
          context.insert(
            StoredRecord(id: profile.id, kind: target("nutritionProfile"), payload: payload))
        }
        for record in goals + favorites + Array(profiles.dropFirst()) { context.delete(record) }
      }
      if first != nil {
        for kind in Self.nutritionKinds {
          let destination = try rawRecords(kind: target(kind))
          for record in try rawRecords(kind: kind) {
            if let match = destination.first(where: { $0.recordID == record.recordID }) {
              guard match.payload == record.payload else { throw NutritionError.invalidEntry }
              context.delete(record)
            } else {
              record.kind = target(kind)
            }
          }
        }
      }
      try validateNutrition(account: first)
      if commit { try context.save() }
    } catch {
      context.rollback()
      throw error
    }
  }
  private func validateNutrition(account: String?) throws {
    for kind in Self.nutritionKinds {
      for record in try rawRecords(kind: account.map { kind + "@" + $0 } ?? kind) {
        let decoder = JSONDecoder()
        let value: TrainingValue
        switch kind {
        case "foodEntry":
          value = .foodEntry(try decoder.decode(FoodEntry.self, from: record.payload))
        case "waterEntry":
          value = .waterEntry(try decoder.decode(WaterEntry.self, from: record.payload))
        case "supplementEntry":
          value = .supplementEntry(try decoder.decode(SupplementEntry.self, from: record.payload))
        case "supplementPlan":
          value = .supplementPlan(try decoder.decode(SupplementPlan.self, from: record.payload))
        default:
          value = .nutritionProfile(
            try decoder.decode(NutritionProfile.self, from: record.payload))
        }
        guard value.key.id == record.recordID else { throw NutritionError.invalidEntry }
        try value.validate()
      }
    }
  }

}
