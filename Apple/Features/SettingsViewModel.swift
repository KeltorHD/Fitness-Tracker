import Foundation
import Observation

@MainActor @Observable final class SettingsViewModel {
  enum CloudState: Equatable {
    case idle, loading
    case result(String)
    case failed

    var message: String? {
      switch self {
      case .idle, .loading: nil
      case .result(let message): message
      case .failed: "Не удалось проверить iCloud. Проверьте подключение и попробуйте ещё раз."
      }
    }
  }
  private(set) var cloudState = CloudState.idle
  private(set) var requestingNotifications = false
  private(set) var notificationMessage: String?
  @ObservationIgnored private let cloud: any CloudAccountChecking
  @ObservationIgnored private let notifications: any RestNotificationServing
  @ObservationIgnored private var cloudRequestID: UUID?
  @ObservationIgnored private var notificationRequestID: UUID?

  init(cloud: any CloudAccountChecking, notifications: any RestNotificationServing) {
    self.cloud = cloud
    self.notifications = notifications
  }

  /// The caller's SwiftUI .task owns cancellation when its screen disappears or retries.
  func checkCloudAccount() async {
    let requestID = UUID()
    cloudRequestID = requestID
    cloudState = .loading
    defer {
      if cloudRequestID == requestID {
        cloudRequestID = nil
        if cloudState == .loading { cloudState = .idle }
      }
    }
    do {
      let status = try await cloud.accountStatus()
      try Task.checkCancellation()
      guard cloudRequestID == requestID else { return }
      cloudState = .result(status.message)
    } catch {
      guard cloudRequestID == requestID, !Task.isCancelled, !(error is CancellationError) else {
        return
      }
      AppErrorReporter.record(error, operation: "checkCloudAccount")
      cloudState = .failed
    }
  }

  func authorizeNotifications() async -> Bool? {
    let requestID = UUID()
    notificationRequestID = requestID
    requestingNotifications = true
    notificationMessage = nil
    defer {
      if notificationRequestID == requestID {
        notificationRequestID = nil
        requestingNotifications = false
      }
    }
    do {
      let allowed = try await notifications.authorize()
      try Task.checkCancellation()
      guard notificationRequestID == requestID else { return nil }
      if !allowed {
        notificationMessage = "Разрешите уведомления FitnessTracker в настройках устройства."
      }
      return allowed
    } catch {
      guard notificationRequestID == requestID, !Task.isCancelled, !(error is CancellationError)
      else { return nil }
      AppErrorReporter.record(error, operation: "authorizeNotifications")
      notificationMessage = "Не удалось включить уведомления. Попробуйте ещё раз."
      return false
    }
  }
}
