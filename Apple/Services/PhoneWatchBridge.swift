import FitSessionCore
import Foundation
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
  var receive: ((Workout) -> Bool)?
  var failure: ((any Error) -> Void)?
  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error { Task { @MainActor in self.failure?(error) } }
  }
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let data = userInfo["workout"] as? Data else { return }
    Task { @MainActor in
      do {
        let workout = try JSONDecoder().decode(Workout.self, from: data)
        try Validation.workout(workout)
        guard workout.status == .completed else { throw TrainingError.invalidState }
        if self.receive?(workout) == true {
          WCSession.default.transferUserInfo(["ack": workout.id.uuidString])
        }
      } catch { self.failure?(error) }
    }
  }
}
