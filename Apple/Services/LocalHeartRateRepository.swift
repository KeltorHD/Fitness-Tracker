import FitLifeCore
import Foundation

/// Account-scoped sensor files remain separate from the SwiftData/CloudKit aggregate and App Group.
actor LocalHeartRateRepository: TrainingHeartRateRepository {
  private let directory: URL?
  private var scope: String?
  private struct Adoption: Codable {
    let account: String
    let complete: Bool
  }
  init(directory: URL? = nil, scope: String? = nil) {
    self.directory = directory
    self.scope = scope
  }

  private func rootFolder() throws -> URL {
    guard
      let base = directory
        ?? FileManager.default.urls(
          for: .applicationSupportDirectory, in: .userDomainMask
        ).first?
        .appendingPathComponent(AppIdentifiers.heartRateDirectory, isDirectory: true)
    else { throw TrackerDataError.invalidRecording }
    return base
  }
  private func folder() throws -> URL {
    let root = try rootFolder()
    var effective = scope
    let marker = root.appendingPathComponent("first-account.json")
    if effective == nil, FileManager.default.fileExists(atPath: marker.path) {
      let adoption = try JSONDecoder().decode(Adoption.self, from: boundedRead(marker))
      if adoption.complete { effective = adoption.account }
    }
    guard let effective else { return root }
    try validateScope(effective)
    return root.appendingPathComponent(effective, isDirectory: true)
  }
  private func file(_ id: UUID) throws -> URL {
    try folder().appendingPathComponent(id.uuidString).appendingPathExtension("json")
  }
  func recording(for workoutID: UUID) throws -> HeartRateRecording? {
    try Task.checkCancellation()
    let path = try file(workoutID)
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let value = try JSONDecoder().decode(HeartRateRecording.self, from: boundedRead(path))
    try value.validate()
    guard value.workoutID == workoutID else { throw TrackerDataError.invalidRecording }
    return value
  }
  private func boundedRead(_ path: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: path)
    var data = Data()
    do {
      while let chunk = try handle.read(upToCount: min(65_536, 2_000_001 - data.count)),
        !chunk.isEmpty
      {
        try Task.checkCancellation()
        data.append(chunk)
        guard data.count <= 2_000_000 else { throw TrackerDataError.invalidRecording }
      }
      try handle.close()
      return data
    } catch {
      try? handle.close()  // Preserve the original read/validation error if cleanup also fails.
      throw error
    }
  }
  func save(_ recording: HeartRateRecording) throws {
    try Task.checkCancellation()
    try recording.validate()
    var folder = try folder()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try JSONEncoder().encode(recording).write(to: file(recording.workoutID), options: options)
  }
  func remove(for workoutID: UUID) throws {
    let path = try file(workoutID)
    if FileManager.default.fileExists(atPath: path.path) {
      try FileManager.default.removeItem(at: path)
    }
  }

  func activateTrainingAccount(_ namespace: String, adoptUnscoped: Bool) throws {
    try Task.checkCancellation()
    try validateScope(namespace)
    let root = try rootFolder()
    let destination = root.appendingPathComponent(namespace, isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    if adoptUnscoped {
      let marker = root.appendingPathComponent("first-account.json")
      if FileManager.default.fileExists(atPath: marker.path) {
        let adoption = try JSONDecoder().decode(Adoption.self, from: boundedRead(marker))
        guard adoption.account == namespace else {
          throw TrainingSyncError.accountMismatch
        }
        if adoption.complete {
          scope = namespace
          return
        }
      } else {
        try JSONEncoder().encode(Adoption(account: namespace, complete: false)).write(
          to: marker, options: protectionOptions)
      }
      for source in try FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil)
      where source.pathExtension == "json"
        && UUID(uuidString: source.deletingPathExtension().lastPathComponent) != nil
      {
        try Task.checkCancellation()
        let data = try boundedRead(source)
        let recording = try JSONDecoder().decode(HeartRateRecording.self, from: data)
        try recording.validate()
        guard
          recording.workoutID.uuidString.lowercased()
            == source.deletingPathExtension().lastPathComponent.lowercased()
        else {
          throw TrackerDataError.invalidRecording
        }
        let target = destination.appendingPathComponent(source.lastPathComponent)
        try data.write(to: target, options: protectionOptions)
      }
      try JSONEncoder().encode(Adoption(account: namespace, complete: true)).write(
        to: marker, options: protectionOptions)
    }
    // Original unscoped files remain for recovery; the first-owner marker prevents another adoption.
    scope = namespace
  }

  func setTrainingAccountScope(_ namespace: String?) throws {
    if let namespace { try validateScope(namespace) }
    scope = namespace
  }

  func compareAndSet(
    workoutID: UUID, expected: HeartRateRecording?, replacement: HeartRateRecording?
  ) throws -> Bool {
    guard try recording(for: workoutID) == expected else { return false }
    if let replacement {
      guard replacement.workoutID == workoutID else { throw TrackerDataError.invalidRecording }
      try save(replacement)
    } else {
      try remove(for: workoutID)
    }
    return true
  }

  private func validateScope(_ value: String) throws {
    guard !value.isEmpty, value.count <= 256,
      value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else { throw TrainingSyncError.invalidData }
  }
  private var protectionOptions: Data.WritingOptions {
    var result: Data.WritingOptions = [.atomic]
    #if os(iOS)
      result.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    return result
  }
}
