import Foundation

extension WorkoutTemplate {
  /// Combines in selection order. Exercise identity, rather than its name or row ID,
  /// determines duplicates; the first occurrence supplies all set targets.
  /// Rest is session-wide, so it comes from the first selected template.
  public static func start(combining templates: [WorkoutTemplate], at date: Date = Date()) throws
    -> Workout
  {
    guard let first = templates.first else { throw TrainingError.emptyWorkout }
    var seen = Set<UUID>()
    var exercises: [WorkoutExercise] = []
    for template in templates {
      // Validate each complete plan, including duplicates, and use the existing fresh-copy rules.
      // Independent templates may share source row/set/stage IDs without sharing exercise identity.
      let workout = try template.start(at: date)
      for row in workout.exercises where seen.insert(row.exercise.id).inserted {
        exercises.append(row)
      }
    }
    let names = templates.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    let name = String(names.joined(separator: " + ").prefix(80))
    return Workout(
      name: name, startedAt: date, exercises: exercises, restSeconds: first.restSeconds)
  }
}
