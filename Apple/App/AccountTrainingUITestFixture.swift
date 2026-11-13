import FitLifeCore
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Synthetic responses exist only in an explicitly requested in-memory Debug UI launch.
@MainActor enum AccountTrainingUITestFixture {
  static func seed(into repository: any WorkoutRepository) throws {
    #if DEBUG
      guard enabled else { return }
      try repository.save(TrainingProtocol.workout.get())
    #endif
  }
  static func session() throws -> AccountSession? {
    #if DEBUG
      guard enabled, let auth = URL(string: "https://auth.example.com/"),
        let api = URL(string: "https://api.example.com/")
      else { return nil }
      let transport = URLSessionConfiguration.ephemeral
      transport.protocolClasses = [TrainingProtocol.self]
      return AccountSession(
        configuration: try ServerConfiguration(authenticationURL: auth, backendURL: api),
        http: ServerHTTPClient(session: URLSession(configuration: transport)),
        credentials: Credentials())
    #else
      return nil
    #endif
  }
  #if DEBUG
    private static var enabled: Bool {
      let arguments = ProcessInfo.processInfo.arguments
      return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-training-sync")
    }
    private actor Credentials: AccountTokenStoring {
      private var tokens: AccountTokens? = AccountTokens(
        accessToken: "ui-testing-access", refreshToken: "ui-testing-refresh",
        expiresAt: .distantFuture,
        profile: AccountProfile(
          id: UUID().uuidString, name: "UI sync fixture", createdAt: .distantPast, logins: ["Email"]
        ))
      func load() -> AccountTokens? { tokens }
      func save(_ tokens: AccountTokens) { self.tokens = tokens }
      func clear() { tokens = nil }
    }
    private final class TrainingProtocol: URLProtocol {
      static let workout: Result<Workout, any Error> = Result {
        var workout = Workout(
          name: "UI: local version", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try WorkoutEngine.cancel(&workout, at: workout.startedAt.addingTimeInterval(120))
        return workout
      }
      private static let latest = Mutex<TrainingChange?>(nil)
      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func startLoading() {
        do {
          guard let url = request.url, url.host == "api.example.com",
            request.value(forHTTPHeaderField: "Authorization") == "Bearer ui-testing-access",
            url.path == "/v1/training/changes"
          else { throw URLError(.unsupportedURL) }
          let data: Data
          if request.httpMethod == "POST" {
            let body = try requestBody()
            guard var mutations = try JSONSerialization.jsonObject(with: body) as? [[String: Any]],
              mutations.count == 1
            else { throw URLError(.badServerResponse) }
            mutations[0]["baseRevision"] = nil
            mutations[0]["revision"] = 2
            let change = try TrainingCoding.decoder().decode(
              TrainingChange.self, from: JSONSerialization.data(withJSONObject: mutations[0]))
            Self.latest.withLock { $0 = change }
            data = try TrainingCoding.encoder().encode([change])
          } else {
            let after =
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "after"
              }?.value.flatMap(Int64.init) ?? 0
            var remote = try Self.workout.get()
            remote.name = "UI: server version"
            let initial = try TrainingChange(
              key: TrainingValue.workout(remote).key, revision: 1, value: .workout(remote))
            let change = Self.latest.withLock { $0 ?? initial }
            data = Data(
              "{\"changes\":\(String(decoding: try TrainingCoding.encoder().encode(change.revision > after ? [change] : []), as: UTF8.self)),\"cursor\":\(max(after, change.revision)),\"hasMore\":false}"
                .utf8)
          }
          guard
            let response = HTTPURLResponse(
              url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
          else { throw URLError(.badServerResponse) }
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: data)
          client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
      }
      private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 8192)
        var body = Data()
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          guard count >= 0, body.count + count <= 30 * 1024 * 1024 else {
            throw URLError(.cannotDecodeRawData)
          }
          if count == 0 { break }
          body.append(contentsOf: buffer.prefix(count))
        }
        return body
      }
      override func stopLoading() {}
    }
  #endif
}
