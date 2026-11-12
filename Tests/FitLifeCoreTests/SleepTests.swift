import Foundation
import Testing

@testable import FitLifeCore

private func sleepCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
  return calendar
}
private let sleepDay = Date(timeIntervalSince1970: 1_700_006_400)

@Test func recordedSleepSharesIncludeAwakeAndExcludeBedAndUnknownGaps() throws {
  let calendar = sleepCalendar()
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  let start = window.start.addingTimeInterval(10 * 3600)
  func sample(_ offset: Double, _ length: Double, _ stage: SleepStage) -> SleepSample {
    SleepSample(
      interval: DateInterval(start: start.addingTimeInterval(offset), duration: length),
      stage: stage,
      sourceID: "fixture", sourceName: "fixture")
  }
  let night = SleepNight(
    day: sleepDay, calendar: calendar,
    samples: [
      sample(0, 14_400, .inBed), sample(0, 3600, .core),
      sample(5400, 1800, .awake), sample(7200, 3600, .rem),
    ])
  #expect(night.recordedStageFraction(.awake) == 0.2)
  #expect(night.recordedStageFraction(.core) == 0.4)
  #expect(night.recordedStageFraction(.rem) == 0.4)
  #expect(night.recordedStageFraction(.inBed) == nil)
  #expect(night.fraction(.core) == 0.5)
  let empty = SleepNight(day: sleepDay, calendar: calendar, samples: [])
  #expect(empty.recordedStageFraction(.awake) == nil)
}

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
    !SleepAlarmPlan(fireDate: now.addingTimeInterval(3600), windowMinutes: 0, delivery: .phoneOnly)
      .canArmWatch(at: now))
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

@Test func sleepInsightsKeepGapsUnknownAndJoinAdjacentSleepStages() throws {
  let calendar = sleepCalendar()
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  let start = window.start.addingTimeInterval(3600)
  func sample(_ startMinute: Double, _ minutes: Double, _ stage: SleepStage) -> SleepSample {
    SleepSample(
      interval: DateInterval(
        start: start.addingTimeInterval(startMinute * 60), duration: minutes * 60), stage: stage,
      sourceID: "test", sourceName: "test")
  }
  let night = SleepNight(
    day: sleepDay, calendar: calendar,
    samples: [
      sample(0, 180, .inBed), sample(20, 30, .core), sample(50, 30, .deep),
      sample(80, 10, .awake), sample(100, 20, .rem),
    ])
  #expect(night.sleepOnsetLatency == 1200.0)
  #expect(night.asleep == 4800.0)
  #expect(night.longestSleepEpisode == 3600.0)
  #expect(night.awakeDuration == 600.0)
  #expect(night.efficiency == 80.0 / 180)
  #expect(night.fraction(.deep) == 30.0 / 80)
  #expect(night.fraction(.awake) == nil)
  #expect(night.period(at: start.addingTimeInterval(50 * 60))?.stage == .deep)
  #expect(night.period(at: start.addingTimeInterval(95 * 60)) == nil)
  #expect(night.period(at: start.addingTimeInterval(120 * 60)) == nil)
  #expect(night.period(at: Date(timeIntervalSince1970: .nan)) == nil)
}

@Test func sleepEfficiencyRequiresBedCoverageAndLatencyRequiresKnownBedtime() throws {
  let calendar = sleepCalendar()
  let window = try #require(SleepNight.window(endingOn: sleepDay, calendar: calendar))
  func sample(_ offset: Double, _ hours: Double, _ stage: SleepStage) -> SleepSample {
    SleepSample(
      interval: DateInterval(
        start: window.start.addingTimeInterval(offset * 3600), duration: hours * 3600),
      stage: stage, sourceID: "test", sourceName: "test")
  }
  let missingBed = SleepNight(
    day: sleepDay, calendar: calendar, samples: [sample(2, 5, .unspecified)])
  #expect(missingBed.efficiency == nil)
  #expect(missingBed.sleepOnsetLatency == nil)
  #expect(missingBed.awakeDuration == nil)
  let gap = SleepNight(
    day: sleepDay, calendar: calendar,
    samples: [sample(0, 3, .inBed), sample(4, 3, .inBed), sample(2, 4, .core)])
  #expect(gap.efficiency == nil)
  let clipped = SleepNight(
    day: sleepDay, calendar: calendar, samples: [sample(-1, 9, .inBed), sample(2, 5, .core)])
  #expect(clipped.sleepOnsetLatency == nil)
}

@Test func sleepTrendExcludesUnrecordedNightsAndComparesOnlyPreviousCalendarDay() throws {
  let calendar = sleepCalendar()
  let day = calendar.startOfDay(for: sleepDay)
  let nights = try (-29...0).map { offset -> SleepNight in
    let date = try #require(calendar.date(byAdding: .day, value: offset, to: day))
    let window = try #require(SleepNight.window(endingOn: date, calendar: calendar))
    let samples =
      offset == -1
      ? []
      : [
        SleepSample(
          interval: DateInterval(start: window.start, duration: offset == 0 ? 8 * 3600 : 6 * 3600),
          stage: .unspecified, sourceID: "test", sourceName: "test")
      ]
    return SleepNight(day: date, calendar: calendar, samples: samples)
  }
  let week = SleepTrend(nights: nights, endingOn: day, days: 7, calendar: calendar)
  #expect(week.nights.count == 7)
  #expect(week.recorded.count == 6)
  #expect(week.average == 22_800.0)
  #expect(week.shortest == 21_600.0)
  #expect(week.longest == 28_800.0)
  #expect(week.differenceFromPrevious(try #require(nights.last), calendar: calendar) == nil)
  #expect(
    SleepTrend(nights: nights, endingOn: day, days: 30, calendar: calendar).recorded.count == 29)
}

@Test func legacySleepAlarmPlansKeepPhoneReserveAndEnabledState() throws {
  let plan = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 20)
  let data = try JSONEncoder().encode(plan)
  var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  json.removeValue(forKey: "delivery")
  json.removeValue(forKey: "isEnabled")
  let decoded = try JSONDecoder().decode(
    SleepAlarmPlan.self, from: JSONSerialization.data(withJSONObject: json))
  #expect(decoded == plan)
  let watch = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 0, delivery: .watchOnly)
  #expect(watch.canArmWatch(at: sleepDay.addingTimeInterval(-120)))
  #expect(watch.watchStart == sleepDay.addingTimeInterval(-60))
  #expect(
    !SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 20, isEnabled: false).canArmWatch(
      at: sleepDay.addingTimeInterval(-120)))
}

@Test func sleepAlarmDeliveryRoutesPhoneAndWatchIndependently() {
  let now = sleepDay.addingTimeInterval(-3600)
  let phone = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 0, delivery: .phoneOnly)
  let watch = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 0, delivery: .watchOnly)
  let all = SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 0, delivery: .phoneAndWatch)
  #expect(phone.isValid)
  #expect(!phone.canArmWatch(at: now))
  #expect(watch.canArmWatch(at: now))
  #expect(all.canArmWatch(at: now))
  #expect(!SleepAlarmPlan(fireDate: sleepDay, windowMinutes: 20, delivery: .phoneOnly).isValid)
  #expect(
    !SleepAlarmWatchEvent(plan: phone, kind: .dismissed, date: sleepDay).canCancelBackup(
      for: phone, now: sleepDay))
  #expect(SleepAlarmDelivery.allCases.count == 3)
}
