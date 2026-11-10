import FitnessTrackerCore
import Foundation
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
  var sleepEvent: ((SleepAlarmWatchEvent) -> Void)?
  var sleepReady: (() -> Void)?
  var sleepConnection: ((Bool, Bool) -> Void)?
  private func updateSleepConnection() {
    let session = WCSession.default
    let paired =
      session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    sleepConnection?(paired, paired && session.isReachable)
  }
  func sendSleepAlarms(_ value: SleepAlarmSync) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated,
      WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
    else { return }
    do {
      try WCSession.default.updateApplicationContext([
        "sleepAlarms": try JSONEncoder().encode(value)
      ])
    } catch { failure?(error) }
  }
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
    if let error {
      Task { @MainActor in self.failure?(error) }
    } else {
      Task { @MainActor in
        self.updateSleepConnection()
        self.sleepReady?()
      }
    }
  }
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    Task { @MainActor in self.sleepConnection?(false, false) }
  }
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in self.updateSleepConnection() }
  }
  nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor in
      self.updateSleepConnection()
      self.sleepReady?()
    }
  }
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    self.session(session, didReceiveUserInfo: message)
  }
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    if let data = userInfo["sleepAlarmEvent"] as? Data {
      Task { @MainActor in
        do {
          self.sleepEvent?(try JSONDecoder().decode(SleepAlarmWatchEvent.self, from: data))
        } catch { self.failure?(error) }
      }
      return
    }
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
