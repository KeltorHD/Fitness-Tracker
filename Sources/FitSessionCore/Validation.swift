import Foundation

public enum TrainingError: Error, Equatable, LocalizedError, Sendable {
  case invalidName, invalidRepetitions, invalidWeight, invalidSetCount, invalidRest
  case invalidDate, invalidState, emptyWorkout, missingExercise, missingSet, duplicateID
  public var errorDescription: String? {
    switch self {
    case .invalidName: "Введите название (1–80 символов)."
    case .invalidRepetitions: "Число повторений должно быть от 1 до 1000."
    case .invalidWeight: "Вес должен быть от 0 до 1500 кг."
    case .invalidSetCount: "Добавьте от 1 до 30 подходов."
    case .invalidRest: "Отдых должен быть от 0 до 3600 секунд."
    case .invalidDate: "Некорректное время тренировки."
    case .invalidState: "Действие недоступно в текущем состоянии тренировки."
    case .emptyWorkout: "Выполните хотя бы один подход перед завершением."
    case .missingExercise: "Упражнение не найдено."
    case .missingSet: "Подход не найден."
    case .duplicateID: "Обнаружены повторяющиеся идентификаторы."
    }
  }
}

public enum Validation {
  public static func name(_ value: String) throws {
    guard (1...80).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
      throw TrainingError.invalidName
    }
  }
  public static func set(_ value: WorkoutSet) throws {
    guard (1...1000).contains(value.repetitions) else { throw TrainingError.invalidRepetitions }
    guard value.weightKG.isFinite, (0...1500).contains(value.weightKG) else {
      throw TrainingError.invalidWeight
    }
  }
  public static func template(_ value: WorkoutTemplate) throws {
    try name(value.name)
    guard !value.exercises.isEmpty else { throw TrainingError.emptyWorkout }
    guard (0...3600).contains(value.restSeconds) else { throw TrainingError.invalidRest }
    try unique(value.exercises.map(\.id))
    for exercise in value.exercises {
      try name(exercise.exercise.name)
      guard (1...30).contains(exercise.setCount) else { throw TrainingError.invalidSetCount }
      try set(WorkoutSet(repetitions: exercise.repetitions, weightKG: exercise.weightKG))
    }
  }
  public static func workout(_ value: Workout) throws {
    try name(value.name)
    guard (0...3600).contains(value.restSeconds) else { throw TrainingError.invalidRest }
    guard value.pausedSeconds.isFinite, value.pausedSeconds >= 0,
      value.startedAt.timeIntervalSince1970.isFinite
    else { throw TrainingError.invalidDate }
    if let end = value.endedAt {
      guard end >= value.startedAt, value.pausedSeconds <= end.timeIntervalSince(value.startedAt)
      else {
        throw TrainingError.invalidDate
      }
    }
    guard (value.status == .paused) == (value.pausedAt != nil),
      ([.completed, .cancelled].contains(value.status)) == (value.endedAt != nil)
    else {
      throw TrainingError.invalidState
    }
    if let pause = value.pausedAt, pause < value.startedAt { throw TrainingError.invalidDate }
    var previousEnd = value.startedAt
    for pause in value.pauses {
      guard pause.startedAt >= previousEnd, pause.endedAt >= pause.startedAt,
        pause.endedAt <= (value.endedAt ?? .distantFuture)
      else { throw TrainingError.invalidDate }
      previousEnd = pause.endedAt
    }
    guard abs(value.pauses.reduce(0) { $0 + $1.duration } - value.pausedSeconds) < 0.01 else {
      throw TrainingError.invalidDate
    }
    if let pause = value.pausedAt, pause < previousEnd { throw TrainingError.invalidDate }
    try unique(value.exercises.map(\.id))
    try unique(value.exercises.flatMap(\.sets).map(\.id))
    for exercise in value.exercises {
      try name(exercise.exercise.name)
      guard (1...30).contains(exercise.sets.count) else { throw TrainingError.invalidSetCount }
      for item in exercise.sets {
        try set(item)
        if let date = item.completedAt {
          guard date >= value.startedAt, date <= (value.endedAt ?? .distantFuture) else {
            throw TrainingError.invalidDate
          }
        }
      }
    }
    if value.status == .completed, value.completedSets == 0 { throw TrainingError.emptyWorkout }
  }
  private static func unique(_ ids: [UUID]) throws {
    guard Set(ids).count == ids.count else { throw TrainingError.duplicateID }
  }
}
