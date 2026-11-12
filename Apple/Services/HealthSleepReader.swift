import FitLifeCore
import Foundation
import HealthKit

@MainActor final class HealthSleepReader: HealthSleepReading {
  func authorize() async throws { try await Self.requestPermission() }
  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] {
    try await Self.read(day: day, calendar: calendar)
  }
  @concurrent nonisolated private static func requestPermission() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    try await HKHealthStore().requestAuthorization(
      toShare: [], read: [HKCategoryType(.sleepAnalysis)])
  }
  @concurrent nonisolated private static func read(day: Date, calendar: Calendar) async throws
    -> [SleepNight]
  {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    let days = (-29...0).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
    guard let first = days.first.flatMap({ SleepNight.window(endingOn: $0, calendar: calendar) }),
      let last = SleepNight.window(endingOn: day, calendar: calendar)
    else { return [] }
    let now = Date()
    guard first.start < now else {
      return days.map { SleepNight(day: $0, calendar: calendar, samples: []) }
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: first.start, end: min(last.end, now), options: [])
    let records = try await HKSampleQueryDescriptor(
      predicates: [
        .categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)
      ], sortDescriptors: [SortDescriptor(\.startDate)], limit: 20_001
    ).result(for: HKHealthStore())
    try Task.checkCancellation()
    guard records.count <= 20_000 else {
      throw ServiceError.unavailable("Слишком много записей сна. Выберите другую дату.")
    }
    let samples = records.compactMap { sample -> SleepSample? in
      guard min(sample.endDate, now) > sample.startDate else { return nil }
      let stage: SleepStage
      switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
      case .inBed: stage = .inBed
      case .awake: stage = .awake
      case .asleepCore: stage = .core
      case .asleepDeep: stage = .deep
      case .asleepREM: stage = .rem
      case .asleepUnspecified: stage = .unspecified
      default: return nil
      }
      return SleepSample(
        id: sample.uuid,
        interval: DateInterval(start: sample.startDate, end: min(sample.endDate, now)),
        stage: stage,
        sourceID: sample.sourceRevision.source.bundleIdentifier + "|"
          + (sample.device?.localIdentifier ?? sample.sourceRevision.productType ?? ""),
        sourceName: sample.sourceRevision.source.name,
        fromWatch: sample.sourceRevision.productType?.hasPrefix("Watch") == true)
    }
    return days.map { SleepNight(day: $0, calendar: calendar, samples: samples) }
  }
}
