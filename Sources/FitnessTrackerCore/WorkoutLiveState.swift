import Foundation

/// Small, SDK-independent projection for system-rendered Live Activity timers.
public struct WorkoutLiveState: Codable, Hashable, Sendable {
  public let completedSets: Int
  public let totalSets: Int
  public let paused: Bool
  public let timerStart: Date
  public let timerEnd: Date
  public let timerPausedAt: Date?
  public let restStartsAt: Date?
  public let restEndsAt: Date?
  public let nextExerciseName: String?
  public let nextSetNumber: Int?
  public let languageCode: String?
  public let nextDropStageNumber: Int?
  public let nextDropStageCount: Int?

  public init(workout: Workout, at date: Date = Date(), languageCode: String? = nil) {
    self.languageCode = languageCode
    completedSets = workout.fullyCompletedSets
    totalSets = workout.totalSets
    paused = workout.status == .paused
    // Moving the anchor forward by accumulated pauses makes a system count-up timer
    // match active duration, without a per-second task in the app process.
    timerStart = workout.startedAt.addingTimeInterval(workout.pausedSeconds)
    timerEnd = max(timerStart, workout.startedAt.addingTimeInterval(8 * 3600))
    timerPausedAt = workout.pausedAt ?? workout.endedAt
    if workout.status == .active, let end = workout.restEndsAt, end > date {
      restStartsAt = end.addingTimeInterval(-Double(workout.restSeconds))
      restEndsAt = end
    } else {
      restStartsAt = nil
      restEndsAt = nil
    }
    let exercise = workout.exercises.first { $0.sets.contains { !$0.isFullyCompleted } }
    nextExerciseName = exercise.map { String($0.exercise.name.prefix(80)) }
    nextSetNumber = exercise?.sets.firstIndex { !$0.isFullyCompleted }.map { $0 + 1 }
    if let set = exercise?.sets.first(where: { !$0.isFullyCompleted }), set.isDropSet {
      nextDropStageNumber = set.stages.firstIndex { $0.completedAt == nil }.map { $0 + 1 }
      nextDropStageCount = set.stages.count
    } else {
      nextDropStageNumber = nil
      nextDropStageCount = nil
    }
  }

  public var progress: Double {
    totalSets > 0 ? min(1, Double(completedSets) / Double(totalSets)) : 0
  }
}

public enum WorkoutLiveAction: Equatable, Sendable {
  case pause
  case resume
  /// A delayed tap must not clear a different set's newer rest interval.
  case skipRest(expectedEnd: Date)

  /// Explicit desired states make repeated system deliveries idempotent.
  @discardableResult public func apply(
    to workout: inout Workout, expectedWorkoutID: UUID, at date: Date = Date()
  ) throws -> Bool {
    guard workout.id == expectedWorkoutID, [.active, .paused].contains(workout.status) else {
      throw TrainingError.invalidState
    }
    switch self {
    case .pause:
      guard workout.status != .paused else { return false }
      try WorkoutEngine.pause(&workout, at: date)
    case .resume:
      guard workout.status != .active else { return false }
      try WorkoutEngine.resume(&workout, at: date)
    case .skipRest(let expectedEnd):
      guard workout.status == .active, let end = workout.restEndsAt,
        end == expectedEnd
      else { return false }
      workout.restEndsAt = nil
    }
    return true
  }
}
