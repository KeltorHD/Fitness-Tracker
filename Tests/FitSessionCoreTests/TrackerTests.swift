import Foundation
import Testing

@testable import FitSessionCore

@Test func heartRatePacketsDecodeWidthsContactEnergyAndRRIntervals() throws {
  let simple = try BluetoothHeartRateMeasurement.decode(Data([0, 72]))
  #expect(simple.beatsPerMinute == 72 && simple.hasSkinContact == nil)
  let extended = try BluetoothHeartRateMeasurement.decode(Data([31, 44, 1, 7, 0, 0, 4, 0, 2]))
  #expect(extended.beatsPerMinute == 300)
  #expect(extended.hasSkinContact == true)
  #expect(extended.energyKJ == 7)
  #expect(extended.rrIntervals == [1, 0.5])
  #expect(try BluetoothHeartRateMeasurement.decode(Data([4, 80])).hasSkinContact == false)
}

@Test(arguments: [
  Data(), Data([0]), Data([1, 80]), Data([8, 80, 0]), Data([16, 80]),
  Data([16, 80, 1]), Data([0, 80, 9]), Data([32, 80]),
])
func truncatedOrMalformedHeartRatePacketsAreRejected(_ data: Data) {
  #expect(throws: TrackerDataError.malformedPacket) {
    try BluetoothHeartRateMeasurement.decode(data)
  }
}

@Test func sensorRecordingExcludesPausesStalePacketsAndOtherWorkouts() throws {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  var workout = Workout(name: "Sensor", startedAt: start)
  var record = try HeartRateRecording(workoutID: workout.id, mode: .bluetooth)
  func reading(_ seconds: Double, _ bpm: Double = 80) -> HeartRateReading {
    HeartRateReading(date: start.addingTimeInterval(seconds), beatsPerMinute: bpm)
  }
  #expect(try !record.append(reading(-1), to: workout))
  #expect(try record.append(reading(0), to: workout))
  #expect(try !record.append(reading(1), to: workout))
  try WorkoutEngine.pause(&workout, at: start.addingTimeInterval(10))
  #expect(try !record.append(reading(15), to: workout))
  try WorkoutEngine.resume(&workout, at: start.addingTimeInterval(20))
  #expect(try !record.append(reading(15), to: workout))
  #expect(try record.append(reading(25, 100), to: workout))
  #expect(try !record.append(reading(30, .nan), to: workout))
  #expect(try !record.append(reading(30, 0), to: workout))
  #expect(try !record.append(reading(30), to: Workout(name: "Other")))
  #expect(record.average == 90 && record.maximum == 100)
  try WorkoutEngine.cancel(&workout, at: start.addingTimeInterval(40))
  #expect(try !record.append(reading(45), to: workout))
  #expect(
    try JSONDecoder().decode(HeartRateRecording.self, from: JSONEncoder().encode(record)) == record)
}

@Test func sensorValidationRejectsCorruptPersistedValuesAndFutureReadings() throws {
  let date = Date(timeIntervalSince1970: 100)
  let reading = HeartRateReading(date: date, beatsPerMinute: 80)
  #expect(reading.isFresh(at: date.addingTimeInterval(15)))
  #expect(!reading.isFresh(at: date.addingTimeInterval(16)))
  #expect(!reading.isFresh(at: date.addingTimeInterval(-1)))
  #expect(throws: TrackerDataError.invalidRecording) {
    try HeartRateRecording(workoutID: UUID(), mode: .appleHealth, readings: [reading, reading])
  }
  #expect(throws: TrackerDataError.invalidRecording) {
    try HeartRateRecording(
      workoutID: UUID(), mode: .bluetooth,
      readings: [HeartRateReading(date: date, beatsPerMinute: .infinity)])
  }
}

@Test func sleepMergesStagesAndDevicesClippingCalendarWindowAcrossDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
  let end = try #require(calendar.date(byAdding: .day, value: 1, to: day))
  #expect(end.timeIntervalSince(day) == 25 * 3600)
  let window = DateInterval(start: day, end: end)
  let intervals = [
    DateInterval(start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(7200)),
    DateInterval(start: day.addingTimeInterval(3600), end: day.addingTimeInterval(10800)),
  ]
  #expect(TrackerCalculations.sleepDuration(intervals, within: window) == 10800)
  #expect(TrackerCalculations.sleepDuration([], within: window) == nil)
}
