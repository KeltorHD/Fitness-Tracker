import ActivityKit
import FitSessionCore
import Foundation

@MainActor final class LiveActivityService {
  func update(for workout: Workout?) async throws {
    let activities = Activity<WorkoutActivityAttributes>.activities
    for activity in activities
    where activity.attributes.workoutID != workout?.id || workout?.endedAt != nil {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    try Task.checkCancellation()
    guard let workout, workout.endedAt == nil else { return }
    let state = WorkoutActivityAttributes.ContentState(
      completedSets: workout.completedSets,
      totalSets: workout.totalSets, paused: workout.status == .paused,
      restEndsAt: workout.restEndsAt)
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600))
    if let activity = activities.first(where: { $0.attributes.workoutID == workout.id }) {
      await activity.update(content)
    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
      _ = try Activity.request(
        attributes: WorkoutActivityAttributes(workoutID: workout.id, name: workout.name),
        content: content, pushType: nil)
    }
  }
}
