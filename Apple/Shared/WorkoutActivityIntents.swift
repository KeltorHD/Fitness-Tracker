import AppIntents
import FitSessionCore
import Foundation

struct SetWorkoutPausedIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Пауза или продолжение тренировки"
  static let isDiscoverable = false
  static let openAppWhenRun = false

  @Parameter(title: "Тренировка") var workoutID: String
  @Parameter(title: "На паузе") var paused: Bool

  init() {}
  init(workoutID: UUID, paused: Bool) {
    self.workoutID = workoutID.uuidString
    self.paused = paused
  }

  func perform() async throws -> some IntentResult {
    try await WorkoutIntentExecutor.perform(paused ? .pause : .resume, workoutID: workoutID)
    return .result()
  }
}

struct SkipWorkoutRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Пропустить отдых"
  static let isDiscoverable = false
  static let openAppWhenRun = false

  @Parameter(title: "Тренировка") var workoutID: String
  @Parameter(title: "Окончание отдыха") var restEndsAt: Date

  init() {}
  init(workoutID: UUID, restEndsAt: Date) {
    self.workoutID = workoutID.uuidString
    self.restEndsAt = restEndsAt
  }

  func perform() async throws -> some IntentResult {
    try await WorkoutIntentExecutor.perform(
      .skipRest(expectedEnd: restEndsAt), workoutID: workoutID)
    return .result()
  }
}

@MainActor private enum WorkoutIntentExecutor {
  static func perform(_ action: WorkoutLiveAction, workoutID: String) async throws {
    guard let id = UUID(uuidString: workoutID) else { throw WorkoutIntentError.invalidWorkout }
    #if FITSESSION_APP
      let store = try FitSessionRuntime.store()
      try await store.performLiveAction(action, workoutID: id)
    #else
      // LiveActivityIntent is dispatched to the containing app, never writes from the extension.
      throw WorkoutIntentError.requiresAppProcess
    #endif
  }
}

enum WorkoutIntentError: LocalizedError {
  case invalidWorkout, requiresAppProcess
  var errorDescription: String? {
    switch self {
    case .invalidWorkout: L10n.text("Эта тренировка больше недоступна. Откройте FitSession.")
    case .requiresAppProcess: L10n.text("Действие должно выполняться в приложении FitSession.")
    }
  }
}
