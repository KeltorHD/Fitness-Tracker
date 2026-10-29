import Foundation

enum CloudAccountStatus: Sendable {
  case available, noAccount, restricted, temporarilyUnavailable, unknown

  var message: String {
    switch self {
    case .available: "Учётная запись iCloud доступна."
    case .noAccount: "Войдите в iCloud в настройках устройства."
    case .restricted: "Доступ к iCloud ограничен."
    case .temporarilyUnavailable: "iCloud временно недоступен. Попробуйте позже."
    case .unknown: "Не удалось определить состояние iCloud. Попробуйте ещё раз."
    }
  }
}

@MainActor protocol CloudAccountChecking {
  func accountStatus() async throws -> CloudAccountStatus
}
