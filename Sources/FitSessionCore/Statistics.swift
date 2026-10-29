import Foundation

public struct WeeklyProgress: Identifiable, Equatable, Sendable {
  public var id: Date { week }
  public let week: Date
  public let workouts: Int
  public let volume: Double
}
public struct PersonalRecord: Identifiable, Equatable, Sendable {
  public var id: UUID { exercise.id }
  public let exercise: Exercise
  public let weightKG: Double
  public let estimatedOneRepMax: Double
}
public enum TrainingStatistics {
  /// Epley estimate, restricted to working sets of 1–12 reps; no medical/training prescription.
  public static func estimatedOneRepMax(weightKG: Double, repetitions: Int) -> Double? {
    guard weightKG.isFinite, weightKG > 0, weightKG <= 1500, (1...12).contains(repetitions) else {
      return nil
    }
    return repetitions == 1 ? weightKG : weightKG * (1 + Double(repetitions) / 30)
  }
  public static func records(in workouts: [Workout]) -> [PersonalRecord] {
    var records: [UUID: PersonalRecord] = [:]
    for workout in workouts where workout.status == .completed {
      for exercise in workout.exercises {
        let sets = exercise.sets.filter { $0.completedAt != nil && !$0.isWarmup }
        let bestWeight = sets.map(\.weightKG).max() ?? 0
        let bestEstimate =
          sets.compactMap { estimatedOneRepMax(weightKG: $0.weightKG, repetitions: $0.repetitions) }
          .max() ?? 0
        guard bestWeight > 0 else { continue }
        let previous = records[exercise.exercise.id]
        records[exercise.exercise.id] = PersonalRecord(
          exercise: exercise.exercise,
          weightKG: max(previous?.weightKG ?? 0, bestWeight),
          estimatedOneRepMax: max(previous?.estimatedOneRepMax ?? 0, bestEstimate))
      }
    }
    return records.values.sorted { $0.exercise.name < $1.exercise.name }
  }
  public static func weeks(
    in workouts: [Workout], count: Int = 8, now: Date = Date(),
    calendar: Calendar = .current
  ) -> [WeeklyProgress] {
    guard count > 0, count <= 520,
      let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start
    else { return [] }
    return (0..<count).reversed().compactMap { offset in
      guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current),
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
      else { return nil }
      let matches = workouts.filter {
        $0.status == .completed && $0.startedAt >= start && $0.startedAt < end
          && $0.startedAt <= now
      }
      return WeeklyProgress(
        week: start, workouts: matches.count, volume: matches.reduce(0) { $0 + $1.volume })
    }
  }
  /// Consecutive training weeks; an unfinished current week does not break last week's streak.
  public static func weeklyStreak(
    in workouts: [Workout], now: Date = Date(), calendar: Calendar = .current
  ) -> Int {
    let weeks = weeks(in: workouts, count: 520, now: now, calendar: calendar).reversed()
    var streak = 0
    for (index, week) in weeks.enumerated() {
      if index == 0 && week.workouts == 0 { continue }
      guard week.workouts > 0 else { break }
      streak += 1
    }
    return streak
  }
}
