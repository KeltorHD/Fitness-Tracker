import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
  struct ContentState: Codable, Hashable, Sendable {
    var completedSets: Int
    var totalSets: Int
    var paused: Bool
    var restEndsAt: Date?
  }
  var workoutID: UUID
  var name: String
}
