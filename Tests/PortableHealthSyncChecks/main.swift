import FitLifeCore
import Foundation

private struct CheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(message: message) }
}
@MainActor private final class Namespace { var value = "account-a" }

@MainActor private final class Reader: AppleHealthSyncReading {
  var authorizations = 0
  var reads = 0
  var starts: [HealthMetric: Date] = [:]
  var failPermission = false
  var metric = HealthMetric.bodyWeight
  let id = UUID()
  let day = Date(timeIntervalSince1970: 1_711_756_800)
  var aggregateRequests: [HealthSyncBucket] = []
  func authorize() async throws {
    authorizations += 1
    if failPermission { throw HealthDataError.permissionRequired }
  }
  func page(metric: HealthMetric, since: Date, anchor: Data?) async throws -> HealthAnchoredPage {
    reads += 1
    starts[metric] = since
    if metric == self.metric && anchor == nil {
      return HealthAnchoredPage(
        quantities: [
          HealthQuantity(
            id: id, metric: metric, start: day, end: day,
            value: metric == .steps ? 100 : 72.5, sourceID: "source", sourceName: "Source")
        ], sleep: [], deletedIDs: [], anchor: Data([1]), exhausted: false)
    }
    return HealthAnchoredPage(
      quantities: [], sleep: [], deletedIDs: [], anchor: Data([2]), exhausted: true)
  }
  func aggregate(_ bucket: HealthSyncBucket) async throws -> Double? {
    aggregateRequests.append(bucket)
    return bucket.excludedIDs.isEmpty ? 100 : 90
  }
  func changes(since: Date) -> AsyncThrowingStream<Void, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

@MainActor private final class Remote: HealthSyncRemoteServing {
  var available = true
  var dropResponse = false
  var rateLimitResponses = 0
  var wrongAck = false
  var aggregateConflict = false
  var calls: [HealthSyncBatch] = []
  var payloads: [Data] = []
  var acknowledgements: [UUID: HealthSyncAcknowledgement] = [:]
  var beforeResponse: (@MainActor () -> Void)?
  var pause = false
  var continuation: CheckedContinuation<Void, Never>?
  var waiter: CheckedContinuation<Void, Never>?
  let storage: any HealthSyncStateStoring
  let namespace: Namespace
  init(storage: any HealthSyncStateStoring, namespace: Namespace) {
    self.storage = storage
    self.namespace = namespace
  }
  func pendingBuckets() async throws -> [HealthSyncBucket] { [] }
  func apply(_ payload: Data, account expectedAccount: String) async throws
    -> HealthSyncAcknowledgement
  {
    guard expectedAccount == namespace.value else { throw CancellationError() }
    let batch = try HealthSyncCoding.decoder().decode(HealthSyncBatch.self, from: payload)
    let saved = try await storage.load(expectedAccount)
    try expect(saved?.pending?.batch == batch, "Write-ahead batch must be on disk before HTTP")
    try expect(saved?.pending?.payload == payload, "Exact HTTP bytes must be durable before upload")
    if batch.quantities.contains(where: { $0.metric == .bodyWeight }) {
      try expect(saved?.anchors[.bodyWeight] == nil, "Anchor cannot advance before ACK")
    }
    calls.append(batch)
    payloads.append(payload)
    if rateLimitResponses > 0 {
      rateLimitResponses -= 1
      throw ServerError.rateLimited
    }
    let ack: HealthSyncAcknowledgement
    if let known = acknowledgements[batch.batchID] {
      ack = known
    } else {
      var buckets: [HealthSyncBucket] = []
      if let point = batch.quantities.first, point.metric == .steps {
        buckets = [
          HealthSyncBucket(
            metric: .steps, start: point.start, end: point.start.addingTimeInterval(86_400),
            timeZoneID: "GMT", revision: 1)
        ]
      }
      if aggregateConflict, let bucket = batch.aggregates.first?.bucket {
        aggregateConflict = false
        buckets = [
          HealthSyncBucket(
            metric: bucket.metric, start: bucket.start, end: bucket.end,
            timeZoneID: bucket.timeZoneID, revision: 2, excludedIDs: [UUID()])
        ]
      }
      ack = HealthSyncAcknowledgement(
        batchID: batch.batchID, sequence: batch.sequence, buckets: buckets)
      acknowledgements[batch.batchID] = ack
    }
    if pause {
      await withCheckedContinuation {
        continuation = $0
        waiter?.resume()
        waiter = nil
      }
    }
    beforeResponse?()
    if dropResponse {
      dropResponse = false
      throw ServerError.unavailable
    }
    if wrongAck {
      return HealthSyncAcknowledgement(batchID: UUID(), sequence: batch.sequence, buckets: [])
    }
    return ack
  }
  func waitForRequest() async {
    if continuation == nil { await withCheckedContinuation { waiter = $0 } }
  }
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  { throw HealthDataError.unavailable }
}

@MainActor private final class Publishing { var value = true }
@MainActor private final class LocalProvider: HealthDataProviding {
  let id = HealthProviderID.appleHealth
  let supportedMetrics: Set<HealthMetric> = [.bodyWeight]
  var reads = 0
  var authorizations = 0
  func authorize(metrics: Set<HealthMetric>) async throws -> Set<HealthMetric> {
    authorizations += 1
    return metrics
  }
  func read(start: Date, end: Date, metrics: Set<HealthMetric>, calendar: Calendar) async throws
    -> HealthDataSnapshot
  {
    reads += 1
    return try HealthDataSnapshot(
      provider: .appleHealth, start: start, end: end, fetchedAt: end, metrics: metrics,
      quantities: [
        HealthQuantity(
          id: UUID(), metric: .bodyWeight, start: start, end: start, value: 70, sourceID: "source",
          sourceName: "Source")
      ], sleep: [])
  }
}

@main private struct HealthSyncChecks {
  @MainActor static func main() async throws {
    let suite = "FitLife.HealthSyncChecks.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FitLife-HealthSync-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = HealthSyncStateStore(directory: root)
    let namespace = Namespace()
    let reader = Reader()
    let remote = Remote(storage: disk, namespace: namespace)
    // AppStore injects an ordinary clock closure; the adapter must keep calls on MainActor.
    func coordinator(
      now: @escaping () -> Date = {
        Date(timeIntervalSinceReferenceDate: 760_000_000.001)
      }
    ) -> AppleHealthSyncCoordinator {
      AppleHealthSyncCoordinator(
        reader: reader, remote: remote, storage: disk, defaults: defaults,
        account: { namespace.value },
        now: { now() }, waitForRetry: {}
      )
    }
    let first = coordinator()
    await first.observe(calendar: calendar, continuously: false)
    try expect(
      reader.reads == 0 && reader.authorizations == 0, "No upload or HealthKit query before consent"
    )
    await first.setEnabled(true)
    remote.dropResponse = true
    await first.observe(calendar: calendar, continuously: false)
    let pending = try await disk.load(namespace.value)
    try expect(
      first.error != nil && pending?.pending != nil && pending?.sequence == 0,
      "Lost response preserves durable pending request")
    try expect(pending?.anchors[.bodyWeight] == nil, "Lost ACK preserves old anchor")
    let restarted = coordinator()
    await restarted.observe(calendar: calendar, continuously: false)
    let saved = try await disk.load(namespace.value)
    try expect(
      remote.calls.count == 2 && remote.calls[0].batchID == remote.calls[1].batchID,
      "Restart retries same idempotent batch")
    try expect(remote.payloads[0] == remote.payloads[1], "Restart replays identical HTTP bytes")
    try expect(
      saved?.sequence == 1 && saved?.pending == nil && saved?.anchors[.bodyWeight] == Data([2]),
      "Only ACK commits anchor and sequence")
    try expect(
      restarted.error == nil && restarted.lastSync != nil, "Successful retry recovers visible state"
    )
    await restarted.setEnabled(false)
    let before = reader.reads
    await restarted.observe(calendar: calendar, continuously: false)
    try expect(reader.reads == before, "Opt-out stops reads and uploads")

    namespace.value = "account-b"
    let other = coordinator()
    await other.observe(calendar: calendar, continuously: false)
    try expect(
      try await disk.load(namespace.value) == nil, "Other account cannot reuse consent or anchors")
    await other.setEnabled(true)
    remote.beforeResponse = { namespace.value = "account-c" }
    await other.observe(calendar: calendar, continuously: false)
    let old = try await disk.load("account-b")
    try expect(
      old?.pending != nil && old?.sequence == 0,
      "Account switch cannot acknowledge another namespace")
    try expect(try await disk.load("account-c") == nil, "No state leak into new account")
    remote.beforeResponse = nil

    namespace.value = "account-cancel"
    let cancelled = coordinator()
    await cancelled.setEnabled(true)
    remote.pause = true
    let run = Task { await cancelled.observe(calendar: calendar, continuously: false) }
    await remote.waitForRequest()
    run.cancel()
    remote.resume()
    await run.value
    try expect(
      try await disk.load(namespace.value)?.pending != nil,
      "Cancellation after server commit preserves replayable pending batch")
    remote.pause = false

    namespace.value = "account-wrong-ack"
    let wrong = coordinator()
    await wrong.setEnabled(true)
    remote.wrongAck = true
    await wrong.observe(calendar: calendar, continuously: false)
    let wrongState = try await disk.load(namespace.value)
    try expect(wrong.error != nil && wrongState?.sequence == 0, "Wrong ACK never advances state")
    remote.wrongAck = false

    namespace.value = "account-aggregate"
    reader.metric = .steps
    remote.aggregateConflict = true
    let aggregated = coordinator()
    var updates = 0
    aggregated.onUpdate = { updates += 1 }
    await aggregated.setEnabled(true)
    updates = 0
    await aggregated.observe(calendar: calendar, continuously: false)
    let buckets = reader.aggregateRequests
    try expect(
      buckets.count == 2 && buckets[0].revision == 1 && buckets[1].revision == 2
        && !buckets[1].excludedIDs.isEmpty,
      "CAS conflict re-reads native statistics with server deletion exclusions")
    let state = try await disk.load(namespace.value)
    try expect(
      state?.sequence == 3 && state?.buckets.isEmpty == true && state?.pending == nil
        && updates == 1, "Aggregate queue drains and updates account views once")

    namespace.value = "account-denied"
    reader.failPermission = true
    let denied = coordinator()
    let requestsBeforeDenial = remote.calls.count
    await denied.setEnabled(true)
    await denied.observe(calendar: calendar, continuously: false)
    try expect(
      !denied.enabled && denied.error != nil && remote.calls.count == requestsBeforeDenial,
      "Denied permission cannot enable sharing or upload")
    reader.failPermission = false
    namespace.value = "account-aggregate"

    namespace.value = "account-rate-limited"
    reader.metric = .bodyWeight
    let limited = coordinator()
    await limited.setEnabled(true)
    remote.rateLimitResponses = 1
    let callsBeforeRateLimit = remote.calls.count
    await limited.observe(calendar: calendar, continuously: false)
    try expect(
      limited.error == nil && remote.calls.count == callsBeforeRateLimit + 2,
      "Rate limit retries the pending batch instead of restarting the import")
    let retried = Array(remote.calls.suffix(2))
    try expect(
      retried[0].batchID == retried[1].batchID, "Rate-limit retry preserves idempotent identity")
    namespace.value = "account-aggregate"

    let publishing = Publishing()
    let local = LocalProvider()
    let provider = SyncedAppleHealthProvider(
      local: local, remote: remote, preferLocal: { publishing.value })
    _ = try await provider.authorize(metrics: [.bodyWeight])
    let offline = try await provider.read(
      start: reader.day, end: reader.day.addingTimeInterval(3600), metrics: [.bodyWeight],
      calendar: calendar)
    try expect(
      local.reads == 1 && offline.quantities.first?.value == 70,
      "Publishing iPhone reads actual local data without the server")
    publishing.value = false
    _ = try await provider.authorize(metrics: [.bodyWeight])
    try expect(
      local.authorizations == 1,
      "Read-only account history does not ask for this device’s HealthKit permissions")
    do {
      _ = try await provider.read(
        start: reader.day, end: reader.day.addingTimeInterval(3600), metrics: [.bodyWeight],
        calendar: calendar)
      throw CheckFailure(message: "Expected remote failure")
    } catch HealthDataError.unavailable {}
    try expect(
      local.reads == 1, "Read-only device cannot silently substitute its own HealthKit store")

    let corrupt = root.appendingPathComponent(namespace.value).appendingPathExtension("json")
    try Data("broken".utf8).write(to: corrupt)
    do {
      _ = try await disk.load(namespace.value)
      throw CheckFailure(message: "Corrupt state accepted")
    } catch is DecodingError {}
    try expect(
      FileManager.default.fileExists(atPath: corrupt.path),
      "Corrupt durable state is never deleted/reset")
    print(
      "Apple Health sync: opt-in, durable ACK/anchor replay, restart, account switching, cancellation, CAS/deletion exclusions, opt-out and corruption passed (no HealthKit SDK or network)."
    )
  }
}
