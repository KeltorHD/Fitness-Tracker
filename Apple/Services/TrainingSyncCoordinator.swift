import FitLifeCore
import Foundation
import Observation

enum TrainingLocalApplyResult: Equatable, Sendable { case applied, changed, activeWorkout }

/// Owns one foreground synchronization job. Durable baselines, not callback delivery, track edits.
@MainActor @Observable final class TrainingSyncCoordinator {
  private(set) var isSyncing = false
  private(set) var errorMessage: String?
  private(set) var lastSyncedAt: Date?
  private(set) var pendingCount = 0
  private(set) var needsSignIn = false
  private var state = TrainingSyncState()
  var conflicts: [TrainingConflict] { state.conflicts }
  @ObservationIgnored private let remote: any TrainingRemoteServing
  @ObservationIgnored private let storage: any TrainingSyncStateStoring
  @ObservationIgnored private let cryptography: any ServerCryptography
  @ObservationIgnored private let snapshot: @MainActor () async throws -> TrainingSnapshot
  @ObservationIgnored private let current:
    @MainActor (TrainingRecordKey) async throws -> TrainingValue?
  @ObservationIgnored private let applyLocal:
    @MainActor (TrainingChange, TrainingValue?, TrainingValue?) async throws ->
      TrainingLocalApplyResult
  @ObservationIgnored private let available: @MainActor () -> Bool
  @ObservationIgnored private let debounce: Duration
  @ObservationIgnored private var namespace: String?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var retry: Task<Void, Never>?
  @ObservationIgnored private var requested = false
  @ObservationIgnored private var resolving = false
  @ObservationIgnored private var stopsInFlight = 0
  @ObservationIgnored private var connectionIntent: UUID?
  @ObservationIgnored private var resumeRequested = false

  init(
    remote: any TrainingRemoteServing, storage: any TrainingSyncStateStoring,
    cryptography: any ServerCryptography, debounce: Duration = .seconds(2),
    snapshot: @escaping @MainActor () async throws -> TrainingSnapshot,
    current: @escaping @MainActor (TrainingRecordKey) async throws -> TrainingValue?,
    apply:
      @escaping @MainActor (TrainingChange, TrainingValue?, TrainingValue?) async throws ->
      TrainingLocalApplyResult,
    available: @escaping @MainActor () -> Bool
  ) {
    self.remote = remote
    self.storage = storage
    self.cryptography = cryptography
    self.debounce = debounce
    self.snapshot = snapshot
    self.current = current
    self.applyLocal = apply
    self.available = available
  }

  func disconnect() async {
    let intent = UUID()
    connectionIntent = intent
    await disconnect(intent: intent)
  }

  private func disconnect(intent: UUID) async {
    stopsInFlight += 1
    defer { finishStop() }
    await pause()
    guard connectionIntent == intent else { return }
    namespace = nil
    state = TrainingSyncState()
    errorMessage = nil
    lastSyncedAt = nil
    pendingCount = 0
    needsSignIn = false
    resumeRequested = false
  }

  func pause() async {
    stopsInFlight += 1
    defer { finishStop() }
    generation += 1
    let token = generation
    retry?.cancel()
    retry = nil
    let previous = task
    previous?.cancel()
    await previous?.value
    guard token == generation else { return }
    task = nil
    requested = false
    resolving = false
    isSyncing = false
    if let namespace {
      do { try await storage.save(state, for: namespace) } catch {
        if token == generation, !(error is CancellationError) { errorMessage = message(error) }
      }
    }
  }

  func isConnected(to namespace: String) -> Bool { self.namespace == namespace }

  func connect(_ namespace: String) async throws {
    let intent = UUID()
    connectionIntent = intent
    await disconnect(intent: intent)
    try Task.checkCancellation()
    guard connectionIntent == intent else { throw CancellationError() }
    let token = generation
    let loaded = try await storage.load(namespace)
    try Task.checkCancellation()
    guard token == generation, connectionIntent == intent else { throw CancellationError() }
    self.namespace = namespace
    state = loaded
    requestSync()
  }

  func requestSync(immediately: Bool = false) {
    guard !Task.isCancelled, namespace != nil, available(), !needsSignIn else { return }
    guard stopsInFlight == 0 else {
      resumeRequested = true
      return
    }
    requested = true
    retry?.cancel()
    retry = nil
    guard task == nil, !resolving else { return }
    let token = generation
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.generation == token {
          self.task = nil
          self.isSyncing = false
        }
      }
      do {
        if !immediately { try await Task.sleep(for: self.debounce) }
        repeat {
          try self.check(token)
          self.requested = false
          self.isSyncing = true
          self.errorMessage = nil
          try await self.synchronize(token)
          self.lastSyncedAt = .now
        } while self.requested && self.available()
      } catch {
        guard self.generation == token, !Task.isCancelled, !(error is CancellationError) else {
          return
        }
        self.errorMessage = self.message(error)
        self.needsSignIn =
          error as? ServerError == .signInRequired
          || (error as? ServerTrainingError)?.code == "account_deleted"
        if error as? ServerError == .unavailable || error as? ServerError == .rateLimited {
          // Finite retry belongs to this foreground coordinator and is cancelled on disconnect.
          self.retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, token == self.generation else { return }
            self.requestSync(immediately: true)
          }
        }
      }
    }
  }

  private func finishStop() {
    stopsInFlight -= 1
    if stopsInFlight == 0 && resumeRequested {
      resumeRequested = false
      let token = generation
      retry?.cancel()
      retry = Task { [weak self] in
        guard let self, !Task.isCancelled, token == self.generation else { return }
        self.retry = nil
        self.requestSync(immediately: true)
      }
    }
  }

  func synchronizeNow() async {
    requestSync(immediately: true)
    await task?.value
  }

  private func synchronize(_ token: Int) async throws {
    do { try await pull(token) } catch let error as ServerTrainingError
      where error.code == "cursor_reset_required"
    {
      state.resetServerRevisions()
      try await persist(token)
      try await pull(token)
    }
    while true {
      try check(token)
      // A parent choice may also converge a pulse conflict whose feed page is already checkpointed.
      for conflict in state.conflicts {
        let local = try await current(conflict.id)
        try check(token)
        if local == conflict.remote.value { try acknowledge(conflict.remote) }
      }
      try await persist(token)
      let local = try await snapshot()
      try check(token)
      let pending = try TrainingSyncPlanner.pending(
        local: local.values, state: state, fingerprint: fingerprint)
      pendingCount = pending.count
      guard !pending.isEmpty else { break }
      var batch: [TrainingMutation] = []
      var size = 2
      for mutation in pending.prefix(100) {
        let bytes = try TrainingCoding.encoder().encode(mutation).count + 1
        if !batch.isEmpty && size + bytes > RemoteTrainingClient.maximumRequestBytes { break }
        guard bytes + 2 <= RemoteTrainingClient.maximumRequestBytes else {
          throw ServerTrainingError(code: "record_too_large", current: nil)
        }
        batch.append(mutation)
        size += bytes
      }
      do {
        let changes = try await remote.apply(batch)
        try check(token)
        for change in changes { try acknowledge(change) }
        try await persist(token)
      } catch let error as ServerTrainingError where error.code == "training_conflict" {
        if let current = error.current {
          try await merge(current, token: token)
        } else {
          state.resetServerRevisions()
        }
        try await persist(token)
        try await pull(token)
      }
    }
    try await pull(token)
  }

  private func pull(_ token: Int) async throws {
    var resets = 0
    while true {
      try check(token)
      let page = try await remote.changes(after: state.cursor)
      try check(token)
      try page.validate(after: state.cursor)
      do {
        for change in page.changes { try await merge(change, token: token) }
        state.cursor = page.cursor
        try await persist(token)
      } catch {
        // Preserve acknowledgments of already applied records without advancing the page cursor.
        if !Task.isCancelled { try await persist(token) }
        throw error
      }
      if page.hasMore { continue }
      if state.baselines.contains(where: { $0.revision > page.cursor }) {
        guard resets == 0 else { throw TrainingSyncError.invalidData }
        resets += 1
        state.resetServerRevisions()
        try await persist(token)
        continue
      }
      break
    }
  }

  private func merge(_ change: TrainingChange, token: Int) async throws {
    try check(token)
    let local = try await current(change.key)
    try check(token)
    let baseline = state.baselines.first { $0.key == change.key }
    let decision = try TrainingSyncPlanner.decision(
      local: local, baseline: baseline, remote: change, fingerprint: fingerprint)
    if decision == .ignore { return }
    if decision == .acknowledge {
      try acknowledge(change)
      return
    }
    let parent = TrainingRecordKey(kind: .workout, id: change.key.id)
    if decision == .conflict
      || change.key.kind == .heartRate && state.conflicts.contains(where: { $0.id == parent })
    {
      state.remember(TrainingConflict(remote: change))
      return
    }
    var relatedPulse: TrainingValue?
    if change.key.kind == .workout && change.deleted {
      let pulseKey = TrainingRecordKey(kind: .heartRate, id: change.key.id)
      let pulse = try await current(pulseKey)
      relatedPulse = pulse
      try check(token)
      let pulseHash = try pulse.map(fingerprint)
      let known = state.baselines.first { $0.key == pulseKey }
      if pulseHash != known?.fingerprint {
        state.remember(TrainingConflict(remote: change))
        return
      }
    }
    switch try await applyLocal(change, local, relatedPulse) {
    case .applied:
      try check(token)
      try acknowledge(change)
    case .changed:
      try check(token)
      state.remember(TrainingConflict(remote: change))
    case .activeWorkout:
      try check(token)
      state.remember(TrainingConflict(remote: change, activeWorkoutCollision: true))
    }
  }

  func resolve(
    _ conflict: TrainingConflict, keepLocal: Bool, expectedFingerprint: String?,
    expectedPulseFingerprint: String? = nil
  ) async {
    await task?.value
    let token = generation
    guard namespace != nil, available(), stopsInFlight == 0,
      state.conflicts.contains(where: {
        $0.id == conflict.id && $0.remote.revision == conflict.remote.revision
      })
    else {
      errorMessage = "Серверная запись изменилась. Обновите предпросмотр."
      return
    }
    resolving = true
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.generation == token {
          self.task = nil
          self.resolving = false
          self.isSyncing = false
          if self.requested { self.requestSync(immediately: true) }
        }
      }
      await self.resolveNow(
        conflict, keepLocal: keepLocal, expectedFingerprint: expectedFingerprint,
        expectedPulseFingerprint: expectedPulseFingerprint, token: token)
    }
    await task?.value
  }

  private func resolveNow(
    _ conflict: TrainingConflict, keepLocal: Bool, expectedFingerprint: String?,
    expectedPulseFingerprint: String?, token: Int
  ) async {
    isSyncing = true
    errorMessage = nil
    do {
      let local = try await current(conflict.id)
      try check(token)
      guard try local.map(fingerprint) == expectedFingerprint else {
        throw ServerTrainingError(code: "local_changed", current: nil)
      }
      var relatedPulse: TrainingValue?
      if conflict.id.kind == .workout && conflict.remote.deleted && !keepLocal {
        relatedPulse = try await current(TrainingRecordKey(kind: .heartRate, id: conflict.id.id))
        try check(token)
        guard try relatedPulse.map(fingerprint) == expectedPulseFingerprint else {
          throw ServerTrainingError(code: "local_changed", current: nil)
        }
      }
      if keepLocal {
        let mutation = try TrainingMutation(
          key: conflict.id, baseRevision: conflict.remote.revision, value: local)
        let result = try await remote.apply([mutation])
        try check(token)
        guard let saved = result.first, result.count == 1 else {
          throw TrainingSyncError.invalidData
        }
        try acknowledge(saved)
      } else {
        guard try await applyLocal(conflict.remote, local, relatedPulse) == .applied else {
          throw TrainingSyncError.activeWorkout
        }
        try check(token)
        try acknowledge(conflict.remote)
      }
      try await persist(token)
      requestSync(immediately: true)
    } catch let error as ServerTrainingError where error.code == "training_conflict" {
      if let current = error.current { state.remember(TrainingConflict(remote: current)) }
      do { try await persist(token) } catch { errorMessage = message(error) }
      errorMessage = message(error)
    } catch {
      guard token == generation, !Task.isCancelled else { return }
      errorMessage = message(error)
    }
  }

  private func acknowledge(_ change: TrainingChange) throws {
    state.remember(
      TrainingBaseline(
        key: change.key, revision: change.revision, fingerprint: try change.value.map(fingerprint)))
    state.conflicts.removeAll { $0.id == change.key }
  }
  private func fingerprint(_ value: TrainingValue) throws -> String {
    cryptography.sha256(try value.canonicalData())
  }
  private func persist(_ token: Int) async throws {
    try check(token)
    guard let namespace else { throw CancellationError() }
    try await storage.save(state, for: namespace)
    try check(token)
  }
  private func check(_ token: Int) throws {
    try Task.checkCancellation()
    guard token == generation, namespace != nil, available() else { throw CancellationError() }
  }
  private func message(_ error: any Error) -> String {
    if let error = error as? ServerError {
      return error.errorDescription ?? "Не удалось синхронизировать данные."
    }
    if let error = error as? ServerTrainingError {
      return error.errorDescription ?? "Не удалось синхронизировать данные."
    }
    if error as? TrainingSyncError == .activeWorkout {
      return "Завершите текущую тренировку или остановите приём пульса перед заменой данных."
    }
    return "Не удалось синхронизировать данные. Локальный журнал сохранён; повторите попытку."
  }
}
