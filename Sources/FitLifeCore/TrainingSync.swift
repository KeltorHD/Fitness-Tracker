import Foundation

public enum TrainingKind: String, Codable, CaseIterable, Sendable {
  case workout, template, bodyWeight, heartRate, foodEntry, waterEntry, supplementEntry,
    supplementPlan, nutritionProfile
  public var isNutrition: Bool {
    switch self {
    case .foodEntry, .waterEntry, .supplementEntry, .supplementPlan, .nutritionProfile: true
    default: false
    }
  }
}

public struct TrainingRecordKey: Codable, Hashable, Sendable {
  public let kind: TrainingKind
  public let id: UUID
  public init(kind: TrainingKind, id: UUID) {
    self.kind = kind
    self.id = id
  }
}

/// A single typed aggregate; server synchronization never changes archive v4 or its contents.
public enum TrainingValue: Codable, Equatable, Sendable {
  case workout(Workout)
  case template(WorkoutTemplate)
  case bodyWeight(BodyWeightEntry)
  case heartRate(HeartRateRecording)
  case foodEntry(FoodEntry)
  case waterEntry(WaterEntry)
  case supplementEntry(SupplementEntry)
  case supplementPlan(SupplementPlan)
  case nutritionProfile(NutritionProfile)

  public var key: TrainingRecordKey {
    switch self {
    case .workout(let value): TrainingRecordKey(kind: .workout, id: value.id)
    case .template(let value): TrainingRecordKey(kind: .template, id: value.id)
    case .bodyWeight(let value): TrainingRecordKey(kind: .bodyWeight, id: value.id)
    case .foodEntry(let value): TrainingRecordKey(kind: .foodEntry, id: value.id)
    case .waterEntry(let value): TrainingRecordKey(kind: .waterEntry, id: value.id)
    case .supplementEntry(let value): TrainingRecordKey(kind: .supplementEntry, id: value.id)
    case .supplementPlan(let value): TrainingRecordKey(kind: .supplementPlan, id: value.id)
    case .nutritionProfile(let value): TrainingRecordKey(kind: .nutritionProfile, id: value.id)
    case .heartRate(let value): TrainingRecordKey(kind: .heartRate, id: value.workoutID)
    }
  }

  public var title: String? {
    switch self {
    case .workout(let value): value.name
    case .template(let value): value.name
    case .foodEntry: nil
    case .waterEntry: nil
    case .supplementEntry: nil
    case .supplementPlan: nil
    case .nutritionProfile: nil
    case .bodyWeight, .heartRate: nil
    }
  }

  public func validate() throws {
    switch self {
    case .workout(let value): try Validation.workout(value)
    case .template(let value): try Validation.template(value)
    case .bodyWeight(let value): try Validation.bodyWeightEntry(value)
    case .foodEntry(let value): try value.validate()
    case .waterEntry(let value): try value.validate()
    case .supplementEntry(let value): try value.validate()
    case .supplementPlan(let value): try value.validate()
    case .nutritionProfile(let value): try value.validate()
    case .heartRate(let value): try value.validate()
    }
  }

  /// Sorted selection sets keep local fingerprints stable after decoding and across launches.
  public func canonicalData() throws -> Data { try TrainingCoding.encoder().encode(self) }

  private enum Keys: String, CodingKey { case kind, value }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    self = try Self.decodePayload(
      kind: container.decode(TrainingKind.self, forKey: .kind),
      from: container.superDecoder(forKey: .value))
    try validate()
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(key.kind, forKey: .kind)
    try encodePayload(to: container.superEncoder(forKey: .value))
  }

  static func decodePayload(kind: TrainingKind, from decoder: any Decoder) throws -> Self {
    switch kind {
    case .workout: .workout(try Workout(from: decoder))
    case .template: .template(try WorkoutTemplate(from: decoder))
    case .bodyWeight: .bodyWeight(try BodyWeightEntry(from: decoder))
    case .foodEntry: .foodEntry(try FoodEntry(from: decoder))
    case .waterEntry: .waterEntry(try WaterEntry(from: decoder))
    case .supplementEntry: .supplementEntry(try SupplementEntry(from: decoder))
    case .supplementPlan: .supplementPlan(try SupplementPlan(from: decoder))
    case .nutritionProfile: .nutritionProfile(try NutritionProfile(from: decoder))
    case .heartRate: .heartRate(try HeartRateRecording(from: decoder))
    }
  }

  func encodePayload(to encoder: any Encoder) throws {
    switch self {
    case .workout(let value): try value.encode(to: encoder)
    case .bodyWeight(let value): try value.encode(to: encoder)
    case .foodEntry(let value): try value.encode(to: encoder)
    case .waterEntry(let value): try value.encode(to: encoder)
    case .supplementEntry(let value): try value.encode(to: encoder)
    case .supplementPlan(let value): try value.encode(to: encoder)
    case .nutritionProfile(let value): try value.encode(to: encoder)
    case .heartRate(let value): try value.encode(to: encoder)
    case .template(let value):
      var container = encoder.container(keyedBy: TemplateKeys.self)
      try container.encode(value.id, forKey: .id)
      try container.encode(value.name, forKey: .name)
      try container.encode(value.exercises, forKey: .exercises)
      try container.encode(value.restSeconds, forKey: .restSeconds)
      try container.encode(
        value.muscleGroups.sorted { $0.rawValue < $1.rawValue }, forKey: .muscleGroups)
      try container.encode(value.muscles.sorted { $0.rawValue < $1.rawValue }, forKey: .muscles)
      try container.encode(
        value.muscleRegions.sorted { $0.rawValue < $1.rawValue }, forKey: .muscleRegions)
      try container.encode(
        value.preferredWeekdays.sorted { $0.rawValue < $1.rawValue }, forKey: .preferredWeekdays)
      try container.encode(value.variations, forKey: .variations)
      try container.encodeIfPresent(value.baseVariationName, forKey: .baseVariationName)
    }
  }
  private enum TemplateKeys: String, CodingKey {
    case id, name, exercises, restSeconds, muscleGroups, muscles, muscleRegions, preferredWeekdays
    case variations, baseVariationName
  }
}

public struct TrainingChange: Codable, Equatable, Sendable {
  public let key: TrainingRecordKey
  public let revision: Int64
  public let value: TrainingValue?
  public var deleted: Bool { value == nil }
  public init(key: TrainingRecordKey, revision: Int64, value: TrainingValue?) throws {
    guard revision > 0, value == nil || value?.key == key,
      key.kind != .nutritionProfile || key.id == NutritionProfile.recordID
    else {
      throw TrainingSyncError.invalidData
    }
    try value?.validate()
    self.key = key
    self.revision = revision
    self.value = value
  }
  private enum Keys: String, CodingKey { case kind, id, revision, deleted, value }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    let key = TrainingRecordKey(
      kind: try container.decode(TrainingKind.self, forKey: .kind),
      id: try container.decode(UUID.self, forKey: .id))
    let deleted = try container.decode(Bool.self, forKey: .deleted)
    let value: TrainingValue?
    if deleted {
      guard try container.decodeNil(forKey: .value) else { throw TrainingSyncError.invalidData }
      value = nil
    } else {
      value = try TrainingValue.decodePayload(
        kind: key.kind, from: container.superDecoder(forKey: .value))
    }
    try self.init(key: key, revision: container.decode(Int64.self, forKey: .revision), value: value)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(key.kind, forKey: .kind)
    try container.encode(key.id, forKey: .id)
    try container.encode(revision, forKey: .revision)
    try container.encode(deleted, forKey: .deleted)
    if let value {
      try value.encodePayload(to: container.superEncoder(forKey: .value))
    } else {
      try container.encodeNil(forKey: .value)
    }
  }
}

public struct TrainingMutation: Encodable, Equatable, Sendable {
  public let key: TrainingRecordKey
  public let baseRevision: Int64
  public let value: TrainingValue?
  public init(key: TrainingRecordKey, baseRevision: Int64, value: TrainingValue?) throws {
    guard baseRevision >= 0, value == nil || value?.key == key,
      key.kind != .nutritionProfile || key.id == NutritionProfile.recordID
    else {
      throw TrainingSyncError.invalidData
    }
    try value?.validate()
    self.key = key
    self.baseRevision = baseRevision
    self.value = value
  }
  private enum Keys: String, CodingKey { case kind, id, baseRevision, deleted, value }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(key.kind, forKey: .kind)
    try container.encode(key.id, forKey: .id)
    try container.encode(baseRevision, forKey: .baseRevision)
    try container.encode(value == nil, forKey: .deleted)
    if let value {
      try value.encodePayload(to: container.superEncoder(forKey: .value))
    } else {
      try container.encodeNil(forKey: .value)
    }
  }
}

public struct TrainingPage: Decodable, Sendable {
  public let changes: [TrainingChange]
  public let cursor: Int64
  public let hasMore: Bool
  public init(changes: [TrainingChange], cursor: Int64, hasMore: Bool) {
    self.changes = changes
    self.cursor = cursor
    self.hasMore = hasMore
  }
  public func validate(after: Int64) throws {
    guard changes.count <= 100, cursor >= after,
      Set(changes.map(\.key)).count == changes.count,
      !hasMore || !changes.isEmpty
    else { throw TrainingSyncError.invalidData }
    var previous = after
    for change in changes {
      guard change.revision > previous else { throw TrainingSyncError.invalidData }
      previous = change.revision
    }
    guard cursor == previous else { throw TrainingSyncError.invalidData }
  }
}

public struct TrainingSnapshot: Sendable {
  public let values: [TrainingValue]
  public init(
    workouts: [Workout], templates: [WorkoutTemplate], bodyWeights: [BodyWeightEntry],
    heartRate: [HeartRateRecording], nutrition: NutritionSnapshot = NutritionSnapshot()
  ) throws {
    values =
      workouts.map(TrainingValue.workout) + templates.map(TrainingValue.template)
      + bodyWeights.map(TrainingValue.bodyWeight) + heartRate.map(TrainingValue.heartRate)
      + nutrition.values
    guard Set(values.map(\.key)).count == values.count,
      Set(heartRate.map(\.workoutID)).isSubset(of: Set(workouts.map(\.id)))
    else { throw TrainingSyncError.invalidData }
    for value in values { try value.validate() }
  }
}

public enum TrainingSyncError: Error, Equatable, Sendable {
  case invalidData, accountMismatch, activeWorkout, unsupportedStore
}

public struct TrainingAccountSelection: Codable, Equatable, Sendable {
  public var firstAccountID: String?
  public var currentAccountID: String?
  public init(firstAccountID: String? = nil, currentAccountID: String? = nil) {
    self.firstAccountID = firstAccountID
    self.currentAccountID = currentAccountID
  }
  public func validate() throws {
    guard (firstAccountID == nil) == (currentAccountID == nil) else {
      throw TrainingSyncError.invalidData
    }
    for scope in [firstAccountID, currentAccountID].compactMap({ $0 }) {
      guard !scope.isEmpty, scope.count <= 256,
        scope.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
      else { throw TrainingSyncError.invalidData }
    }
  }
}

/// Account journals share neither training records nor automatic upload ownership.
@MainActor public protocol TrainingAccountRepository: WorkoutRepository {
  var trainingAccountSelection: TrainingAccountSelection { get }
  func activateTrainingAccount(_ namespace: String) throws
  func applyTrainingChanges(_ changes: [TrainingChange]) throws
}

public struct TrainingJournalSnapshot: Equatable, Sendable {
  public var workouts: [Workout]
  public var templates: [WorkoutTemplate]
  public var bodyWeights: [BodyWeightEntry]
  public init(workouts: [Workout], templates: [WorkoutTemplate], bodyWeights: [BodyWeightEntry]) {
    self.workouts = workouts
    self.templates = templates
    self.bodyWeights = bodyWeights
  }
  public func applying(_ changes: [TrainingChange]) throws -> TrainingJournalSnapshot {
    guard Set(changes.map(\.key)).count == changes.count,
      Set(workouts.map(\.id)).count == workouts.count,
      Set(templates.map(\.id)).count == templates.count,
      Set(bodyWeights.map(\.id)).count == bodyWeights.count
    else { throw TrainingSyncError.invalidData }
    var workouts = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
    var templates = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
    var weights = Dictionary(uniqueKeysWithValues: bodyWeights.map { ($0.id, $0) })
    for change in changes {
      try change.value?.validate()
      switch (change.key.kind, change.value) {
      case (.workout, .workout(let value)): workouts[change.key.id] = value
      case (.template, .template(let value)): templates[change.key.id] = value
      case (.bodyWeight, .bodyWeight(let value)): weights[change.key.id] = value
      case (.workout, nil): workouts[change.key.id] = nil
      case (.template, nil): templates[change.key.id] = nil
      case (.bodyWeight, nil): weights[change.key.id] = nil
      case (.foodEntry, _), (.waterEntry, _), (.supplementEntry, _),
        (.supplementPlan, _), (.nutritionProfile, _):
        break
      default: throw TrainingSyncError.invalidData
      }
    }
    guard workouts.values.filter({ [.active, .paused].contains($0.status) }).count <= 1 else {
      throw TrainingSyncError.activeWorkout
    }
    return TrainingJournalSnapshot(
      workouts: workouts.values.sorted { $0.startedAt > $1.startedAt },
      templates: templates.values.sorted { $0.name < $1.name },
      bodyWeights: weights.values.sorted { $0.measuredAt > $1.measuredAt })
  }
}

public enum TrainingCoding {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }
}
