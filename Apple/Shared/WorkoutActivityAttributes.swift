import ActivityKit
import FitSessionCore
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
  typealias ContentState = WorkoutLiveState
  var workoutID: UUID
  var name: String

  var workoutURL: URL? { URL(string: "fitsession://workout?id=\(workoutID.uuidString)") }
}
