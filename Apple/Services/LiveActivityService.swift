import ActivityKit
import FitnessTrackerCore
import Foundation
import UIKit

@MainActor final class LiveActivityService {
  func startIfNeeded(for workout: Workout, heartRate: HeartRateReading? = nil) throws {
    guard workout.endedAt == nil, UIApplication.shared.applicationState == .active,
      ActivityAuthorizationInfo().areActivitiesEnabled,
      !Activity<WorkoutActivityAttributes>.activities.contains(where: {
        $0.attributes.workoutID == workout.id && [.active, .stale].contains($0.activityState)
      })
    else { return }
    let state = localizedState(for: workout, heartRate: heartRate)
    _ = try Activity.request(
      attributes: WorkoutActivityAttributes(workoutID: workout.id, name: workout.name),
      content: ActivityContent(state: state, staleDate: state.heartRateStaleDate),
      pushType: nil)
  }

  func update(
    for workout: Workout?, allowStart: Bool = true, heartRate: HeartRateReading? = nil
  ) async throws {
    // Keep SDK reference objects out of actor crossings; reconciliation uses value snapshots.
    let activities = Activity<WorkoutActivityAttributes>.activities.map {
      (
        id: $0.id, workoutID: $0.attributes.workoutID,
        canUpdate: [.active, .stale].contains($0.activityState)
      )
    }
    for activity in activities
    where activity.workoutID != workout?.id || workout?.endedAt != nil {
      try Task.checkCancellation()
      await Self.endActivity(id: activity.id)
    }
    try Task.checkCancellation()
    guard let workout, workout.endedAt == nil else { return }
    let state = localizedState(for: workout, heartRate: heartRate)
    let matching = activities.filter {
      $0.workoutID == workout.id && $0.canUpdate
    }
    // Reconcile system activities after relaunch; ended/dismissed instances cannot be updated.
    for duplicate in matching.dropFirst() {
      try Task.checkCancellation()
      await Self.endActivity(id: duplicate.id)
    }
    try Task.checkCancellation()
    if let activity = matching.first {
      let updated = await Self.updateActivity(id: activity.id, state: state)
      try Task.checkCancellation()
      if updated { return }
    }
    if allowStart {
      try startIfNeeded(for: workout, heartRate: heartRate)
    }
  }

  private func localizedState(for workout: Workout, heartRate: HeartRateReading?)
    -> WorkoutLiveState
  {
    var display = workout
    for index in display.exercises.indices {
      display.exercises[index].exercise.name = L10n.exerciseName(display.exercises[index].exercise)
    }
    return WorkoutLiveState(
      workout: display, languageCode: L10n.language.rawValue, heartRate: heartRate)
  }

  // @concurrent keeps SDK handles on the generic executor, including with Swift 6.2's
  // NonisolatedNonsendingByDefault. Only Sendable IDs/state cross back to MainActor.
  @concurrent nonisolated private static func endActivity(id: String) async {
    guard !Task.isCancelled else { return }
    guard
      let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id })
    else {
      return
    }
    await activity.end(nil, dismissalPolicy: .immediate)
  }

  @concurrent nonisolated private static func updateActivity(id: String, state: WorkoutLiveState)
    async -> Bool
  {
    guard !Task.isCancelled,
      let activity = Activity<WorkoutActivityAttributes>.activities.first(where: {
        $0.id == id && [.active, .stale].contains($0.activityState)
      })
    else { return false }
    await activity.update(ActivityContent(state: state, staleDate: state.heartRateStaleDate))
    return true
  }
}
