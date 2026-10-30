import FitSessionCore
import Foundation
import Observation

struct HeartRateChartPoint: Identifiable {
  let reading: HeartRateReading
  let segment: Int
  var id: Date { reading.date }
}

@MainActor @Observable final class WorkoutHeartRateViewModel {
  private(set) var recording: HeartRateRecording?
  private(set) var points: [HeartRateChartPoint] = []
  private(set) var loading = false
  private(set) var error: String?
  @ObservationIgnored private let tracker: TrackerViewModel
  @ObservationIgnored private var requestID: UUID?
  init(tracker: TrackerViewModel) { self.tracker = tracker }

  func load(_ workout: Workout, importHealth: Bool) async {
    let id = UUID()
    requestID = id
    loading = true
    error = nil
    defer { if requestID == id { loading = false } }
    do {
      let value: HeartRateRecording?
      if importHealth {
        value = try await tracker.importHeartRate(for: workout)
      } else {
        value = try await tracker.recording(for: workout.id)
      }
      try Task.checkCancellation()
      guard requestID == id else { return }
      let readings = (value?.readings ?? []).filter {
        $0.date >= workout.startedAt && $0.date <= (workout.endedAt ?? .now)
      }
      recording = try value.map {
        try HeartRateRecording(workoutID: $0.workoutID, mode: $0.mode, readings: readings)
      }
      var previous: Date?
      var segment = 0
      points = readings.map { reading in
        if let previous,
          reading.date.timeIntervalSince(previous) > 30
            || workout.pauses.contains(where: {
              $0.startedAt >= previous && $0.startedAt <= reading.date
            })
        {
          segment += 1
        }
        previous = reading.date
        return HeartRateChartPoint(reading: reading, segment: segment)
      }
    } catch {
      guard !Task.isCancelled, requestID == id else { return }
      self.error = tracker.message(
        for: error, operation: "workoutHeartRate",
        fallback: "Не удалось загрузить пульс. Проверьте доступ и попробуйте ещё раз.")
    }
  }
}
