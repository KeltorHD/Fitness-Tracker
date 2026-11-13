import FitLifeCore
import Foundation
import Observation

struct HealthAnchoredPage: Sendable {
  let quantities: [HealthQuantity]
  let sleep: [HealthSleepRecord]
  let deletedIDs: [UUID]
  let anchor: Data
  let exhausted: Bool
  var isEmpty: Bool { quantities.isEmpty && sleep.isEmpty && deletedIDs.isEmpty }
}

@MainActor protocol AppleHealthSyncReading {
  func authorize() async throws
  func page(metric: HealthMetric, since: Date, anchor: Data?) async throws -> HealthAnchoredPage
  func aggregate(_ bucket: HealthSyncBucket) async throws -> Double?
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error>
}

@MainActor @Observable final class AppleHealthSyncCoordinator {
  private(set) var syncing = false
  private(set) var authorizing = false
  private(set) var error: String?
  private(set) var lastSync: Date?
  private(set) var revision = 0
  @ObservationIgnored var onUpdate: (@MainActor () -> Void)?
  @ObservationIgnored private let reader: any AppleHealthSyncReading
  @ObservationIgnored private let remote: any HealthSyncRemoteServing
  @ObservationIgnored private let storage: any HealthSyncStateStoring
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let account: @MainActor () -> String
  @ObservationIgnored private let now: @MainActor () -> Date
  @ObservationIgnored private let waitForRetry: @Sendable () async throws -> Void
  @ObservationIgnored private var requestID: UUID?
  @ObservationIgnored private var operation: (id: UUID, task: Task<Void, Never>)?

  init(
    reader: any AppleHealthSyncReading, remote: any HealthSyncRemoteServing,
    storage: any HealthSyncStateStoring, defaults: UserDefaults = .standard,
    account: @escaping @MainActor () -> String, now: @escaping @MainActor () -> Date = Date.init,
    waitForRetry: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .seconds(65))
    }
  ) {
    self.reader = reader
    self.remote = remote
    self.storage = storage
    self.defaults = defaults
    self.account = account
    self.now = now
    self.waitForRetry = waitForRetry
  }
  var available: Bool { remote.available }
  var enabled: Bool {
    _ = revision
    return defaults.bool(forKey: "appleHealthSync." + account())
  }
  func setEnabled(_ value: Bool) async {
    guard !authorizing else { return }
    authorizing = true
    defer { authorizing = false }
    let namespace = account()
    error = nil
    do {
      if value {
        guard available else { throw HealthDataError.notConnected }
        try await reader.authorize()
      }
      try Task.checkCancellation()
      guard account() == namespace else { throw CancellationError() }
      defaults.set(value, forKey: "appleHealthSync." + namespace)
      if value { defaults.set(UUID().uuidString, forKey: "appleHealthReconciliation." + namespace) }
      if !value { operation?.task.cancel() }
      revision += 1
      onUpdate?()
    } catch is CancellationError {} catch { self.error = HealthProviderMessage.error(error) }
  }
  func requestSync() { revision += 1 }

  /// RootView owns the lifetime; a replacement waits for the previous writer before reading its state.
  func observe(calendar: Calendar, continuously: Bool = true) async {
    let id = UUID()
    requestID = id
    let previous = operation?.task
    previous?.cancel()
    await previous?.value
    guard requestID == id, !Task.isCancelled, enabled, available else { return }
    let namespace = account()
    let task = Task {
      await self.perform(namespace: namespace, calendar: calendar, continuously: continuously)
    }
    operation = (id, task)
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if operation?.id == id { operation = nil }
  }

  private func perform(namespace: String, calendar: Calendar, continuously: Bool) async {
    error = nil
    lastSync = nil
    do {
      var state: HealthSyncState
      if let saved = try await storage.load(namespace) {
        state = saved
      } else {
        guard
          let first = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now()))
        else { throw TrainingError.invalidDate }
        guard let night = SleepNight.window(endingOn: first, calendar: calendar) else {
          throw TrainingError.invalidDate
        }
        state = HealthSyncState(initialStart: first, initialSleepStart: night.start)
        try await storage.save(state, for: namespace)
      }
      try check(namespace)
      lastSync = state.lastSync
      try await drain(&state, namespace: namespace, calendar: calendar)
      guard continuously else { return }
      for try await _ in reader.changes(since: state.initialSleepStart) {
        try check(namespace)
        try await Task.sleep(for: .seconds(2))
        try await drain(&state, namespace: namespace, calendar: calendar)
      }
    } catch is CancellationError {} catch {
      guard account() == namespace, !Task.isCancelled else { return }
      self.error = HealthProviderMessage.error(error)
    }
  }

  private func drain(_ state: inout HealthSyncState, namespace: String, calendar: Calendar)
    async throws
  {
    syncing = true
    defer { syncing = false }
    let previousSequence = state.sequence
    try check(namespace)
    if state.pending != nil { try await deliver(&state, namespace: namespace) }
    let reconciliation = defaults.string(forKey: "appleHealthReconciliation." + namespace)
    if state.reconciliationID != reconciliation {
      state.anchors.removeAll()
      state.reconciliationID = reconciliation
      try await storage.save(state, for: namespace)
    }
    try await aggregates(&state, namespace: namespace, calendar: calendar)
    if state.timeZoneID != calendar.timeZone.identifier {
      for metric in [HealthMetric.steps, .activeEnergy, .distance] {
        state.anchors.removeValue(forKey: metric)
      }
      state.timeZoneID = calendar.timeZone.identifier
      try await storage.save(state, for: namespace)
    }
    for metric in HealthMetric.allCases where metric != .totalEnergy {
      while true {
        try check(namespace)
        let page = try await reader.page(
          metric: metric, since: metric == .sleep ? state.initialSleepStart : state.initialStart,
          anchor: state.anchors[metric])
        try check(namespace)
        guard page.anchor.count <= 65_536 else { throw HealthDataError.invalidData }
        if page.isEmpty {
          state.anchors[metric] = page.anchor
          try await storage.save(state, for: namespace)
          if page.exhausted { break }
          continue
        }
        let batch = try HealthSyncBatch(
          deviceID: state.deviceID, sequence: state.sequence + 1,
          timeZoneID: calendar.timeZone.identifier, observedAt: now(), quantities: page.quantities,
          sleep: page.sleep, deletedIDs: page.deletedIDs)
        state.pending = try PreparedHealthSync(
          batch: batch, metric: metric, anchor: page.anchor, processedBuckets: [])
        try await storage.save(state, for: namespace)
        try await deliver(&state, namespace: namespace)
        try await aggregates(&state, namespace: namespace, calendar: calendar)
      }
    }
    while true {
      let buckets = try await pendingBuckets(namespace: namespace)
      try check(namespace)
      guard !buckets.isEmpty else { break }
      for bucket in buckets {
        try bucket.validate()
        state.buckets[bucket.key] = bucket
      }
      try await storage.save(state, for: namespace)
      try await aggregates(&state, namespace: namespace, calendar: calendar)
    }
    state.lastSync = now()
    try await storage.save(state, for: namespace)
    try check(namespace)
    lastSync = state.lastSync
    error = nil
    if state.sequence != previousSequence { onUpdate?() }
  }
  private func aggregates(_ state: inout HealthSyncState, namespace: String, calendar: Calendar)
    async throws
  {
    while !state.buckets.isEmpty {
      try check(namespace)
      // A timezone change retains queued work until a reader using that bucket's zone recomputes it.
      guard let zone = state.buckets.values.sorted(by: { $0.key < $1.key }).first?.timeZoneID else {
        break
      }
      let buckets = state.buckets.values.filter { $0.timeZoneID == zone }.sorted { $0.key < $1.key }
        .prefix(100)
      var values: [HealthSyncAggregate] = []
      for bucket in buckets {
        let value = try await reader.aggregate(bucket)
        try check(namespace)
        values.append(HealthSyncAggregate(bucket: bucket, value: value))
      }
      let batch = try HealthSyncBatch(
        deviceID: state.deviceID, sequence: state.sequence + 1,
        timeZoneID: buckets.first?.timeZoneID ?? calendar.timeZone.identifier, observedAt: now(),
        aggregates: values)
      state.pending = try PreparedHealthSync(
        batch: batch, metric: nil, anchor: nil, processedBuckets: buckets.map(\.key))
      try await storage.save(state, for: namespace)
      try await deliver(&state, namespace: namespace)
    }
  }
  private func deliver(_ state: inout HealthSyncState, namespace: String) async throws {
    guard let pending = state.pending else { return }
    try check(namespace)
    let acknowledgement = try await upload(pending.payload, namespace: namespace)
    try acknowledgement.validate(for: pending.batch)
    try check(namespace)
    state.sequence = acknowledgement.sequence
    if let metric = pending.metric, let anchor = pending.anchor { state.anchors[metric] = anchor }
    for key in pending.processedBuckets { state.buckets.removeValue(forKey: key) }
    for bucket in acknowledgement.buckets { state.buckets[bucket.key] = bucket }
    state.pending = nil
    try await storage.save(state, for: namespace)
    try check(namespace)
  }
  /// Continue a large initial import after the server's fixed rate window; idle stores are never polled.
  private func upload(_ payload: Data, namespace: String) async throws
    -> HealthSyncAcknowledgement
  {
    for attempt in 0..<3 {
      try check(namespace)
      do { return try await remote.apply(payload, account: namespace) } catch ServerError
        .rateLimited
        where attempt < 2
      {
        try await waitForRetry()
      }
    }
    throw ServerError.rateLimited
  }

  private func pendingBuckets(namespace: String) async throws -> [HealthSyncBucket] {
    for attempt in 0..<3 {
      try check(namespace)
      do { return try await remote.pendingBuckets() } catch ServerError.rateLimited
        where attempt < 2
      { try await waitForRetry() }
    }
    throw ServerError.rateLimited
  }

  private func check(_ namespace: String) throws {
    try Task.checkCancellation()
    guard account() == namespace, enabled, available else { throw CancellationError() }
  }
}
