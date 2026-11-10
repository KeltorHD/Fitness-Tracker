import Foundation

public enum SleepStage: String, Codable, CaseIterable, Sendable {
  case inBed, awake, core, deep, rem, unspecified
  public var isAsleep: Bool { self != .awake && self != .inBed }
  fileprivate var priority: Int {
    switch self {
    case .inBed: 0
    case .unspecified: 1
    case .core: 2
    case .deep: 3
    case .rem: 4
    case .awake: 5
    }
  }
}

public struct SleepSample: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let interval: DateInterval
  public let stage: SleepStage
  public let sourceID: String
  public let sourceName: String
  public let fromWatch: Bool
  public init(
    id: UUID = UUID(), interval: DateInterval, stage: SleepStage,
    sourceID: String, sourceName: String, fromWatch: Bool = false
  ) {
    self.id = id
    self.interval = interval
    self.stage = stage
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.fromWatch = fromWatch
  }
}

public struct SleepPeriod: Identifiable, Equatable, Sendable {
  public var id: Date { interval.start }
  public let interval: DateInterval
  public let stage: SleepStage
}

/// A night ends at noon on its diary date; all calendar boundaries include DST/timezone rules.
public struct SleepNight: Identifiable, Equatable, Sendable {
  public var id: Date { day }
  public let day: Date
  public let window: DateInterval
  public let periods: [SleepPeriod]
  public let sourceName: String?
  public let inBed: TimeInterval?
  public var asleep: TimeInterval? {
    let value = periods.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.interval.duration }
    return value > 0 ? value : nil
  }
  public var sleepStart: Date? { periods.first { $0.stage.isAsleep }?.interval.start }
  public var sleepEnd: Date? { periods.last { $0.stage.isAsleep }?.interval.end }
  public var hasStages: Bool { periods.contains { [.core, .deep, .rem].contains($0.stage) } }
  public func duration(_ stage: SleepStage) -> TimeInterval {
    periods.filter { $0.stage == stage }.reduce(0) { $0 + $1.interval.duration }
  }
  public var awakePeriods: Int {
    guard let start = sleepStart, let end = sleepEnd else { return 0 }
    return periods.filter {
      $0.stage == .awake && $0.interval.start >= start && $0.interval.end <= end
    }.count
  }
  public static func window(endingOn day: Date, calendar: Calendar) -> DateInterval? {
    guard let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
      let start = calendar.date(byAdding: .day, value: -1, to: end)
    else { return nil }
    return DateInterval(start: start, end: end)
  }
  public init(day: Date, calendar: Calendar, samples: [SleepSample]) {
    self.day = calendar.startOfDay(for: day)
    window = Self.window(endingOn: day, calendar: calendar) ?? DateInterval(start: day, duration: 0)
    let window = window
    let clipped = samples.filter {
      $0.interval.duration > 0 && $0.interval.start < window.end && $0.interval.end > window.start
    }
    let sources = Dictionary(grouping: clipped, by: \.sourceID)
    // Choose a single source, preferring Watch stages; never add overlapping devices together.
    let chosen =
      sources.keys.sorted { left, right in
        let a = sources[left] ?? []
        let b = sources[right] ?? []
        let aStages = a.contains { [.core, .deep, .rem].contains($0.stage) }
        let bStages = b.contains { [.core, .deep, .rem].contains($0.stage) }
        if aStages != bStages { return aStages }
        let aWatch = a.contains(where: \.fromWatch)
        let bWatch = b.contains(where: \.fromWatch)
        if aWatch != bWatch { return aWatch }
        let aDuration =
          TrackerCalculations.sleepDuration(
            a.filter { $0.stage.isAsleep }.map(\.interval), within: window) ?? 0
        let bDuration =
          TrackerCalculations.sleepDuration(
            b.filter { $0.stage.isAsleep }.map(\.interval), within: window) ?? 0
        return aDuration != bDuration ? aDuration > bDuration : left < right
      }.first.flatMap { sources[$0] } ?? []
    sourceName = chosen.first?.sourceName
    inBed = TrackerCalculations.sleepDuration(
      chosen.filter { $0.stage == .inBed }.map(\.interval), within: window)
    struct Edge {
      let date: Date
      let stage: SleepStage
      let delta: Int
    }
    var edges: [Edge] = []
    for sample in chosen where sample.stage != .inBed {
      edges.append(
        Edge(date: max(sample.interval.start, window.start), stage: sample.stage, delta: 1))
      edges.append(Edge(date: min(sample.interval.end, window.end), stage: sample.stage, delta: -1))
    }
    edges.sort { $0.date < $1.date }
    var counts: [SleepStage: Int] = [:]
    var result: [SleepPeriod] = []
    var previous: Date?
    var index = 0
    while index < edges.count {
      let date = edges[index].date
      if let previous, date > previous,
        let stage = counts.filter({ $0.value > 0 }).keys.max(by: { $0.priority < $1.priority })
      {
        if let last = result.last, last.stage == stage, last.interval.end == previous {
          result[result.count - 1] = SleepPeriod(
            interval: DateInterval(start: last.interval.start, end: date), stage: stage)
        } else {
          result.append(
            SleepPeriod(interval: DateInterval(start: previous, end: date), stage: stage))
        }
      }
      while index < edges.count, edges[index].date == date {
        counts[edges[index].stage, default: 0] += edges[index].delta
        index += 1
      }
      previous = date
    }
    periods = result
  }
}

public struct SleepAlarmPlan: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let fireDate: Date
  public let windowMinutes: Int
  public var windowStart: Date { fireDate.addingTimeInterval(-Double(windowMinutes) * 60) }
  public init(id: UUID = UUID(), fireDate: Date, windowMinutes: Int) {
    self.id = id
    self.fireDate = fireDate
    self.windowMinutes = windowMinutes
  }
  public var isValid: Bool {
    fireDate.timeIntervalSince1970.isFinite && [0, 5, 10, 15, 20, 30].contains(windowMinutes)
  }
  public func canArmWatch(at now: Date) -> Bool {
    isValid && windowMinutes > 0 && fireDate > now
      && windowStart <= now.addingTimeInterval(36 * 3600)
  }
}

public struct SleepAlarmSync: Codable, Equatable, Sendable {
  public let revision: Date
  public let plans: [SleepAlarmPlan]
  public init(revision: Date, plans: [SleepAlarmPlan]) {
    self.revision = revision
    self.plans = plans
  }
  public var isValid: Bool {
    revision.timeIntervalSince1970.isFinite && plans.count <= 10 && plans.allSatisfy(\.isValid)
      && Set(plans.map(\.id)).count == plans.count
  }
}

public struct SleepAlarmWatchEvent: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case armed, alerted, dismissed, failed }
  public let plan: SleepAlarmPlan
  public let kind: Kind
  public let date: Date
  public init(plan: SleepAlarmPlan, kind: Kind, date: Date) {
    self.plan = plan
    self.kind = kind
    self.date = date
  }
  public func canCancelBackup(for candidate: SleepAlarmPlan, now: Date) -> Bool {
    candidate == plan && candidate.isValid && kind == .dismissed && date >= plan.windowStart
      && date <= plan.fireDate.addingTimeInterval(60) && date <= now.addingTimeInterval(30)
  }
}

/// Experimental movement cue after sustained quiet. It does not classify physiological sleep stages.
public struct SmartWakeDetector: Sendable {
  private var previous: Date?
  private var bucketStart: Date?
  private var samples = 0
  private var activeSamples = 0
  private var quietBuckets = 0
  private var activeBuckets = 0
  private var fired = false
  public init() {}
  public mutating func ingest(at date: Date, movement: Double, plan: SleepAlarmPlan) -> Bool {
    guard !fired, plan.isValid, plan.windowMinutes > 0, movement.isFinite, movement >= 0,
      date >= plan.windowStart, date < plan.fireDate.addingTimeInterval(-30),
      previous.map({ date > $0 }) ?? true
    else { return false }
    if let previous, date.timeIntervalSince(previous) > 3 {
      bucketStart = nil
      samples = 0
      activeSamples = 0
      quietBuckets = 0
      activeBuckets = 0
    }
    previous = date
    if bucketStart == nil { bucketStart = date }
    samples += 1
    if movement >= 0.05 { activeSamples += 1 }
    guard let start = bucketStart, date.timeIntervalSince(start) >= 30 else { return false }
    guard samples >= 30 else {
      bucketStart = date
      samples = 0
      activeSamples = 0
      quietBuckets = 0
      activeBuckets = 0
      return false
    }
    let moving = Double(activeSamples) / Double(samples) >= 0.15
    if !moving {
      quietBuckets += 1
      activeBuckets = 0
    } else if quietBuckets >= 2 {
      activeBuckets += 1
    } else {
      quietBuckets = 0
    }
    bucketStart = date
    samples = 0
    activeSamples = 0
    if activeBuckets >= 2 {
      fired = true
      return true
    }
    return false
  }
}

@MainActor public protocol HealthSleepReading {
  func authorize() async throws
  func nights(endingOn day: Date, calendar: Calendar) async throws -> [SleepNight]
}
