import FitSessionCore
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

@MainActor final class SwiftDataWorkoutRepository: WorkoutRepository {
  let container: ModelContainer
  private let context: ModelContext
  init(inMemory: Bool = false, cloudEnabled: Bool = false) throws {
    let schema = Schema([StoredRecord.self])
    let cloudID =
      Bundle.main.object(forInfoDictionaryKey: "FitSessionCloudContainer") as? String ?? ""
    let configuration = ModelConfiguration(
      "FitSession", schema: schema, isStoredInMemoryOnly: inMemory,
      groupContainer: .none,
      cloudKitDatabase: cloudEnabled && !inMemory ? .private(cloudID) : .none)
    container = try ModelContainer(for: schema, configurations: [configuration])
    context = ModelContext(container)
    context.autosaveEnabled = false
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
  private func allRecords(kind: String) throws -> [StoredRecord] {
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
      let matches = try allRecords(kind: kind).filter { $0.recordID == id }
      if let record = matches.first {
        record.payload = data
        record.modifiedAt = Date()
        for duplicate in matches.dropFirst() { context.delete(duplicate) }
      } else {
        context.insert(StoredRecord(id: id, kind: kind, payload: data))
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
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
}
