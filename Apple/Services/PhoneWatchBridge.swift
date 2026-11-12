import FitnessTrackerCore
import Foundation
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
  var sleepEvent: ((SleepAlarmWatchEvent) -> Void)?
  var sleepReady: (() -> Void)?
  var sleepConnection: ((SleepWatchConnection) -> Void)?
  var heartRateEvent: ((WatchHeartRateEvent) -> Void)?
  var heartRateFailure: ((UUID) -> Void)?
  var heartRateDisconnected: (() -> Void)?
  private func updateSleepConnection() {
    let session = WCSession.default
    let state: SleepWatchConnection
    if session.activationState != .activated {
      state = .checking
    } else if !session.isPaired {
      state = .notPaired
    } else if !session.isWatchAppInstalled {
      state = .appNotInstalled
    } else {
      state = session.isReachable ? .reachable : .unreachable
    }
    sleepConnection?(state)
    if state != .reachable { heartRateDisconnected?() }
  }
  func sendHeartRateCommand(_ command: WatchHeartRateCommand) throws {
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled
    else {
      throw ServiceError.unavailable(
        "Установите FitnessTracker на Apple Watch и откройте приложение на часах.")
    }
    let data = try JSONEncoder().encode(command)
    if command.action == .stop || command.action == .pause {
      var context = session.applicationContext
      context["heartRateCommand"] = data
      try session.updateApplicationContext(context)
    }
    guard session.isReachable else {
      if command.action == .stop { return }
      throw ServiceError.unavailable(
        "Откройте FitnessTracker на Apple Watch и держите часы рядом с iPhone.")
    }
    session.sendMessage(["heartRateCommand": data], replyHandler: nil) { [weak self] _ in
      Task { @MainActor in self?.heartRateFailure?(command.sessionID) }
    }
  }
  func sendSleepAlarms(_ value: SleepAlarmSync) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated,
      WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
    else { return }
    do {
      var context = WCSession.default.applicationContext
      context["sleepAlarms"] = try JSONEncoder().encode(value)
      try WCSession.default.updateApplicationContext(context)
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
    Task { @MainActor in
      self.sleepConnection?(.checking)
      self.heartRateDisconnected?()
    }
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
    if let data = message["heartRateEvent"] as? Data, data.count <= 2048 {
      Task { @MainActor in
        do {
          self.heartRateEvent?(try JSONDecoder().decode(WatchHeartRateEvent.self, from: data))
        } catch { self.failure?(error) }
      }
      return
    }
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
