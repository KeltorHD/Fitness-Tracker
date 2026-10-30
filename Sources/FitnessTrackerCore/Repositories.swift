import Foundation

@MainActor public protocol WorkoutRepository {
  func workouts() throws -> [Workout]
  func save(_ workout: Workout) throws
  func deleteWorkout(id: UUID) throws
  func templates() throws -> [WorkoutTemplate]
  func saveTemplate(_ template: WorkoutTemplate) throws
  func deleteTemplate(id: UUID) throws
  func bodyWeights() throws -> [BodyWeightEntry]
  func saveBodyWeight(_ entry: BodyWeightEntry) throws
  func deleteBodyWeight(id: UUID) throws
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
  private var measurements: [UUID: BodyWeightEntry] = [:]
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
  public func bodyWeights() throws -> [BodyWeightEntry] {
    measurements.values.sorted {
      $0.measuredAt == $1.measuredAt
        ? $0.id.uuidString < $1.id.uuidString : $0.measuredAt > $1.measuredAt
    }
  }
  public func saveBodyWeight(_ entry: BodyWeightEntry) throws {
    try Validation.bodyWeightEntry(entry)
    measurements[entry.id] = entry
  }
  public func deleteBodyWeight(id: UUID) throws { measurements[id] = nil }
  public func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    let plan = try ArchiveImportPlan(
      archive: archive, existingWorkouts: workouts(), existingTemplates: templates(),
      existingBodyWeights: bodyWeights())
    var nextSessions = sessions
    var nextRoutines = routines
    var nextMeasurements = measurements
    for workout in plan.workouts { nextSessions[workout.id] = workout }
    for template in plan.templates { nextRoutines[template.id] = template }
    for entry in plan.bodyWeights { nextMeasurements[entry.id] = entry }
    sessions = nextSessions
    routines = nextRoutines
    measurements = nextMeasurements
    return plan.summary
  }
}
