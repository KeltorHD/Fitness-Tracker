import Foundation
import Testing

@testable import FitnessTrackerCore

private func sleepCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
  return calendar
}
private let sleepDay = Date(timeIntervalSince1970: 1_700_006_400)

@Test func sleepNightUsesOneSourceAndUnionsOverlappingStages() throws {
  let calendar = sleepCalendar()
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  let start = window.start.addingTimeInterval(10 * 3600)
  func sample(_ offset: Double, _ hours: Double, _ stage: SleepStage, _ source: String = "watch")
    -> SleepSample
  {
    SleepSample(
      interval: DateInterval(
        start: start.addingTimeInterval(offset * 3600), duration: hours * 3600), stage: stage,
      sourceID: source, sourceName: source, fromWatch: source == "watch")
  }
  let night = SleepNight(
    day: sleepDay, calendar: calendar,
    samples: [
      sample(0, 8, .inBed), sample(0, 8, .unspecified, "phone"),
      sample(0, 3, .core), sample(0, 3, .core), sample(3, 2, .deep),
      sample(5, 1, .awake), sample(6, 2, .rem), sample(5, 3, .unspecified),
    ])
  #expect(night.sourceName == "watch")
  #expect(night.asleep == 25_200.0)
  #expect(night.inBed == 28_800.0)
  #expect(night.duration(.deep) == 2 * 3600)
  #expect(night.duration(.unspecified) == 0)
  #expect(night.awakePeriods == 1)
  #expect(night.periods.map(\.stage) == [.core, .deep, .awake, .rem])
  #expect(night.sleepStart == start)
  #expect(night.sleepEnd == start.addingTimeInterval(8 * 3600))
}

@Test func sleepNightEmptyAndBedOnlyDoNotInventSleep() throws {
  let calendar = sleepCalendar()
  let empty = SleepNight(day: sleepDay, calendar: calendar, samples: [])
  #expect(empty.asleep == nil)
  #expect(empty.inBed == nil)
  #expect(empty.sleepStart == nil)
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  let bed = SleepSample(interval: window, stage: .inBed, sourceID: "manual", sourceName: "manual")
  let night = SleepNight(day: sleepDay, calendar: calendar, samples: [bed, bed])
  #expect(night.asleep == nil)
  #expect(night.inBed == window.duration)
  #expect(!night.hasStages)
}

@Test func sleepNightClipsToNoonAndDistinguishesUnknownStages() throws {
  let calendar = sleepCalendar()
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  let sample = SleepSample(
    interval: DateInterval(
      start: window.start.addingTimeInterval(-3600), end: window.end.addingTimeInterval(3600)),
    stage: .unspecified, sourceID: "manual", sourceName: "manual")
  let night = SleepNight(day: sleepDay, calendar: calendar, samples: [sample])
  #expect(night.asleep == window.duration)
  #expect(night.sleepStart == window.start)
  #expect(night.sleepEnd == window.end)
  #expect(!night.hasStages)
}

@Test func sleepNightWindowsRespectDST() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
  for (month, day, hours) in [(3, 31, 23), (10, 27, 25)] {
    let date = try #require(calendar.date(from: DateComponents(year: 2024, month: month, day: day)))
    let window = try #require(SleepNight.window(endingOn: date, calendar: calendar))
    #expect(window.duration == Double(hours) * 3600)
    #expect(calendar.component(.hour, from: window.start) == 12)
    #expect(calendar.component(.hour, from: window.end) == 12)
  }
}

@Test func sleepAlarmPlansValidateWindowsAndWatchSchedulingHorizon() {
  let now = sleepDay
  let plan = SleepAlarmPlan(fireDate: now.addingTimeInterval(37 * 3600), windowMinutes: 30)
  #expect(!plan.canArmWatch(at: now))
  #expect(
    SleepAlarmPlan(fireDate: now.addingTimeInterval(36.5 * 3600), windowMinutes: 30).canArmWatch(
      at: now))
  #expect(!SleepAlarmPlan(fireDate: now, windowMinutes: 30).canArmWatch(at: now))
  #expect(
    !SleepAlarmPlan(fireDate: now.addingTimeInterval(3600), windowMinutes: 0).canArmWatch(at: now))
  #expect(!SleepAlarmPlan(fireDate: now, windowMinutes: 31).isValid)
  #expect(!SleepAlarmPlan(fireDate: Date(timeIntervalSince1970: .nan), windowMinutes: 20).isValid)
  #expect(!SleepAlarmSync(revision: now, plans: [plan, plan]).isValid)
  #expect(
    !SleepAlarmSync(
      revision: now, plans: (0...10).map { _ in SleepAlarmPlan(fireDate: now, windowMinutes: 0) }
    ).isValid)
}

@Test func onlyExplicitWatchDismissalWithinWindowCanCancelReserve() {
  let plan = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 20)
  let now = plan.windowStart.addingTimeInterval(120)
  #expect(
    !SleepAlarmWatchEvent(plan: plan, kind: .alerted, date: now).canCancelBackup(
      for: plan, now: now))
  #expect(
    SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now).canCancelBackup(
      for: plan, now: now))
  #expect(
    !SleepAlarmWatchEvent(
      plan: plan, kind: .dismissed, date: plan.windowStart.addingTimeInterval(-1)
    ).canCancelBackup(for: plan, now: now))
  #expect(
    !SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now.addingTimeInterval(31))
      .canCancelBackup(for: plan, now: now))
  #expect(
    !SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: plan.fireDate.addingTimeInterval(61))
      .canCancelBackup(for: plan, now: plan.fireDate.addingTimeInterval(61)))
  let replacement = SleepAlarmPlan(
    id: plan.id, fireDate: plan.fireDate.addingTimeInterval(60), windowMinutes: 20)
  #expect(
    !SleepAlarmWatchEvent(plan: plan, kind: .dismissed, date: now).canCancelBackup(
      for: replacement, now: now))
}

@Test func smartWakeRequiresQuietThenSustainedMovementAndFiresOnce() {
  let plan = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 20)
  var detector = SmartWakeDetector()
  var alerts = 0
  for tick in 0...600 {
    let seconds = Double(tick) / 2
    if detector.ingest(
      at: plan.windowStart.addingTimeInterval(seconds), movement: seconds < 61 ? 0.001 : 0.2,
      plan: plan)
    {
      alerts += 1
    }
  }
  #expect(alerts == 1)
}

@Test func smartWakeDoesNotAlertForNoiseMovementAloneOrSensorGaps() {
  let plan = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 5)
  for mode in 0...2 {
    var detector = SmartWakeDetector()
    var alerted = false
    for tick in 0...500 {
      let seconds = Double(tick) / 2
      if mode == 2 && seconds >= 60 && seconds < 70 { continue }
      let movement = mode == 0 ? 0.001 : (mode == 1 || seconds >= 60 ? 0.2 : 0.001)
      alerted =
        detector.ingest(
          at: plan.windowStart.addingTimeInterval(seconds), movement: movement, plan: plan)
        || alerted
    }
    #expect(!alerted)
  }
  var detector = SmartWakeDetector()
  let beforeWindow = detector.ingest(
    at: plan.windowStart.addingTimeInterval(-1), movement: 0.2, plan: plan)
  #expect(!beforeWindow)
  let atDeadline = detector.ingest(at: plan.fireDate, movement: 0.2, plan: plan)
  #expect(!atDeadline)
  let invalidMovement = detector.ingest(at: plan.windowStart, movement: .nan, plan: plan)
  #expect(!invalidMovement)
}
