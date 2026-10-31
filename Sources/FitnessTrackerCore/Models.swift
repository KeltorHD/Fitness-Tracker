import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
  case chest, back, legs, shoulders, arms, core, fullBody
}

public enum WeightUnit: String, Codable, CaseIterable, Sendable {
  case kilograms = "kg"
  case pounds = "lb"
  public func kilograms(from value: Double) -> Double {
    self == .kilograms ? value : value * 0.45359237
  }
  public func display(_ kilograms: Double) -> Double {
    self == .kilograms ? kilograms : kilograms / 0.45359237
  }
}

public struct Exercise: Identifiable, Codable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  public var muscle: MuscleGroup
  public var instructions: String
  public init(id: UUID = UUID(), name: String, muscle: MuscleGroup, instructions: String = "") {
    self.id = id
    self.name = name
    self.muscle = muscle
    self.instructions = instructions
  }
}

public struct WorkoutSet: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var repetitions: Int
  /// Always stored in kilograms. Zero represents bodyweight without added load.
  public var weightKG: Double
  public var isWarmup: Bool
  /// Completion of the base stage. Additional stages keep their own timestamps.
  public var completedAt: Date?
  public var loadMultiplier: Int?
  public var dropStages: [DropSetStage]?
  public init(
    id: UUID = UUID(), repetitions: Int = 8, weightKG: Double = 0,
    isWarmup: Bool = false, completedAt: Date? = nil, loadMultiplier: Int? = nil,
    dropStages: [DropSetStage]? = nil
  ) {
    self.id = id
    self.repetitions = repetitions
    self.weightKG = weightKG
    self.isWarmup = isWarmup
    self.completedAt = completedAt
    self.loadMultiplier = loadMultiplier
    self.dropStages = dropStages
  }
  public var isDropSet: Bool { !(dropStages ?? []).isEmpty }
  public var isFullyCompleted: Bool {
    completedAt != nil && (dropStages ?? []).allSatisfy { $0.completedAt != nil }
  }
  public var stages: [DropSetStage] {
    [DropSetStage(id: id, repetitions: repetitions, weightKG: weightKG, completedAt: completedAt)]
      + (dropStages ?? [])
  }
  public var performedStages: [DropSetStage] { stages.filter { $0.completedAt != nil } }
  public var performedRepetitions: Int { performedStages.reduce(0) { $0 + $1.repetitions } }
  public var volume: Double {
    isWarmup
      ? 0
      : performedStages.reduce(0) {
        $0 + $1.weightKG * Double($1.repetitions) * Double(loadMultiplier ?? 1)
      }
  }
}

public struct WorkoutExercise: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var exercise: Exercise
  public var sets: [WorkoutSet]
  public init(id: UUID = UUID(), exercise: Exercise, sets: [WorkoutSet] = [WorkoutSet()]) {
    self.id = id
    self.exercise = exercise
    self.sets = sets
  }
}

public struct TemplateExercise: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var exercise: Exercise
  public var setCount: Int
  public var repetitions: Int
  public var weightKG: Double
  public var loadMultiplier: Int?
  /// Lossless individual targets; nil retains legacy uniform targets.
  public var plannedSets: [WorkoutSet]?
  public init(
    id: UUID = UUID(), exercise: Exercise, setCount: Int = 3,
    repetitions: Int = 8, weightKG: Double = 0, loadMultiplier: Int? = nil,
    plannedSets: [WorkoutSet]? = nil
  ) {
    self.id = id
    self.exercise = exercise
    self.setCount = setCount
    self.repetitions = repetitions
    self.weightKG = weightKG
    self.loadMultiplier = loadMultiplier
    self.plannedSets = plannedSets
  }
}

public struct WorkoutTemplate: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var exercises: [TemplateExercise]
  public var restSeconds: Int
  public var muscleGroups: Set<MuscleGroup>
  public init(
    id: UUID = UUID(), name: String, exercises: [TemplateExercise], restSeconds: Int = 90,
    muscleGroups: Set<MuscleGroup> = []
  ) {
    self.id = id
    self.name = name
    self.exercises = exercises
    self.restSeconds = restSeconds
    self.muscleGroups = muscleGroups
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, exercises, restSeconds, muscleGroups
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    exercises = try container.decode([TemplateExercise].self, forKey: .exercises)
    restSeconds = try container.decode(Int.self, forKey: .restSeconds)
    // Additive migration: existing templates have no preferred muscle filter.
    muscleGroups = try container.decodeIfPresent(Set<MuscleGroup>.self, forKey: .muscleGroups) ?? []
  }

  public func start(at date: Date = Date()) throws -> Workout {
    try Validation.template(self)
    return Workout(
      name: name, startedAt: date,
      exercises: exercises.map { item in
        WorkoutExercise(
          exercise: item.exercise,
          sets: item.plannedSets.map { $0.map { $0.freshCopy() } }
            ?? (0..<item.setCount).map { _ in
              WorkoutSet(
                repetitions: item.repetitions, weightKG: item.weightKG,
                loadMultiplier: item.loadMultiplier)
            })
      }, restSeconds: restSeconds)
  }
}

public enum WorkoutStatus: String, Codable, Sendable { case active, paused, completed, cancelled }

public struct WorkoutPause: Codable, Equatable, Sendable {
  public var startedAt: Date
  public var endedAt: Date
  public init(startedAt: Date, endedAt: Date) {
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
  public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

public struct Workout: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var startedAt: Date
  public var endedAt: Date?
  public var status: WorkoutStatus
  public var exercises: [WorkoutExercise]
  public var restSeconds: Int
  public var restEndsAt: Date?
  public var pausedAt: Date?
  public var pauses: [WorkoutPause]
  public var pausedSeconds: TimeInterval
  public var notes: String
  /// Explicitly recorded body weight for this session. Missing in legacy payloads; never inferred.
  public var bodyWeightKG: Double?
  /// False for imports without an end time. Nil means recorded duration for legacy/native sessions.
  public var durationIsKnown: Bool?
  public init(
    id: UUID = UUID(), name: String, startedAt: Date = Date(),
    exercises: [WorkoutExercise] = [], restSeconds: Int = 90, bodyWeightKG: Double? = nil
  ) {
    self.id = id
    self.name = name
    self.startedAt = startedAt
    self.exercises = exercises
    self.restSeconds = restSeconds
    self.status = .active
    self.pausedSeconds = 0
    self.pauses = []
    self.notes = ""
    self.bodyWeightKG = bodyWeightKG
  }
  public var completedSets: Int { exercises.flatMap(\.sets).filter { $0.completedAt != nil }.count }
  public var fullyCompletedSets: Int { exercises.flatMap(\.sets).filter(\.isFullyCompleted).count }
  public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
  public var volume: Double { exercises.flatMap(\.sets).reduce(0) { $0 + $1.volume } }
  public func duration(at date: Date = Date()) -> TimeInterval {
    max(0, (endedAt ?? pausedAt ?? date).timeIntervalSince(startedAt) - pausedSeconds)
  }
  public func remainingRest(at date: Date = Date()) -> TimeInterval {
    max(0, restEndsAt?.timeIntervalSince(date) ?? 0)
  }
}
