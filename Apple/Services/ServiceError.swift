import Foundation

enum ServiceError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    if case .unavailable(let message) = self { message } else { nil }
  }
}
