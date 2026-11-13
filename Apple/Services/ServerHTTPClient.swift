import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Never follow a server redirect with credentials, and never share the browser's cookies/cache.
final class ServerRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

struct ServerHTTPClient: Sendable {
  let session: URLSession

  init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 120
      self.session = URLSession(
        configuration: configuration, delegate: ServerRedirectPolicy(), delegateQueue: nil)
    }
  }

  func send(_ request: URLRequest, maximumBytes: Int = 65_536) async throws -> Data {
    var request = request
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
      throw ServerError.unavailable
    }
    guard let response = response as? HTTPURLResponse, data.count <= maximumBytes else {
      throw ServerError.invalidResponse
    }
    if [400, 403, 409, 413, 429, 502, 503].contains(response.statusCode) {
      struct TrainingFailure: Decodable {
        let code: String
        let current: TrainingChange?
      }
      if let failure = try? TrainingCoding.decoder().decode(TrainingFailure.self, from: data),
        failure.code.hasPrefix("health_") || failure.code.hasPrefix("invalid_health_")
      {
        switch failure.code {
        case "health_not_connected": throw HealthDataError.notConnected
        case "health_permission_required": throw HealthDataError.permissionRequired
        case "health_rate_limited": throw ServerError.rateLimited
        case "health_provider_unavailable": throw HealthDataError.unavailable
        default: throw HealthDataError.invalidData
        }
      }
      if let failure = try? TrainingCoding.decoder().decode(TrainingFailure.self, from: data),
        failure.code.hasPrefix("training_") || failure.code.hasPrefix("invalid_training_")
          || [
            "workout_missing", "cursor_reset_required", "account_deleted", "invalid_cursor",
            "record_too_large",
          ]
          .contains(failure.code)
      {
        throw ServerTrainingError(code: failure.code, current: failure.current)
      }
    }
    switch response.statusCode {
    case 200..<300: return data
    case 401: throw ServerError.signInRequired
    case 429: throw ServerError.rateLimited
    case 500..<600: throw ServerError.unavailable
    default: throw ServerError.rejected(response.statusCode)
    }
  }
}
