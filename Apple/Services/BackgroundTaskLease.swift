import UIKit

/// Finite time to finish a pending system update, never an always-running workout loop.
@MainActor final class BackgroundTaskLease {
  private var identifier: UIBackgroundTaskIdentifier = .invalid
  private var onExpiration: (@MainActor () -> Void)?

  func begin(onExpiration: @escaping @MainActor () -> Void) {
    self.onExpiration = onExpiration
    identifier = UIApplication.shared.beginBackgroundTask(withName: "FitnessTracker.LiveActivity") {
      [weak self] in
      // UIKit invokes the expiration handler on the main thread; release before returning.
      MainActor.assumeIsolated {
        self?.onExpiration?()
        self?.end()
      }
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
    onExpiration = nil
  }
}
