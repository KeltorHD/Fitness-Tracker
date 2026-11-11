import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func watchHeartRateEventsRequireCurrentValidMeasurements() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let id = UUID()
  func event(_ reading: HeartRateReading?, date: Date, state: WatchHeartRateEvent.State = .running)
    -> WatchHeartRateEvent
  {
    WatchHeartRateEvent(sessionID: id, sequence: 1, state: state, date: date, reading: reading)
  }
  let valid = HeartRateReading(date: now, beatsPerMinute: 90)
  #expect(event(valid, date: now).isRecent(at: now))
  #expect(!event(valid, date: now.addingTimeInterval(-16)).isRecent(at: now))
  #expect(!event(valid, date: now.addingTimeInterval(6)).isRecent(at: now))
  #expect(!event(valid, date: now, state: .paused).isRecent(at: now))
  #expect(
    !event(HeartRateReading(date: now.addingTimeInterval(-20), beatsPerMinute: 90), date: now)
      .isRecent(at: now))
  #expect(!event(HeartRateReading(date: now, beatsPerMinute: .nan), date: now).isRecent(at: now))
  #expect(event(nil, date: now, state: .stopped).isRecent(at: now))
}
