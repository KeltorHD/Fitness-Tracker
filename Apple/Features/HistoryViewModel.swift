import FitLifeCore
import Foundation
import Observation

@MainActor @Observable final class HistoryViewModel {
  var filterDate: Date? { didSet { rebuild() } }
  private(set) var weeks: [JournalWeek] = []
  private(set) var days: [TrainingCalendarDay] = []
  private(set) var diarySummary: DiaryTrainingSummary?
  private var selectedDay: Date?
  @ObservationIgnored private var workouts: [Workout] = []
  @ObservationIgnored private var calendar: Calendar
  @ObservationIgnored private let now: () -> Date

  init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
    self.calendar = calendar
    self.now = now
  }
  func refresh(workouts: [Workout], calendar: Calendar, day: Date? = nil) {
    self.workouts = workouts
    self.calendar = calendar
    selectedDay = day
    rebuild()
  }
  private func rebuild() {
    let date = now()
    diarySummary = DiaryTrainingSummary(
      workouts: workouts, day: selectedDay ?? filterDate ?? date, now: date, calendar: calendar)
    weeks = TrainingJournal.weeks(in: workouts, on: filterDate, now: date, calendar: calendar)
    let trained = Set(
      workouts.filter { $0.status == .completed && $0.startedAt <= date }.map {
        calendar.startOfDay(for: $0.startedAt)
      })
    days = TrainingJournal.weekDays(
      containing: filterDate ?? selectedDay ?? date, calendar: calendar
    ).map {
      TrainingCalendarDay(date: $0, isInMonth: true, hasWorkout: trained.contains($0))
    }
  }
}
