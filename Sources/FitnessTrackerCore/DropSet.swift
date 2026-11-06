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
      loadMultiplier: loadMultiplier, dropStages: stages.isEmpty ? nil : stages, note: note)
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
    if set.completedAt != nil {
      // A started group may only grow by one pending stage. Recorded work stays immutable.
      let original = set.dropStages ?? []
      guard set.isDropSet, !set.isFullyCompleted,
        repetitions == set.repetitions, weightKG == set.weightKG,
        stages.count == original.count + 1, stages.last?.completedAt == nil
      else { throw TrainingError.invalidState }
      for (old, new) in zip(original, stages) {
        guard old.id == new.id, old.completedAt == new.completedAt,
          old.completedAt == nil || old == new
        else { throw TrainingError.invalidState }
      }
    } else {
      guard stages.allSatisfy({ $0.completedAt == nil }) else { throw TrainingError.invalidState }
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

  public static func removeDropStage(
    in workout: inout Workout, exerciseID: UUID, setID: UUID, stageID: UUID
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }),
      let index = workout.exercises[e].sets[s].dropStages?.firstIndex(where: { $0.id == stageID })
    else { throw TrainingError.missingSet }
    let original = workout.exercises[e].sets[s]
    var updated = original
    updated.dropStages?.remove(at: index)
    if updated.dropStages?.isEmpty == true { updated.dropStages = nil }
    var candidate = workout
    candidate.exercises[e].sets[s] = updated
    try Validation.workout(candidate)
    let oldDeadline = restDeadline(in: workout, exerciseID: exerciseID, setIndex: s)
    let newDeadline = restDeadline(in: candidate, exerciseID: exerciseID, setIndex: s)
    if let oldDeadline, candidate.restEndsAt == oldDeadline {
      let shared = hasRestDeadline(oldDeadline, in: candidate)
      if !shared { candidate.restEndsAt = newDeadline }
    } else if oldDeadline == nil, candidate.restEndsAt == nil {
      candidate.restEndsAt = newDeadline
    }
    workout = candidate
  }

  /// Corrects recorded values during an ongoing session without re-completing the target.
  public static func correctCompletedTarget(
    in workout: inout Workout, exerciseID: UUID, targetID: UUID,
    repetitions: Int, weightKG: Double
  ) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard
      let s = workout.exercises[e].sets.firstIndex(where: {
        $0.stages.contains { $0.id == targetID }
      })
    else { throw TrainingError.missingSet }
    var candidate = workout
    if candidate.exercises[e].sets[s].id == targetID {
      guard candidate.exercises[e].sets[s].completedAt != nil else {
        throw TrainingError.invalidState
      }
      candidate.exercises[e].sets[s].repetitions = repetitions
      candidate.exercises[e].sets[s].weightKG = weightKG
    } else {
      guard
        let d = candidate.exercises[e].sets[s].dropStages?.firstIndex(where: { $0.id == targetID }),
        candidate.exercises[e].sets[s].dropStages?[d].completedAt != nil
      else { throw TrainingError.invalidState }
      candidate.exercises[e].sets[s].dropStages?[d].repetitions = repetitions
      candidate.exercises[e].sets[s].dropStages?[d].weightKG = weightKG
    }
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
    workout.restEndsAt = restDeadline(in: workout, exerciseID: exerciseID, setIndex: s)
  }
}
