import CloudKit
import Foundation

@MainActor enum CloudKitService {
  static func accountDescription() async throws -> String {
    let id = Bundle.main.object(forInfoDictionaryKey: "FitSessionCloudContainer") as? String ?? ""
    let status = try await CKContainer(identifier: id).accountStatus()
    switch status {
    case .available:
      return "Учётная запись iCloud доступна. Синхронизация SwiftData выполняется системой."
    case .noAccount: return "Войдите в iCloud в настройках устройства."
    case .restricted: return "Доступ к iCloud ограничен."
    case .temporarilyUnavailable: return "iCloud временно недоступен."
    default: return "Не удалось определить состояние iCloud."
    }
  }
}
