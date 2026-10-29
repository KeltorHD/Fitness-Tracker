import ActivityKit
import FitSessionCore
import Foundation
import UIKit

@MainActor final class LiveActivityService {
  func startIfNeeded(for workout: Workout) throws {
    guard workout.endedAt == nil, UIApplication.shared.applicationState == .active,
      ActivityAuthorizationInfo().areActivitiesEnabled,
      !Activity<WorkoutActivityAttributes>.activities.contains(where: {
        $0.attributes.workoutID == workout.id && [.active, .stale].contains($0.activityState)
      })
    else { return }
    _ = try Activity.request(
      attributes: WorkoutActivityAttributes(workoutID: workout.id, name: workout.name),
      content: ActivityContent(state: localizedState(for: workout), staleDate: nil),
      pushType: nil)
  }

  func update(for workout: Workout?, allowStart: Bool = true) async throws {
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
    let state = localizedState(for: workout)
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
      try startIfNeeded(for: workout)
    }
  }

  private func localizedState(for workout: Workout) -> WorkoutLiveState {
    var display = workout
    for index in display.exercises.indices {
      display.exercises[index].exercise.name = L10n.exerciseName(display.exercises[index].exercise)
    }
    return WorkoutLiveState(workout: display, languageCode: L10n.language.rawValue)
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
    await activity.update(ActivityContent(state: state, staleDate: nil))
    return true
  }
}
