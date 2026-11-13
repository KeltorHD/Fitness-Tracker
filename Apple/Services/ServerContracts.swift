import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum ServerCallback: Equatable, Sendable {
  case https
  case customScheme(String)
}

struct ServerConfiguration: Equatable, Sendable {
  static let clientID = "fitlife-ios"
  static let personalClientID = "fitlife-ios-personal"
  static let callbackPath = "/ios/oauth/callback"
  let callbackHost: String
  let callback: ServerCallback
  let callbackURL: URL
  var oauthClientID: String { callback == .https ? Self.clientID : Self.personalClientID }
  let authenticationURL: URL
  let backendURL: URL

  init(authenticationURL: URL, backendURL: URL, callback: ServerCallback = .https) throws {
    for url in [authenticationURL, backendURL] {
      guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
        url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/"
      else { throw ServerError.invalidConfiguration }
    }
    guard let host = authenticationURL.host else { throw ServerError.invalidConfiguration }
    self.callbackHost = host
    self.callback = callback
    switch callback {
    case .https:
      callbackURL = authenticationURL.appendingPathComponent("ios/oauth/callback")
    case .customScheme(let scheme):
      let labels = scheme.split(separator: ".", omittingEmptySubsequences: false)
      guard scheme.count <= 253, labels.count >= 2,
        scheme.first.map({ ("a"..."z").contains(String($0)) }) == true,
        labels.allSatisfy({
          $0.range(of: "\\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\z", options: .regularExpression)
            != nil
        }),
        let url = URL(string: scheme + ":" + Self.callbackPath)
      else { throw ServerError.invalidConfiguration }
      callbackURL = url
    }
    self.authenticationURL = authenticationURL.appendingPathComponent("")
    self.backendURL = backendURL.appendingPathComponent("")
  }

  static func configured(in bundle: Bundle = .main) throws -> Self? {
    try configured(info: bundle.infoDictionary ?? [:])
  }

  static func configured(info: [String: Any]) throws -> Self? {
    let auth = info["FitLifeAuthenticationURL"] as? String ?? ""
    let api = info["FitLifeBackendURL"] as? String ?? ""
    guard !auth.isEmpty || !api.isEmpty else { return nil }
    guard let authURL = URL(string: auth), let apiURL = URL(string: api) else {
      throw ServerError.invalidConfiguration
    }
    let callback: ServerCallback
    switch info["FitLifeAuthenticationCallbackMode"] as? String ?? "https" {
    case "https": callback = .https
    case "customScheme":
      callback = .customScheme(info["FitLifeAuthenticationCallbackScheme"] as? String ?? "")
    default: throw ServerError.invalidConfiguration
    }
    return try Self(authenticationURL: authURL, backendURL: apiURL, callback: callback)
  }
}

enum ServerError: Error, Equatable, LocalizedError, Sendable {
  case invalidConfiguration, invalidResponse, invalidCallback, signInRequired,
    authenticationCancelled
  case rateLimited, unavailable, credentialStorage
  case rejected(Int)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration: "Синхронизация с сервером пока недоступна."
    case .invalidResponse: "Не удалось проверить ответ сервера. Повторите попытку."
    case .invalidCallback: "Не удалось подтвердить вход. Попробуйте войти ещё раз."
    case .signInRequired: "Войдите в аккаунт для синхронизации тренировок."
    case .authenticationCancelled: "Вход в аккаунт не завершён."
    case .rateLimited: "Слишком много запросов. Подождите минуту и повторите попытку."
    case .unavailable: "Сервер недоступен. Проверьте подключение и повторите попытку."
    case .credentialStorage:
      "Не удалось открыть защищённую сессию. Разблокируйте устройство и повторите попытку."
    case .rejected: "Сервер не смог выполнить запрос. Повторите попытку."
    }
  }
}

/// Expected server decisions carry typed current data for reconciliation, never diagnostic logging.
struct ServerTrainingError: Error, LocalizedError, Sendable {
  let code: String
  let current: TrainingChange?
  var errorDescription: String? {
    switch code {
    case "training_conflict":
      "Есть изменения с другого устройства. Выберите, какие данные сохранить."
    case "workout_missing": "Не удалось синхронизировать связанную тренировку. Повторите попытку."
    case "cursor_reset_required": "Серверный журнал изменился. Проверьте расхождения данных."
    case "training_limit": "Достигнут предел записей серверного журнала."
    case "account_deleted": "Аккаунт удалён. Войдите в аккаунт заново."
    case "server_update_required": "Для синхронизации тренировок требуется обновить сервер."
    case "record_too_large":
      "Одна из записей слишком велика для синхронизации. Локальные данные сохранены."
    case "local_changed": "Запись изменилась на устройстве. Обновите предпросмотр."
    default: "Сервер не принял изменения. Локальные данные сохранены."
    }
  }
}

struct AccountProfile: Codable, Equatable, Sendable {
  let id: String
  let name: String
  let createdAt: Date
  let logins: [String]
}

struct AccountTokens: Codable, Equatable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Date
  let profile: AccountProfile
}

struct OAuthAttempt: Equatable, Sendable {
  let verifier: String
  let state: String
  let challenge: String

  func authorizationURL(
    configuration: ServerConfiguration, manageAccount: Bool, manageHealth: Bool = false
  ) throws -> URL {
    guard
      var parts = URLComponents(
        url: configuration.authenticationURL.appendingPathComponent("connect/authorize"),
        resolvingAgainstBaseURL: false)
    else { throw ServerError.invalidConfiguration }
    // Identity is fetched from the protected profile endpoint; ID tokens are not used by this client.
    parts.queryItems = [
      URLQueryItem(name: "client_id", value: configuration.oauthClientID),
      URLQueryItem(name: "redirect_uri", value: configuration.callbackURL.absoluteString),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "profile offline_access"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    if !manageAccount {
      parts.queryItems?.append(URLQueryItem(name: "prompt", value: "select_account"))
    }
    if manageAccount {
      parts.queryItems?.append(
        URLQueryItem(name: "screen", value: manageHealth ? "health" : "account"))
    }
    guard let url = parts.url else { throw ServerError.invalidConfiguration }
    return url
  }

  func code(from callback: URL, configuration: ServerConfiguration) throws -> String {
    guard callback.scheme == configuration.callbackURL.scheme,
      callback.host == configuration.callbackURL.host,
      URLComponents(url: callback, resolvingAgainstBaseURL: false)?.percentEncodedPath
        == ServerConfiguration.callbackPath,
      callback.user == nil, callback.password == nil,
      callback.port == configuration.callbackURL.port,
      callback.fragment == nil,
      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
      Set(items.map(\.name)).count == items.count,
      items.first(where: { $0.name == "state" })?.value == state
    else { throw ServerError.invalidCallback }
    if let issuer = items.first(where: { $0.name == "iss" })?.value,
      issuer != configuration.authenticationURL.absoluteString
    {
      throw ServerError.invalidCallback
    }
    if items.first(where: { $0.name == "error" })?.value == "access_denied" {
      throw CancellationError()
    }
    guard !items.contains(where: { $0.name == "error" }),
      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 4096
    else { throw ServerError.invalidCallback }
    return code
  }
}

protocol AccountTokenStoring: Sendable {
  func load() async throws -> AccountTokens?
  func save(_ tokens: AccountTokens) async throws
  func clear() async throws
}

protocol ServerCryptography: Sendable {
  func authorizationAttempt() throws -> OAuthAttempt
  func sha256(_ data: Data) -> String
}

enum ServerJSON {
  static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let string = try decoder.singleValueContainer().decode(String.self)
      if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
        return date
      }
      return try Date.ISO8601FormatStyle().parse(string)
    }
    do { return try decoder.decode(type, from: data) } catch { throw ServerError.invalidResponse }
  }

  static func form(_ fields: [(String, String)]) -> Data {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return Data(
      fields.map { key, value in
        "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
      }.joined(separator: "&").utf8)
  }
}
