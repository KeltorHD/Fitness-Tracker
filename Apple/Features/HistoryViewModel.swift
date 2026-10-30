import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class HistoryViewModel {
  var filterDate: Date? { didSet { rebuild() } }
  private(set) var weeks: [JournalWeek] = []
  private(set) var days: [TrainingCalendarDay] = []
  @ObservationIgnored private var workouts: [Workout] = []
  @ObservationIgnored private var calendar: Calendar
  @ObservationIgnored private let now: () -> Date

  init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
    self.calendar = calendar
    self.now = now
  }
  func refresh(workouts: [Workout], calendar: Calendar) {
    self.workouts = workouts
    self.calendar = calendar
    rebuild()
  }
  private func rebuild() {
    let date = now()
    weeks = TrainingJournal.weeks(in: workouts, on: filterDate, now: date, calendar: calendar)
    let trained = Set(
      workouts.filter { $0.status == .completed && $0.startedAt <= date }.map {
        calendar.startOfDay(for: $0.startedAt)
      })
    days = TrainingJournal.weekDays(containing: date, calendar: calendar).map {
      TrainingCalendarDay(date: $0, isInMonth: true, hasWorkout: trained.contains($0))
    }
  }
}
