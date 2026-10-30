import ActivityKit
import FitnessTrackerCore
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
  typealias ContentState = WorkoutLiveState
  var workoutID: UUID
  var name: String

  var workoutURL: URL? { URL(string: "fitnesstracker://workout?id=\(workoutID.uuidString)") }
}
