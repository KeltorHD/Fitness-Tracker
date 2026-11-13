import FitLifeCore
import Foundation

struct PreparedHealthSync: Codable, Sendable {
  let batch: HealthSyncBatch
  let payload: Data
  let metric: HealthMetric?
  let anchor: Data?
  let processedBuckets: [String]

  private enum CodingKeys: String, CodingKey { case payload, metric, anchor, processedBuckets }

  init(batch: HealthSyncBatch, metric: HealthMetric?, anchor: Data?, processedBuckets: [String])
    throws
  {
    try batch.validate()
    let payload = try HealthSyncCoding.encoder().encode(batch)
    self.batch = try Self.decode(payload)
    self.payload = payload
    self.metric = metric
    self.anchor = anchor
    self.processedBuckets = processedBuckets
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    payload = try container.decode(Data.self, forKey: .payload)
    batch = try Self.decode(payload)
    metric = try container.decodeIfPresent(HealthMetric.self, forKey: .metric)
    anchor = try container.decodeIfPresent(Data.self, forKey: .anchor)
    processedBuckets = try container.decode([String].self, forKey: .processedBuckets)
  }

  private static func decode(_ payload: Data) throws -> HealthSyncBatch {
    guard payload.count <= 4 * 1024 * 1024 else { throw HealthDataError.invalidData }
    let batch = try HealthSyncCoding.decoder().decode(HealthSyncBatch.self, from: payload)
    try batch.validate()
    return batch
  }
}

struct HealthSyncState: Codable, Sendable {
  var version = 1
  var deviceID = UUID()
  var sequence: Int64 = 0
  let initialStart: Date
  let initialSleepStart: Date
  var anchors: [HealthMetric: Data] = [:]
  var buckets: [String: HealthSyncBucket] = [:]
  var pending: PreparedHealthSync?
  var lastSync: Date?
  var timeZoneID: String?
  var reconciliationID: String?

  func validate() throws {
    guard version == 1, sequence >= 0, sequence < Int64.max,
      initialStart.timeIntervalSince1970.isFinite, initialSleepStart.timeIntervalSince1970.isFinite,
      initialSleepStart <= initialStart,
      initialStart.timeIntervalSince(initialSleepStart) <= 26 * 3600, anchors.count <= 9,
      anchors.values.allSatisfy({ $0.count <= 65_536 }), buckets.count <= 2000,
      lastSync?.timeIntervalSince1970.isFinite != false
    else { throw HealthDataError.invalidData }
    for (key, bucket) in buckets {
      try bucket.validate()
      guard key == bucket.key else { throw HealthDataError.invalidData }
    }
    if let pending {
      try pending.batch.validate()
      guard pending.batch.deviceID == deviceID, pending.batch.sequence == sequence + 1,
        pending.metric == nil || pending.anchor != nil, (pending.anchor?.count ?? 0) <= 65_536,
        pending.processedBuckets.count <= 100
      else { throw HealthDataError.invalidData }
    }
  }
}

protocol HealthSyncStateStoring: Sendable {
  func load(_ namespace: String) async throws -> HealthSyncState?
  func save(_ state: HealthSyncState, for namespace: String) async throws
}

actor MemoryHealthSyncStateStore: HealthSyncStateStoring {
  private var values: [String: HealthSyncState] = [:]
  func load(_ namespace: String) -> HealthSyncState? { values[namespace] }
  func save(_ state: HealthSyncState, for namespace: String) throws {
    try state.validate()
    values[namespace] = state
  }
}

/// Anchors and the write-ahead batch are committed together; corruption is never reset to an empty sync.
actor HealthSyncStateStore: HealthSyncStateStoring {
  private let directory: URL?
  init(directory: URL? = nil) { self.directory = directory }
  private func file(_ namespace: String) throws -> URL {
    try HealthDataCacheKey(account: namespace, provider: .appleHealth, metrics: [.sleep]).validate()
    guard
      let root = directory
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FitLife/HealthSync", isDirectory: true)
    else { throw HealthDataError.unavailable }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var folder = root
    try folder.setResourceValues(values)
    return root.appendingPathComponent(namespace).appendingPathExtension("json")
  }
  func load(_ namespace: String) throws -> HealthSyncState? {
    let path = try file(namespace)
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: path)
    let data: Data
    do {
      var buffer = Data()
      while let part = try handle.read(upToCount: min(65_536, 8 * 1024 * 1024 + 1 - buffer.count)),
        !part.isEmpty
      {
        try Task.checkCancellation()
        buffer.append(part)
        guard buffer.count <= 8 * 1024 * 1024 else { throw HealthDataError.invalidData }
      }
      try handle.close()
      data = buffer
    } catch {
      try? handle.close()
      throw error
    }
    let state = try TrainingCoding.decoder().decode(HealthSyncState.self, from: data)
    try state.validate()
    return state
  }
  func save(_ state: HealthSyncState, for namespace: String) throws {
    try state.validate()
    try Task.checkCancellation()
    let data = try TrainingCoding.encoder().encode(state)
    guard data.count <= 8 * 1024 * 1024 else { throw HealthDataError.invalidData }
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(to: file(namespace), options: options)
  }
}
