import Foundation

/// Recorded sets retain their original position and snapshot, including warmups and notes.
public struct ExerciseWorkoutHistorySet: Identifiable, Equatable, Sendable {
  public var id: UUID { self.set.id }
  public let position: Int
  public let set: WorkoutSet
}

public struct ExerciseWorkoutHistoryRow: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let position: Int
  public let name: String
  public let sets: [ExerciseWorkoutHistorySet]
}

public struct ExerciseWorkoutHistoryEntry: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let date: Date
  public let name: String
  public let rows: [ExerciseWorkoutHistoryRow]

  /// Uses saved sessions only; template and catalog edits cannot rewrite recorded targets.
  public static func entries(
    for exerciseID: UUID, workouts: [Workout], now: Date = Date(), links: [ExerciseLink] = []
  ) -> [Self] {
    let resolvedID = PersonalExercises.catalogID(for: exerciseID, links: links)
    return workouts.compactMap { workout -> Self? in
      guard workout.status == .completed, workout.startedAt <= now else { return nil }
      let rows = workout.exercises.enumerated().compactMap {
        index, row -> ExerciseWorkoutHistoryRow? in
        guard PersonalExercises.catalogID(for: row.exercise.id, links: links) == resolvedID else {
          return nil
        }
        let sets = row.sets.enumerated().compactMap { index, set -> ExerciseWorkoutHistorySet? in
          guard !set.performedStages.isEmpty else { return nil }
          return ExerciseWorkoutHistorySet(position: index + 1, set: set)
        }
        guard !sets.isEmpty else { return nil }
        return ExerciseWorkoutHistoryRow(
          id: row.id, position: index + 1, name: row.exercise.name, sets: sets)
      }
      guard !rows.isEmpty else { return nil }
      return Self(id: workout.id, date: workout.startedAt, name: workout.name, rows: rows)
    }.sorted {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
    }
  }
}

public struct ExerciseWorkoutHistoryFilter: Equatable, Sendable {
  public enum SortOrder: String, CaseIterable, Sendable { case newest, oldest }
  public enum SetKind: String, CaseIterable, Sendable { case all, working, warmup, dropSet }

  public var query = ""
  public var period = ExerciseProgressPeriod.allTime
  public var setKind = SetKind.all
  public var sortOrder = SortOrder.newest

  public init() {}

  public var hasFilters: Bool { period != .allTime || setKind != .all }
  public var isActive: Bool {
    hasFilters || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  public var isModified: Bool { isActive || sortOrder != .newest }

  public func apply(
    to entries: [ExerciseWorkoutHistoryEntry], now: Date, calendar: Calendar
  ) -> [ExerciseWorkoutHistoryEntry] {
    let start = period.startDate(relativeTo: now, calendar: calendar)
    let tokens = Self.normalize(query).split(whereSeparator: \.isWhitespace)
    return entries.compactMap { entry -> ExerciseWorkoutHistoryEntry? in
      let name = Self.normalize(entry.name)
      guard entry.date <= now, start.map({ entry.date >= $0 }) ?? true,
        tokens.allSatisfy({ name.contains($0) })
      else { return nil }
      guard setKind != .all else { return entry }
      let rows = entry.rows.compactMap { row -> ExerciseWorkoutHistoryRow? in
        let sets = row.sets.filter { recorded in
          switch setKind {
          case .all: true
          case .working: !recorded.set.isWarmup
          case .warmup: recorded.set.isWarmup
          case .dropSet: recorded.set.isDropSet
          }
        }
        guard !sets.isEmpty else { return nil }
        return ExerciseWorkoutHistoryRow(
          id: row.id, position: row.position, name: row.name, sets: sets)
      }
      guard !rows.isEmpty else { return nil }
      return ExerciseWorkoutHistoryEntry(
        id: entry.id, date: entry.date, name: entry.name, rows: rows)
    }.sorted {
      if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
      return sortOrder == .newest ? $0.date > $1.date : $0.date < $1.date
    }
  }

  private static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
  }
}

public enum ExerciseProgressPeriod: String, CaseIterable, Identifiable, Sendable {
  case fourWeeks, twelveWeeks, twentySixWeeks, allTime
  public var id: String { rawValue }

  public func startDate(relativeTo date: Date, calendar: Calendar = .current) -> Date? {
    let weeks: Int
    switch self {
    case .fourWeeks: weeks = 4
    case .twelveWeeks: weeks = 12
    case .twentySixWeeks: weeks = 26
    case .allTime: return nil
    }
    return calendar.date(byAdding: .weekOfYear, value: -weeks, to: date)
  }
}

/// One exercise in one completed workout, combining repeated rows of that exercise.
public struct ExerciseProgressPoint: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let date: Date
  public let maximumWeightKG: Double
  public let volume: Double
  public let estimatedOneRepMaxKG: Double?
  public let repetitions: Int
  public let setCount: Int
}

public struct ExerciseProgressHistory: Identifiable, Equatable, Sendable {
  public var id: UUID { exercise.id }
  public let exercise: Exercise
  public let points: [ExerciseProgressPoint]

  public func points(
    in period: ExerciseProgressPeriod, relativeTo date: Date, calendar: Calendar = .current
  ) -> [ExerciseProgressPoint] {
    let start = period.startDate(relativeTo: date, calendar: calendar)
    return points.filter { point in
      guard point.date <= date else { return false }
      guard let start else { return true }
      return point.date >= start
    }
  }
}

/// Only performed working sets are included. Bodyweight exercises remain available without
/// inventing added load or a one-repetition maximum. No persistence schema changes are needed.
public struct ExerciseProgressReport: Equatable, Sendable {
  public let exercises: [ExerciseProgressHistory]

  public init(workouts: [Workout], now: Date = Date(), links: [ExerciseLink] = []) {
    let completed = workouts.filter { $0.status == .completed && $0.startedAt <= now }.sorted {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
    }
    var definitions: [UUID: Exercise] = [:]
    var histories: [UUID: [ExerciseProgressPoint]] = [:]
    for workout in completed {
      let rows = Dictionary(grouping: workout.exercises) {
        PersonalExercises.catalogID(for: $0.exercise.id, links: links)
      }
      for (exerciseID, items) in rows {
        let sets = items.flatMap(\.sets).filter { $0.completedAt != nil && !$0.isWarmup }
        guard !sets.isEmpty, let exercise = items.last?.exercise else { continue }
        definitions[exerciseID] =
          links.contains(where: { $0.catalogID == exerciseID })
          ? ExerciseLibrary.entry(for: exerciseID)?.exercise ?? exercise : exercise
        histories[exerciseID, default: []].append(
          ExerciseProgressPoint(
            id: workout.id, date: workout.startedAt,
            maximumWeightKG: sets.map(\.weightKG).max() ?? 0,
            volume: sets.reduce(0) { $0 + $1.volume },
            estimatedOneRepMaxKG: sets.compactMap {
              TrainingStatistics.estimatedOneRepMax(
                weightKG: $0.weightKG, repetitions: $0.repetitions)
            }.max(),
            repetitions: sets.reduce(0) { $0 + $1.performedRepetitions }, setCount: sets.count))
      }
    }
    exercises = definitions.values.map {
      ExerciseProgressHistory(exercise: $0, points: histories[$0.id] ?? [])
    }.sorted {
      $0.exercise.name == $1.exercise.name
        ? $0.id.uuidString < $1.id.uuidString : $0.exercise.name < $1.exercise.name
    }
  }
}
