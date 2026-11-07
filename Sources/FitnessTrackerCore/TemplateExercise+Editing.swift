import Foundation

extension TemplateExercise {
  /// Replacing an editor row keeps its planned count/group, never another exercise's targets.
  public func replacing(with exercise: Exercise) -> Self {
    Self(exercise: exercise, setCount: setCount, supersetID: supersetID)
  }

  /// Native drag requests move each superset as a whole and retain its internal order.
  public static func moving(_ rowID: UUID, to destination: Int, in rows: [Self]) throws -> [Self] {
    guard let source = rows.firstIndex(where: { $0.id == rowID }) else {
      throw TrainingError.missingExercise
    }
    guard (0...rows.count).contains(destination) else { throw TrainingError.invalidState }
    guard Set(rows.map(\.id)).count == rows.count else { throw TrainingError.duplicateID }
    guard SupersetStructure.invalidIDs(in: rows.map(\.supersetID)).isEmpty else {
      throw TrainingError.invalidSuperset
    }
    let indices =
      rows[source].supersetID.map { group in
        rows.indices.filter { rows[$0].supersetID == group }
      } ?? [source]
    guard let first = indices.first, let last = indices.last else {
      throw TrainingError.missingExercise
    }
    if (first...(last + 1)).contains(destination) { return rows }
    var target = destination
    if rows.indices.contains(target), let group = rows[target].supersetID {
      let members = rows.indices.filter { rows[$0].supersetID == group }
      if let start = members.first, let end = members.last, target > start {
        target = source < destination ? end + 1 : start
      }
    }
    let movingIDs = Set(indices.map { rows[$0].id })
    let remaining = rows.filter { !movingIDs.contains($0.id) }
    let insertion = target - indices.filter { $0 < target }.count
    return Array(remaining.prefix(insertion)) + indices.map { rows[$0] }
      + Array(remaining.dropFirst(insertion))
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
