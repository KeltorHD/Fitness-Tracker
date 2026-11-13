import FitLifeCore
import Foundation

struct HealthDataCacheKey: Hashable, Sendable {
  let account: String
  let provider: HealthProviderID
  let metrics: Set<HealthMetric>
  let timeZoneID: String
  init(
    account: String, provider: HealthProviderID, metrics: Set<HealthMetric>,
    timeZoneID: String = "UTC"
  ) {
    self.account = account
    self.provider = provider
    self.metrics = metrics
    self.timeZoneID = timeZoneID
  }
  var component: String {
    provider.rawValue + "-" + metrics.map(\.rawValue).sorted().joined(separator: "-") + "-"
      + Data(timeZoneID.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
  func validate() throws {
    guard !account.isEmpty, account.count <= 256, !metrics.isEmpty, timeZoneID.utf8.count <= 80,
      TimeZone(identifier: timeZoneID) != nil,
      account.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else { throw HealthDataError.invalidData }
  }
}

protocol HealthDataCaching: Sendable {
  func load(_ key: HealthDataCacheKey) async throws -> HealthDataSnapshot?
  func save(_ snapshot: HealthDataSnapshot, for key: HealthDataCacheKey) async throws
  func remove(account: String, provider: HealthProviderID) async throws
}

actor MemoryHealthDataCache: HealthDataCaching {
  private var values: [HealthDataCacheKey: HealthDataSnapshot] = [:]
  func load(_ key: HealthDataCacheKey) throws -> HealthDataSnapshot? {
    try key.validate()
    return values[key]
  }
  func save(_ snapshot: HealthDataSnapshot, for key: HealthDataCacheKey) throws {
    try key.validate()
    try snapshot.validate()
    guard snapshot.provider == key.provider else { throw HealthDataError.invalidData }
    values[key] = snapshot
  }
  func remove(account: String, provider: HealthProviderID) {
    values = values.filter { $0.key.account != account || $0.key.provider != provider }
  }
}

/// A bounded last snapshot per query purpose, account and provider; never a shared global health history.
actor HealthDataCache: HealthDataCaching {
  private let directory: URL?
  init(directory: URL? = nil) { self.directory = directory }

  private struct Envelope: Codable {
    let version: Int
    let snapshot: HealthDataSnapshot
  }

  private func folder(_ account: String) throws -> URL {
    try HealthDataCacheKey(account: account, provider: .appleHealth, metrics: [.sleep]).validate()
    guard
      let root = directory
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FitLife/HealthProviders", isDirectory: true)
    else { throw HealthDataError.unavailable }
    let result = root.appendingPathComponent(account, isDirectory: true)
    try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var url = result
    try url.setResourceValues(values)
    return result
  }

  func load(_ key: HealthDataCacheKey) throws -> HealthDataSnapshot? {
    try key.validate()
    let file = try folder(key.account).appendingPathComponent(key.component).appendingPathExtension(
      "json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: file)
    let data: Data
    do {
      var result = Data()
      while let bytes = try handle.read(
        upToCount: min(65_536, 32 * 1024 * 1024 + 1 - result.count)), !bytes.isEmpty
      {
        try Task.checkCancellation()
        result.append(bytes)
        guard result.count <= 32 * 1024 * 1024 else { throw HealthDataError.invalidData }
      }
      try handle.close()
      data = result
    } catch {
      try? handle.close()
      throw error
    }
    let envelope = try TrainingCoding.decoder().decode(Envelope.self, from: data)
    guard envelope.version == 1, envelope.snapshot.provider == key.provider,
      envelope.snapshot.metrics.isSubset(of: key.metrics)
    else { throw HealthDataError.invalidData }
    try envelope.snapshot.validate()
    return envelope.snapshot
  }

  func save(_ snapshot: HealthDataSnapshot, for key: HealthDataCacheKey) throws {
    try key.validate()
    try snapshot.validate()
    guard snapshot.provider == key.provider, snapshot.metrics.isSubset(of: key.metrics) else {
      throw HealthDataError.invalidData
    }
    try Task.checkCancellation()
    let data = try TrainingCoding.encoder().encode(Envelope(version: 1, snapshot: snapshot))
    guard data.count <= 32 * 1024 * 1024 else { throw HealthDataError.invalidData }
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(
      to: folder(key.account).appendingPathComponent(key.component).appendingPathExtension("json"),
      options: options)
  }

  func remove(account: String, provider: HealthProviderID) throws {
    let folder = try folder(account)
    for url in try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    where url.lastPathComponent.hasPrefix(provider.rawValue + "-") && url.pathExtension == "json" {
      try FileManager.default.removeItem(at: url)
    }
  }
}
