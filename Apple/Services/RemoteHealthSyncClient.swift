import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@MainActor protocol HealthSyncRemoteServing {
  var available: Bool { get }
  func pendingBuckets() async throws -> [HealthSyncBucket]
  func apply(_ payload: Data, account namespace: String) async throws
    -> HealthSyncAcknowledgement
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
}

@MainActor final class RemoteHealthSyncClient: HealthSyncRemoteServing {
  private let session: AccountSession
  private let cryptography: any ServerCryptography
  private let account: @MainActor () -> String
  init(
    session: AccountSession, cryptography: any ServerCryptography,
    account: @escaping @MainActor () -> String
  ) {
    self.session = session
    self.cryptography = cryptography
    self.account = account
  }
  var available: Bool {
    let prefix =
      cryptography.sha256(Data(session.configuration.authenticationURL.absoluteString.utf8)) + "-"
    return account().hasPrefix(prefix)
      && UUID(uuidString: String(account().dropFirst(prefix.count))) != nil
  }
  private func owner(expectedAccount: String? = nil) async throws -> String {
    let namespace = expectedAccount ?? account()
    try Task.checkCancellation()
    guard account() == namespace else { throw CancellationError() }
    guard available else { throw HealthDataError.notConnected }
    let profile = try await session.profile()
    guard account() == namespace else { throw CancellationError() }
    guard let profile, let id = UUID(uuidString: profile.id),
      namespace == cryptography.sha256(
        Data(session.configuration.authenticationURL.absoluteString.utf8)) + "-"
        + id.uuidString.lowercased()
    else { throw HealthDataError.notConnected }
    return profile.id
  }
  func pendingBuckets() async throws -> [HealthSyncBucket] {
    let id = try await owner()
    let request = URLRequest(
      url: session.configuration.backendURL.appendingPathComponent(
        "v1/health/providers/appleHealth/pending"))
    let bytes = try await session.authorizedData(
      request, maximumBytes: 1024 * 1024, expectedUserID: id)
    struct Response: Decodable { let buckets: [HealthSyncBucket] }
    let response = try ServerJSON.decode(Response.self, from: bytes)
    guard response.buckets.count <= 100,
      Set(response.buckets.map(\.key)).count == response.buckets.count,
      response.buckets.reduce(0, { $0 + $1.excludedIDs.count }) <= 10_000
    else { throw HealthDataError.invalidData }
    for bucket in response.buckets { try bucket.validate() }
    return response.buckets
  }
  func apply(_ payload: Data, account namespace: String) async throws
    -> HealthSyncAcknowledgement
  {
    let id = try await owner(expectedAccount: namespace)
    guard payload.count <= 4 * 1024 * 1024 else { throw HealthDataError.invalidData }
    let batch = try HealthSyncCoding.decoder().decode(HealthSyncBatch.self, from: payload)
    try batch.validate()
    var request = URLRequest(
      url: session.configuration.backendURL.appendingPathComponent(
        "v1/health/providers/appleHealth/changes"))
    request.httpMethod = "POST"
    request.httpBody = payload
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let response = try await session.authorizedData(
      request, maximumBytes: 1024 * 1024, expectedUserID: id)
    let ack = try ServerJSON.decode(HealthSyncAcknowledgement.self, from: response)
    try ack.validate(for: batch)
    return ack
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    let id = try await owner()
    guard
      var url = URLComponents(
        url: session.configuration.backendURL.appendingPathComponent(
          "v1/health/providers/appleHealth/data"), resolvingAgainstBaseURL: false)
    else { throw ServerError.invalidConfiguration }
    url.queryItems = [
      URLQueryItem(
        name: "start", value: start.ISO8601Format(.init(includingFractionalSeconds: true))),
      URLQueryItem(name: "end", value: end.ISO8601Format(.init(includingFractionalSeconds: true))),
      URLQueryItem(name: "metrics", value: metrics.map(\.rawValue).sorted().joined(separator: ",")),
      URLQueryItem(name: "zoneName", value: calendar.timeZone.identifier),
    ]
    guard let address = url.url else { throw ServerError.invalidConfiguration }
    let bytes = try await session.authorizedData(
      URLRequest(url: address), maximumBytes: 32 * 1024 * 1024, expectedUserID: id)
    let result = try await Self.decode(bytes)
    guard result.provider == .appleHealth, abs(result.start.timeIntervalSince(start)) < 0.001,
      abs(result.end.timeIntervalSince(end)) < 0.001, result.metrics.isSubset(of: metrics)
    else { throw HealthDataError.invalidData }
    return result
  }
  @concurrent nonisolated private static func decode(_ data: Data) async throws
    -> HealthDataSnapshot
  {
    try ServerJSON.decode(HealthDataSnapshot.self, from: data)
  }
}

/// A publishing iPhone keeps native offline reads; other account devices use Backend history.
@MainActor final class SyncedAppleHealthProvider: HealthDataProviding {
  let id = HealthProviderID.appleHealth
  var supportedMetrics: Set<HealthMetric> { local.supportedMetrics }
  private let local: any HealthDataProviding
  private let remote: any HealthSyncRemoteServing
  private let preferLocal: @MainActor () -> Bool
  init(
    local: any HealthDataProviding, remote: any HealthSyncRemoteServing,
    preferLocal: @escaping @MainActor () -> Bool = { false }
  ) {
    self.local = local
    self.remote = remote
    self.preferLocal = preferLocal
  }
  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    if remote.available && !preferLocal() { return metrics.intersection(supportedMetrics) }
    return try await local.authorize(metrics: metrics)
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    if remote.available && !preferLocal() {
      return try await remote.read(start: start, end: end, metrics: metrics, calendar: calendar)
    }
    return try await local.read(start: start, end: end, metrics: metrics, calendar: calendar)
  }
}
