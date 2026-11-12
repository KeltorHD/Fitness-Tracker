import ActivityKit
import FitLifeCore
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
  typealias ContentState = WorkoutLiveState
  var workoutID: UUID
  var name: String

  var workoutURL: URL? { URL(string: "fitlife://workout?id=\(workoutID.uuidString)") }
}
