import FitnessTrackerCore
import Foundation
import Observation

struct HealthChartsObservation: Hashable {
  let day: Date
  let calendar: Calendar
  let enabled: Bool
  let active: Bool
  let request: Int
}

/// RootView owns the observation task, cancels it in the background and restarts after day changes.
@MainActor @Observable final class HealthChartsViewModel {
  @ObservationIgnored var onHeartRateChange: (@MainActor () -> Void)?
  var day: Date
  var enabled: Bool {
    didSet {
      defaults.set(enabled, forKey: "healthChartsEnabled")
      onHeartRateChange?()
    }
  }
  private(set) var snapshot: HealthChartSnapshot? { didSet { onHeartRateChange?() } }
  private(set) var points: [HeartRateChartPoint] = []
  private(set) var workoutPoints: [HeartRateChartPoint] = []
  private(set) var loading = false
  private(set) var observing = false
  private(set) var error: String?
  private(set) var request = 0
  private(set) var updatedAt: Date?
  private(set) var updateChanged: Bool?
  @ObservationIgnored private let reader: any HealthChartsReading
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let errorMessage: (any Error) -> String
  @ObservationIgnored private var generation: UUID?
  @ObservationIgnored private var workout: Workout?
  @ObservationIgnored private var baseline: HealthChartSnapshot?

  init(
    reader: any HealthChartsReading, defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init, errorMessage: @escaping (any Error) -> String
  ) {
    self.reader = reader
    self.defaults = defaults
    self.now = now
    self.errorMessage = errorMessage
    day = now()
    enabled = defaults.bool(forKey: "healthChartsEnabled")
  }

  func retry() {
    generation = nil
    reader.stopChanges()
    observing = false
    loading = true
    updatedAt = nil
    updateChanged = nil
    error = nil
    request += 1
  }

  func attach(_ workout: Workout?) {
    self.workout = workout
    rebuildWorkoutPoints()
  }

  private func rebuildWorkoutPoints() {
    guard let workout else {
      workoutPoints = []
      return
    }
    let end = workout.pausedAt ?? workout.endedAt ?? now()
    let readings = (snapshot?.currentDayHeartRate ?? []).filter { reading in
      reading.date >= workout.startedAt && reading.date <= end
        && !workout.pauses.contains { ($0.startedAt...$0.endedAt).contains(reading.date) }
    }
    workoutPoints = HeartRateChartPoint.make(readings: readings, pauses: workout.pauses)
  }

  func clear() {
    reader.stopChanges()
    generation = nil
    snapshot = nil
    points = []
    workoutPoints = []
    loading = false
    observing = false
    error = nil
    updatedAt = nil
    updateChanged = nil
    baseline = nil
  }

  func observe(calendar: Calendar) async {
    guard !Task.isCancelled else { return }
    guard enabled else {
      clear()
      return
    }
    reader.stopChanges()
    let id = UUID()
    generation = id
    let selectedDay = day
    snapshot = nil
    points = []
    workoutPoints = []
    loading = true
    observing = false
    error = nil
    updatedAt = nil
    updateChanged = nil
    defer {
      if generation == id {
        reader.stopChanges()
        loading = false
        observing = false
      }
    }
    do {
      try await reader.requestChartAuthorization()
      try Task.checkCancellation()
      guard generation == id, enabled else { return }
      guard
        let start = calendar.date(
          byAdding: .day, value: -6, to: calendar.startOfDay(for: now()))
      else { throw TrainingError.invalidDate }
      try await reload(day: selectedDay, calendar: calendar, generation: id, reportResult: true)
      guard generation == id, enabled else { return }
      observing = true
      // The initial anchored result also catches changes made during the first read.
      for try await _ in reader.changes(since: start) {
        try Task.checkCancellation()
        guard generation == id, enabled else { return }
        try await reload(day: selectedDay, calendar: calendar, generation: id)
      }
    } catch {
      guard generation == id, !Task.isCancelled, !(error is CancellationError) else { return }
      self.error = errorMessage(error)
    }
  }

  private func reload(
    day: Date, calendar: Calendar, generation id: UUID, reportResult: Bool = false
  ) async throws {
    let value = try await reader.chartSnapshot(day: day, calendar: calendar)
    try Task.checkCancellation()
    guard generation == id, enabled else { return }
    snapshot = value
    if reportResult || baseline != value {
      updateChanged = baseline.flatMap { previous in
        calendar.isDate(previous.day, inSameDayAs: value.day) ? previous != value : nil
      }
      updatedAt = now()
    }
    baseline = value
    points = HeartRateChartPoint.make(readings: value.heartRate, gap: 300)
    rebuildWorkoutPoints()
    loading = false
  }
}
