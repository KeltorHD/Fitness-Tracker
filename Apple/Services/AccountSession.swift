import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

actor AccountSession {
  let configuration: ServerConfiguration
  private let http: ServerHTTPClient
  private let credentials: any AccountTokenStoring
  private var tokens: AccountTokens?
  private var loaded = false
  private var generation = 0
  private var refresh: (id: UUID, task: Task<AccountTokens, any Error>)?

  init(
    configuration: ServerConfiguration, http: ServerHTTPClient, credentials: any AccountTokenStoring
  ) {
    self.configuration = configuration
    self.http = http
    self.credentials = credentials
  }

  func profile() async throws -> AccountProfile? {
    try await loadCredentials()
    return tokens?.profile
  }

  func finishAuthorization(_ attempt: OAuthAttempt, callback: URL) async throws -> AccountProfile {
    let code = try attempt.code(from: callback, configuration: configuration)
    generation += 1
    let current = generation
    refresh?.task.cancel()
    refresh = nil
    var request = URLRequest(
      url: configuration.authenticationURL.appendingPathComponent("connect/token"))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = ServerJSON.form([
      ("grant_type", "authorization_code"), ("client_id", configuration.oauthClientID),
      ("redirect_uri", configuration.callbackURL.absoluteString), ("code", code),
      ("code_verifier", attempt.verifier),
    ])
    let response = try ServerJSON.decode(TokenResponse.self, from: await http.send(request))
    try response.validate()
    var profileRequest = URLRequest(
      url: configuration.authenticationURL.appendingPathComponent("v1/account"))
    profileRequest.setValue("Bearer \(response.accessToken)", forHTTPHeaderField: "Authorization")
    let profile = try ServerJSON.decode(AccountProfile.self, from: await http.send(profileRequest))
    guard UUID(uuidString: profile.id) != nil, generation == current else {
      throw ServerError.invalidResponse
    }
    let value = response.session(profile: profile)
    try Task.checkCancellation()
    try await credentials.save(value)
    guard generation == current else { throw CancellationError() }
    tokens = value
    loaded = true
    return profile
  }

  func authorizedData(_ request: URLRequest, maximumBytes: Int = 65_536) async throws -> Data {
    let current = generation
    let token = try await accessToken()
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let data = try await http.send(request, maximumBytes: maximumBytes)
      guard current == generation else { throw CancellationError() }
      return data
    } catch ServerError.signInRequired {
      let replacement = try await accessToken(rejected: token)
      guard current == generation else { throw CancellationError() }
      request.setValue("Bearer \(replacement)", forHTTPHeaderField: "Authorization")
      let data = try await http.send(request, maximumBytes: maximumBytes)
      guard current == generation else { throw CancellationError() }
      return data
    }
  }

  func logout() async throws {
    try await loadCredentials()
    // Finish an in-flight rotation before revoking its latest refresh token.
    if let refresh {
      tokens = try await refresh.task.value
      if self.refresh?.id == refresh.id { self.refresh = nil }
    }
    if let value = tokens {
      var request = URLRequest(
        url: configuration.authenticationURL.appendingPathComponent("connect/revoke"))
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody = ServerJSON.form([
        ("client_id", configuration.oauthClientID), ("token", value.refreshToken),
        ("token_type_hint", "refresh_token"),
      ])
      _ = try await http.send(request)
    }
    try await forget()
  }

  func deleteAccount() async throws {
    var request = URLRequest(
      url: configuration.authenticationURL.appendingPathComponent("v1/account"))
    request.httpMethod = "DELETE"
    _ = try await authorizedData(request)
    try await forget()
  }

  private func forget() async throws {
    generation += 1
    refresh?.task.cancel()
    refresh = nil
    try await credentials.clear()
    tokens = nil
    loaded = true
  }

  private func loadCredentials() async throws {
    guard !loaded else { return }
    let current = generation
    let saved = try await credentials.load()
    guard generation == current else { throw CancellationError() }
    guard !loaded else { return }
    tokens = saved
    loaded = true
  }

  private func accessToken(rejected: String? = nil) async throws -> String {
    try await loadCredentials()
    guard let value = tokens else { throw ServerError.signInRequired }
    if value.expiresAt.timeIntervalSinceNow > 60 && value.accessToken != rejected {
      return value.accessToken
    }
    let current = generation
    let pending: (id: UUID, task: Task<AccountTokens, any Error>)
    if let refresh {
      pending = refresh
    } else {
      let http = http
      let credentials = credentials
      let clientID = configuration.oauthClientID
      let url = configuration.authenticationURL.appendingPathComponent("connect/token")
      // The session owns this shared rotation. Cancelling one screen must not lose a rotated token.
      let task = Task<AccountTokens, any Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ServerJSON.form([
          ("grant_type", "refresh_token"), ("client_id", clientID),
          ("refresh_token", value.refreshToken),
        ])
        let response: TokenResponse
        do {
          response = try ServerJSON.decode(TokenResponse.self, from: await http.send(request))
        } catch ServerError.rejected(400) {
          throw ServerError.signInRequired
        }
        try response.validate()
        let replacement = response.session(profile: value.profile)
        try Task.checkCancellation()
        try await credentials.save(replacement)
        return replacement
      }
      pending = (UUID(), task)
      refresh = pending
    }
    do {
      let replacement = try await pending.task.value
      guard generation == current else { throw CancellationError() }
      tokens = replacement
      if refresh?.id == pending.id { refresh = nil }
      return replacement.accessToken
    } catch {
      if refresh?.id == pending.id { refresh = nil }
      if error as? ServerError == .signInRequired, generation == current { try await forget() }
      throw error
    }
  }
}

private struct TokenResponse: Decodable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Double
  let tokenType: String
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case tokenType = "token_type"
  }

  func validate() throws {
    guard !accessToken.isEmpty, !refreshToken.isEmpty, tokenType.lowercased() == "bearer",
      expiresIn.isFinite, expiresIn > 0, expiresIn <= 86_400
    else { throw ServerError.invalidResponse }
  }

  func session(profile: AccountProfile) -> AccountTokens {
    AccountTokens(
      accessToken: accessToken, refreshToken: refreshToken,
      expiresAt: Date().addingTimeInterval(expiresIn), profile: profile)
  }
}
