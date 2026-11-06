/// Completion counts every base set and drop stage, including warmups.
/// Reaching full progress never changes the session's saved lifecycle status.
public struct WorkoutCompletionProgress: Equatable, Sendable {
  public let completed: Int
  public let total: Int
  public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
  public var isComplete: Bool { total > 0 && completed == total }

  public init() {
    completed = 0
    total = 0
  }

  public init(workout: Workout) {
    self.init(exercises: workout.exercises)
  }

  public init(exercise: WorkoutExercise) {
    self.init(exercises: [exercise])
  }

  public init(group: WorkoutExerciseGroup) {
    self.init(exercises: group.exercises)
  }

  private init(exercises: [WorkoutExercise]) {
    var completed = 0
    var total = 0
    for exercise in exercises {
      for set in exercise.sets {
        for stage in set.stages {
          total += 1
          if stage.completedAt != nil { completed += 1 }
        }
      }
    }
    self.completed = completed
    self.total = total
  }
}
