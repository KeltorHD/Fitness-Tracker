import CloudKit
import Foundation

@MainActor struct CloudKitService: CloudAccountChecking {
  var available = AppCapabilities.current.supportsCloudSync
  var containerIdentifier: String? =
    Bundle.main.object(
      forInfoDictionaryKey: "FitSessionCloudContainer") as? String

  func accountStatus() async throws -> CloudAccountStatus {
    guard available else {
      throw ServiceError.unavailable("Синхронизация iCloud сейчас недоступна.")
    }
    guard let id = containerIdentifier, !id.isEmpty, !id.contains("$(") else {
      throw ServiceError.unavailable("Проверка iCloud сейчас недоступна.")
    }
    let status = try await CKContainer(identifier: id).accountStatus()
    switch status {
    case .available: return .available
    case .noAccount: return .noAccount
    case .restricted: return .restricted
    case .temporarilyUnavailable: return .temporarilyUnavailable
    default: return .unknown
    }
  }
}
