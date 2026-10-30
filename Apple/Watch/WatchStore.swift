import FitnessTrackerCore
import Foundation
import Observation
import WatchConnectivity

private struct WatchArchive: Codable {
  var active: Workout?
  var pending: [Workout] = []
}

/// A wrist set logger. Timestamps survive suspension; no background sensor session is claimed.
@MainActor @Observable final class WatchStore: NSObject, WCSessionDelegate {
  private(set) var active: Workout?
  private(set) var pending: [Workout] = []
  var error: String?
  @ObservationIgnored private var archiveURL: URL?
  @ObservationIgnored private var archiveReadable = true
  override init() {
    super.init()
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
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let message = error?.localizedDescription
    Task { @MainActor in if let message { self.error = message } else { self.sync() } }
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
