import Foundation

@MainActor public protocol WorkoutRepository {
  func workouts() throws -> [Workout]
  func save(_ workout: Workout) throws
  func deleteWorkout(id: UUID) throws
  func templates() throws -> [WorkoutTemplate]
  func saveTemplate(_ template: WorkoutTemplate) throws
  func deleteTemplate(id: UUID) throws
  /// Validate the complete archive, then add new records in a single transaction or change nothing.
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary
}

@MainActor public protocol HealthWorkoutExporting {
  func requestAuthorization() async throws
  func export(_ workout: Workout) async throws
}

@MainActor public final class MemoryWorkoutRepository: WorkoutRepository {
  private var sessions: [UUID: Workout] = [:]
  private var routines: [UUID: WorkoutTemplate] = [:]
  public init() {}
  public func workouts() throws -> [Workout] {
    sessions.values.sorted { $0.startedAt > $1.startedAt }
  }
  public func save(_ workout: Workout) throws {
    try Validation.workout(workout)
    sessions[workout.id] = workout
  }
  public func deleteWorkout(id: UUID) throws { sessions[id] = nil }
  public func templates() throws -> [WorkoutTemplate] {
    routines.values.sorted { $0.name < $1.name }
  }
  public func saveTemplate(_ template: WorkoutTemplate) throws {
    try Validation.template(template)
    routines[template.id] = template
  }
  public func deleteTemplate(id: UUID) throws { routines[id] = nil }
  public func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    let plan = try ArchiveImportPlan(
      archive: archive, existingWorkouts: workouts(), existingTemplates: templates())
    var nextSessions = sessions
    var nextRoutines = routines
    for workout in plan.workouts { nextSessions[workout.id] = workout }
    for template in plan.templates { nextRoutines[template.id] = template }
    sessions = nextSessions
    routines = nextRoutines
    return plan.summary
  }
}
