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
    guard ["workout", "template", "bodyWeight"].contains(kind),
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
      if selection.firstAccountID == nil {
        for kind in ["workout", "template", "bodyWeight"] {
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
      workouts: workouts(), templates: templates(), bodyWeights: bodyWeights()
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
          context.insert(StoredRecord(id: id, kind: "foodEntry", payload: data))
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
      try entry.validate()
      return entry
    }
  }
  func saveWaterEntry(_ entry: WaterEntry) throws {
    try entry.validate()
    try upsert(id: entry.id, kind: "waterEntry", data: JSONEncoder().encode(entry))
  }
  func deleteWaterEntry(id: UUID) throws { try remove(id: id, kind: "waterEntry") }
  func favoriteFoodProducts() throws -> [FoodProduct] {
    var seen = Set<String>()
    return try records(kind: "favoriteFoodProduct").map {
      let product = try JSONDecoder().decode(FoodProduct.self, from: $0.payload)
      try product.validate()
      return product
    }.filter { seen.insert($0.id).inserted }
  }
  func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws {
    try product.validate()
    let data = try JSONEncoder().encode(product)
    do {
      let matches = try allRecords(kind: "favoriteFoodProduct").filter {
        try JSONDecoder().decode(FoodProduct.self, from: $0.payload).id == product.id
      }
      if isFavorite {
        if let record = matches.first {
          record.payload = data
          record.modifiedAt = .now
          for duplicate in matches.dropFirst() { context.delete(duplicate) }
        } else {
          context.insert(StoredRecord(id: UUID(), kind: "favoriteFoodProduct", payload: data))
        }
      } else {
        for record in matches { context.delete(record) }
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  func deleteFoodEntry(id: UUID) throws { try remove(id: id, kind: "foodEntry") }
  func nutritionGoal() throws -> NutritionGoal? {
    guard let record = try records(kind: "nutritionGoal").first else { return nil }
    let goal = try JSONDecoder().decode(NutritionGoal.self, from: record.payload)
    try goal.validate()
    return goal
  }
  func saveNutritionGoal(_ goal: NutritionGoal?) throws {
    // A stable aggregate ID keeps the same goal across launches and CloudKit devices.
    guard let id = UUID(uuidString: "345B105D-8EFC-4EA2-99D3-770805C86F71") else {
      throw NutritionError.invalidValues
    }
    if let goal {
      try goal.validate()
      try upsert(id: id, kind: "nutritionGoal", data: JSONEncoder().encode(goal))
    } else {
      try remove(id: id, kind: "nutritionGoal")
    }
  }
}
