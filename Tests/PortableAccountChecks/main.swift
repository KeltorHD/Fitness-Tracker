import FitLifeCore
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct FixtureCryptography: ServerCryptography {
  func authorizationAttempt() -> OAuthAttempt {
    OAuthAttempt(verifier: "fixed-verifier", state: "expected-state", challenge: "fixed-challenge")
  }

  func sha256(_ data: Data) -> String { String(repeating: "0", count: 64) }
}

private actor FixtureCredentials: AccountTokenStoring {
  private var value: AccountTokens?
  func load() -> AccountTokens? { value }
  func save(_ tokens: AccountTokens) { value = tokens }
  func clear() { value = nil }
}

/// Проверяет реальные URLSession-запросы, не допуская обращения к внешней сети.
private final class AccountProtocol: URLProtocol {
  static let operations = Mutex<[String: Int]>([:])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { preconditionFailure("Missing fixture URL") }
    precondition(url.scheme == "https")
    let personal = url.host == "personal-auth.example.com"
    let clientID = personal ? ServerConfiguration.personalClientID : ServerConfiguration.clientID
    let callback =
      personal
      ? "com.example.fitlife:/ios/oauth/callback"
      : "https://auth.example.com/ios/oauth/callback"
    let body: String
    if url.path == "/connect/token" || url.path == "/connect/revoke" {
      let data = request.httpBody ?? Data()
      let form = String(decoding: data, as: UTF8.self)
      let items = URLComponents(string: "https://fixture.example.com/?" + form)?.queryItems ?? []
      let fields = Dictionary(
        items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
      precondition(fields["client_id"] == clientID)
      let operation = fields["grant_type"] ?? "revoke"
      Self.operations.withLock { $0[clientID + operation, default: 0] += 1 }
      switch operation {
      case "authorization_code":
        precondition(
          fields["redirect_uri"] == callback && fields["code_verifier"] == "fixed-verifier")
        precondition(fields["code"] == "one-time-code")
        body =
          #"{"access_token":"initial","refresh_token":"first-refresh","token_type":"Bearer","expires_in":1}"#
      case "refresh_token":
        precondition(fields["refresh_token"] == "first-refresh")
        body =
          #"{"access_token":"rotated","refresh_token":"next-refresh","token_type":"Bearer","expires_in":600}"#
      case "revoke":
        precondition(
          fields["token"] == "next-refresh" && fields["token_type_hint"] == "refresh_token")
        body = "{}"
      default: preconditionFailure("Unexpected fixture grant")
      }
    } else if url.path == "/v1/account" {
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer initial")
      body =
        #"{"id":"00000000-0000-0000-0000-000000000001","name":"Fixture","createdAt":"2026-01-01T00:00:00Z","logins":["Email"]}"#
    } else {
      precondition(url.path == "/v1/backups")
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer rotated")
      body = "[]"
    }
    guard
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else {
      preconditionFailure("Invalid fixture response")
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@main struct AccountChecks {
  @MainActor static func main() async throws {
    let auth = URL(string: "https://auth.example.com/")!
    let api = URL(string: "https://api.example.com/")!
    let full = try ServerConfiguration(authenticationURL: auth, backendURL: api)
    let personal = try ServerConfiguration(
      authenticationURL: URL(string: "https://personal-auth.example.com/")!, backendURL: api,
      callback: .customScheme("com.example.fitlife"))
    let attempt = FixtureCryptography().authorizationAttempt()
    precondition(full.oauthClientID != personal.oauthClientID)
    precondition(full.callbackURL.absoluteString == "https://auth.example.com/ios/oauth/callback")
    precondition(
      personal.callbackURL.absoluteString == "com.example.fitlife:/ios/oauth/callback")
    for configuration in [full, personal] {
      for manage in [false, true] {
        let request = try attempt.authorizationURL(
          configuration: configuration, manageAccount: manage)
        let query = URLComponents(url: request, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(
          query.first(where: { $0.name == "client_id" })?.value == configuration.oauthClientID)
        precondition(
          query.first(where: { $0.name == "redirect_uri" })?.value
            == configuration.callbackURL.absoluteString)
        precondition(query.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
        precondition(query.first(where: { $0.name == "scope" })?.value == "profile offline_access")
      }
    }
    for scheme in [
      "", "fitlife", "https", "Com.example", "com..example", "com.-example", "com.example-",
      "com.example:/callback", "com.example\n", "com." + String(repeating: "a", count: 64),
    ] {
      do {
        _ = try ServerConfiguration(
          authenticationURL: auth, backendURL: api, callback: .customScheme(scheme))
        preconditionFailure("Accepted invalid callback scheme")
      } catch ServerError.invalidConfiguration {}
    }
    var info: [String: Any] = [
      "FitLifeAuthenticationURL": auth.absoluteString,
      "FitLifeBackendURL": api.absoluteString,
    ]
    let legacyConfiguration = try ServerConfiguration.configured(info: info)
    precondition(legacyConfiguration?.callback == .https)
    info["FitLifeAuthenticationCallbackMode"] = "customScheme"
    info["FitLifeAuthenticationCallbackScheme"] = "com.example.fitlife"
    let personalConfiguration = try ServerConfiguration.configured(info: info)
    precondition(personalConfiguration?.callback == .customScheme("com.example.fitlife"))
    info["FitLifeAuthenticationCallbackMode"] = "$(UNEXPANDED_MODE)"
    do {
      _ = try ServerConfiguration.configured(info: info)
      preconditionFailure("Accepted unknown callback mode")
    } catch ServerError.invalidConfiguration {}

    for callback in [
      "https://auth.example.com/ios/oauth/callback?code=a&state=expected-state",
      "com.example.other:/ios/oauth/callback?code=a&state=expected-state",
      "com.example.fitlife://host/ios/oauth/callback?code=a&state=expected-state",
      "com.example.fitlife:/ios/%6Fauth/callback?code=a&state=expected-state",
      "com.example.fitlife:/other?code=a&state=expected-state",
      "com.example.fitlife:/ios/oauth/callback?code=a&state=wrong",
      "com.example.fitlife:/ios/oauth/callback?code=a&state=expected-state&state=expected-state",
      "com.example.fitlife:/ios/oauth/callback?code=a&state=expected-state&iss=https%3A%2F%2Fattacker.example.com%2F",
      "com.example.fitlife:/ios/oauth/callback?code=a&state=expected-state#fragment",
    ] {
      do {
        _ = try attempt.code(from: URL(string: callback)!, configuration: personal)
        preconditionFailure("Accepted wrong or ambiguous callback")
      } catch ServerError.invalidCallback {}
    }

    // Полный жизненный цикл проверяет выбор client_id при code, refresh и revoke.
    for configuration in [full, personal] {
      let credentials = FixtureCredentials()
      let transport = URLSessionConfiguration.ephemeral
      transport.protocolClasses = [AccountProtocol.self]
      let urlSession = URLSession(configuration: transport)
      defer { urlSession.invalidateAndCancel() }
      let session = AccountSession(
        configuration: configuration, http: ServerHTTPClient(session: urlSession),
        credentials: credentials)
      var callback = URLComponents(url: configuration.callbackURL, resolvingAgainstBaseURL: false)!
      callback.queryItems = [
        URLQueryItem(name: "code", value: "one-time-code"),
        URLQueryItem(name: "state", value: "expected-state"),
      ]
      _ = try await session.finishAuthorization(attempt, callback: callback.url!)
      let client = RemoteBackupClient(session: session, cryptography: FixtureCryptography())
      let backups = try await client.list()
      precondition(backups.isEmpty)
      try await session.logout()
      let remainingCredentials = await credentials.load()
      precondition(remainingCredentials == nil)
      for operation in ["authorization_code", "refresh_token", "revoke"] {
        precondition(
          AccountProtocol.operations.withLock { $0[configuration.oauthClientID + operation] } == 1)
      }
      let model = AccountBackupViewModel(
        session: session, client: client,
        snapshot: { throw ServerError.invalidConfiguration },
        preview: { _ in preconditionFailure("Unexpected import") })
      await model.perform(.signIn) { _ in throw ServerError.authenticationCancelled }
      precondition(!model.isBusy && model.errorMessage == nil && model.notice != nil)
      precondition(!model.noticeIsSuccess)
      await model.perform(.signIn) { _ in throw CancellationError() }
      precondition(!model.isBusy && model.errorMessage == nil && model.notice == nil)
      await model.perform(.signIn) { _ in throw ServerError.invalidCallback }
      precondition(model.errorMessage != nil && model.retryAction == .signIn)
    }
    print(
      "Account checks: HTTPS/custom callback isolation, strict validation, PKCE requests, code/refresh/revoke client binding and cancellation feedback OK (HTTP fixtures; no Apple SDK)."
    )
  }
}
