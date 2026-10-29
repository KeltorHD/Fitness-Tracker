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
      content: ActivityContent(state: WorkoutLiveState(workout: workout), staleDate: nil),
      pushType: nil)
  }

  func update(for workout: Workout?, allowStart: Bool = true) async throws {
    let activities = Activity<WorkoutActivityAttributes>.activities
    for activity in activities
    where activity.attributes.workoutID != workout?.id || workout?.endedAt != nil {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    try Task.checkCancellation()
    guard let workout, workout.endedAt == nil else { return }
    let state = WorkoutLiveState(workout: workout)
    let content = ActivityContent(state: state, staleDate: nil)
    let matching = activities.filter {
      $0.attributes.workoutID == workout.id && [.active, .stale].contains($0.activityState)
    }
    // Reconcile system activities after relaunch; ended/dismissed instances cannot be updated.
    for duplicate in matching.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
    if let activity = matching.first {
      await activity.update(content)
    } else if allowStart {
      try startIfNeeded(for: workout)
    }
  }
}
