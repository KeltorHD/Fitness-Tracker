import FitSessionCore
import Foundation

/// Device-local sensor data. Never stored in the SwiftData/CloudKit aggregate or App Group.
actor LocalHeartRateRepository: HeartRateRecordingRepository {
  private let directory: URL?
  init(directory: URL? = nil) { self.directory = directory }

  private func folder() throws -> URL {
    guard
      let base = directory
        ?? FileManager.default.urls(
          for: .applicationSupportDirectory, in: .userDomainMask
        ).first?
        .appendingPathComponent("FitSession/HeartRate", isDirectory: true)
    else { throw TrackerDataError.invalidRecording }
    return base
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
}
