import FitLifeCore
import Foundation

/// Isolated UI fixtures require both explicit launch flags and a Debug build.
/// Neither HealthKit records nor system alarms are created by these fixtures.
@MainActor enum SleepUITestFixture {
  static func reader(fallback: any HealthSleepReading = HealthSleepReader())
    -> any HealthSleepReading
  {
    #if DEBUG
      if enabled { return Reader() }
    #endif
    return fallback
  }
  static func scheduler() -> (any SleepAlarmScheduling)? {
    #if DEBUG
      if enabled { return Scheduler() }
    #endif
    return nil
  }
  #if DEBUG
    private static var enabled: Bool {
      let args = ProcessInfo.processInfo.arguments
      return args.contains("--ui-testing") && args.contains("--ui-testing-sleep")
    }
    private final class Reader: HealthSleepReading {
      func authorize() async throws {}
      func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight] {
        (-29...0).compactMap { offset in
          guard let date = calendar.date(byAdding: .day, value: offset, to: day),
            let window = SleepNight.window(endingOn: date, calendar: calendar)
          else { return nil }
          if offset == -4 { return SleepNight(day: date, calendar: calendar, samples: []) }
          let start = window.start.addingTimeInterval(11 * 3600)
          func sample(_ minute: Double, _ length: Double, _ stage: SleepStage) -> SleepSample {
            SleepSample(
              interval: DateInterval(
                start: start.addingTimeInterval(minute * 60), duration: length * 60), stage: stage,
              sourceID: "ui-test", sourceName: "Тестовые данные сна", fromWatch: true)
          }
          return SleepNight(
            day: date, calendar: calendar,
            samples: [
              sample(-20, 520, .inBed), sample(0, 90, .core), sample(90, 65, .deep),
              sample(155, 45, .rem), sample(200, 10, .awake), sample(210, 150, .core),
              sample(360, 40, .deep), sample(400, Double(60 + abs(offset % 3) * 10), .rem),
            ])
        }
      }
    }
    private final class Scheduler: SleepAlarmScheduling {
      private var ids: Set<UUID> = []
      func schedule(_ plan: SleepAlarmPlan) async throws { ids.insert(plan.id) }
      func cancel(_ id: UUID) throws { ids.remove(id) }
      func activeIDs() throws -> Set<UUID> { ids }
    }
  #endif
}
