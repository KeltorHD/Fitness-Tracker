import Foundation

/// Value-based state machine. Callers persist a new value only after a successful mutation.
public enum WorkoutEngine {
  public static func completeSet(
    in workout: inout Workout, exerciseID: UUID, setID: UUID,
    repetitions: Int, weightKG: Double, at date: Date = Date()
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard date >= latestEvent(in: workout) else { throw TrainingError.invalidDate }
    guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    guard workout.exercises[e].sets[s].completedAt == nil else { throw TrainingError.invalidState }
    var item = workout.exercises[e].sets[s]
    item.repetitions = repetitions
    item.weightKG = weightKG
    try Validation.set(item)
    item.completedAt = date
    workout.exercises[e].sets[s] = item
    workout.restEndsAt =
      workout.restSeconds > 0 ? date.addingTimeInterval(Double(workout.restSeconds)) : nil
  }
  public static func pause(_ workout: inout Workout, at date: Date = Date()) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard date >= latestEvent(in: workout) else { throw TrainingError.invalidDate }
    workout.status = .paused
    workout.pausedAt = date
    workout.restEndsAt = nil
  }
  public static func resume(_ workout: inout Workout, at date: Date = Date()) throws {
    guard workout.status == .paused, let pause = workout.pausedAt else {
      throw TrainingError.invalidState
    }
    guard date >= pause else { throw TrainingError.invalidDate }
    workout.pauses.append(WorkoutPause(startedAt: pause, endedAt: date))
    workout.pausedSeconds += date.timeIntervalSince(pause)
    workout.pausedAt = nil
    workout.status = .active
  }
  public static func finish(_ workout: inout Workout, at date: Date = Date()) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    guard workout.completedSets > 0 else { throw TrainingError.emptyWorkout }
    try end(&workout, status: .completed, at: date)
  }
  public static func cancel(_ workout: inout Workout, at date: Date = Date()) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    try end(&workout, status: .cancelled, at: date)
  }
  private static func end(_ workout: inout Workout, status: WorkoutStatus, at date: Date) throws {
    let latestSet = latestEvent(in: workout)
    guard date >= latestSet, date >= (workout.pausedAt ?? workout.startedAt) else {
      throw TrainingError.invalidDate
    }
    if let pause = workout.pausedAt {
      workout.pauses.append(WorkoutPause(startedAt: pause, endedAt: date))
      workout.pausedSeconds += date.timeIntervalSince(pause)
    }
    workout.pausedAt = nil
    workout.endedAt = date
    workout.status = status
    workout.restEndsAt = nil
  }
  private static func latestEvent(in workout: Workout) -> Date {
    max(
      workout.startedAt,
      workout.exercises.flatMap(\.sets).compactMap(\.completedAt).max() ?? workout.startedAt,
      workout.pauses.last?.endedAt ?? workout.startedAt)
  }
  public static func addExercise(_ exercise: Exercise, to workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    try Validation.name(exercise.name)
    workout.exercises.append(WorkoutExercise(exercise: exercise))
  }
  public static func addSet(exerciseID: UUID, to workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let i = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard workout.exercises[i].sets.count < 30 else { throw TrainingError.invalidSetCount }
    let last = workout.exercises[i].sets.last ?? WorkoutSet()
    workout.exercises[i].sets.append(
      WorkoutSet(repetitions: last.repetitions, weightKG: last.weightKG))
  }
}
