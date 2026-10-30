import FitnessTrackerCore
import Foundation

enum LiveHeartRateState: Equatable, Sendable {
  case idle, starting, running, paused, stopped, failed
}

struct LiveHeartRateSnapshot: Sendable {
  var sessionID: UUID?
  var state: LiveHeartRateState = .idle
  var reading: HeartRateReading?
}

/// Public platform services produce value events; the presentation model owns workout identity.
@MainActor protocol LiveHeartRateServing: AnyObject {
  var onChange: (@MainActor (LiveHeartRateSnapshot) -> Void)? { get set }
  func start(sessionID: UUID) async throws
  func pause()
  func resume()
  func stop()
}
