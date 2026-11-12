import FitLifeCore
import Foundation
import Observation

@MainActor protocol SleepAlarmScheduling {
  func schedule(_ plan: SleepAlarmPlan) async throws
  func cancel(_ id: UUID) throws
  func activeIDs() throws -> Set<UUID>
}

enum SleepWatchConnection: Equatable, Sendable {
  case checking, notPaired, appNotInstalled, unreachable, reachable
  var message: String {
    switch self {
    case .checking: "Проверяем подключение Apple Watch"
    case .notPaired: "Apple Watch не связаны с этим iPhone"
    case .appNotInstalled:
      "Установите FitLife на Apple Watch через Xcode или приложение Watch."
    case .unreachable: "Откройте FitLife на Apple Watch, чтобы подтвердить связь."
    case .reachable: "Apple Watch на связи"
    }
  }
}

enum SleepAlarmError: Error, LocalizedError {
  case invalid, permission, unreadable, unavailable, watchUnavailable
  var errorDescription: String? {
    switch self {
    case .invalid: "Выберите будущее время и окно пробуждения до 30 минут."
    case .permission: "Разрешите будильники для FitLife в настройках iPhone."
    case .unreadable: "Не удалось прочитать настройки будильников. Сохранённые данные не удалены."
    case .unavailable: "Не удалось настроить будильник. Повторите попытку."
    case .watchUnavailable:
      "Откройте FitLife на подключённых Apple Watch, чтобы выбрать сигнал только на часах."
    }
  }
}

/// A single snapshot also preserves a confirmed Watch handoff across iPhone process restarts.
/// Legacy v1 arrays decode with the original enabled phone reserve behavior.
private struct SleepAlarmArchive: Codable {
  var plans: [SleepAlarmPlan]
  var watchOnly: Set<UUID>
  var cleanup: Set<UUID>
  init(plans: [SleepAlarmPlan], watchOnly: Set<UUID>, cleanup: Set<UUID>) {
    self.plans = plans
    self.watchOnly = watchOnly
    self.cleanup = cleanup
  }
  private enum CodingKeys: String, CodingKey { case plans, watchOnly, cleanup }
  init(from decoder: any Decoder) throws {
    if var legacy = try? decoder.unkeyedContainer() {
      var result: [SleepAlarmPlan] = []
      while !legacy.isAtEnd { result.append(try legacy.decode(SleepAlarmPlan.self)) }
      plans = result
      watchOnly = []
      cleanup = []
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      plans = try container.decode([SleepAlarmPlan].self, forKey: .plans)
      watchOnly = try container.decode(Set<UUID>.self, forKey: .watchOnly)
      cleanup = try container.decodeIfPresent(Set<UUID>.self, forKey: .cleanup) ?? []
    }
  }
}

@MainActor @Observable final class SleepAlarmStore {
  private(set) var plans: [SleepAlarmPlan] = []
  private(set) var watchFailed: Set<UUID> = []
  private(set) var systemConfirmed: Set<UUID> = []
  private(set) var watchArmed: Set<UUID> = []
  private(set) var watchOnlyConfirmed: Set<UUID> = []
  private(set) var phoneSilenced: Set<UUID> = []
  private(set) var watchConnection = SleepWatchConnection.checking
  var watchReachable: Bool { watchConnection == .reachable }
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
  @ObservationIgnored private var pendingCleanup: Set<UUID> = []
  @ObservationIgnored private let key = "sleepAlarmPlans.v1"
  var activePlans: [SleepAlarmPlan] { plans.filter { $0.isEnabled && $0.fireDate > now() } }

  init(
    scheduler: any SleepAlarmScheduling, defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init
  ) {
    self.scheduler = scheduler
    self.defaults = defaults
    self.now = now
    if let data = defaults.data(forKey: key) {
      do {
        let value = try JSONDecoder().decode(SleepAlarmArchive.self, from: data)
        let eligible = Set(
          value.plans.filter { $0.isEnabled && $0.delivery == .watchOnly }.map(\.id))
        guard SleepAlarmSync(revision: now(), plans: value.plans).isValid,
          value.watchOnly.isSubset(of: eligible), value.cleanup.count <= 10,
          value.cleanup.isDisjoint(with: Set(value.plans.map(\.id)))
        else { throw SleepAlarmError.unreadable }
        plans = value.plans.sorted { $0.fireDate < $1.fireDate }
        watchOnlyConfirmed = value.watchOnly
        pendingCleanup = value.cleanup
      } catch {
        readable = false
        self.error = SleepAlarmError.unreadable.localizedDescription
      }
    }
  }
  func setWatchConnection(_ connection: SleepWatchConnection) {
    watchConnection = connection
  }
  func add(fireDate: Date, windowMinutes: Int, delivery: SleepAlarmDelivery = .phoneAndWatch) async
    -> Bool
  {
    await save(
      replacing: nil, fireDate: fireDate, windowMinutes: windowMinutes, delivery: delivery,
      enabled: true)
  }
  func update(
    _ plan: SleepAlarmPlan, fireDate: Date, windowMinutes: Int, delivery: SleepAlarmDelivery
  ) async -> Bool {
    await save(
      replacing: plan, fireDate: fireDate, windowMinutes: windowMinutes, delivery: delivery,
      enabled: plan.isEnabled)
  }
  func setEnabled(_ enabled: Bool, for plan: SleepAlarmPlan) async -> Bool {
    await save(
      replacing: plan, fireDate: plan.fireDate, windowMinutes: plan.windowMinutes,
      delivery: plan.delivery, enabled: enabled)
  }
  private func save(
    replacing old: SleepAlarmPlan?, fireDate: Date, windowMinutes: Int,
    delivery: SleepAlarmDelivery, enabled: Bool
  ) async -> Bool {
    guard !busy else { return false }
    guard pendingCleanup.isEmpty else {
      error = SleepAlarmError.unavailable.localizedDescription
      return false
    }
    guard readable else {
      error = SleepAlarmError.unreadable.localizedDescription
      return false
    }
    let plan = SleepAlarmPlan(
      fireDate: fireDate, windowMinutes: windowMinutes, delivery: delivery, isEnabled: enabled)
    guard plan.isValid, !enabled || fireDate > now(), old != nil || plans.count < 10,
      old.map({ plans.contains($0) }) ?? true
    else {
      error = SleepAlarmError.invalid.localizedDescription
      return false
    }
    if enabled, delivery == .watchOnly, !watchReachable {
      error = SleepAlarmError.watchUnavailable.localizedDescription
      return false
    }
    busy = true
    let hadSavedSettings = defaults.data(forKey: key) != nil
    error = nil
    notice = nil
    defer { busy = false }
    do {
      _ = try JSONEncoder().encode(plan)
      if enabled {
        // Persist intent before crossing the asynchronous system boundary. A crash
        // or failed rollback leaves an ID that refresh can cancel, never an orphan.
        try persistCleanup(pendingCleanup.union([plan.id]))
        try await scheduler.schedule(plan)
      }
      if let old, !plans.contains(old) { throw SleepAlarmError.invalid }
      let updated = (plans.filter { $0.id != old?.id } + [plan]).sorted {
        $0.fireDate < $1.fireDate
      }
      let handoffs = watchOnlyConfirmed.subtracting(old.map { [$0.id] } ?? [])
      let cleanup = pendingCleanup.subtracting([plan.id])
      let data = try encode(updated, watchOnly: handoffs, cleanup: cleanup)
      if let old { try scheduler.cancel(old.id) }
      apply(updated, watchOnly: handoffs, data: data, cleanup: cleanup)
      if let old { clearStatus(old.id) }
      if let old, old.canArmWatch(at: now()) {
        notice =
          "Откройте FitLife на Watch, чтобы подтвердить изменение или выключение сигнала на часах."
      }
      if enabled { systemConfirmed.insert(plan.id) }
      publish()
      return true
    } catch {
      if pendingCleanup.contains(plan.id) {
        do {
          try scheduler.cancel(plan.id)
          try persistCleanup(pendingCleanup.subtracting([plan.id]))
          if !hadSavedSettings, plans.isEmpty, pendingCleanup.isEmpty {
            defaults.removeObject(forKey: key)
          }
        } catch {
          report(error)
          return false
        }
      }
      report(error)
      return false
    }
  }
  func remove(_ plan: SleepAlarmPlan) {
    guard !busy, readable, plans.contains(plan) else { return }
    do {
      let value = plans.filter { $0.id != plan.id }
      let handoffs = watchOnlyConfirmed.subtracting([plan.id])
      let data = try encode(value, watchOnly: handoffs)
      try scheduler.cancel(plan.id)
      apply(value, watchOnly: handoffs, data: data)
      clearStatus(plan.id)
      notice =
        plan.canArmWatch(at: now())
        ? "Откройте FitLife на Watch, чтобы подтвердить отмену умного окна." : nil
      error = nil
      publish()
    } catch { report(error) }
  }
  func refresh() {
    guard !busy, readable else { return }
    do {
      for id in pendingCleanup {
        try scheduler.cancel(id)
        try persistCleanup(pendingCleanup.subtracting([id]))
      }
      let ids = try scheduler.activeIDs()
      phoneSilenced = watchOnlyConfirmed.subtracting(ids)
      systemConfirmed = ids.intersection(Set(plans.filter(\.isEnabled).map(\.id)))
      // Handoff intent is persisted before cancellation. After a process interruption
      // retry cancellation if the system still has the phone reserve.
      for plan in plans where watchOnlyConfirmed.contains(plan.id) && ids.contains(plan.id) {
        try scheduler.cancel(plan.id)
        systemConfirmed.remove(plan.id)
        phoneSilenced.insert(plan.id)
      }
      let remaining = plans.filter {
        !$0.isEnabled || systemConfirmed.contains($0.id)
          || (watchOnlyConfirmed.contains($0.id) && $0.fireDate.addingTimeInterval(60) > now())
      }
      if remaining != plans { try commit(remaining) }
      let idsRemaining = Set(remaining.map(\.id))
      phoneSilenced.formIntersection(idsRemaining)
      watchArmed.formIntersection(idsRemaining)
      watchFailed.formIntersection(idsRemaining)
      error = nil
      publish()
    } catch {
      systemConfirmed = []
      phoneSilenced = []
      report(error)
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
        plans: plans.filter {
          $0.isEnabled && $0.delivery.includesWatch
            && (systemConfirmed.contains($0.id) || watchOnlyConfirmed.contains($0.id))
        }))
  }
  func receive(_ event: SleepAlarmWatchEvent) {
    guard readable,
      let plan = plans.first(where: {
        $0 == event.plan && $0.isEnabled && $0.delivery.includesWatch
      }),
      event.date <= now().addingTimeInterval(30),
      latestWatchEvent[plan.id].map({ event.date >= $0 }) ?? true
    else { return }
    latestWatchEvent[plan.id] = event.date
    switch event.kind {
    case .armed:
      guard systemConfirmed.contains(plan.id) || watchOnlyConfirmed.contains(plan.id),
        plan.fireDate > now()
      else { return }
      watchArmed = [plan.id]
      watchFailed.remove(plan.id)
      if plan.delivery == .watchOnly, event.date >= now().addingTimeInterval(-60),
        !busy, !watchOnlyConfirmed.contains(plan.id)
      {
        do {
          // Only a fresh, exact Watch scheduling acknowledgement can silence iPhone.
          try commit(plans, watchOnly: watchOnlyConfirmed.union([plan.id]))
          try scheduler.cancel(plan.id)
          systemConfirmed.remove(plan.id)
          phoneSilenced.insert(plan.id)
          error = nil
          publish()
        } catch { report(error) }
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
        clearStatus(plan.id)
        lastWatchAlert = event.date
      } catch { report(error) }
    }
  }
  private func clearStatus(_ id: UUID) {
    systemConfirmed.remove(id)
    phoneSilenced.remove(id)
    watchArmed.remove(id)
    watchFailed.remove(id)
    latestWatchEvent.removeValue(forKey: id)
  }
  private func encode(_ value: [SleepAlarmPlan], watchOnly: Set<UUID>, cleanup: Set<UUID>? = nil)
    throws -> Data
  {
    try JSONEncoder().encode(
      SleepAlarmArchive(plans: value, watchOnly: watchOnly, cleanup: cleanup ?? pendingCleanup))
  }
  private func apply(
    _ value: [SleepAlarmPlan], watchOnly: Set<UUID>, data: Data, cleanup: Set<UUID>? = nil
  ) {
    defaults.set(data, forKey: key)
    plans = value
    watchOnlyConfirmed = watchOnly
    if let cleanup { pendingCleanup = cleanup }
  }
  private func persistCleanup(_ value: Set<UUID>) throws {
    let data = try encode(plans, watchOnly: watchOnlyConfirmed, cleanup: value)
    apply(plans, watchOnly: watchOnlyConfirmed, data: data, cleanup: value)
  }
  private func commit(_ value: [SleepAlarmPlan], watchOnly: Set<UUID>? = nil) throws {
    let ids = Set(value.filter { $0.isEnabled && $0.delivery == .watchOnly }.map(\.id))
    let handoffs = (watchOnly ?? watchOnlyConfirmed).intersection(ids)
    apply(value, watchOnly: handoffs, data: try encode(value, watchOnly: handoffs))
    publish()
  }
  private func report(_ error: any Error) {
    self.error =
      (error as? SleepAlarmError)?.localizedDescription
      ?? SleepAlarmError.unavailable.localizedDescription
  }
}
