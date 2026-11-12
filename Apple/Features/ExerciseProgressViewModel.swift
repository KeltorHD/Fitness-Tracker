import FitLifeCore
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
  var historyFilter = ExerciseWorkoutHistoryFilter() { didSet { filterHistory() } }
  private(set) var histories: [ExerciseProgressHistory] = []
  private(set) var history: ExerciseProgressHistory?
  private(set) var historyEntries: [ExerciseWorkoutHistoryEntry] = []
  private(set) var filteredHistoryEntries: [ExerciseWorkoutHistoryEntry] = []
  private(set) var points: [ExerciseProgressPoint] = []
  private(set) var series: [ExerciseProgressMetric: [ExerciseMetricPoint]] = [:]
  private(set) var selectedPoint: ExerciseProgressPoint?
  var displayedPoint: ExerciseProgressPoint? { selectedPoint ?? points.last }
  @ObservationIgnored private let fixedExerciseID: UUID?
  @ObservationIgnored private var pendingWorkoutID: UUID?
  @ObservationIgnored private var calendar: Calendar = .current
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var workouts: [Workout] = []

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
    self.workouts = workouts
    self.calendar = calendar
    histories = ExerciseProgressReport(workouts: workouts, now: now()).exercises
    if fixedExerciseID == nil, !histories.contains(where: { $0.id == selectedExerciseID }) {
      selectedExerciseID = histories.first?.id
    } else {
      rebuild(clearSelection: false)
    }
  }

  private func rebuild(clearSelection: Bool) {
    let date = now()
    historyEntries =
      selectedExerciseID.map {
        ExerciseWorkoutHistoryEntry.entries(for: $0, workouts: workouts, now: date)
      } ?? []
    filterHistory()
    history = histories.first { $0.id == selectedExerciseID }
    points = history?.points(in: period, relativeTo: date, calendar: calendar) ?? []
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

  private func filterHistory() {
    filteredHistoryEntries = historyFilter.apply(to: historyEntries, now: now(), calendar: calendar)
  }
}
