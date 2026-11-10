import FitnessTrackerCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}

@MainActor private final class Scheduler: SleepAlarmScheduling {
  var ids: Set<UUID> = []
  var failSchedule = false
  var failCancel = false
  var failRead = false
  var cancelled: [UUID] = []
  var duringSchedule: (() -> Void)?
  func schedule(_ plan: SleepAlarmPlan) async throws {
    if failSchedule { throw CheckFailure(message: "Private service details") }
    duringSchedule?()
    ids.insert(plan.id)
  }
  func cancel(_ id: UUID) throws {
    if failCancel { throw CheckFailure(message: "Private cancellation details") }
    if ids.remove(id) != nil { cancelled.append(id) }
  }
  func activeIDs() throws -> Set<UUID> {
    if failRead { throw CheckFailure(message: "Private read details") }
    return ids
  }
}

@MainActor private final class Reader: HealthSleepReading {
  var authorizations = 0
  var reads = 0
  var fail = false
  var suspend = false
  var result: [SleepNight] = []
  var pending: CheckedContinuation<[SleepNight], any Error>?
  private var waiter: CheckedContinuation<Void, Never>?
  func authorize() async throws { authorizations += 1 }
  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] {
    reads += 1
    if suspend {
      return try await withCheckedThrowingContinuation {
        pending = $0
        waiter?.resume()
        waiter = nil
      }
    }
    if fail { throw CheckFailure(message: "Private health details") }
    return result
  }
  func waitForRead() async {
    if pending == nil { await withCheckedContinuation { waiter = $0 } }
  }
}

@main private struct PortableSleepChecks {
  @MainActor private static func checkWatchHandoffAndEditing() async throws {
    let suite = "FitnessTracker.SleepHandoffChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "Defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let scheduler = Scheduler()
    let store = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: { now })
    try expect(
      !(await store.add(
        fireDate: now.addingTimeInterval(3600), windowMinutes: 20, delivery: .watchOnly)),
      "Offline Watch cannot select watch-only")
    store.setWatchConnection(paired: true, reachable: true)
    try expect(
      await store.add(
        fireDate: now.addingTimeInterval(3600), windowMinutes: 20, delivery: .watchOnly),
      "Reserve installed before Watch handoff")
    guard let plan = store.plans.first else { throw CheckFailure(message: "Watch plan") }
    try expect(
      scheduler.ids == [plan.id] && store.phoneSilenced.isEmpty,
      "Phone stays armed until fresh exact Watch acknowledgement")
    let legacy = SleepAlarmPlan(
      id: plan.id, fireDate: plan.fireDate, windowMinutes: plan.windowMinutes)
    store.receive(SleepAlarmWatchEvent(plan: legacy, kind: .armed, date: now))
    try expect(scheduler.ids == [plan.id], "Old Watch version cannot silence phone")
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .armed, date: now.addingTimeInterval(-61)))
    try expect(scheduler.ids == [plan.id], "Stale acknowledgement cannot silence phone")
    scheduler.failCancel = true
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .armed, date: now))
    try expect(
      scheduler.ids == [plan.id] && store.phoneSilenced.isEmpty, "Failed handoff keeps phone backup"
    )
    scheduler.failCancel = false
    let restored = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: { now })
    restored.refresh()
    try expect(
      restored.plans == [plan] && scheduler.ids.isEmpty && restored.phoneSilenced == [plan.id],
      "Persisted handoff resumes after process interruption")
    restored.refresh()
    try expect(restored.plans == [plan], "Watch-only plan survives absence from AlarmKit")
    restored.receive(SleepAlarmWatchEvent(plan: plan, kind: .failed, date: now))
    try expect(
      restored.watchFailed == [plan.id] && scheduler.ids.isEmpty,
      "Watch-only failure never silently enables phone sound")
    restored.setWatchConnection(paired: false, reachable: false)
    try expect(
      await restored.update(
        plan, fireDate: now.addingTimeInterval(7200), windowMinutes: 10, delivery: .phoneAndWatch),
      "User can restore phone delivery without Watch connection")
    guard let edited = restored.plans.first else { throw CheckFailure(message: "Edited plan") }
    try expect(
      edited.id != plan.id && scheduler.ids == [edited.id],
      "Editing replaces reserve and rejects old event IDs")
    restored.receive(SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: plan.windowStart))
    try expect(restored.plans == [edited], "Old dismissal cannot remove edited plan")
    scheduler.failCancel = true
    try expect(
      !(await restored.update(
        edited, fireDate: now.addingTimeInterval(10800), windowMinutes: 5, delivery: .phoneAndWatch)),
      "Editing reports cancellation failure")
    try expect(
      restored.plans == [edited] && scheduler.ids.count == 2,
      "Failed rollback retains old plan and cleanup intent")
    scheduler.failCancel = false
    let recovered = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: { now })
    recovered.refresh()
    try expect(
      recovered.plans == [edited] && scheduler.ids == [edited.id],
      "Restart cleans uncommitted system reserve")
    try expect(await recovered.setEnabled(false, for: edited), "Disable keeps editable settings")
    guard let disabled = recovered.plans.first else { throw CheckFailure(message: "Disabled plan") }
    try expect(
      !disabled.isEnabled && scheduler.ids.isEmpty, "Disabled alarms have no system reserve")
    recovered.refresh()
    try expect(recovered.plans == [disabled], "Refresh preserves disabled settings")
    try expect(await recovered.setEnabled(true, for: disabled), "Enable schedules a fresh reserve")
    guard let enabled = recovered.plans.first else { throw CheckFailure(message: "Enabled plan") }
    try expect(
      enabled.isEnabled && enabled.id != disabled.id && scheduler.ids == [enabled.id],
      "Enable cannot accept old Watch acknowledgement")
    defaults.set(try JSONEncoder().encode([legacy]), forKey: "sleepAlarmPlans.v1")
    let migrated = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: { now })
    try expect(
      migrated.plans == [legacy] && migrated.watchOnlyConfirmed.isEmpty,
      "Legacy array migration preserves phone backup preference")
  }
  @MainActor static func main() async throws {
    let suite = "FitnessTracker.SleepChecks.\(UUID())"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw CheckFailure(message: "Defaults")
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    let clock = { now }
    let scheduler = Scheduler()
    let store = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: clock)
    var syncs: [SleepAlarmSync] = []
    store.send = { syncs.append($0) }
    scheduler.failSchedule = true
    try expect(
      !(await store.add(fireDate: now.addingTimeInterval(3600), windowMinutes: 20)),
      "Failed system alarm must not be saved")
    try expect(
      store.plans.isEmpty && defaults.data(forKey: "sleepAlarmPlans.v1") == nil,
      "Failure leaves settings untouched")
    try expect(store.error?.contains("Private") != true, "Do not expose SDK details")
    scheduler.failSchedule = false
    try expect(
      await store.add(fireDate: now.addingTimeInterval(3600), windowMinutes: 20), "Schedule reserve"
    )
    guard let plan = store.plans.first else { throw CheckFailure(message: "Missing plan") }
    try expect(
      syncs.last?.plans == [plan] && store.systemConfirmed == [plan.id],
      "Watch sees only confirmed reserves")
    let persisted = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: clock)
    try expect(
      persisted.plans == [plan] && persisted.systemConfirmed.isEmpty,
      "Reload requires system verification")
    persisted.refresh()
    try expect(persisted.systemConfirmed == [plan.id], "Refresh verifies reserve")
    scheduler.failCancel = true
    store.remove(plan)
    try expect(
      store.plans == [plan] && scheduler.ids == [plan.id],
      "Cancel failure preserves reserve and settings")
    scheduler.failCancel = false
    now = plan.windowStart.addingTimeInterval(120)
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .armed, date: now))
    try expect(store.watchArmed == [plan.id], "Valid Watch acknowledgement")
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .failed, date: now.addingTimeInterval(-1)))
    try expect(store.watchArmed == [plan.id], "Old failure cannot replace newer acknowledgement")
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .alerted, date: now))
    try expect(
      store.plans == [plan] && scheduler.cancelled.isEmpty,
      "Haptic attempt alone never cancels mandatory reserve")
    let other = SleepAlarmPlan(fireDate: plan.fireDate, windowMinutes: plan.windowMinutes)
    store.receive(SleepAlarmWatchEvent(plan: other, kind: .dismissed, date: now))
    try expect(store.plans == [plan], "Unrelated event cannot cancel alarm")
    store.receive(
      SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now.addingTimeInterval(31)))
    try expect(store.plans == [plan], "Future Watch event rejected")
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now))
    store.receive(SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now))
    try expect(
      store.plans.isEmpty && scheduler.cancelled == [plan.id],
      "Explicit dismissal cancels exactly once")
    let lastRevision = syncs.last?.revision ?? .distantPast
    now = now.addingTimeInterval(-86400)
    store.publish()
    try expect(
      (syncs.last?.revision ?? .distantPast) > lastRevision,
      "Clock reversal cannot regress sync revision")

    try expect(
      await store.add(fireDate: now.addingTimeInterval(3600), windowMinutes: 20),
      "Add another reserve")
    guard let first = store.plans.first else { throw CheckFailure(message: "First plan") }
    now = first.windowStart.addingTimeInterval(60)
    scheduler.duringSchedule = {
      store.receive(SleepAlarmWatchEvent(plan: first, kind: .dismissed, date: now))
    }
    try expect(
      await store.add(fireDate: now.addingTimeInterval(7200), windowMinutes: 10),
      "Reentrant schedule")
    scheduler.duringSchedule = nil
    let reloaded = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: clock)
    try expect(
      reloaded.plans == store.plans && !reloaded.plans.contains(first),
      "Permission await must not resurrect a dismissed alarm")
    scheduler.failRead = true
    store.refresh()
    try expect(
      !store.plans.isEmpty && syncs.last?.plans.isEmpty == true,
      "Unknown system state keeps settings but never arms Watch")
    scheduler.failRead = false
    scheduler.ids = []
    store.refresh()
    try expect(store.plans.isEmpty, "Removed system alarms are reconciled")
    try await checkWatchHandoffAndEditing()
    let corrupt = Data("broken settings".utf8)
    defaults.set(corrupt, forKey: "sleepAlarmPlans.v1")
    let broken = SleepAlarmStore(scheduler: scheduler, defaults: defaults, now: clock)
    try expect(
      !(await broken.add(fireDate: now.addingTimeInterval(3600), windowMinutes: 20)),
      "Unreadable settings block overwrite")
    try expect(
      defaults.data(forKey: "sleepAlarmPlans.v1") == corrupt,
      "Corrupt settings preserved for recovery")

    let reader = Reader()
    let model = SleepDiaryModel(reader: reader, defaults: defaults)
    await model.load(day: now, calendar: .current)
    try expect(
      reader.reads == 0 && reader.authorizations == 0, "Health reads require explicit opt-in")
    await model.enable()
    await model.load(day: now, calendar: .current)
    try expect(
      model.enabled && reader.authorizations == 1 && model.nights.isEmpty,
      "Opt-in and empty health state")
    reader.fail = true
    await model.load(day: now, calendar: .current)
    try expect(
      model.error != nil && model.error?.contains("Private") != true,
      "Readable error without health data leakage")
    reader.fail = false
    reader.suspend = true
    let old = Task { await model.load(day: now, calendar: .current) }
    await reader.waitForRead()
    let stale = reader.pending
    reader.pending = nil
    reader.suspend = false
    let newer = now.addingTimeInterval(86400)
    reader.result = [SleepNight(day: newer, calendar: .current, samples: [])]
    await model.load(day: newer, calendar: .current)
    stale?.resume(returning: [SleepNight(day: now, calendar: .current, samples: [])])
    await old.value
    try expect(model.nights == reader.result, "Older read cannot replace selected date")
    reader.suspend = true
    let pending = Task { await model.load(day: now, calendar: .current) }
    await reader.waitForRead()
    model.disable()
    reader.pending?.resume(returning: reader.result)
    reader.pending = nil
    await pending.value
    try expect(
      !model.enabled && model.nights.isEmpty && !model.loading,
      "Disable clears data and rejects late replies")
    print(
      "Portable sleep checks: alarm persistence/failures/reconciliation, Watch reserve safety, opt-in and stale Health reads passed."
    )
  }
}
