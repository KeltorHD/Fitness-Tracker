import FitnessTrackerCore
import Foundation
import Observation
import WatchConnectivity
import WatchKit

private struct WatchArchive: Codable {
  var active: Workout?
  var pending: [Workout] = []
}

/// A wrist set logger with a separately owned, explicit HealthKit heart-rate session.
@MainActor @Observable final class WatchStore: NSObject, WCSessionDelegate {
  let sleepAlarm = WatchSleepAlarm()
  let heartRate = WatchHeartRateController(source: HealthKitLiveHeartRateService())
  private(set) var active: Workout?
  private(set) var pending: [Workout] = []
  var error: String?
  @ObservationIgnored private var archiveURL: URL?
  @ObservationIgnored private var archiveReadable = true
  override init() {
    super.init()
    heartRate.send = { [weak self] event in
      guard WCSession.default.activationState == .activated else {
        self?.heartRate.deliveryFailed()
        return
      }
      do {
        let data = try JSONEncoder().encode(event)
        WCSession.default.sendMessage(["heartRateEvent": data], replyHandler: nil) {
          [weak self] _ in
          Task { @MainActor in self?.heartRate.deliveryFailed() }
        }
      } catch { self?.heartRate.deliveryFailed() }
    }
    sleepAlarm.send = { [weak self] event in
      guard WCSession.default.activationState == .activated else { return }
      do {
        let message = ["sleepAlarmEvent": try JSONEncoder().encode(event)]
        // Durable delivery also covers a failed immediate send; duplicates are idempotent.
        WCSession.default.transferUserInfo(message)
        if WCSession.default.isReachable {
          WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
      } catch { self?.error = L10n.text("Не удалось отправить состояние будильника на iPhone.") }
    }
    do {
      let folder = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
      archiveURL = folder.appendingPathComponent(AppCompatibility.watchArchiveFileName)
      if let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) {
        let archive = try JSONDecoder().decode(
          WatchArchive.self, from: Data(contentsOf: archiveURL))
        if let workout = archive.active { try Validation.workout(workout) }
        for workout in archive.pending { try Validation.workout(workout) }
        active = archive.active
        pending = archive.pending
      }
    } catch {
      archiveReadable = false
      self.error =
        L10n.format(
          "Не удалось открыть запись Watch: %@. Файл сохранён; новые записи заблокированы до восстановления.",
          String(error.localizedDescription))
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  func start() {
    guard active == nil else { return }
    do { try commit(active: ExerciseCatalog.starterTemplates[0].start(), pending: pending) } catch {
      self.error = error.localizedDescription
    }
  }
  func update(_ action: (inout Workout) throws -> Void) {
    guard var workout = active else { return }
    do {
      try action(&workout)
      try Validation.workout(workout)
      try commit(active: workout, pending: pending)
    } catch { self.error = error.localizedDescription }
  }
  func finish() {
    guard var workout = active else { return }
    do {
      try WorkoutEngine.finish(&workout)
      try commit(active: nil, pending: pending + [workout])
      sync()
    } catch { self.error = error.localizedDescription }
  }
  func cancel() {
    guard var workout = active else { return }
    do {
      try WorkoutEngine.cancel(&workout)
      try commit(active: nil, pending: pending)
    } catch { self.error = error.localizedDescription }
  }
  func sync() {
    guard WCSession.default.activationState == .activated else { return }
    do {
      for workout in pending {
        let queued = WCSession.default.outstandingUserInfoTransfers.contains {
          ($0.userInfo["id"] as? String) == workout.id.uuidString
        }
        if !queued {
          WCSession.default.transferUserInfo([
            "id": workout.id.uuidString, "workout": try JSONEncoder().encode(workout),
          ])
        }
      }
    } catch { self.error = error.localizedDescription }
  }
  private func commit(active: Workout?, pending: [Workout]) throws {
    guard archiveReadable else { throw CocoaError(.fileReadCorruptFile) }
    guard let archiveURL else { throw CocoaError(.fileNoSuchFile) }
    try JSONEncoder().encode(WatchArchive(active: active, pending: pending)).write(
      to: archiveURL, options: .atomic)
    self.active = active
    self.pending = pending
  }
  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    if let command = applicationContext["heartRateCommand"] as? Data {
      receiveHeartRateCommand(command)
    }
    guard let data = applicationContext["sleepAlarms"] as? Data else { return }
    Task { @MainActor in
      do {
        self.sleepAlarm.receive(try JSONDecoder().decode(SleepAlarmSync.self, from: data))
      } catch { self.error = L10n.text("Не удалось прочитать будильники с iPhone.") }
    }
  }
  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if let data = message["heartRateCommand"] as? Data { receiveHeartRateCommand(data) }
  }
  nonisolated private func receiveHeartRateCommand(_ data: Data) {
    guard data.count <= 2048 else { return }
    Task { @MainActor in
      do {
        let command = try JSONDecoder().decode(WatchHeartRateCommand.self, from: data)
        if command.action == .start, WKApplication.shared().applicationState != .active {
          self.heartRate.send?(
            WatchHeartRateEvent(
              sessionID: command.sessionID, sequence: 1, state: .failed, date: .now))
          return
        }
        self.heartRate.receive(command)
      } catch { self.error = L10n.text("Не удалось прочитать команду приёма пульса.") }
    }
  }
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let message = error?.localizedDescription
    Task { @MainActor in
      if let message {
        self.error = message
      } else {
        if let data = WCSession.default.receivedApplicationContext["heartRateCommand"] as? Data {
          self.receiveHeartRateCommand(data)
        }
        if let data = WCSession.default.receivedApplicationContext["sleepAlarms"] as? Data {
          do {
            self.sleepAlarm.receive(try JSONDecoder().decode(SleepAlarmSync.self, from: data))
          } catch { self.error = L10n.text("Не удалось прочитать будильники с iPhone.") }
        }
        self.sync()
      }
    }
  }
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let id = userInfo["ack"] as? String else { return }
    Task { @MainActor in
      do {
        try self.commit(
          active: self.active, pending: self.pending.filter { $0.id.uuidString != id })
      } catch { self.error = error.localizedDescription }
    }
  }
  nonisolated func session(
    _ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?
  ) {
    if let message = error?.localizedDescription { Task { @MainActor in self.error = message } }
  }
}
