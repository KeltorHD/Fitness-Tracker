import Foundation

/// Anchors are workout row IDs, so repeated occurrences of the same exercise remain distinct.
public enum WorkoutExerciseInsertion: Equatable, Sendable {
  case end
  case before(UUID)
  case after(UUID)
}

/// Value-based state machine. Callers persist a new value only after a successful mutation.
public enum WorkoutEngine {
  public static func setBodyWeight(_ weightKG: Double?, in workout: inout Workout) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    if let weightKG { try Validation.bodyWeight(weightKG) }
    workout.bodyWeightKG = weightKG
  }
  public static func setWarmup(
    _ warmup: Bool, in workout: inout Workout, exerciseID: UUID, setID: UUID
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let exercise = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let set = workout.exercises[exercise].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    guard workout.exercises[exercise].sets[set].completedAt == nil else {
      throw TrainingError.invalidState
    }
    guard !warmup || !workout.exercises[exercise].sets[set].isDropSet else {
      throw TrainingError.invalidDropSet
    }
    workout.exercises[exercise].sets[set].isWarmup = warmup
  }

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
      item.isFullyCompleted && workout.restSeconds > 0
      ? date.addingTimeInterval(Double(workout.restSeconds)) : nil
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
  static func latestEvent(in workout: Workout) -> Date {
    max(
      workout.startedAt,
      workout.exercises.flatMap(\.sets).flatMap(\.performedStages).compactMap(\.completedAt).max()
        ?? workout.startedAt,
      workout.pauses.last?.endedAt ?? workout.startedAt)
  }
  public static func repeatWorkout(_ original: Workout, at date: Date = Date()) throws -> Workout {
    try Validation.workout(original)
    guard original.status == .completed else { throw TrainingError.invalidState }
    let exercises = original.exercises.compactMap { item -> WorkoutExercise? in
      let completed = item.sets.filter { $0.completedAt != nil }
      guard !completed.isEmpty else { return nil }
      return WorkoutExercise(
        exercise: item.exercise,
        sets: completed.map { $0.freshCopy(performedOnly: true) })
    }
    return Workout(
      name: original.name, startedAt: date, exercises: exercises, restSeconds: original.restSeconds)
  }

  public static func makeTemplate(from workout: Workout) throws -> WorkoutTemplate {
    try Validation.workout(workout)
    guard workout.status == .completed else { throw TrainingError.invalidState }
    let exercises = workout.exercises.compactMap { item -> TemplateExercise? in
      let completed = item.sets.filter { $0.completedAt != nil }
      guard let first = completed.first else { return nil }
      return TemplateExercise(
        exercise: item.exercise, setCount: completed.count, repetitions: first.repetitions,
        weightKG: first.weightKG, loadMultiplier: first.loadMultiplier,
        plannedSets: completed.contains(where: { $0.isDropSet || $0.note != nil })
          ? completed.map { $0.freshCopy(performedOnly: true) } : nil)
    }
    let template = WorkoutTemplate(
      name: workout.name, exercises: exercises, restSeconds: workout.restSeconds)
    try Validation.template(template)
    return template
  }

  public static func addExercise(
    _ exercise: Exercise, to workout: inout Workout, position: WorkoutExerciseInsertion = .end
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    try Validation.name(exercise.name)
    let index: Int
    switch position {
    case .end: index = workout.exercises.endIndex
    case .before(let id), .after(let id):
      guard let anchor = workout.exercises.firstIndex(where: { $0.id == id }) else {
        throw TrainingError.missingExercise
      }
      index = position == .before(id) ? anchor : anchor + 1
    }
    workout.exercises.insert(WorkoutExercise(exercise: exercise), at: index)
  }

  public static func removeExercise(id: UUID, from workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let index = workout.exercises.firstIndex(where: { $0.id == id }) else {
      throw TrainingError.missingExercise
    }
    let removedDeadline = restDeadline(for: workout.exercises[index], seconds: workout.restSeconds)
    workout.exercises.remove(at: index)
    if let removedDeadline, workout.restEndsAt == removedDeadline,
      !workout.exercises.contains(where: {
        restDeadline(for: $0, seconds: workout.restSeconds) == removedDeadline
      })
    {
      workout.restEndsAt = nil
    }
  }

  private static func restDeadline(for row: WorkoutExercise, seconds: Int) -> Date? {
    row.sets.filter(\.isFullyCompleted).compactMap { $0.stages.last?.completedAt }.max()
      .map { $0.addingTimeInterval(Double(seconds)) }
  }

  public static func addSet(
    exerciseID: UUID, to workout: inout Workout, after setID: UUID? = nil
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let i = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard workout.exercises[i].sets.count < 30 else { throw TrainingError.invalidSetCount }
    let index: Int
    if let setID {
      guard let anchor = workout.exercises[i].sets.firstIndex(where: { $0.id == setID }) else {
        throw TrainingError.missingSet
      }
      index = anchor + 1
    } else {
      index = workout.exercises[i].sets.endIndex
    }
    let source = index > 0 ? workout.exercises[i].sets[index - 1] : WorkoutSet()
    var copy = source.freshCopy()
    copy.isWarmup = false
    copy.note = nil
    workout.exercises[i].sets.insert(copy, at: index)
  }

  public static func removeSet(exerciseID: UUID, setID: UUID, from workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let row = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let index = workout.exercises[row].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    guard workout.exercises[row].sets.count > 1 else { throw TrainingError.invalidSetCount }
    let set = workout.exercises[row].sets[index]
    let deadline =
      set.isFullyCompleted
      ? set.stages.last?.completedAt?.addingTimeInterval(Double(workout.restSeconds)) : nil
    workout.exercises[row].sets.remove(at: index)
    if let deadline, workout.restEndsAt == deadline,
      !workout.exercises.contains(where: {
        restDeadline(for: $0, seconds: workout.restSeconds) == deadline
      })
    {
      workout.restEndsAt = nil
    }
  }

  public static func setNote(
    _ note: String, exerciseID: UUID, setID: UUID, in workout: inout Workout
  ) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    guard let row = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else {
      throw TrainingError.missingExercise
    }
    guard let set = workout.exercises[row].sets.firstIndex(where: { $0.id == setID }) else {
      throw TrainingError.missingSet
    }
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= 2000 else { throw TrainingError.invalidSetNote }
    workout.exercises[row].sets[set].note = trimmed.isEmpty ? nil : trimmed
  }
}
