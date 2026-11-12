import Foundation
import Testing

@testable import FitLifeCore

private func diaryCalendarFixture(firstWeekday: Int = 2) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
  calendar.firstWeekday = firstWeekday
  return calendar
}

@Test func commonDiaryCalendarMovesWholeWeeksAcrossDSTWithoutChangingLocalWeekdayOrHour() throws {
  let calendar = diaryCalendarFixture()
  let date = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 12)))
  let next = try #require(DiaryCalendar.shifted(date, by: 1, mode: .week, calendar: calendar))
  #expect(calendar.component(.weekday, from: next) == calendar.component(.weekday, from: date))
  #expect(calendar.component(.hour, from: next) == 12)
  #expect(next.timeIntervalSince(date) == 167 * 3600)
  #expect(DiaryCalendar.shifted(next, by: -1, mode: .week, calendar: calendar) == date)
}

@Test func commonDiaryMonthClampsDayAndKeepsSixCalendarRows() throws {
  let calendar = diaryCalendarFixture()
  let january = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 31)))
  let february = try #require(
    DiaryCalendar.shifted(january, by: 1, mode: .month, calendar: calendar))
  #expect(calendar.component(.day, from: february) == 29)
  let page = try #require(
    DiaryCalendar.page(
      containing: february, mode: .month, workouts: [], now: february, calendar: calendar
    ))
  #expect(page.days.count == 42)
  #expect(page.days.filter(\.isInMonth).count == 29)
  #expect(
    calendar.component(.weekday, from: try #require(page.days.first).date) == calendar.firstWeekday)
  #expect(Set(page.days.map(\.date)).count == 42)
}

@Test func commonDiaryPagesHonorLocaleWeekStartAndMarkOnlyCompletedRecordedWorkouts() throws {
  for firstWeekday in [1, 2, 7] {
    let calendar = diaryCalendarFixture(firstWeekday: firstWeekday)
    let date = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12)))
    var logged = Workout(name: "Fixture", startedAt: date)
    logged.status = .completed
    let futureDate = try #require(calendar.date(byAdding: .day, value: 1, to: date))
    var future = logged
    future.startedAt = futureDate
    let active = Workout(name: "Active", startedAt: futureDate)
    let snapshot = DiaryCalendar.page(
      containing: date, mode: .week, workouts: [logged, future, active], now: date,
      calendar: calendar)
    let page = try #require(snapshot)
    #expect(page.days.count == 7)
    #expect(calendar.component(.weekday, from: try #require(page.days.first).date) == firstWeekday)
    #expect(page.days.filter(\.hasWorkout).map(\.date) == [calendar.startOfDay(for: date)])
  }
  #expect(
    DiaryCalendar.shifted(
      Date(timeIntervalSince1970: .nan), by: 1, mode: .week, calendar: diaryCalendarFixture())
      == nil)
}
