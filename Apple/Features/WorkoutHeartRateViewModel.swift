import FitnessTrackerCore
import Foundation
import Observation

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
        try HeartRateRecording(
          workoutID: $0.workoutID, mode: $0.mode, readings: readings, origin: $0.origin)
      }
      points = HeartRateChartPoint.make(readings: readings, pauses: workout.pauses)
    } catch {
      guard !Task.isCancelled, requestID == id else { return }
      self.error = tracker.message(
        for: error, operation: "workoutHeartRate",
        fallback: "Не удалось загрузить пульс. Проверьте доступ и попробуйте ещё раз.")
    }
  }
}
