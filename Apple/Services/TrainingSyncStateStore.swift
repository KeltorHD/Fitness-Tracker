import FitLifeCore
import Foundation

struct LocalTrainingAccount: Codable, Equatable, Identifiable, Sendable {
  var id: String { namespace }
  let namespace: String
  let name: String
  let server: String
}

protocol TrainingSyncStateStoring: Sendable {
  func load(_ namespace: String) async throws -> TrainingSyncState
  func save(_ state: TrainingSyncState, for namespace: String) async throws
  func accounts() async throws -> [LocalTrainingAccount]
  func register(_ account: LocalTrainingAccount) async throws
}

actor MemoryTrainingSyncStateStore: TrainingSyncStateStoring {
  private var states: [String: TrainingSyncState] = [:]
  private var registry: [LocalTrainingAccount] = []
  func load(_ namespace: String) -> TrainingSyncState { states[namespace] ?? TrainingSyncState() }
  func save(_ state: TrainingSyncState, for namespace: String) throws {
    try state.validate()
    states[namespace] = state
  }
  func accounts() -> [LocalTrainingAccount] { registry }
  func register(_ account: LocalTrainingAccount) {
    registry.removeAll { $0.namespace == account.namespace }
    registry.append(account)
  }
}

/// Baselines discover pending edits/deletions from the durable local journal after a restart.
actor TrainingSyncStateStore: TrainingSyncStateStoring {
  private let directory: URL?
  init(directory: URL? = nil) { self.directory = directory }

  private func folder() throws -> URL {
    guard
      let result = directory
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FitLife/TrainingSync", isDirectory: true)
    else { throw TrainingSyncError.invalidData }
    try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
    return result
  }
  private func file(_ namespace: String) throws -> URL {
    guard !namespace.isEmpty, namespace.count <= 256,
      namespace.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else { throw TrainingSyncError.invalidData }
    return try folder().appendingPathComponent(namespace).appendingPathExtension("json")
  }
  func load(_ namespace: String) throws -> TrainingSyncState {
    let url = try file(namespace)
    guard FileManager.default.fileExists(atPath: url.path) else { return TrainingSyncState() }
    var state = try TrainingCoding.decoder().decode(TrainingSyncState.self, from: read(url))
    try state.validate()
    if state.nutritionFeedVersion == nil {
      state.cursor = 0
      state.nutritionFeedVersion = 1
      try save(state, for: namespace)
    }
    return state
  }
  func save(_ state: TrainingSyncState, for namespace: String) throws {
    try state.validate()
    try write(TrainingCoding.encoder().encode(state), to: file(namespace))
  }
  func accounts() throws -> [LocalTrainingAccount] {
    let url = try folder().appendingPathComponent("accounts.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let result = try JSONDecoder().decode([LocalTrainingAccount].self, from: read(url))
    guard Set(result.map(\.namespace)).count == result.count else {
      throw TrainingSyncError.invalidData
    }
    return result
  }
  func register(_ account: LocalTrainingAccount) throws {
    _ = try file(account.namespace)
    var values = try accounts().filter { $0.namespace != account.namespace }
    values.append(account)
    try write(JSONEncoder().encode(values), to: folder().appendingPathComponent("accounts.json"))
  }
  private func read(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    do {
      var data = Data()
      while let part = try handle.read(upToCount: min(65_536, 64 * 1024 * 1024 + 1 - data.count)),
        !part.isEmpty
      {
        try Task.checkCancellation()
        data.append(part)
        guard data.count <= 64 * 1024 * 1024 else { throw TrainingSyncError.invalidData }
      }
      try handle.close()
      return data
    } catch {
      try? handle.close()
      throw error
    }
  }
  private func write(_ data: Data, to url: URL) throws {
    try Task.checkCancellation()
    guard data.count <= 64 * 1024 * 1024 else { throw TrainingSyncError.invalidData }
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(to: url, options: options)
  }
}
