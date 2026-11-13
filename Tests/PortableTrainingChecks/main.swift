import FitLifeCore
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private func expect(
  _ condition: Bool, _ message: String = "Training check failed", file: StaticString = #file,
  line: UInt = #line
) { precondition(condition, message, file: file, line: line) }

private struct Fingerprints: ServerCryptography {
  func authorizationAttempt() -> OAuthAttempt {
    OAuthAttempt(verifier: "v", state: "s", challenge: "c")
  }
  func sha256(_ data: Data) -> String { data.base64EncodedString() }
}

private actor RemoteJournal: TrainingRemoteServing {
  var records: [TrainingRecordKey: TrainingChange] = [:]
  var revision: Int64 = 0
  var offline = false
  var beforeApply: (@Sendable () async -> Void)?
  var beforeRead: (@Sendable () async -> Void)?
  func setOffline(_ value: Bool) { offline = value }
  func onApply(_ action: @escaping @Sendable () async -> Void) { beforeApply = action }
  func onRead(_ action: @escaping @Sendable () async -> Void) { beforeRead = action }
  func reset() {
    records = [:]
    revision = 0
  }
  func value(_ key: TrainingRecordKey) -> TrainingValue? { records[key]?.value }
  func changes(after cursor: Int64) async throws -> TrainingPage {
    if let beforeRead {
      self.beforeRead = nil
      await beforeRead()
    }
    if offline { throw ServerError.unavailable }
    if cursor > revision { throw ServerTrainingError(code: "cursor_reset_required", current: nil) }
    let changes = records.values.filter { $0.revision > cursor }.sorted {
      $0.revision < $1.revision
    }
    return TrainingPage(changes: changes, cursor: changes.last?.revision ?? cursor, hasMore: false)
  }
  func put(_ value: TrainingValue?, key: TrainingRecordKey) throws {
    revision += 1
    records[key] = try TrainingChange(key: key, revision: revision, value: value)
    if key.kind == .workout && value == nil {
      let pulse = TrainingRecordKey(kind: .heartRate, id: key.id)
      if records[pulse] != nil { try put(nil, key: pulse) }
    }
  }
  func apply(_ mutations: [TrainingMutation]) async throws -> [TrainingChange] {
    if let beforeApply {
      self.beforeApply = nil
      await beforeApply()
    }
    if offline { throw ServerError.unavailable }
    for item in mutations {
      let previous = records[item.key]
      if previous?.value != item.value && (previous?.revision ?? 0) != item.baseRevision {
        throw ServerTrainingError(code: "training_conflict", current: previous)
      }
    }
    var result: [TrainingChange] = []
    for item in mutations {
      if let previous = records[item.key], previous.value == item.value {
        result.append(previous)
      } else {
        try put(item.value, key: item.key)
        result.append(records[item.key]!)
      }
    }
    return result
  }
}

@MainActor private final class LocalJournal {
  let roots = MemoryWorkoutRepository()
  var pulse: [UUID: HeartRateRecording] = [:]
  func snapshot() throws -> TrainingSnapshot {
    try TrainingSnapshot(
      workouts: roots.workouts(), templates: roots.templates(), bodyWeights: roots.bodyWeights(),
      heartRate: Array(pulse.values), nutrition: roots.nutritionSnapshot())
  }
  func value(_ key: TrainingRecordKey) throws -> TrainingValue? {
    switch key.kind {
    case .workout: try roots.workouts().first { $0.id == key.id }.map(TrainingValue.workout)
    case .template: try roots.templates().first { $0.id == key.id }.map(TrainingValue.template)
    case .bodyWeight:
      try roots.bodyWeights().first { $0.id == key.id }.map(TrainingValue.bodyWeight)
    case .heartRate: pulse[key.id].map(TrainingValue.heartRate)
    case .foodEntry, .waterEntry, .supplementEntry, .supplementPlan, .nutritionProfile:
      try roots.currentNutritionValue(key)
    }
  }
  func apply(_ change: TrainingChange, expected: TrainingValue?, relatedPulse: TrainingValue?)
    throws -> TrainingLocalApplyResult
  {
    guard try value(change.key) == expected else { return .changed }
    if change.key.kind == .heartRate {
      if case .heartRate(let next) = change.value {
        pulse[change.key.id] = next
      } else {
        pulse[change.key.id] = nil
      }
    } else {
      if change.key.kind == .workout && change.deleted {
        guard pulse[change.key.id].map(TrainingValue.heartRate) == relatedPulse else {
          return .changed
        }
        pulse[change.key.id] = nil
      }
      try roots.applyTrainingChanges([change])
    }
    return .applied
  }
  func coordinator(
    _ remote: RemoteJournal, storage: any TrainingSyncStateStoring,
    available: @escaping @MainActor () -> Bool = { true }
  )
    -> TrainingSyncCoordinator
  {
    TrainingSyncCoordinator(
      remote: remote, storage: storage, cryptography: Fingerprints(), debounce: .zero,
      snapshot: { try self.snapshot() }, current: { try self.value($0) },
      apply: { try self.apply($0, expected: $1, relatedPulse: $2) }, available: available)
  }
}

private actor Gate {
  private var entered = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiting: CheckedContinuation<Void, Never>?
  func block() async {
    entered = true
    waiting?.resume()
    waiting = nil
    if !released { await withCheckedContinuation { continuation = $0 } }
  }
  func untilEntered() async {
    if !entered { await withCheckedContinuation { waiting = $0 } }
  }
  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}

private func workout() throws -> Workout {
  var workout = Workout(name: "Офлайн", startedAt: Date(timeIntervalSince1970: 100))
  try WorkoutEngine.cancel(&workout, at: Date(timeIntervalSince1970: 200))
  return workout
}

private actor GatedStateStore: TrainingSyncStateStoring {
  private var values: [String: TrainingSyncState] = [:]
  private var saveGate: Gate?
  func suspendNextSave(_ gate: Gate) { saveGate = gate }
  func load(_ namespace: String) -> TrainingSyncState { values[namespace] ?? TrainingSyncState() }
  func save(_ state: TrainingSyncState, for namespace: String) async throws {
    if let gate = saveGate {
      saveGate = nil
      await gate.block()
    }
    try state.validate()
    values[namespace] = state
  }
  func accounts() -> [LocalTrainingAccount] { [] }
  func register(_ account: LocalTrainingAccount) {}
}

@MainActor private final class ForegroundState { var active = false }

@main struct TrainingChecks {
  @MainActor static func main() async throws {
    try await nutritionSyncAcrossDevicesAndOfflineDeletion()
    try await offlineDeletionAndInflightEdit()
    try await conflictsAndRelatedPulse()
    try await cancelledReadCannotCrossAccount()
    try await overlappingTransitionsKeepLatestAccountAndResumeForeground()
    try await restoredServerRequiresDeletionChoice()
    try await durableFilesAndPulseAdoption()
    try await wireValidation()
    print(
      "Training checks: restart/offline deletion, edits during upload, explicit conflicts, pulse cascade, cancellation, overlapping scene/account transitions, server restore, durable state corruption, scoped pulse adoption/CAS and real HTTP validation passed (no Apple SDK)."
    )
  }

  @MainActor private static func nutritionSyncAcrossDevicesAndOfflineDeletion() async throws {
    let remote = RemoteJournal()
    let first = LocalJournal()
    let second = LocalJournal()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let plan = SupplementPlan(
      prototype: SupplementEntry(date: now, kind: .creatine, amount: 3), startDate: now,
      timeZoneID: "UTC", remindersEnabled: true)
    let intake = plan.intake(scheduledFor: now, takenAt: now)
    let water = WaterEntry(date: now, milliliters: 250)
    try first.roots.saveSupplementPlan(plan)
    try first.roots.saveSupplementEntry(intake)
    try first.roots.saveWaterEntry(water)
    try first.roots.saveNutritionGoal(NutritionGoal(calories: 2100))
    let storageA = MemoryTrainingSyncStateStore()
    let storageB = MemoryTrainingSyncStateStore()
    let syncA = first.coordinator(remote, storage: storageA)
    let syncB = second.coordinator(remote, storage: storageB)
    try await syncA.connect("account-a")
    await syncA.synchronizeNow()
    try await syncB.connect("account-a")
    await syncB.synchronizeNow()
    expect(try second.roots.supplementPlans() == [plan])
    expect(try second.roots.supplementEntries() == [intake])
    expect(try second.roots.waterEntries() == [water])
    expect(try second.roots.nutritionGoal()?.calories == 2100)
    await syncA.disconnect()
    await remote.setOffline(true)
    try first.roots.deleteSupplementPlan(id: plan.id)
    try first.roots.deleteWaterEntry(id: water.id)
    let restarted = first.coordinator(remote, storage: storageA)
    try await restarted.connect("account-a")
    await restarted.synchronizeNow()
    expect(restarted.errorMessage != nil)
    await restarted.disconnect()
    await remote.setOffline(false)
    let online = first.coordinator(remote, storage: storageA)
    try await online.connect("account-a")
    await online.synchronizeNow()
    await syncB.synchronizeNow()
    expect(try second.roots.supplementPlans().isEmpty && second.roots.waterEntries().isEmpty)
    expect(try second.roots.supplementEntries() == [intake])
    await online.disconnect()
    await syncB.disconnect()
    print(
      "Nutrition journal: two-device sync, profile, offline deletions after restart and preserved supplement history passed."
    )
  }

  @MainActor private static func overlappingTransitionsKeepLatestAccountAndResumeForeground()
    async throws
  {
    let remote = RemoteJournal()
    let storage = GatedStateStore()
    let local = LocalJournal()
    let foreground = ForegroundState()
    let sync = local.coordinator(remote, storage: storage, available: { foreground.active })
    try await sync.connect("initial")
    let switching = Gate()
    await storage.suspendNextSave(switching)
    let earlier = Task { try await sync.connect("account-a") }
    await switching.untilEntered()
    try await sync.connect("account-b")
    await switching.release()
    do {
      try await earlier.value
      preconditionFailure("An older account transition superseded the latest one")
    } catch is CancellationError {}
    expect(sync.isConnected(to: "account-b") && !sync.isConnected(to: "account-a"))

    // A cancelled scene task can finish its checkpoint after the next foreground request arrives.
    let checkpoint = Gate()
    let reading = Gate()
    await storage.suspendNextSave(checkpoint)
    let pause = Task { await sync.pause() }
    await checkpoint.untilEntered()
    foreground.active = true
    let value = TrainingValue.workout(try workout())
    try await remote.put(value, key: value.key)
    await remote.onRead { await reading.block() }
    sync.requestSync(immediately: true)
    pause.cancel()
    await checkpoint.release()
    await pause.value
    await reading.untilEntered()
    expect(sync.isSyncing, "Foreground request during checkpoint was lost")
    await reading.release()
    await sync.synchronizeNow()
    expect(try local.value(value.key) == value)
    await sync.disconnect()
  }

  @MainActor private static func offlineDeletionAndInflightEdit() async throws {
    let remote = RemoteJournal()
    let storage = MemoryTrainingSyncStateStore()
    let local = LocalJournal()
    let original = try workout()
    let key = TrainingValue.workout(original).key
    try local.roots.save(original)
    let sync = local.coordinator(remote, storage: storage)
    await remote.onApply {
      await MainActor.run {
        var changed = original
        changed.notes = "Правка во время отправки"
        try! local.roots.save(changed)
      }
    }
    try await sync.connect("account-a")
    await sync.synchronizeNow()
    let saved = await remote.value(key)
    expect(saved == (try local.value(key)))
    if case .workout(let current) = saved {
      expect(current.notes == "Правка во время отправки")
    } else {
      preconditionFailure("Upload lost workout")
    }
    await sync.disconnect()
    try local.roots.deleteWorkout(id: original.id)
    await remote.setOffline(true)
    let restarted = local.coordinator(remote, storage: storage)
    try await restarted.connect("account-a")
    await restarted.synchronizeNow()
    expect(restarted.errorMessage != nil)
    let stillSaved = await remote.value(key)
    expect(stillSaved != nil)
    await restarted.disconnect()
    await remote.setOffline(false)
    let online = local.coordinator(remote, storage: storage)
    try await online.connect("account-a")
    await online.synchronizeNow()
    let deleted = await remote.value(key)
    expect(deleted == nil && online.conflicts.isEmpty)
    let otherAccount = await storage.load("account-b")
    expect(otherAccount.baselines.isEmpty)
    await online.disconnect()
  }

  @MainActor private static func conflictsAndRelatedPulse() async throws {
    let remote = RemoteJournal()
    let storage = MemoryTrainingSyncStateStore()
    let local = LocalJournal()
    let original = try workout()
    let key = TrainingValue.workout(original).key
    let pulse = try HeartRateRecording(
      workoutID: original.id, mode: .bluetooth,
      readings: [HeartRateReading(date: Date(timeIntervalSince1970: 101), beatsPerMinute: 95.5)])
    try local.roots.save(original)
    local.pulse[original.id] = pulse
    let sync = local.coordinator(remote, storage: storage)
    try await sync.connect("account-a")
    await sync.synchronizeNow()
    await sync.pause()
    var localEdit = original
    localEdit.notes = "Локальная версия"
    try local.roots.save(localEdit)
    var remoteEdit = original
    remoteEdit.notes = "Серверная версия"
    try await remote.put(.workout(remoteEdit), key: key)
    let weight = BodyWeightEntry(measuredAt: Date(timeIntervalSince1970: 300), weightKG: 80)
    try local.roots.saveBodyWeight(weight)
    await sync.synchronizeNow()
    expect(sync.conflicts.count == 1)
    let otherSaved = await remote.value(TrainingValue.bodyWeight(weight).key)
    expect(otherSaved == .bodyWeight(weight))
    let conflict = sync.conflicts[0]
    await sync.resolve(conflict, keepLocal: false, expectedFingerprint: "stale")
    expect(try sync.conflicts.count == 1 && local.value(key) == .workout(localEdit))
    await sync.resolve(
      conflict, keepLocal: true,
      expectedFingerprint: Fingerprints().sha256(
        try TrainingValue.workout(localEdit).canonicalData()))
    await sync.synchronizeNow()
    let winning = await remote.value(key)
    expect(winning == .workout(localEdit) && sync.conflicts.isEmpty)
    await sync.pause()

    // An edited local pulse prevents an otherwise clean remote workout deletion.
    let editedPulse = try HeartRateRecording(
      workoutID: original.id, mode: .bluetooth,
      readings: pulse.readings + [
        HeartRateReading(date: Date(timeIntervalSince1970: 106), beatsPerMinute: 100)
      ])
    local.pulse[original.id] = editedPulse
    try await remote.put(nil, key: key)
    await sync.synchronizeNow()
    expect(sync.conflicts.contains { $0.id == key })
    expect(try local.value(key) != nil && local.pulse[original.id] == editedPulse)
    let deletion = sync.conflicts.first { $0.id == key }!
    await sync.resolve(
      deletion, keepLocal: false,
      expectedFingerprint: Fingerprints().sha256(
        try TrainingValue.workout(localEdit).canonicalData()),
      expectedPulseFingerprint: Fingerprints().sha256(
        try TrainingValue.heartRate(editedPulse).canonicalData()))
    await sync.synchronizeNow()
    expect(try local.value(key) == nil && local.pulse[original.id] == nil && sync.conflicts.isEmpty)
    await sync.disconnect()
  }

  @MainActor private static func cancelledReadCannotCrossAccount() async throws {
    let remote = RemoteJournal()
    let storage = MemoryTrainingSyncStateStore()
    let local = LocalJournal()
    let gate = Gate()
    let value = TrainingValue.workout(try workout())
    try await remote.put(value, key: value.key)
    await remote.onRead { await gate.block() }
    let sync = local.coordinator(remote, storage: storage)
    try await sync.connect("account-a")
    let read = Task { await sync.synchronizeNow() }
    await gate.untilEntered()
    var stopping = false
    let stop = Task {
      stopping = true
      await sync.disconnect()
    }
    while !stopping { await Task.yield() }
    await gate.release()
    await stop.value
    await read.value
    expect(try local.roots.workouts().isEmpty)
    expect(!sync.isConnected(to: "account-a"))
    let state = await storage.load("account-a")
    expect(state.cursor == 0 && state.baselines.isEmpty)
  }

  @MainActor private static func restoredServerRequiresDeletionChoice() async throws {
    let remote = RemoteJournal()
    let storage = MemoryTrainingSyncStateStore()
    let local = LocalJournal()
    let original = try workout()
    let key = TrainingValue.workout(original).key
    try local.roots.save(original)
    let sync = local.coordinator(remote, storage: storage)
    try await sync.connect("account-a")
    await sync.synchronizeNow()
    try local.roots.deleteWorkout(id: original.id)
    await sync.synchronizeNow()
    await sync.disconnect()
    await remote.reset()
    try await remote.put(.workout(original), key: key)
    let restored = local.coordinator(remote, storage: storage)
    try await restored.connect("account-a")
    await restored.synchronizeNow()
    expect(try local.roots.workouts().isEmpty)
    expect(restored.conflicts.count == 1, "Restored archive resurrected a deleted workout")
    await restored.resolve(restored.conflicts[0], keepLocal: true, expectedFingerprint: nil)
    await restored.synchronizeNow()
    let deleted = await remote.value(key)
    expect(deleted == nil && restored.conflicts.isEmpty)
    await restored.disconnect()
  }

  private static func durableFilesAndPulseAdoption() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stateDirectory = directory.appendingPathComponent("state")
    let storage = TrainingSyncStateStore(directory: stateDirectory)
    var state = TrainingSyncState()
    state.cursor = 12
    try await storage.save(state, for: "account-a")
    let reloaded = try await TrainingSyncStateStore(directory: stateDirectory).load("account-a")
    expect(reloaded == state)
    var legacy =
      try JSONSerialization.jsonObject(with: TrainingCoding.encoder().encode(state))
      as! [String: Any]
    legacy.removeValue(forKey: "nutritionFeedVersion")
    try JSONSerialization.data(withJSONObject: legacy).write(
      to: stateDirectory.appendingPathComponent("account-a.json"))
    let upgraded = try await storage.load("account-a")
    expect(upgraded.cursor == 0 && upgraded.nutritionFeedVersion == 1)
    expect(upgraded.baselines == state.baselines && upgraded.conflicts == state.conflicts)
    let repeatedUpgrade = try await storage.load("account-a")
    expect(repeatedUpgrade == upgraded)
    try Data("broken".utf8).write(to: stateDirectory.appendingPathComponent("account-a.json"))
    do {
      _ = try await storage.load("account-a")
      preconditionFailure("Corruption silently reset state")
    } catch is DecodingError {}
    do {
      try await storage.save(state, for: "../escape")
      preconditionFailure("Accepted unsafe scope")
    } catch TrainingSyncError.invalidData {}

    let pulseDirectory = directory.appendingPathComponent("pulse")
    let repository = LocalHeartRateRepository(directory: pulseDirectory)
    let id = UUID()
    let recording = try HeartRateRecording(
      workoutID: id, mode: .bluetooth,
      readings: [HeartRateReading(date: Date(timeIntervalSince1970: 105), beatsPerMinute: 111.25)])
    try await repository.save(recording)
    try await repository.activateTrainingAccount("account-a", adoptUnscoped: true)
    expect(try await repository.recording(for: id) == recording)
    let changed = try await repository.compareAndSet(workoutID: id, expected: nil, replacement: nil)
    expect(!changed)
    try await repository.activateTrainingAccount("account-b", adoptUnscoped: false)
    expect(try await repository.recording(for: id) == nil)
    try await repository.activateTrainingAccount("account-a", adoptUnscoped: true)
    let removed = try await repository.compareAndSet(
      workoutID: id, expected: recording, replacement: nil)
    expect(removed)
    let restarted = LocalHeartRateRepository(directory: pulseDirectory)
    try await restarted.activateTrainingAccount("account-a", adoptUnscoped: true)
    expect(try await restarted.recording(for: id) == nil, "Adoption resurrected a deleted pulse")
    do {
      try await restarted.activateTrainingAccount("account-b", adoptUnscoped: true)
      preconditionFailure("Pulse adopted twice")
    } catch TrainingSyncError.accountMismatch {}
  }

  private static func wireValidation() async throws {
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [TrainingProtocol.self]
    let urlSession = URLSession(configuration: transport)
    defer { urlSession.invalidateAndCancel() }
    let auth = URL(string: "https://auth.example.com/")!
    let api = URL(string: "https://api.example.com/")!
    let session = AccountSession(
      configuration: try ServerConfiguration(authenticationURL: auth, backendURL: api),
      http: ServerHTTPClient(session: urlSession), credentials: WireCredentials())
    let remote = RemoteTrainingClient(session: session)
    let value = TrainingValue.workout(try workout())
    let change = try TrainingChange(key: value.key, revision: 1, value: value)
    TrainingProtocol.response.withLock {
      $0 = (200, try! TrainingCoding.encoder().encode([change]))
    }
    let result = try await remote.apply([
      TrainingMutation(key: value.key, baseRevision: 0, value: value)
    ])
    expect(result == [change])
    let precise = TrainingValue.supplementEntry(
      SupplementEntry(
        date: Date(timeIntervalSinceReferenceDate: 815_432_100.1234567), kind: .creatine, amount: 3)
    )
    let preciseChange = try TrainingChange(key: precise.key, revision: 2, value: precise)
    let preciseData = try TrainingCoding.encoder().encode([preciseChange])
    TrainingProtocol.response.withLock { $0 = (200, preciseData) }
    let preciseResult = try await remote.apply([
      TrainingMutation(key: precise.key, baseRevision: 0, value: precise)
    ])
    expect(try preciseResult[0].value?.canonicalData() == precise.canonicalData())
    TrainingProtocol.response.withLock {
      $0 = (400, Data(#"{"code":"invalid_training_mutation","current":null}"#.utf8))
    }
    do {
      _ = try await remote.apply([
        TrainingMutation(key: precise.key, baseRevision: 0, value: precise)
      ])
      preconditionFailure("Old backend rejection did not request an update")
    } catch let error as ServerTrainingError { expect(error.code == "server_update_required") }
    let wrong = try TrainingChange(
      key: TrainingRecordKey(kind: .workout, id: UUID()), revision: 2, value: nil)
    TrainingProtocol.response.withLock { $0 = (200, try! TrainingCoding.encoder().encode([wrong])) }
    do {
      _ = try await remote.apply([TrainingMutation(key: value.key, baseRevision: 0, value: value)])
      preconditionFailure("Accepted another record")
    } catch ServerError.invalidResponse {}
    TrainingProtocol.response.withLock {
      $0 = (
        409,
        Data(
          "{\"code\":\"training_conflict\",\"current\":\(String(decoding: try! TrainingCoding.encoder().encode(change), as: UTF8.self))}"
            .utf8)
      )
    }
    do {
      _ = try await remote.apply([TrainingMutation(key: value.key, baseRevision: 0, value: nil)])
      preconditionFailure("Lost conflict")
    } catch let error as ServerTrainingError { expect(error.current == change) }
    TrainingProtocol.response.withLock {
      $0 = (200, Data(#"{"changes":[],"cursor":5,"hasMore":true}"#.utf8))
    }
    do {
      _ = try await remote.changes(after: 0)
      preconditionFailure("Accepted malformed cursor")
    } catch TrainingSyncError.invalidData {}
    TrainingProtocol.response.withLock { $0 = (404, Data()) }
    do {
      _ = try await remote.changes(after: 0)
      preconditionFailure("Ignored missing server update")
    } catch let error as ServerTrainingError { expect(error.code == "server_update_required") }
  }
}

private actor WireCredentials: AccountTokenStoring {
  func load() -> AccountTokens? {
    AccountTokens(
      accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture,
      profile: AccountProfile(
        id: UUID().uuidString, name: "Fixture", createdAt: .distantPast, logins: []))
  }
  func save(_ tokens: AccountTokens) {}
  func clear() {}
}

private final class TrainingProtocol: URLProtocol {
  static let response = Mutex<(Int, Data)>((200, Data()))
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    expect(request.url?.host == "api.example.com" && request.url?.path == "/v1/training/changes")
    expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
    let (status, data) = Self.response.withLock { $0 }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
