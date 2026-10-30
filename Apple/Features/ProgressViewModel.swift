import FitnessTrackerCore
import Foundation
import Observation

struct TrainingMonthPage: Identifiable {
  let offset: Int
  let date: Date
  let summary: TrainingMonthSummary
  var id: Int { offset }
}

@MainActor @Observable final class ProgressViewModel {
  var month: Date { didSet { rebuild() } }
  let exerciseProgress: ExerciseProgressViewModel
  let bodyWeight: BodyWeightViewModel
  private(set) var report: TrainingReport
  private(set) var monthPages: [TrainingMonthPage] = []
  @ObservationIgnored private var workouts: [Workout] = []
  @ObservationIgnored private var calendar: Calendar
  @ObservationIgnored private let now: () -> Date

  init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
    self.calendar = calendar
    self.now = now
    exerciseProgress = ExerciseProgressViewModel(now: now)
    bodyWeight = BodyWeightViewModel(now: now)
    let date = now()
    month = date
    report = TrainingReport(workouts: [], month: date, now: date, calendar: calendar)
    rebuild()
  }

  var year: Int { calendar.component(.year, from: month) }

  func refresh(workouts: [Workout], calendar: Calendar, bodyWeights: [BodyWeightEntry] = []) {
    self.workouts = workouts
    self.calendar = calendar
    exerciseProgress.refresh(workouts: workouts, calendar: calendar)
    bodyWeight.refresh(entries: bodyWeights, workouts: workouts)
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
  func showCurrentMonth() { month = now() }
  private func rebuild() {
    let currentTime = now()
    report = TrainingReport(workouts: workouts, month: month, now: currentTime, calendar: calendar)
    let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
    monthPages = (-1...1).compactMap { offset in
      guard let date = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
      let summary =
        offset == 0
        ? report.month
        : TrainingMonthSummary(
          workouts: workouts, month: date, now: currentTime, calendar: calendar)
      return TrainingMonthPage(offset: offset, date: date, summary: summary)
    }
  }
}
