import FitnessTrackerCore
import Foundation
import HealthKit

@MainActor final class HealthMetricsReader: HealthMetricsReading, HealthChartsReading {
  private var observationTask: Task<Void, Never>?
  func requestChartAuthorization() async throws { try await Self.authorizeCharts() }
  func chartSnapshot(day: Date, calendar: Calendar) async throws -> HealthChartSnapshot {
    try await Self.readCharts(day: day, calendar: calendar)
  }
  func changes(since date: Date) -> AsyncThrowingStream<Void, any Error> {
    stopChanges()
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { await Self.observeChanges(since: date, continuation: continuation) }
      observationTask = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }
  func stopChanges() {
    observationTask?.cancel()
    observationTask = nil
  }

  @concurrent nonisolated private static func authorizeCharts() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    try await HKHealthStore().requestAuthorization(
      toShare: [], read: [HKQuantityType(.stepCount), HKQuantityType(.heartRate)])
  }

  @concurrent nonisolated private static func observeChanges(
    since date: Date, continuation: AsyncThrowingStream<Void, any Error>.Continuation
  ) async {
    do {
      let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: [])
      let query = HKAnchoredObjectQueryDescriptor<HKQuantitySample>(
        predicates: [
          .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate),
          .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
        ], anchor: nil)
      for try await _ in query.results(for: HKHealthStore()) {
        try Task.checkCancellation()
        continuation.yield(())
      }
      continuation.finish()
    } catch {
      continuation.finish(throwing: error)
    }
  }

  @concurrent nonisolated private static func readCharts(day: Date, calendar: Calendar) async throws
    -> HealthChartSnapshot
  {
    let now = Date()
    let window = try HealthChartWindow(day: day, now: now, calendar: calendar)
    let interval = window.day
    let store = HKHealthStore()
    let stepQuery = HKStatisticsCollectionQueryDescriptor(
      predicate: .quantitySample(
        type: HKQuantityType(.stepCount),
        predicate: predicate(window.stepsInterval)),
      options: .cumulativeSum, anchorDate: interval.start,
      intervalComponents: DateComponents(calendar: calendar, timeZone: calendar.timeZone, day: 1))
    let totals = try await stepQuery.result(for: store)
    try Task.checkCancellation()
    let steps = window.stepDays.map { date in
      let count = totals.statistics(for: date)?.sumQuantity()?.doubleValue(for: .count())
      return HealthStepDay(
        date: date,
        steps: count.flatMap { $0.isFinite && $0 >= 0 ? Int(exactly: $0.rounded()) : nil })
    }
    let samples = try await HKSampleQueryDescriptor(
      predicates: [
        .quantitySample(
          type: HKQuantityType(.heartRate),
          predicate: HKQuery.predicateForSamples(
            withStart: interval.start, end: min(interval.end, now),
            options: [.strictStartDate, .strictEndDate]))
      ], sortDescriptors: [SortDescriptor(\.startDate)], limit: 100_001
    ).result(for: store)
    try Task.checkCancellation()
    guard samples.count <= 100_000 else { throw TrackerDataError.recordingFull }
    var seen = Set<Date>()
    let readings = samples.compactMap { sample -> HeartRateReading? in
      let reading = HeartRateReading(
        date: sample.startDate,
        beatsPerMinute: sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
      return reading.isValid && seen.insert(reading.date).inserted ? reading : nil
    }
    let currentSamples: [HKQuantitySample]
    if calendar.isDate(day, inSameDayAs: now) {
      currentSamples = samples
    } else {
      currentSamples = try await HKSampleQueryDescriptor(
        predicates: [
          .quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForSamples(
              withStart: calendar.startOfDay(for: now), end: now,
              options: [.strictStartDate, .strictEndDate]))
        ], sortDescriptors: [SortDescriptor(\.startDate)], limit: 100_001
      ).result(for: store)
    }
    try Task.checkCancellation()
    guard currentSamples.count <= 100_000 else { throw TrackerDataError.recordingFull }
    let latest = currentSamples.last
    let latestReading = latest.map {
      HeartRateReading(
        date: $0.startDate,
        beatsPerMinute: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
    }
    return HealthChartSnapshot(
      day: interval.start, steps: steps, heartRate: readings,
      latestHeartRate: latestReading?.isValid == true ? latestReading : nil,
      heartRateSource: latest?.sourceRevision.source.name,
      currentDayHeartRate: currentSamples.compactMap {
        let reading = HeartRateReading(
          date: $0.startDate,
          beatsPerMinute: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        return reading.isValid ? reading : nil
      })
  }

  func requestReadAuthorization() async throws { try await Self.authorize() }
  func requestHeartRateAuthorization() async throws {
    try await Self.authorize(heartRateOnly: true)
  }
  func daySummary(for day: Date, calendar: Calendar) async throws -> HealthDaySummary {
    try await Self.readDay(day, calendar: calendar)
  }
  func heartRate(for workout: Workout) async throws -> HeartRateRecording {
    try await Self.readWorkout(workout)
  }

  // SDK handles are created/used on the generic executor. Only value data crosses MainActor.
  @concurrent nonisolated private static func authorize(heartRateOnly: Bool = false) async throws {
    try Task.checkCancellation()
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    let types: Set<HKObjectType> =
      heartRateOnly
      ? [HKQuantityType(.heartRate)]
      : [
        HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
        HKCategoryType(.sleepAnalysis),
      ]
    try await HKHealthStore().requestAuthorization(toShare: [], read: types)
  }

  nonisolated private static func predicate(_ interval: DateInterval) -> NSPredicate {
    HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
  }

  @concurrent nonisolated private static func readDay(_ day: Date, calendar: Calendar) async throws
    -> HealthDaySummary
  {
    guard let interval = calendar.dateInterval(of: .day, for: day), interval.start <= .now,
      let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
      let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon)
    else { throw TrainingError.invalidDate }
    let store = HKHealthStore()
    let steps = try await total(.stepCount, unit: .count(), interval: interval, store: store)
    try Task.checkCancellation()
    let energy = try await total(
      .activeEnergyBurned, unit: .kilocalorie(), interval: interval, store: store)
    let rate = try await HKSampleQueryDescriptor(
      predicates: [
        .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate(interval))
      ],
      sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1
    ).result(for: store).first
    let sleepWindow = DateInterval(start: previousNoon, end: min(noon, .now))
    let sleep = try await HKSampleQueryDescriptor(
      predicates: [
        .categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate(sleepWindow))
      ],
      sortDescriptors: [SortDescriptor(\.startDate)], limit: 10_000
    ).result(for: store)
    try Task.checkCancellation()
    let asleep = Set([
      HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
      HKCategoryValueSleepAnalysis.asleepCore.rawValue,
      HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
      HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ])
    let sleepIntervals = sleep.filter { asleep.contains($0.value) }.map {
      DateInterval(start: $0.startDate, end: $0.endDate)
    }
    let reading = rate.map {
      HeartRateReading(
        date: $0.startDate,
        beatsPerMinute: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
    }
    return HealthDaySummary(
      day: interval.start, steps: steps.flatMap { $0 >= 0 ? Int(exactly: $0.rounded()) : nil },
      activeEnergyKCal: energy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
      sleepSeconds: TrackerCalculations.sleepDuration(sleepIntervals, within: sleepWindow),
      latestHeartRate: reading?.isValid == true ? reading : nil,
      heartRateSource: rate?.sourceRevision.source.name)
  }

  nonisolated private static func total(
    _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, interval: DateInterval,
    store: HKHealthStore
  ) async throws -> Double? {
    let result = try await HKStatisticsQueryDescriptor(
      predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate(interval)),
      options: .cumulativeSum
    ).result(for: store)
    return result?.sumQuantity()?.doubleValue(for: unit)
  }

  @concurrent nonisolated private static func readWorkout(_ workout: Workout) async throws
    -> HeartRateRecording
  {
    try Validation.workout(workout)
    guard workout.status == .completed, let end = workout.endedAt else {
      throw TrainingError.invalidState
    }
    let samples = try await HKSampleQueryDescriptor(
      predicates: [
        .quantitySample(
          type: HKQuantityType(.heartRate),
          predicate: HKQuery.predicateForSamples(
            withStart: workout.startedAt, end: end, options: [.strictStartDate, .strictEndDate]))
      ],
      sortDescriptors: [SortDescriptor(\.startDate)], limit: 100_001
    ).result(for: HKHealthStore())
    try Task.checkCancellation()
    guard samples.count <= 100_000 else { throw TrackerDataError.recordingFull }
    var seen = Set<Date>()
    let readings = samples.compactMap { sample -> HeartRateReading? in
      let reading = HeartRateReading(
        date: sample.startDate,
        beatsPerMinute: sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
      guard reading.isValid, seen.insert(reading.date).inserted,
        !workout.pauses.contains(where: { ($0.startedAt...$0.endedAt).contains(reading.date) })
      else { return nil }
      return reading
    }
    // Bound the chart/storage while retaining both endpoints of long recordings.
    let stride = max(
      1, Int(ceil(Double(readings.count) / Double(HeartRateRecording.maximumReadings))))
    var sampled = readings.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    if let last = readings.last, sampled.last != last {
      if sampled.count == HeartRateRecording.maximumReadings { sampled.removeLast() }
      sampled.append(last)
    }
    return try HeartRateRecording(workoutID: workout.id, mode: .appleHealth, readings: sampled)
  }
}
