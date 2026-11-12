import CoreMotion
import FitnessTrackerCore
import Foundation
import Observation
import WatchKit

/// One scheduled WatchKit session. Motion stays on the watch and is never presented as a measured sleep stage.
@MainActor @Observable final class WatchSleepAlarm: NSObject, WKExtendedRuntimeSessionDelegate {
  private(set) var plans: [SleepAlarmPlan] = []
  private(set) var armedPlan: SleepAlarmPlan?
  private(set) var ringing = false
  var error: String?
  @ObservationIgnored var send: ((SleepAlarmWatchEvent) -> Void)?
  @ObservationIgnored private var runtime: WKExtendedRuntimeSession?
  @ObservationIgnored private let motion = CMMotionManager()
  @ObservationIgnored private var detector = SmartWakeDetector()
  @ObservationIgnored private var deadlineTask: Task<Void, Never>?
  @ObservationIgnored private var confirmationTask: Task<Void, Never>?
  @ObservationIgnored private var revision = Date.distantPast
  @ObservationIgnored private var readable = true
  @ObservationIgnored private var sensorUnavailable = false
  private var next: SleepAlarmPlan? {
    plans.filter { $0.canArmWatch(at: .now) }.min { $0.fireDate < $1.fireDate }
  }
  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: "watchSleepAlarms.v1") {
      do {
        let sync = try JSONDecoder().decode(SleepAlarmSync.self, from: data)
        guard sync.isValid else { throw SleepAlarmErrorForWatch.invalid }
        plans = sync.plans.filter { $0.delivery.includesWatch }
        revision = sync.revision
      } catch {
        readable = false
        self.error = L10n.text("Не удалось прочитать будильники на Watch. Данные не удалены.")
      }
    }
    if let data = UserDefaults.standard.data(forKey: "watchArmedSleepPlan.v1") {
      do { armedPlan = try JSONDecoder().decode(SleepAlarmPlan.self, from: data) } catch {
        readable = false
        self.error = L10n.text("Не удалось прочитать будильники на Watch. Данные не удалены.")
      }
    }
  }
  func receive(_ sync: SleepAlarmSync) {
    guard readable, sync.isValid, sync.revision >= revision else { return }
    do {
      UserDefaults.standard.set(try JSONEncoder().encode(sync), forKey: "watchSleepAlarms.v1")
      plans = sync.plans.filter { $0.delivery.includesWatch }
      revision = sync.revision
      if let armedPlan, plans.contains(armedPlan),
        runtime?.state == .scheduled || runtime?.state == .running
      {
        send?(
          SleepAlarmWatchEvent(
            plan: armedPlan, kind: sensorUnavailable ? .failed : .armed, date: .now))
      }
      // Scheduling/cancellation is only permitted while the Watch app is active.
      if WKApplication.shared().applicationState == .active, let armedPlan,
        !plans.contains(armedPlan)
      {
        invalidateActive()
      }
    } catch { self.error = L10n.text("Не удалось сохранить будильник на Watch.") }
  }
  func arm() {
    guard readable, WKApplication.shared().applicationState == .active else { return }
    guard let plan = next else {
      error = L10n.text("Нет умного будильника на ближайшие 36 часов.")
      return
    }
    let start = max(plan.watchStart, Date().addingTimeInterval(2))
    guard start < plan.fireDate else {
      error = statusMessage(
        "Окно уже заканчивается. Резервный будильник остаётся на iPhone.", for: plan)
      return
    }
    if armedPlan == plan, !sensorUnavailable,
      runtime?.state == .scheduled || runtime?.state == .running
    {
      send?(SleepAlarmWatchEvent(plan: plan, kind: .armed, date: .now))
      return
    }
    invalidateActive()
    do {
      UserDefaults.standard.set(try JSONEncoder().encode(plan), forKey: "watchArmedSleepPlan.v1")
      armedPlan = plan
      error = nil
      let session = WKExtendedRuntimeSession()
      runtime = session
      session.delegate = self
      session.start(at: start)
      confirmationTask = Task { [weak self] in
        for _ in 0..<10 {
          do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
          guard let self, self.runtime === session, self.armedPlan == plan else { return }
          if session.state == .scheduled || session.state == .running {
            self.send?(SleepAlarmWatchEvent(plan: plan, kind: .armed, date: .now))
            return
          }
          if session.state == .invalid { return }
        }
        self?.error = self?.statusMessage(
          "Watch ещё не подтвердили умное окно. Резервный будильник остаётся на iPhone.", for: plan)
      }
    } catch { self.error = L10n.text("Не удалось сохранить будильник на Watch.") }
  }
  func resume(_ session: WKExtendedRuntimeSession) {
    runtime = session
    session.delegate = self
    if session.state == .running { startSensors(for: ObjectIdentifier(session)) }
  }
  func becameActive() {
    if let armedPlan, !plans.contains(armedPlan) { invalidateActive() }
  }
  func stop() {
    guard WKApplication.shared().applicationState == .active else { return }
    if ringing, let armedPlan {
      send?(SleepAlarmWatchEvent(plan: armedPlan, kind: .dismissed, date: .now))
    }
    invalidateActive()
  }
  private func invalidateActive() {
    if let armedPlan, !ringing {
      send?(SleepAlarmWatchEvent(plan: armedPlan, kind: .failed, date: .now))
    }
    motion.stopAccelerometerUpdates()
    deadlineTask?.cancel()
    confirmationTask?.cancel()
    runtime?.invalidate()
    runtime = nil
    armedPlan = nil
    ringing = false
    sensorUnavailable = false
    UserDefaults.standard.removeObject(forKey: "watchArmedSleepPlan.v1")
  }
  private func startSensors(for identity: ObjectIdentifier) {
    guard runtime.map(ObjectIdentifier.init) == identity, let plan = armedPlan,
      readable, plan.delivery.includesWatch, plans.contains(plan)
    else { return }
    detector = SmartWakeDetector()
    sensorUnavailable = false
    deadlineTask?.cancel()
    deadlineTask = Task { [weak self] in
      let delay = max(0, plan.fireDate.timeIntervalSinceNow)
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      self?.fire(plan)
    }
    guard plan.windowMinutes > 0 else { return }
    guard motion.isAccelerometerAvailable else {
      sensorUnavailable = true
      error = L10n.text("Датчик движения недоступен. Разбудим в конце окна.")
      send?(SleepAlarmWatchEvent(plan: plan, kind: .failed, date: .now))
      return
    }
    motion.accelerometerUpdateInterval = 0.5
    motion.startAccelerometerUpdates(to: .main) { [weak self] data, error in
      if error != nil {
        Task { @MainActor [weak self] in
          guard let self, self.runtime.map(ObjectIdentifier.init) == identity else { return }
          self.motion.stopAccelerometerUpdates()
          self.sensorUnavailable = true
          self.error = L10n.text("Датчик движения недоступен. Разбудим в конце окна.")
          self.send?(SleepAlarmWatchEvent(plan: plan, kind: .failed, date: .now))
        }
        return
      }
      guard let vector = data?.acceleration else { return }
      let movement = abs(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z) - 1)
      let date = Date()
      Task { @MainActor [weak self] in
        guard let self, self.runtime.map(ObjectIdentifier.init) == identity, !self.ringing,
          self.plans.contains(plan), self.detector.ingest(at: date, movement: movement, plan: plan)
        else { return }
        self.fire(plan)
      }
    }
  }
  private func fire(_ plan: SleepAlarmPlan) {
    guard !ringing, runtime?.state == .running, plans.contains(plan), armedPlan == plan,
      Date() >= plan.windowStart, Date() <= plan.fireDate.addingTimeInterval(60)
    else {
      return
    }
    ringing = true
    motion.stopAccelerometerUpdates()
    deadlineTask?.cancel()
    runtime?.notifyUser(hapticType: .notification, repeatHandler: { _ in 2 })
    send?(SleepAlarmWatchEvent(plan: plan, kind: .alerted, date: Date()))
  }
  private func statusMessage(_ fallback: String, for plan: SleepAlarmPlan) -> String {
    L10n.text(
      plan.delivery == .watchOnly
        ? "Проверьте подготовку будильника на Watch. В режиме «только часы» резерв на iPhone может быть выключен."
        : fallback)
  }
  nonisolated func extendedRuntimeSessionDidStart(
    _ extendedRuntimeSession: WKExtendedRuntimeSession
  ) {
    let identity = ObjectIdentifier(extendedRuntimeSession)
    Task { @MainActor in self.startSensors(for: identity) }
  }
  nonisolated func extendedRuntimeSessionWillExpire(
    _ extendedRuntimeSession: WKExtendedRuntimeSession
  ) {
    let identity = ObjectIdentifier(extendedRuntimeSession)
    Task { @MainActor in
      guard self.runtime.map(ObjectIdentifier.init) == identity, let plan = self.armedPlan else {
        return
      }
      self.fire(plan)
    }
  }
  nonisolated func extendedRuntimeSession(
    _ extendedRuntimeSession: WKExtendedRuntimeSession,
    didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?
  ) {
    let identity = ObjectIdentifier(extendedRuntimeSession)
    let endedNormally = reason == .none && error == nil
    Task { @MainActor in
      guard self.runtime.map(ObjectIdentifier.init) == identity else { return }
      self.motion.stopAccelerometerUpdates()
      self.deadlineTask?.cancel()
      self.confirmationTask?.cancel()
      if let plan = self.armedPlan {
        if endedNormally, self.ringing {
          // A system alarm Stop ends the runtime normally. Our own invalidate clears
          // runtime first, so its later callback cannot acknowledge another plan.
          self.send?(SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: .now))
        } else {
          self.error = self.statusMessage(
            "Умное окно на Watch остановлено. Резервный будильник остаётся на iPhone.", for: plan)
          self.send?(SleepAlarmWatchEvent(plan: plan, kind: .failed, date: .now))
        }
      }
      self.runtime = nil
      self.armedPlan = nil
      self.ringing = false
      UserDefaults.standard.removeObject(forKey: "watchArmedSleepPlan.v1")
    }
  }
}

private enum SleepAlarmErrorForWatch: Error { case invalid }
