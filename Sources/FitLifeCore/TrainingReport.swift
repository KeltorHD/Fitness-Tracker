import Foundation

public struct ExerciseVolumePoint: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let date: Date
  public let volume: Double
}

public struct TrainingMonthSummary: Equatable, Sendable {
  public let days: [TrainingCalendarDay]
  public let workoutCount: Int
  public let trainingDayFraction: Double

  public init(
    workouts: [Workout], month: Date, now: Date = Date(), calendar: Calendar = .current
  ) {
    days = TrainingJournal.monthDays(
      containing: month, workouts: workouts, now: now, calendar: calendar)
    workoutCount =
      workouts.filter {
        $0.status == .completed && $0.startedAt <= now
          && calendar.isDate($0.startedAt, equalTo: month, toGranularity: .month)
      }.count
    let inMonth = days.filter(\.isInMonth)
    trainingDayFraction = Double(inMonth.filter(\.hasWorkout).count) / Double(max(1, inMonth.count))
  }
}

/// Immutable projection rebuilt when history or the selected month changes, rather than in View.body.
public struct TrainingReport: Equatable, Sendable {
  public let records: [PersonalRecord]
  public let weeks: [WeeklyProgress]
  public let years: [Int]
  public let month: TrainingMonthSummary
  public let exerciseVolumes: [UUID: [ExerciseVolumePoint]]

  public init(
    workouts: [Workout], month: Date, now: Date = Date(), calendar: Calendar = .current
  ) {
    let completed = workouts.filter { $0.status == .completed && $0.startedAt <= now }
    records = TrainingStatistics.records(in: completed)
    weeks = TrainingStatistics.weeks(in: completed, count: 26, now: now, calendar: calendar)
    years = Set(
      completed.map { calendar.component(.year, from: $0.startedAt) }
        + [calendar.component(.year, from: now)]
    ).sorted(by: >)
    self.month = TrainingMonthSummary(
      workouts: completed, month: month, now: now, calendar: calendar)
    var points: [UUID: [ExerciseVolumePoint]] = [:]
    for workout in completed
    where calendar.isDate(
      workout.startedAt, equalTo: month, toGranularity: .year)
    {
      var volumes: [UUID: Double] = [:]
      for item in workout.exercises {
        volumes[item.exercise.id, default: 0] += item.sets.reduce(0) { $0 + $1.volume }
      }
      for (exerciseID, volume) in volumes {
        points[exerciseID, default: []].append(
          ExerciseVolumePoint(id: workout.id, date: workout.startedAt, volume: volume))
      }
    }
    exerciseVolumes = points.mapValues {
      $0.sorted {
        $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
      }
    }
  }
}
