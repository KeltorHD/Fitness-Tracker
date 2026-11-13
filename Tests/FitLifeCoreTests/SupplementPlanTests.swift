import Foundation
import Testing

@testable import FitLifeCore

private func instant(_ value: String) throws -> Date {
  try #require(ISO8601DateFormatter().date(from: value))
}

@Test func supplementScheduleUsesCalendarDaysAcrossDSTAndKeepsIntervalPhase() throws {
  let start = try instant("2024-03-08T17:00:00Z")
  let plan = SupplementPlan(
    prototype: SupplementEntry(date: start, kind: .creatine, amount: 3),
    recurrence: .intervalDays, intervalDays: 2, times: [540], startDate: start,
    timeZoneID: "America/New_York")
  let dates = plan.occurrences(
    from: try instant("2024-03-09T00:00:00Z"), through: try instant("2024-03-13T00:00:00Z"))
  #expect(dates == [try instant("2024-03-10T13:00:00Z"), try instant("2024-03-12T13:00:00Z")])
}

@Test func supplementScheduleResolvesMissingAndRepeatedDSTTimesOnce() throws {
  var plan = SupplementPlan(
    prototype: SupplementEntry(kind: .creatine, amount: 3), times: [150],
    startDate: try instant("2024-03-10T05:00:00Z"), timeZoneID: "America/New_York")
  #expect(
    plan.occurrences(from: plan.startDate, through: try instant("2024-03-11T03:59:59Z")) == [
      try instant("2024-03-10T07:00:00Z")
    ])
  plan.startDate = try instant("2024-11-03T04:00:00Z")
  plan.times = [90]
  #expect(
    plan.occurrences(from: plan.startDate, through: try instant("2024-11-04T04:59:59Z")) == [
      try instant("2024-11-03T05:30:00Z")
    ])
}

@Test func supplementWeekdaysEndDateAndPauseAreRespected() throws {
  var plan = SupplementPlan(
    prototype: SupplementEntry(kind: .protein, amount: 25), recurrence: .weekdays,
    weekdays: [2, 4], times: [480, 1200], startDate: try instant("2024-04-01T00:00:00Z"),
    endDate: try instant("2024-04-03T00:00:00Z"), timeZoneID: "UTC")
  let end = try instant("2024-04-08T00:00:00Z")
  let dates = plan.occurrences(from: plan.startDate, through: end)
  #expect(dates.count == 4)
  #expect(dates.last == (try instant("2024-04-03T20:00:00Z")))
  #expect(plan.occurrences(from: plan.startDate, through: end, limit: 1).count == 1)
  plan.enabled = false
  #expect(plan.occurrences(from: plan.startDate, through: end).isEmpty)
}

@Test func scheduledIntakeIdentityIsStableAcrossDevicesButManualRepeatIsIndependent() throws {
  let date = try instant("2024-04-01T09:00:00Z")
  let plan = SupplementPlan(
    prototype: SupplementEntry(date: date, kind: .creatine, amount: 3), startDate: date,
    timeZoneID: "UTC")
  let first = plan.intake(scheduledFor: date, takenAt: date)
  let second = plan.intake(scheduledFor: date, takenAt: date.addingTimeInterval(600))
  #expect(first.id == second.id)
  #expect(first.planID == plan.id && first.scheduledFor == date)
  #expect(first.date != second.date)
  let copy = first.repeated(on: date)
  #expect(copy.id != first.id && copy.planID == nil && copy.scheduledFor == nil)
  let decoded = try TrainingCoding.decoder().decode(
    TrainingValue.self, from: TrainingCoding.encoder().encode(TrainingValue.supplementPlan(plan)))
  #expect(decoded == .supplementPlan(plan))
}

@Test(arguments: [
  "duplicateTimes", "emptyTimes", "tooManyTimes", "negativeTime", "invalidWeekday", "emptyWeekdays",
  "interval", "timezone", "endDate", "prototype",
])
func supplementScheduleRejectsInvalidUserData(_ scenario: String) throws {
  var plan = SupplementPlan(
    prototype: SupplementEntry(kind: .creatine, amount: 3),
    startDate: try instant("2024-04-01T00:00:00Z"), timeZoneID: "UTC")
  switch scenario {
  case "duplicateTimes": plan.times = [540, 540]
  case "emptyTimes": plan.times = []
  case "tooManyTimes": plan.times = Array(0...8)
  case "negativeTime": plan.times = [-1]
  case "invalidWeekday": plan.weekdays = [8]
  case "emptyWeekdays": plan.recurrence = .weekdays
  case "interval": plan.intervalDays = 0
  case "timezone": plan.timeZoneID = "Invalid/Nowhere"
  case "endDate": plan.endDate = plan.startDate.addingTimeInterval(-1)
  default: plan.prototype.id = UUID()
  }
  #expect(throws: (any Error).self) { try plan.validate() }
}

@Test @MainActor func nutritionSyncIsAccountScopedAndPlanDeletionPreservesIntakes() throws {
  let repository = MemoryWorkoutRepository()
  let plan = SupplementPlan(prototype: SupplementEntry(kind: .creatine, amount: 3))
  let entry = plan.intake(scheduledFor: plan.startDate, takenAt: plan.startDate)
  try repository.saveSupplementPlan(plan)
  try repository.saveSupplementEntry(entry)
  try repository.saveWaterEntry(WaterEntry(milliliters: 200))
  try repository.activateTrainingAccount("account-a")
  #expect(try repository.supplementEntries() == [entry])
  try repository.activateTrainingAccount("account-b")
  #expect(try repository.nutritionSnapshot().values.isEmpty)
  try repository.activateTrainingAccount("account-a")
  try repository.applyTrainingChanges([
    TrainingChange(key: .init(kind: .supplementPlan, id: plan.id), revision: 1, value: nil)
  ])
  #expect(try repository.supplementPlans().isEmpty)
  #expect(try repository.supplementEntries() == [entry])
  #expect(try repository.waterEntries().count == 1)
}

@Test func invalidScheduledDateIsRejectedWithoutTrappingDuringIdentityCalculation() throws {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let plan = SupplementPlan(
    prototype: SupplementEntry(date: date, kind: .creatine, amount: 3), startDate: date)
  let invalid = plan.intake(scheduledFor: Date(timeIntervalSince1970: .infinity), takenAt: date)
  #expect(throws: NutritionError.invalidSupplement) { try invalid.validate() }
}
