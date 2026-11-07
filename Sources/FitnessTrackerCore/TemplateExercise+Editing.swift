import Foundation

extension TemplateExercise {
  /// Replacing an editor row keeps its planned count/group, never another exercise's targets.
  public func replacing(with exercise: Exercise) -> Self {
    Self(exercise: exercise, setCount: setCount, supersetID: supersetID)
  }

  /// Native drag requests move each superset as a whole and retain its internal order.
  public static func reorderedKeepingSupersets(_ rows: [Self], orderedIDs: [UUID]) throws -> [Self]
  {
    guard orderedIDs.count == rows.count, Set(orderedIDs).count == rows.count,
      Set(orderedIDs) == Set(rows.map(\.id))
    else { throw TrainingError.missingExercise }
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    let groups = Dictionary(grouping: rows.filter { $0.supersetID != nil }, by: \.supersetID)
    var visited: Set<UUID> = []
    return orderedIDs.flatMap { id -> [Self] in
      guard visited.insert(id).inserted, let row = byID[id] else { return [] }
      guard let groupID = row.supersetID, let members = groups[groupID] else { return [row] }
      visited.formUnion(members.map(\.id))
      return members
    }
  }

  /// Latest recorded rows, matched by exercise identity and occurrence, for display only.
  public static func previousResults(
    for rows: [Self], history: [Workout], before date: Date = Date()
  ) -> [UUID: WorkoutExercise] {
    let completed = history.filter {
      $0.status == .completed && $0.endedAt.map { $0 <= date } == true
    }.sorted {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt
    }
    var occurrences: [UUID: Int] = [:]
    var result: [UUID: WorkoutExercise] = [:]
    for row in rows {
      let occurrence = occurrences[row.exercise.id, default: 0]
      occurrences[row.exercise.id] = occurrence + 1
      for workout in completed {
        let matches = workout.exercises.filter { $0.exercise.id == row.exercise.id }
        guard matches.indices.contains(occurrence),
          matches[occurrence].sets.contains(where: { !$0.performedStages.isEmpty })
        else { continue }
        result[row.id] = matches[occurrence]
        break
      }
    }
    return result
  }
}
