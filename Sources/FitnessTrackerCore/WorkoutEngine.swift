import Foundation

/// Anchors are workout row IDs, so repeated occurrences of the same exercise remain distinct.
public enum WorkoutExerciseInsertion: Equatable, Sendable {
  case end
  case before(UUID)
  case after(UUID)
}

/// Independently entered numeric values; nil leaves the corresponding target unchanged.
public struct WorkoutSetInputValues: Equatable, Sendable {
  public let repetitions: Int?
  public let weightKG: Double?

  public init(repetitions: Int? = nil, weightKG: Double? = nil) {
    self.repetitions = repetitions
    self.weightKG = weightKG
  }
}

/// Value-based state machine. Callers persist a new value only after a successful mutation.
public enum WorkoutEngine {
  /// Saves pending input without marking targets complete or changing rest and selection.
  public static func updatePendingValues(
    _ values: [UUID: WorkoutSetInputValues], in workout: inout Workout
  ) throws {
    guard [.active, .paused].contains(workout.status) else { throw TrainingError.invalidState }
    var candidate = workout
    var remaining = Set(values.keys)
    for row in candidate.exercises.indices {
      for index in candidate.exercises[row].sets.indices {
        var set = candidate.exercises[row].sets[index]
        if let input = values[set.id] {
          guard set.completedAt == nil else { throw TrainingError.invalidState }
          if let weight = input.weightKG { set.weightKG = weight }
          if let repetitions = input.repetitions { set.repetitions = repetitions }
          remaining.remove(set.id)
        }
        if var stages = set.dropStages {
          for stage in stages.indices {
            guard let input = values[stages[stage].id] else { continue }
            guard stages[stage].completedAt == nil else { throw TrainingError.invalidState }
            if let weight = input.weightKG { stages[stage].weightKG = weight }
            if let repetitions = input.repetitions { stages[stage].repetitions = repetitions }
            remaining.remove(stages[stage].id)
          }
          set.dropStages = stages
        }
        candidate.exercises[row].sets[index] = set
      }
    }
    guard remaining.isEmpty else { throw TrainingError.missingSet }
    try Validation.workout(candidate)
    workout = candidate
  }
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
    workout.restEndsAt = restDeadline(in: workout, exerciseID: exerciseID, setIndex: s)
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
    var groupIDs: [UUID: UUID] = [:]
    var exercises = original.exercises.compactMap { item -> WorkoutExercise? in
      let completed = item.sets.filter { $0.completedAt != nil }
      guard !completed.isEmpty else { return nil }
      return WorkoutExercise(
        exercise: item.exercise,
        sets: completed.map { $0.freshCopy(performedOnly: true) },
        supersetID: item.supersetID.map { id in
          if let existing = groupIDs[id] { return existing }
          let new = UUID()
          groupIDs[id] = new
          return new
        })
    }
    normalizeSupersets(in: &exercises)
    return Workout(
      name: original.name, startedAt: date, exercises: exercises, restSeconds: original.restSeconds)
  }

  public static func makeTemplate(from workout: Workout) throws -> WorkoutTemplate {
    try Validation.workout(workout)
    guard workout.status == .completed else { throw TrainingError.invalidState }
    var groupIDs: [UUID: UUID] = [:]
    let exercises = workout.exercises.compactMap { item -> TemplateExercise? in
      let completed = item.sets.filter { $0.completedAt != nil }
      guard let first = completed.first else { return nil }
      return TemplateExercise(
        exercise: item.exercise, setCount: completed.count, repetitions: first.repetitions,
        weightKG: first.weightKG, loadMultiplier: first.loadMultiplier,
        plannedSets: completed.map { $0.freshCopy(performedOnly: true) },
        supersetID: item.supersetID.map { id in
          if let existing = groupIDs[id] { return existing }
          let new = UUID()
          groupIDs[id] = new
          return new
        })
    }
    let template = WorkoutTemplate(
      name: workout.name, exercises: TemplateExercise.normalizingSupersets(exercises),
      restSeconds: workout.restSeconds)
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
      if let group = workout.groupContaining(exerciseID: id), group.isSuperset,
        let first = workout.exercises.firstIndex(where: { $0.id == group.id }),
        let last = group.exercises.last,
        let end = workout.exercises.firstIndex(where: { $0.id == last.id })
      {
        index = position == .before(id) ? first : end + 1
      } else {
        index = position == .before(id) ? anchor : anchor + 1
      }
    }
    workout.exercises.insert(
      WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)]), at: index)
  }

  /// Adds fresh template rows without replacing recorded work or session-wide settings.
  public static func addTemplates(
    _ templates: [WorkoutTemplate], to workout: inout Workout, prefillTargets: Bool = true
  ) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    let additions = try WorkoutTemplate.start(
      combining: templates, at: workout.startedAt, prefillTargets: prefillTargets)
    var candidate = workout
    candidate.exercises.append(contentsOf: additions.exercises)
    try Validation.workout(candidate)
    workout = candidate
  }

  /// Replaces an unused row in place. Recorded work remains attributed to its original exercise;
  /// in that case a fresh replacement row is inserted immediately after it.
  @discardableResult
  public static func replaceExercise(id: UUID, with exercise: Exercise, in workout: inout Workout)
    throws -> UUID
  {
    guard workout.status == .active else { throw TrainingError.invalidState }
    try Validation.name(exercise.name)
    guard let index = workout.exercises.firstIndex(where: { $0.id == id }) else {
      throw TrainingError.missingExercise
    }
    let original = workout.exercises[index]
    if original.exercise.id == exercise.id { return original.id }
    var candidate = workout
    let hasRecordedWork = original.sets.contains { !$0.performedStages.isEmpty }
    let replacement = WorkoutExercise(
      id: hasRecordedWork ? UUID() : original.id, exercise: exercise,
      sets: [WorkoutSet(repetitions: 0)], supersetID: original.supersetID)
    if hasRecordedWork {
      candidate.exercises.insert(replacement, at: index + 1)
    } else {
      candidate.exercises[index] = replacement
    }
    reconcileRest(in: &candidate)
    try Validation.workout(candidate)
    workout = candidate
    return replacement.id
  }

  /// Reorders workout rows without changing exercise, set or completion identities.
  /// A stale order that omits or introduces rows is rejected before mutation.
  public static func reorderExercises(_ rowIDs: [UUID], in workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard Set(rowIDs).count == rowIDs.count else { throw TrainingError.duplicateID }
    guard rowIDs.count == workout.exercises.count,
      Set(rowIDs) == Set(workout.exercises.map(\.id))
    else { throw TrainingError.missingExercise }
    let rows = Dictionary(
      workout.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var candidate = workout
    candidate.exercises = rowIDs.compactMap { rows[$0] }
    try Validation.workout(candidate)
    workout = candidate
  }

  public static func removeExercise(id: UUID, from workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let index = workout.exercises.firstIndex(where: { $0.id == id }) else {
      throw TrainingError.missingExercise
    }
    let removedDeadline = restDeadline(for: workout.exercises[index], seconds: workout.restSeconds)
    workout.exercises.remove(at: index)
    normalizeSupersets(in: &workout.exercises)
    reconcileRest(in: &workout)
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
    let previous = index > 0 ? workout.exercises[i].sets[index - 1] : nil
    workout.exercises[i].sets.insert(
      WorkoutSet(
        repetitions: previous?.repetitions ?? 0, weightKG: previous?.weightKG ?? 0,
        loadMultiplier: previous?.loadMultiplier), at: index)
    if workout.exercises[i].supersetID != nil { reconcileRest(in: &workout) }
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
    let deadline = restDeadline(in: workout, exerciseID: exerciseID, setIndex: index)
    let wasGrouped = workout.exercises[row].supersetID != nil
    workout.exercises[row].sets.remove(at: index)
    if wasGrouped { reconcileRest(in: &workout) }
    if let deadline, workout.restEndsAt == deadline,
      !hasRestDeadline(deadline, in: workout)
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
