import FitnessTrackerCore
import Foundation
import Observation

@MainActor protocol SleepAlarmScheduling {
  func schedule(_ plan: SleepAlarmPlan) async throws
  func cancel(_ id: UUID) throws
  func activeIDs() throws -> Set<UUID>
}

enum SleepAlarmError: Error, LocalizedError {
  case invalid, permission, unreadable, unavailable
  var errorDescription: String? {
    switch self {
    case .invalid: "Выберите будущее время и окно пробуждения до 30 минут."
    case .permission: "Разрешите будильники для FitnessTracker в настройках iPhone."
    case .unreadable: "Не удалось прочитать настройки будильников. Сохранённые данные не удалены."
    case .unavailable: "Не удалось настроить будильник. Повторите попытку."
    }
  }
}

/// System alarms own delivery; this store owns settings and acknowledgements, never raw sleep/sensor data.
@MainActor @Observable final class SleepAlarmStore {
  private(set) var plans: [SleepAlarmPlan] = []
  private(set) var watchFailed: Set<UUID> = []
  private(set) var systemConfirmed: Set<UUID> = []
  private(set) var watchArmed: Set<UUID> = []
  private(set) var lastWatchAlert: Date?
  private(set) var busy = false
  var notice: String?
  var error: String?
  @ObservationIgnored var send: ((SleepAlarmSync) -> Void)?
  @ObservationIgnored private let scheduler: any SleepAlarmScheduling
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var latestWatchEvent: [UUID: Date] = [:]
  @ObservationIgnored private var readable = true
  @ObservationIgnored private let key = "sleepAlarmPlans.v1"
  init(
    scheduler: any SleepAlarmScheduling, defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init
  ) {
    self.scheduler = scheduler
    self.defaults = defaults
    self.now = now
    if let data = defaults.data(forKey: key) {
      do {
        let value = try JSONDecoder().decode([SleepAlarmPlan].self, from: data)
        guard SleepAlarmSync(revision: now(), plans: value).isValid else {
          throw SleepAlarmError.unreadable
        }
        plans = value
      } catch {
        readable = false
        self.error = SleepAlarmError.unreadable.localizedDescription
      }
    }
  }
  func add(fireDate: Date, windowMinutes: Int) async -> Bool {
    guard !busy else { return false }
    guard readable else {
      error = SleepAlarmError.unreadable.localizedDescription
      return false
    }
    let plan = SleepAlarmPlan(fireDate: fireDate, windowMinutes: windowMinutes)
    guard plan.isValid, fireDate > now(), plans.count < 10 else {
      error = SleepAlarmError.invalid.localizedDescription
      return false
    }
    busy = true
    error = nil
    defer { busy = false }
    do {
      // Validate serialization first, then include any Watch events received while awaiting permission.
      _ = try JSONEncoder().encode(plan)
      try await scheduler.schedule(plan)
      let updated = (plans + [plan]).sorted { $0.fireDate < $1.fireDate }
      let data: Data
      do { data = try JSONEncoder().encode(updated) } catch {
        try scheduler.cancel(plan.id)
        throw error
      }
      systemConfirmed.insert(plan.id)
      plans = updated
      defaults.set(data, forKey: key)
      publish()
      return true
    } catch {
      self.error =
        (error as? SleepAlarmError)?.localizedDescription
        ?? SleepAlarmError.unavailable.localizedDescription
      return false
    }
  }
  func remove(_ plan: SleepAlarmPlan) {
    guard !busy, readable, plans.contains(plan) else { return }
    do {
      try scheduler.cancel(plan.id)
      try commit(plans.filter { $0.id != plan.id })
      systemConfirmed.remove(plan.id)
      watchArmed.remove(plan.id)
      notice =
        plan.windowMinutes > 0
        ? "Откройте FitnessTracker на Watch, чтобы подтвердить отмену умного окна." : nil
      error = nil
    } catch {
      self.error =
        (error as? SleepAlarmError)?.localizedDescription
        ?? SleepAlarmError.unavailable.localizedDescription
    }
  }
  func refresh() {
    guard !busy, readable else { return }
    do {
      let ids = try scheduler.activeIDs()
      systemConfirmed = ids.intersection(Set(plans.map(\.id)))
      // Keep a pending alert until AlarmKit confirms it is absent.
      let remaining = plans.filter { ids.contains($0.id) }
      if remaining != plans { try commit(remaining) }
      watchArmed.formIntersection(systemConfirmed)
      watchFailed.formIntersection(systemConfirmed)
      error = nil
      publish()
    } catch {
      systemConfirmed = []
      self.error =
        (error as? SleepAlarmError)?.localizedDescription
        ?? SleepAlarmError.unavailable.localizedDescription
      publish()
    }
  }
  func publish() {
    let stamp = max(
      now().timeIntervalSince1970, defaults.double(forKey: "sleepAlarmSyncRevision") + 0.001)
    defaults.set(stamp, forKey: "sleepAlarmSyncRevision")
    send?(
      SleepAlarmSync(
        revision: Date(timeIntervalSince1970: stamp),
        plans: plans.filter { systemConfirmed.contains($0.id) }))
  }
  func receive(_ event: SleepAlarmWatchEvent) {
    guard readable, let plan = plans.first(where: { $0 == event.plan }) else { return }
    guard event.date <= now().addingTimeInterval(30),
      latestWatchEvent[plan.id].map({ event.date >= $0 }) ?? true
    else { return }
    latestWatchEvent[plan.id] = event.date
    switch event.kind {
    case .armed:
      if systemConfirmed.contains(plan.id), event.date <= now().addingTimeInterval(30),
        plan.fireDate > now()
      {
        watchArmed = [plan.id]
        watchFailed.remove(plan.id)
      }
    case .failed:
      watchArmed.remove(plan.id)
      watchFailed.insert(plan.id)
    case .alerted:
      guard event.date >= plan.windowStart, event.date <= plan.fireDate.addingTimeInterval(60)
      else { return }
      lastWatchAlert = event.date
    case .dismissed:
      guard event.canCancelBackup(for: plan, now: now()) else { return }
      do {
        try scheduler.cancel(plan.id)
        try commit(plans.filter { $0.id != plan.id })
        systemConfirmed.remove(plan.id)
        lastWatchAlert = event.date
        watchArmed.remove(plan.id)
      } catch {
        self.error =
          (error as? SleepAlarmError)?.localizedDescription
          ?? SleepAlarmError.unavailable.localizedDescription
      }
    }
  }
  private func commit(_ value: [SleepAlarmPlan]) throws {
    let data = try JSONEncoder().encode(value)
    defaults.set(data, forKey: key)
    plans = value
    publish()
  }
}
