import Foundation

/// Associates a historical, non-catalog exercise with a catalog exercise without editing workouts.
public struct ExerciseLink: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let catalogID: UUID

  public init(id: UUID, catalogID: UUID) {
    self.id = id
    self.catalogID = catalogID
  }

  public func validate() throws {
    let empty = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    guard id != empty, id != catalogID, ExerciseLibrary.entry(for: id) == nil,
      ExerciseLibrary.entry(for: catalogID) != nil
    else { throw TrainingSyncError.invalidData }
  }
}

/// Historical exercises and templates are the source of the personal list; no data is duplicated.
public enum PersonalExercises {
  public static func list(workouts: [Workout], templates: [WorkoutTemplate]) -> [Exercise] {
    var exercises: [UUID: Exercise] = [:]
    let catalog = Set(ExerciseLibrary.entries.map(\.id))
    for workout in workouts.sorted(by: {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
    }) {
      for row in workout.exercises where !catalog.contains(row.exercise.id) {
        exercises[row.exercise.id] = row.exercise
      }
    }
    for template in templates {
      let rows = template.exercises + template.variations.flatMap(\.exercises)
      for row in rows where !catalog.contains(row.exercise.id) {
        if exercises[row.exercise.id] == nil { exercises[row.exercise.id] = row.exercise }
      }
    }
    return exercises.values.sorted {
      $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name
    }
  }

  public static func catalogID(for id: UUID, links: [ExerciseLink]) -> UUID {
    links.first(where: { $0.id == id })?.catalogID ?? id
  }
}
