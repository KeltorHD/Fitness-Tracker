import Foundation

public struct DropSetStage: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var repetitions: Int
  public var weightKG: Double
  public var completedAt: Date?
  public init(id: UUID = UUID(), repetitions: Int = 8, weightKG: Double, completedAt: Date? = nil) {
    self.id = id
    self.repetitions = repetitions
    self.weightKG = weightKG
    self.completedAt = completedAt
  }
}

extension WorkoutSet {
  /// New identities and no completion dates. Repeating a journal can omit unperformed drops.
  public func freshCopy(performedOnly: Bool = false) -> WorkoutSet {
    let stages = (dropStages ?? []).filter { !performedOnly || $0.completedAt != nil }.map {
      DropSetStage(repetitions: $0.repetitions, weightKG: $0.weightKG)
    }
    return WorkoutSet(
      repetitions: repetitions, weightKG: weightKG, isWarmup: isWarmup,
      loadMultiplier: loadMultiplier, dropStages: stages.isEmpty ? nil : stages)
  }
}

extension WorkoutEngine {
  public static func configureDropSet(
    in workout: inout Workout, exerciseID: UUID, setID: UUID,
    repetitions: Int, weightKG: Double, stages: [DropSetStage]
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    var set = workout.exercises[e].sets[s]
    guard set.completedAt == nil, stages.allSatisfy({ $0.completedAt == nil }) else {
      throw TrainingError.invalidState
    }
    guard !set.isWarmup || stages.isEmpty else { throw TrainingError.invalidDropSet }
    set.repetitions = repetitions
    set.weightKG = weightKG
    set.dropStages = stages.isEmpty ? nil : stages
    try Validation.set(set)
    var candidate = workout
    candidate.exercises[e].sets[s] = set
    try Validation.workout(candidate)
    workout = candidate
  }

  public static func completeDropStage(
    in workout: inout Workout, exerciseID: UUID, setID: UUID, stageID: UUID,
    repetitions: Int, weightKG: Double, dropStages: [DropSetStage]? = nil, at date: Date = Date()
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard date >= latestEvent(in: workout) else { throw TrainingError.invalidDate }
    guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    var set = workout.exercises[e].sets[s]
    if let dropStages {
      let original = set.dropStages ?? []
      guard original.map(\.id) == dropStages.map(\.id) else { throw TrainingError.invalidState }
      for (old, new) in zip(original, dropStages) {
        guard old.completedAt == new.completedAt, old.completedAt == nil || old == new else {
          throw TrainingError.invalidState
        }
      }
      set.dropStages = dropStages
    }
    guard set.completedAt != nil,
      let index = set.dropStages?.firstIndex(where: { $0.completedAt == nil }),
      set.dropStages?[index].id == stageID
    else { throw TrainingError.invalidDropStageOrder }
    set.dropStages?[index].weightKG = weightKG
    set.dropStages?[index].repetitions = repetitions
    set.dropStages?[index].completedAt = date
    try Validation.set(set)
    workout.exercises[e].sets[s] = set
    workout.restEndsAt =
      set.isFullyCompleted && workout.restSeconds > 0
      ? date.addingTimeInterval(Double(workout.restSeconds)) : nil
  }
}
