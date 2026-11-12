import Foundation

/// A stable projection of one standalone exercise or adjacent superset members.
public struct WorkoutExerciseGroup: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let supersetID: UUID?
  public let exercises: [WorkoutExercise]

  public var isSuperset: Bool { supersetID != nil && exercises.count > 1 }
  public var roundCount: Int { exercises.map { $0.sets.count }.max() ?? 0 }
  public var completedRounds: Int {
    (0..<roundCount).filter { index in
      exercises.allSatisfy { index >= $0.sets.count || $0.sets[index].isFullyCompleted }
    }.count
  }
  public var isCompleted: Bool {
    !exercises.isEmpty && exercises.allSatisfy { $0.sets.allSatisfy(\.isFullyCompleted) }
  }
  public var nextPendingSet: WorkoutSetLocation? {
    for index in 0..<roundCount {
      for row in exercises where index < row.sets.count && !row.sets[index].isFullyCompleted {
        return WorkoutSetLocation(exerciseID: row.id, setID: row.sets[index].id, setIndex: index)
      }
    }
    return nil
  }
}

public struct WorkoutSetLocation: Equatable, Hashable, Sendable {
  public let exerciseID: UUID
  public let setID: UUID
  public let setIndex: Int
  public var roundIndex: Int { setIndex }
}

extension WorkoutExercise {
  /// Completed-workout editors can deliberately dissolve groups broken by draft row edits.
  public static func normalizingSupersets(_ rows: [WorkoutExercise]) -> [WorkoutExercise] {
    var copy = rows
    WorkoutEngine.normalizeSupersets(in: &copy)
    return copy
  }
}

extension Workout {
  public var exerciseGroups: [WorkoutExerciseGroup] {
    var groups: [WorkoutExerciseGroup] = []
    var index = exercises.startIndex
    while index < exercises.endIndex {
      let row = exercises[index]
      var end = index + 1
      if let id = row.supersetID {
        while end < exercises.endIndex && exercises[end].supersetID == id { end += 1 }
      }
      groups.append(
        WorkoutExerciseGroup(
          id: row.id, supersetID: row.supersetID, exercises: Array(exercises[index..<end])))
      index = end
    }
    return groups
  }

  public func groupContaining(exerciseID: UUID) -> WorkoutExerciseGroup? {
    exerciseGroups.first { $0.exercises.contains { $0.id == exerciseID } }
  }

  public func supersetRows(for exerciseID: UUID) -> [WorkoutExercise] {
    groupContaining(exerciseID: exerciseID)?.exercises ?? []
  }

  public func nextPendingSet(inGroupContaining exerciseID: UUID) -> WorkoutSetLocation? {
    groupContaining(exerciseID: exerciseID)?.nextPendingSet
  }

  /// Shared by the app, Watch and Live Activity so all surfaces follow the same round order.
  public var nextPendingSet: WorkoutSetLocation? {
    exerciseGroups.lazy.compactMap(\.nextPendingSet).first
  }
}

extension WorkoutEngine {
  /// Existing groups touched by the selection are merged intact and placed at the first member.
  @discardableResult
  public static func groupExercises(_ rowIDs: [UUID], in workout: inout Workout) throws -> UUID {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard Set(rowIDs).count == rowIDs.count else { throw TrainingError.duplicateID }
    guard rowIDs.count >= 2 else { throw TrainingError.invalidSuperset }
    let requested = Set(rowIDs)
    guard requested.isSubset(of: Set(workout.exercises.map(\.id))) else {
      throw TrainingError.missingExercise
    }
    let touched = Set(
      workout.exercises.filter { requested.contains($0.id) }.compactMap(\.supersetID))
    let members = workout.exercises.filter {
      requested.contains($0.id) || $0.supersetID.map { touched.contains($0) } == true
    }
    let memberIDs = Set(members.map(\.id))
    guard let first = members.first else { throw TrainingError.invalidSuperset }
    let groupID = UUID()
    let grouped = members.map { row in
      var copy = row
      copy.supersetID = groupID
      return copy
    }
    var candidate = workout
    candidate.exercises = workout.exercises.flatMap { row -> [WorkoutExercise] in
      if row.id == first.id { return grouped }
      return memberIDs.contains(row.id) ? [] : [row]
    }
    reconcileRest(in: &candidate)
    try Validation.workout(candidate)
    workout = candidate
    return groupID
  }

  public static func ungroupExercises(supersetID: UUID, in workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard workout.exercises.contains(where: { $0.supersetID == supersetID }) else {
      throw TrainingError.invalidSuperset
    }
    var candidate = workout
    for index in candidate.exercises.indices
    where candidate.exercises[index].supersetID == supersetID {
      candidate.exercises[index].supersetID = nil
    }
    reconcileRest(in: &candidate)
    try Validation.workout(candidate)
    workout = candidate
  }

  /// Adds one shared round, filling missing member ordinals with fresh blank sets first.
  public static func addSupersetRound(supersetID: UUID, to workout: inout Workout) throws {
    guard workout.status == .active else { throw TrainingError.invalidState }
    guard let group = workout.exerciseGroups.first(where: { $0.supersetID == supersetID }),
      group.isSuperset
    else { throw TrainingError.invalidSuperset }
    try Validation.workout(workout)
    let targetCount = group.roundCount + 1
    guard targetCount <= 30 else { throw TrainingError.invalidSetCount }
    var candidate = workout
    for row in group.exercises {
      for _ in row.sets.count..<targetCount {
        try addSet(exerciseID: row.id, to: &candidate)
      }
    }
    try Validation.workout(candidate)
    workout = candidate
  }

  static func normalizeSupersets(in rows: inout [WorkoutExercise]) {
    let invalid = SupersetStructure.invalidIDs(in: rows.map(\.supersetID))
    for index in rows.indices {
      if let id = rows[index].supersetID, invalid.contains(id) { rows[index].supersetID = nil }
    }
  }

  /// A drop set is one member of a round. Every member must finish before rest begins.
  static func restDeadline(in workout: Workout, exerciseID: UUID, setIndex: Int) -> Date? {
    guard workout.restSeconds > 0,
      let group = workout.groupContaining(exerciseID: exerciseID)
    else { return nil }
    let sets = group.exercises.compactMap { row in
      setIndex < row.sets.count ? row.sets[setIndex] : nil
    }
    guard !sets.isEmpty, sets.allSatisfy(\.isFullyCompleted),
      let latest = sets.flatMap(\.performedStages).compactMap(\.completedAt).max()
    else { return nil }
    return latest.addingTimeInterval(Double(workout.restSeconds))
  }

  static func hasRestDeadline(_ deadline: Date, in workout: Workout) -> Bool {
    workout.exerciseGroups.contains { group in
      (0..<group.roundCount).contains { index in
        restDeadline(in: workout, exerciseID: group.id, setIndex: index) == deadline
      }
    }
  }

  static func reconcileRest(in workout: inout Workout) {
    if let deadline = workout.restEndsAt, !hasRestDeadline(deadline, in: workout) {
      workout.restEndsAt = nil
    }
  }
}

enum SupersetStructure {
  static func invalidIDs(in groupIDs: [UUID?]) -> Set<UUID> {
    var positions: [UUID: [Int]] = [:]
    for (index, id) in groupIDs.enumerated() {
      if let id { positions[id, default: []].append(index) }
    }
    return Set(
      positions.compactMap { id, indices in
        guard let first = indices.first, let last = indices.last,
          indices.count >= 2, last - first + 1 == indices.count
        else { return id }
        return nil
      })
  }
}
