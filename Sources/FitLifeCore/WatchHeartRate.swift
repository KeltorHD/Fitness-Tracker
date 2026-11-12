import Foundation

/// Live messages only: heart-rate events must never be queued as application context or user info.
public struct WatchHeartRateCommand: Codable, Equatable, Sendable {
  public enum Action: String, Codable, Sendable { case start, pause, resume, stop }
  public let sessionID: UUID
  public let sequence: UInt64
  public let action: Action
  public let date: Date
  public init(sessionID: UUID, sequence: UInt64, action: Action, date: Date) {
    self.sessionID = sessionID
    self.sequence = sequence
    self.action = action
    self.date = date
  }
  public func isRecent(at now: Date) -> Bool {
    sequence > 0 && date.timeIntervalSince1970.isFinite
      && (-15...60).contains(now.timeIntervalSince(date))
  }
}

public struct WatchHeartRateEvent: Codable, Equatable, Sendable {
  public enum State: String, Codable, Sendable { case starting, running, paused, stopped, failed }
  public let sessionID: UUID
  public let sequence: UInt64
  public let state: State
  public let date: Date
  public let reading: HeartRateReading?
  public init(
    sessionID: UUID, sequence: UInt64, state: State, date: Date, reading: HeartRateReading? = nil
  ) {
    self.sessionID = sessionID
    self.sequence = sequence
    self.state = state
    self.date = date
    self.reading = reading
  }
  public func isRecent(at now: Date) -> Bool {
    guard sequence > 0, date.timeIntervalSince1970.isFinite,
      (-5...15).contains(now.timeIntervalSince(date))
    else { return false }
    guard let reading else { return true }
    return state == .running && reading.isFresh(at: now)
  }
}
