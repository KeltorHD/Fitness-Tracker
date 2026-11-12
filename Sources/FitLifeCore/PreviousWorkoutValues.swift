import Foundation

/// Recorded values from one earlier session, addressed by the current session's target IDs.
public struct PreviousWorkoutValues: Equatable, Sendable {
  public let workoutID: UUID
  public let date: Date
  public let stages: [UUID: DropSetStage]
  /// Full recorded structure, used once when a new exercise is added to a session.
  public let recordedSets: [WorkoutSet]

  /// Repeated exercises match by occurrence; warmup and working sets have separate ordinals.
  /// Unperformed historical targets retain their positions and never become suggestions.
  public init?(exerciseRowID: UUID, in workout: Workout, history: [Workout]) {
    guard let rowIndex = workout.exercises.firstIndex(where: { $0.id == exerciseRowID }) else {
      return nil
    }
    let row = workout.exercises[rowIndex]
    let occurrence = workout.exercises[..<rowIndex].filter {
      $0.exercise.id == row.exercise.id
    }.count
    var previous: (workout: Workout, row: WorkoutExercise)?
    for candidate in history {
      guard candidate.id != workout.id, candidate.status == .completed,
        candidate.startedAt < workout.startedAt,
        let endedAt = candidate.endedAt, endedAt <= workout.startedAt
      else { continue }
      if let previous {
        guard
          candidate.startedAt > previous.workout.startedAt
            || (candidate.startedAt == previous.workout.startedAt
              && candidate.id.uuidString < previous.workout.id.uuidString)
        else { continue }
      }
      let rows = candidate.exercises.filter { $0.exercise.id == row.exercise.id }
      guard rows.indices.contains(occurrence),
        rows[occurrence].sets.contains(where: { !$0.performedStages.isEmpty })
      else { continue }
      previous = (candidate, rows[occurrence])
    }
    guard let previous else { return nil }
    let warmups = previous.row.sets.filter(\.isWarmup)
    let working = previous.row.sets.filter { !$0.isWarmup }
    var warmupIndex = 0
    var workingIndex = 0
    var values: [UUID: DropSetStage] = [:]
    for set in row.sets {
      let index = set.isWarmup ? warmupIndex : workingIndex
      if set.isWarmup { warmupIndex += 1 } else { workingIndex += 1 }
      let recorded = set.isWarmup ? warmups : working
      guard recorded.indices.contains(index) else { continue }
      let recordedStages = recorded[index].stages
      for (stageIndex, target) in set.stages.enumerated() {
        guard recordedStages.indices.contains(stageIndex),
          recordedStages[stageIndex].completedAt != nil
        else { continue }
        values[target.id] = recordedStages[stageIndex]
      }
    }
    workoutID = previous.workout.id
    date = previous.workout.startedAt
    stages = values
    recordedSets = previous.row.sets.filter { $0.completedAt != nil }
  }
}

extension WorkoutEngine {
  /// Copies the latest recorded count and values only into newly created, empty exercise rows.
  /// Existing edits, removed sets, completed targets and explicitly repeated sessions stay intact.
  public static func applyPreviousTargets(
    to rowIDs: Set<UUID>, in workout: inout Workout, history: [Workout]
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    var candidate = workout
    for index in candidate.exercises.indices {
      let row = candidate.exercises[index]
      guard rowIDs.contains(row.id),
        row.sets.allSatisfy({
          $0.completedAt == nil && $0.repetitions == 0 && $0.weightKG == 0 && !$0.isDropSet
        }),
        let previous = PreviousWorkoutValues(exerciseRowID: row.id, in: workout, history: history)
      else { continue }
      let plannedWarmups = row.sets.filter(\.isWarmup)
      let plannedWorking = row.sets.filter { !$0.isWarmup }
      var warmupIndex = 0
      var workingIndex = 0
      candidate.exercises[index].sets = previous.recordedSets.map { set in
        var copy = set.freshCopy(performedOnly: true)
        let ordinal = set.isWarmup ? warmupIndex : workingIndex
        let planned = set.isWarmup ? plannedWarmups : plannedWorking
        if set.isWarmup { warmupIndex += 1 } else { workingIndex += 1 }
        // Current plan notes take priority; otherwise retain the previous set's note.
        if planned.indices.contains(ordinal), let note = planned[ordinal].note {
          copy.note = note
        }
        return copy
      }
    }
    try Validation.workout(candidate)
    workout = candidate
  }
}
