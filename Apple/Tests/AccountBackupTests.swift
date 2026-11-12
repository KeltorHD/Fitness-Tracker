import FitLifeCore
import Foundation
import Synchronization
import XCTest

@testable import FitLife

private actor AccountCredentialFixture: AccountTokenStoring {
  var value: AccountTokens?
  var writes = 0
  let failsToSave: Bool

  init(_ value: AccountTokens?, failsToSave: Bool = false) {
    self.value = value
    self.failsToSave = failsToSave
  }

  func load() -> AccountTokens? { value }
  func save(_ value: AccountTokens) throws {
    if failsToSave { throw ServerError.credentialStorage }
    self.value = value
    writes += 1
  }
  func clear() { value = nil }
}

private final class AccountURLProtocol: URLProtocol {
  static let counts = Mutex<[String: Int]>([:])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { preconditionFailure("Missing fixture URL") }
    Self.counts.withLock { $0[url.absoluteString, default: 0] += 1 }
    let host = url.host ?? ""
    if host.hasPrefix("offline") {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let status: Int
    let body: String
    if url.path == "/connect/token" {
      status = host.hasPrefix("expired") ? 400 : 200
      body =
        status == 400
        ? #"{"error":"invalid_grant"}"#
        : #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":600}"#
    } else {
      status = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? 200 : 401
      body = "[]"
    }
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else {
      preconditionFailure("Invalid fixture response")
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor final class AccountBackupTests: XCTestCase {
  func testAuthorizationRequestsProtocolScopesWithoutBackendPermissions() throws {
    let authURL = try XCTUnwrap(URL(string: "https://auth.example.com/"))
    let backendURL = try XCTUnwrap(URL(string: "https://api.example.com/"))
    let configuration = try ServerConfiguration(authenticationURL: authURL, backendURL: backendURL)
    let attempt = OAuthAttempt(verifier: "verifier", state: "expected", challenge: "challenge")
    for manageAccount in [false, true] {
      let url = try attempt.authorizationURL(
        configuration: configuration, manageAccount: manageAccount)
      let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
      XCTAssertEqual(query.first(where: { $0.name == "scope" })?.value, "profile offline_access")
    }
  }

  private func setup(prefix: String = "ok", failsToSave: Bool = false) throws -> (
    AccountSession, AccountCredentialFixture, URLRequest
  ) {
    let host = "\(prefix)-\(UUID().uuidString.lowercased()).test"
    let url = try XCTUnwrap(URL(string: "https://\(host)/"))
    let configuration = try ServerConfiguration(authenticationURL: url, backendURL: url)
    let profile = AccountProfile(
      id: UUID().uuidString, name: "Test", createdAt: .now, logins: ["Apple"])
    let credentials = AccountCredentialFixture(
      AccountTokens(
        accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantPast,
        profile: profile),
      failsToSave: failsToSave)
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [AccountURLProtocol.self]
    let http = ServerHTTPClient(session: URLSession(configuration: transport))
    return (
      AccountSession(configuration: configuration, http: http, credentials: credentials),
      credentials, URLRequest(url: url.appendingPathComponent("v1/backups"))
    )
  }

  func testParallelRequestsShareOneRotationAndPersistBeforeUsingTheToken() async throws {
    let (session, credentials, request) = try setup()
    try await withThrowingTaskGroup(of: Data.self) { group in
      for _ in 0..<8 { group.addTask { try await session.authorizedData(request) } }
      for try await data in group { XCTAssertEqual(data, Data("[]".utf8)) }
    }
    let value = await credentials.value
    let writes = await credentials.writes
    XCTAssertEqual(value?.refreshToken, "new-refresh")
    XCTAssertEqual(writes, 1)
    let configuration = await session.configuration
    let endpoint = configuration.authenticationURL.appendingPathComponent("connect/token")
      .absoluteString
    XCTAssertEqual(AccountURLProtocol.counts.withLock { $0[endpoint] }, 1)
  }

  func testRejectedRefreshClearsOnlyCredentialsAndRequiresSignIn() async throws {
    let (session, credentials, request) = try setup(prefix: "expired")
    do {
      _ = try await session.authorizedData(request)
      XCTFail("Expected expired session")
    } catch let error as ServerError { XCTAssertEqual(error, .signInRequired) }
    let profile = try await session.profile()
    let saved = await credentials.value
    XCTAssertNil(profile)
    XCTAssertNil(saved)
  }

  func testNetworkAndCredentialFailuresKeepTheExistingSessionForRetry() async throws {
    for (prefix, failingVault, expected) in [
      ("offline", false, ServerError.unavailable), ("ok", true, ServerError.credentialStorage),
    ] {
      let (session, credentials, request) = try setup(prefix: prefix, failsToSave: failingVault)
      do {
        _ = try await session.authorizedData(request)
        XCTFail("Expected fixture failure")
      } catch let error as ServerError { XCTAssertEqual(error, expected) }
      let saved = await credentials.value
      XCTAssertEqual(saved?.refreshToken, "old-refresh")
    }
  }

  func testCallbackRejectsWrongStateOriginIssuerAndDuplicateParameters() throws {
    let url = try XCTUnwrap(URL(string: "https://auth.example.com/"))
    let config = try ServerConfiguration(authenticationURL: url, backendURL: url)
    let attempt = OAuthAttempt(verifier: "verifier", state: "expected", challenge: "challenge")
    for value in [
      "fitnesstracker://oauth/callback?code=a&state=expected",
      "https://auth.example.com/other?code=a&state=expected",
      "http://auth.example.com/ios/oauth/callback?code=a&state=expected",
      "https://auth.example.com:444/ios/oauth/callback?code=a&state=expected",
      "https://auth.example.com/ios/oauth/callback?code=a&state=wrong",
      "https://attacker.test/ios/oauth/callback?code=a&state=expected",
      "https://auth.example.com/ios/oauth/callback?code=a&state=expected&state=expected",
      "https://auth.example.com/ios/oauth/callback?code=a&state=expected&iss=https%3A%2F%2Fattacker.test%2F",
      "https://auth.example.com/ios/oauth/callback?code=a&state=expected#fragment",
    ] {
      XCTAssertThrowsError(
        try attempt.code(from: XCTUnwrap(URL(string: value)), configuration: config))
    }
    let valid = try XCTUnwrap(
      URL(string: "https://auth.example.com/ios/oauth/callback?code=one-time&state=expected"))
    XCTAssertEqual(try attempt.code(from: valid, configuration: config), "one-time")
    XCTAssertEqual(
      AppleServerCryptography().sha256(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  func testRestoreChecksIntegrityBeforeOpeningImport() async throws {
    let (session, _, _) = try setup()
    let client = RemoteBackupClient(session: session, cryptography: AppleServerCryptography())
    let corrupt = RemoteBackup(
      id: UUID(), createdAt: .now, archiveVersion: 4, size: 2,
      sha256: String(repeating: "0", count: 64))
    do {
      _ = try await client.download(corrupt)
      XCTFail("Expected integrity error")
    } catch let error as ServerError { XCTAssertEqual(error, .invalidResponse) }
  }
}
