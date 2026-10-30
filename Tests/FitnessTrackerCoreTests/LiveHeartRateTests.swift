import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func legacyHeartRateRecordingsRemainReadableWithoutOrigin() throws {
  let id = UUID()
  let payload = Data(
    "{\"schemaVersion\":1,\"workoutID\":\"\(id)\",\"mode\":\"appleHealth\",\"readings\":[]}".utf8)
  let record = try JSONDecoder().decode(HeartRateRecording.self, from: payload)
  try record.validate()
  #expect(record.workoutID == id && record.origin == nil && !record.isLiveSensorRecording)
}

@Test func liveHealthKitRecordingsPreserveOriginAndExcludePauses() throws {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  var workout = Workout(name: "Live", startedAt: start)
  var record = try HeartRateRecording(
    workoutID: workout.id, mode: .appleHealth, origin: .liveHealthKit)
  #expect(record.isLiveSensorRecording)
  #expect(try record.append(HeartRateReading(date: start, beatsPerMinute: 80), to: workout))
  try WorkoutEngine.pause(&workout, at: start.addingTimeInterval(10))
  try WorkoutEngine.resume(&workout, at: start.addingTimeInterval(20))
  #expect(
    try !record.append(
      HeartRateReading(date: start.addingTimeInterval(15), beatsPerMinute: 90), to: workout))
  #expect(
    try record.append(
      HeartRateReading(date: start.addingTimeInterval(25), beatsPerMinute: 100), to: workout))
  let restored = try JSONDecoder().decode(
    HeartRateRecording.self, from: JSONEncoder().encode(record))
  try restored.validate()
  #expect(restored == record && restored.origin == .liveHealthKit)
  #expect(throws: TrackerDataError.invalidRecording) {
    try HeartRateRecording(workoutID: workout.id, mode: .bluetooth, origin: .liveHealthKit)
  }
}
