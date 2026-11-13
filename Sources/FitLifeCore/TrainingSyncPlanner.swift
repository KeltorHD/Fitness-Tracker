import Foundation

public struct TrainingBaseline: Codable, Equatable, Sendable {
  public let key: TrainingRecordKey
  public let revision: Int64
  /// Nil represents a synchronized deletion; payloads remain in the local repository.
  public let fingerprint: String?
  public init(key: TrainingRecordKey, revision: Int64, fingerprint: String?) {
    self.key = key
    self.revision = revision
    self.fingerprint = fingerprint
  }
}

public struct TrainingConflict: Codable, Equatable, Identifiable, Sendable {
  public var id: TrainingRecordKey { remote.key }
  public let remote: TrainingChange
  public let activeWorkoutCollision: Bool
  public init(remote: TrainingChange, activeWorkoutCollision: Bool = false) {
    self.remote = remote
    self.activeWorkoutCollision = activeWorkoutCollision
  }
}

public struct TrainingSyncState: Codable, Equatable, Sendable {
  public var version = 1
  public var cursor: Int64 = 0
  public var baselines: [TrainingBaseline] = []
  public var conflicts: [TrainingConflict] = []
  public init() {}
  public func validate() throws {
    guard version == 1, cursor >= 0,
      Set(baselines.map(\.key)).count == baselines.count,
      Set(conflicts.map(\.id)).count == conflicts.count,
      baselines.allSatisfy({
        $0.revision >= 0 && ($0.fingerprint == nil || $0.fingerprint?.isEmpty == false)
      })
    else { throw TrainingSyncError.invalidData }
  }
  public mutating func remember(_ baseline: TrainingBaseline) {
    baselines.removeAll { $0.key == baseline.key }
    baselines.append(baseline)
  }
  public mutating func remember(_ conflict: TrainingConflict) {
    conflicts.removeAll { $0.id == conflict.id }
    conflicts.append(conflict)
  }
  /// A restored server database needs reconciliation of known deletions as well as live records.
  public mutating func resetServerRevisions() {
    cursor = 0
    conflicts = []
    baselines = baselines.map {
      TrainingBaseline(key: $0.key, revision: 0, fingerprint: $0.fingerprint)
    }
  }
}

/// Decisions are made against a fresh local value after the network await, never an old snapshot.
public enum TrainingMergeDecision: Equatable, Sendable {
  case ignore
  case acknowledge
  case apply
  case conflict
}

public enum TrainingSyncPlanner {
  public static func decision(
    local: TrainingValue?, baseline: TrainingBaseline?, remote: TrainingChange,
    fingerprint: (TrainingValue) throws -> String
  ) throws -> TrainingMergeDecision {
    if let baseline, baseline.revision >= remote.revision { return .ignore }
    if local == remote.value { return .acknowledge }
    if baseline?.revision == 0 { return .conflict }
    let current = try local.map(fingerprint)
    let dirty = baseline.map { $0.fingerprint != current } ?? (local != nil)
    return dirty ? .conflict : .apply
  }

  public static func pending(
    local: [TrainingValue], state: TrainingSyncState,
    fingerprint: (TrainingValue) throws -> String
  ) throws -> [TrainingMutation] {
    try state.validate()
    guard Set(local.map(\.key)).count == local.count else { throw TrainingSyncError.invalidData }
    let values = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
    let baselines = Dictionary(uniqueKeysWithValues: state.baselines.map { ($0.key, $0) })
    let conflicts = Set(state.conflicts.map(\.id))
    let keys = Set(values.keys).union(baselines.keys).subtracting(conflicts)
    return try keys.sorted(by: ordered).compactMap { key in
      if key.kind == .heartRate && conflicts.contains(TrainingRecordKey(kind: .workout, id: key.id))
      {
        return nil
      }
      let value = values[key]
      let hash = try value.map(fingerprint)
      guard
        baselines[key]?.revision == 0 || baselines[key]?.fingerprint != hash
          || baselines[key] == nil && value != nil
      else {
        return nil
      }
      return try TrainingMutation(
        key: key, baseRevision: baselines[key]?.revision ?? 0, value: value)
    }
  }

  public static func ordered(_ lhs: TrainingRecordKey, _ rhs: TrainingRecordKey) -> Bool {
    let order: [TrainingKind: Int] = [.workout: 0, .template: 1, .bodyWeight: 2, .heartRate: 3]
    let left = order[lhs.kind, default: 0]
    let right = order[rhs.kind, default: 0]
    return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
  }
}
