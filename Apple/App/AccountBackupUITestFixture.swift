import FitLifeCore
import Foundation

/// Synthetic server responses are available only for an explicit in-memory Debug UI launch.
enum AccountBackupUITestFixture {
  static func session() throws -> AccountSession? {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      guard arguments.contains("--ui-testing"), arguments.contains("--ui-testing-backups") else {
        return nil
      }
      guard let auth = URL(string: "https://auth.example.com/"),
        let api = URL(string: "https://api.example.com/")
      else { throw ServerError.invalidConfiguration }
      _ = try BackupProtocol.payload.get()
      let transport = URLSessionConfiguration.ephemeral
      transport.protocolClasses = [BackupProtocol.self]
      return AccountSession(
        configuration: try ServerConfiguration(authenticationURL: auth, backendURL: api),
        http: ServerHTTPClient(session: URLSession(configuration: transport)),
        credentials: Credentials())
    #else
      return nil
    #endif
  }

  #if DEBUG
    private actor Credentials: AccountTokenStoring {
      private var tokens: AccountTokens? = AccountTokens(
        accessToken: "ui-testing-access", refreshToken: "ui-testing-refresh",
        expiresAt: .distantFuture,
        profile: AccountProfile(
          id: UUID().uuidString, name: "UI backup fixture", createdAt: .distantPast,
          logins: ["Email"]))

      func load() -> AccountTokens? { tokens }
      func save(_ tokens: AccountTokens) { self.tokens = tokens }
      func clear() { tokens = nil }
    }

    private final class BackupProtocol: URLProtocol {
      private static let id = UUID()
      private static let date = Date(timeIntervalSince1970: 1_700_000_000)
      static let payload: Result<Data, any Error> = Result {
        let row = WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [WorkoutSet()])
        var workout = Workout(
          name: "UI fixture: server backup", startedAt: date, exercises: [row])
        try WorkoutEngine.completeSet(
          in: &workout, exerciseID: row.id, setID: row.sets[0].id,
          repetitions: 8, weightKG: 40, at: date.addingTimeInterval(60))
        try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(120))
        return try WorkoutArchiveCodec.encode(
          WorkoutArchive(workouts: [workout], templates: [], exportedAt: date))
      }

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        do {
          guard let url = request.url, url.host == "api.example.com",
            request.value(forHTTPHeaderField: "Authorization") == "Bearer ui-testing-access"
          else { throw URLError(.badServerResponse) }
          let payload = try Self.payload.get()
          let body: Data
          let status: Int
          switch (request.httpMethod ?? "GET", url.path) {
          case ("GET", "/v1/backups"):
            let backup = RemoteBackup(
              id: Self.id, createdAt: Self.date, archiveVersion: WorkoutArchive.currentVersion,
              size: payload.count, sha256: AppleServerCryptography().sha256(payload))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            body = try encoder.encode([backup])
            status = 200
          case ("GET", "/v1/backups/\(Self.id.uuidString.lowercased())"):
            body = payload
            status = 200
          case ("DELETE", "/v1/backups/\(Self.id.uuidString.lowercased())"):
            body = Data()
            status = 204
          default:
            throw URLError(.unsupportedURL)
          }
          guard
            let response = HTTPURLResponse(
              url: url, statusCode: status, httpVersion: nil, headerFields: nil)
          else { throw URLError(.badServerResponse) }
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: body)
          client?.urlProtocolDidFinishLoading(self)
        } catch {
          client?.urlProtocol(self, didFailWithError: error)
        }
      }

      override func stopLoading() {}
    }
  #endif
}
