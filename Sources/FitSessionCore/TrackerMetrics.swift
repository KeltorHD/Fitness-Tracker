import Foundation

public enum TrackerMode: String, CaseIterable, Codable, Sendable {
  case appleHealth, bluetooth
}

public struct HeartRateReading: Codable, Hashable, Sendable, Identifiable {
  public let date: Date
  public let beatsPerMinute: Double
  public var id: Date { date }
  public init(date: Date, beatsPerMinute: Double) {
    self.date = date
    self.beatsPerMinute = beatsPerMinute
  }
  public var isValid: Bool {
    date.timeIntervalSince1970.isFinite && beatsPerMinute.isFinite
      && (1...300).contains(beatsPerMinute)
  }
  public func isFresh(at date: Date, maximumAge: TimeInterval = 15) -> Bool {
    guard maximumAge.isFinite, maximumAge >= 0 else { return false }
    return isValid && (0...maximumAge).contains(date.timeIntervalSince(self.date))
  }
}

/// Stored separately from Workout: personal sensor data must not enter CloudKit or archives.
public struct HeartRateRecording: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let workoutID: UUID
  public let mode: TrackerMode
  public private(set) var readings: [HeartRateReading]
  public static let maximumReadings = 10_000
  public init(workoutID: UUID, mode: TrackerMode, readings: [HeartRateReading] = []) throws {
    schemaVersion = 1
    self.workoutID = workoutID
    self.mode = mode
    self.readings = readings
    try validate()
  }
  public var average: Double? {
    readings.isEmpty ? nil : readings.reduce(0) { $0 + $1.beatsPerMinute } / Double(readings.count)
  }
  public var maximum: Double? { readings.map(\.beatsPerMinute).max() }

  public func validate() throws {
    guard schemaVersion == 1, readings.count <= Self.maximumReadings else {
      throw TrackerDataError.invalidRecording
    }
    var previous = Date.distantPast
    for reading in readings {
      guard reading.isValid, reading.date > previous else {
        throw TrackerDataError.invalidRecording
      }
      previous = reading.date
    }
  }

  /// Five-second sampling bounds storage; paused/ended sessions and delayed packets are ignored.
  @discardableResult public mutating func append(_ reading: HeartRateReading, to workout: Workout)
    throws -> Bool
  {
    guard workout.id == workoutID, workout.status == .active,
      reading.isValid, reading.date >= workout.startedAt,
      !workout.pauses.contains(where: { ($0.startedAt...$0.endedAt).contains(reading.date) })
    else { return false }
    if let last = readings.last, reading.date.timeIntervalSince(last.date) < 5 { return false }
    guard readings.count < Self.maximumReadings else { throw TrackerDataError.recordingFull }
    readings.append(reading)
    return true
  }
}

public struct HealthDaySummary: Sendable, Equatable {
  public let day: Date
  public let steps: Int?
  public let activeEnergyKCal: Double?
  public let sleepSeconds: TimeInterval?
  public let latestHeartRate: HeartRateReading?
  public let heartRateSource: String?
  public init(
    day: Date, steps: Int?, activeEnergyKCal: Double?, sleepSeconds: TimeInterval?,
    latestHeartRate: HeartRateReading?, heartRateSource: String?
  ) {
    self.day = day
    self.steps = steps
    self.activeEnergyKCal = activeEnergyKCal
    self.sleepSeconds = sleepSeconds
    self.latestHeartRate = latestHeartRate
    self.heartRateSource = heartRateSource
  }
  public var isEmpty: Bool {
    steps == nil && activeEnergyKCal == nil && sleepSeconds == nil && latestHeartRate == nil
  }
}

public enum TrackerCalculations {
  /// Union intervals from multiple sleep stages/devices without counting overlap twice.
  public static func sleepDuration(_ intervals: [DateInterval], within window: DateInterval)
    -> TimeInterval?
  {
    let clipped = intervals.compactMap { interval -> DateInterval? in
      let start = max(interval.start, window.start)
      let end = min(interval.end, window.end)
      return end > start ? DateInterval(start: start, end: end) : nil
    }.sorted { $0.start < $1.start }
    guard var current = clipped.first else { return nil }
    var total: TimeInterval = 0
    for interval in clipped.dropFirst() {
      if interval.start <= current.end {
        current = DateInterval(start: current.start, end: max(current.end, interval.end))
      } else {
        total += current.duration
        current = interval
      }
    }
    return total + current.duration
  }
}

public enum TrackerDataError: Error, Equatable, Sendable {
  case malformedPacket, invalidRecording, recordingFull
}

public protocol HeartRateRecordingRepository: Sendable {
  func recording(for workoutID: UUID) async throws -> HeartRateRecording?
  func save(_ recording: HeartRateRecording) async throws
  func remove(for workoutID: UUID) async throws
}

@MainActor public protocol HealthMetricsReading {
  func requestReadAuthorization() async throws
  func requestHeartRateAuthorization() async throws
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary
  func heartRate(for workout: Workout) async throws -> HeartRateRecording
}
