import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct HealthConnectionStatus: Decodable, Equatable, Sendable {
  let provider: HealthProviderID
  let available: Bool
  let connected: Bool
  let metrics: Set<HealthMetric>
}

@MainActor final class MiFitnessDataProvider: HealthDataProviding {
  let id = HealthProviderID.miFitness
  let supportedMetrics: Set<HealthMetric> = [
    .sleep, .steps, .bodyWeight, .bodyFatPercentage, .heartRate, .restingHeartRate, .totalEnergy,
    .bloodOxygen,
  ]
  private let session: AccountSession?
  private let cryptography: any ServerCryptography
  private let account: @MainActor () -> String

  init(
    session: AccountSession?, cryptography: any ServerCryptography,
    account: @escaping @MainActor () -> String
  ) {
    self.session = session
    self.cryptography = cryptography
    self.account = account
  }

  func connection() async throws -> HealthConnectionStatus {
    let (session, userID) = try await authorizedSession()
    let request = URLRequest(
      url: session.configuration.authenticationURL.appendingPathComponent("v1/health/connections"))
    let statuses = try ServerJSON.decode(
      [HealthConnectionStatus].self,
      from: await session.authorizedData(request, expectedUserID: userID))
    guard let status = statuses.first(where: { $0.provider == .miFitness }),
      Set(statuses.map(\.provider)).count == statuses.count,
      status.metrics.isSubset(of: supportedMetrics)
    else { throw ServerError.invalidResponse }
    return status
  }

  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    let status = try await connection()
    guard status.available else { throw HealthDataError.unavailable }
    guard status.connected else { throw HealthDataError.notConnected }
    guard !status.metrics.intersection(metrics).isEmpty else {
      throw HealthDataError.permissionRequired
    }
    return status.metrics
  }

  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    guard !metrics.isEmpty, metrics.isSubset(of: supportedMetrics) else {
      throw HealthDataError.unsupportedMetric
    }
    let (session, userID) = try await authorizedSession()
    let originalAccount = account()
    guard
      var url = URLComponents(
        url: session.configuration.backendURL.appendingPathComponent(
          "v1/health/providers/miFitness/data"), resolvingAgainstBaseURL: false)
    else { throw ServerError.invalidConfiguration }
    url.queryItems = [
      URLQueryItem(
        name: "start", value: start.ISO8601Format(.init(includingFractionalSeconds: true))),
      URLQueryItem(name: "end", value: end.ISO8601Format(.init(includingFractionalSeconds: true))),
      URLQueryItem(name: "metrics", value: metrics.map(\.rawValue).sorted().joined(separator: ",")),
      URLQueryItem(name: "zoneName", value: calendar.timeZone.identifier),
    ]
    guard let address = url.url else { throw ServerError.invalidConfiguration }
    let data = try await session.authorizedData(
      URLRequest(url: address), maximumBytes: 32 * 1024 * 1024, expectedUserID: userID)
    let snapshot = try await Self.decode(data)
    guard originalAccount == account(), snapshot.provider == .miFitness,
      abs(snapshot.start.timeIntervalSince(start)) < 0.001,
      abs(snapshot.end.timeIntervalSince(end)) < 0.001, snapshot.metrics.isSubset(of: metrics)
    else { throw HealthDataError.invalidData }
    try Task.checkCancellation()
    return snapshot
  }

  func disconnect() async throws {
    let (session, userID) = try await authorizedSession()
    var request = URLRequest(
      url: session.configuration.authenticationURL.appendingPathComponent(
        "v1/health/connections/mi-fitness"))
    request.httpMethod = "DELETE"
    _ = try await session.authorizedData(request, expectedUserID: userID)
  }

  private func authorizedSession() async throws -> (AccountSession, String) {
    guard let session else { throw HealthDataError.unavailable }
    guard let profile = try await session.profile(), let id = UUID(uuidString: profile.id) else {
      throw HealthDataError.notConnected
    }
    let namespace =
      cryptography.sha256(Data(session.configuration.authenticationURL.absoluteString.utf8)) + "-"
      + id.uuidString.lowercased()
    guard namespace == account() else { throw HealthDataError.notConnected }
    return (session, profile.id)
  }

  @concurrent nonisolated private static func decode(_ data: Data) async throws
    -> HealthDataSnapshot
  {
    try ServerJSON.decode(HealthDataSnapshot.self, from: data)
  }
}
