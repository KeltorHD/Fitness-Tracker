import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class ProgressViewModel {
  var month: Date { didSet { rebuild() } }
  let exerciseProgress: ExerciseProgressViewModel
  private(set) var report: TrainingReport
  @ObservationIgnored private var workouts: [Workout] = []
  @ObservationIgnored private var calendar: Calendar
  @ObservationIgnored private let now: () -> Date

  init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
    self.calendar = calendar
    self.now = now
    exerciseProgress = ExerciseProgressViewModel(now: now)
    let date = now()
    month = date
    report = TrainingReport(workouts: [], month: date, now: date, calendar: calendar)
  }

  var year: Int { calendar.component(.year, from: month) }

  func refresh(workouts: [Workout], calendar: Calendar) {
    self.workouts = workouts
    self.calendar = calendar
    exerciseProgress.refresh(workouts: workouts, calendar: calendar)
    rebuild()
  }
  func selectYear(_ year: Int) {
    var parts = calendar.dateComponents([.month], from: month)
    parts.year = year
    parts.day = 1
    if let date = calendar.date(from: parts) { month = date }
  }
  func moveMonth(by value: Int) {
    let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
    if let date = calendar.date(byAdding: .month, value: value, to: start) { month = date }
  }
  private func rebuild() {
    report = TrainingReport(workouts: workouts, month: month, now: now(), calendar: calendar)
  }
}
