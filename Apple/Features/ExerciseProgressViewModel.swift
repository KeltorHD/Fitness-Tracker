import FitnessTrackerCore
import Foundation
import Observation

enum ExerciseProgressMetric: String, CaseIterable, Identifiable {
  case maximumWeight, volume, oneRepMax, repetitions, sets
  var id: String { rawValue }
  var usesWeight: Bool { [.maximumWeight, .volume, .oneRepMax].contains(self) }
  var usesLine: Bool { [.maximumWeight, .oneRepMax].contains(self) }

  func value(in point: ExerciseProgressPoint) -> Double? {
    switch self {
    case .maximumWeight: point.maximumWeightKG
    case .volume: point.volume
    case .oneRepMax: point.estimatedOneRepMaxKG
    case .repetitions: Double(point.repetitions)
    case .sets: Double(point.setCount)
    }
  }
}

struct ExerciseMetricPoint: Identifiable, Equatable {
  let id: UUID
  let date: Date
  let value: Double
}

@MainActor @Observable final class ExerciseProgressViewModel {
  var selectedExerciseID: UUID? { didSet { rebuild(clearSelection: true) } }
  var period: ExerciseProgressPeriod { didSet { rebuild(clearSelection: true) } }
  var selectedDate: Date? { didSet { updateSelection() } }
  private(set) var histories: [ExerciseProgressHistory] = []
  private(set) var history: ExerciseProgressHistory?
  private(set) var points: [ExerciseProgressPoint] = []
  private(set) var series: [ExerciseProgressMetric: [ExerciseMetricPoint]] = [:]
  private(set) var selectedPoint: ExerciseProgressPoint?
  var displayedPoint: ExerciseProgressPoint? { selectedPoint ?? points.last }
  @ObservationIgnored private let fixedExerciseID: UUID?
  @ObservationIgnored private var pendingWorkoutID: UUID?
  @ObservationIgnored private var calendar: Calendar = .current
  @ObservationIgnored private let now: () -> Date

  init(
    exerciseID: UUID? = nil, workoutID: UUID? = nil,
    period: ExerciseProgressPeriod = .twelveWeeks, now: @escaping () -> Date = Date.init
  ) {
    self.fixedExerciseID = exerciseID
    self.pendingWorkoutID = workoutID
    self.selectedExerciseID = exerciseID
    self.period = period
    self.now = now
  }

  func refresh(workouts: [Workout], calendar: Calendar) {
    self.calendar = calendar
    histories = ExerciseProgressReport(workouts: workouts, now: now()).exercises
    if fixedExerciseID == nil, !histories.contains(where: { $0.id == selectedExerciseID }) {
      selectedExerciseID = histories.first?.id
    } else {
      rebuild(clearSelection: false)
    }
  }

  private func rebuild(clearSelection: Bool) {
    history = histories.first { $0.id == selectedExerciseID }
    points = history?.points(in: period, relativeTo: now(), calendar: calendar) ?? []
    series = Dictionary(
      uniqueKeysWithValues: ExerciseProgressMetric.allCases.map { metric in
        (
          metric,
          points.compactMap { point -> ExerciseMetricPoint? in
            guard let value = metric.value(in: point) else { return nil }
            return ExerciseMetricPoint(id: point.id, date: point.date, value: value)
          }
        )
      })
    if let point = points.first(where: { $0.id == pendingWorkoutID }) {
      pendingWorkoutID = nil
      selectedPoint = point
      selectedDate = point.date
    } else if clearSelection {
      selectedDate = nil
    } else {
      updateSelection()
    }
  }

  private func updateSelection() {
    guard let selectedDate, selectedDate.timeIntervalSince1970.isFinite else {
      selectedPoint = nil
      return
    }
    let nearest = points.min {
      abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
    }
    if let previous = points.first(where: { $0.id == selectedPoint?.id }), let nearest,
      abs(previous.date.timeIntervalSince(selectedDate))
        == abs(nearest.date.timeIntervalSince(selectedDate))
    {
      selectedPoint = previous
    } else {
      selectedPoint = nearest
    }
  }
}
