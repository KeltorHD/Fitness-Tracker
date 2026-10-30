import Foundation

/// One personal repository/context; an optional disposable memory workspace for demonstrations.
@MainActor public final class WorkoutWorkspaceRepository: WorkoutRepository {
  private let personal: any WorkoutRepository
  private var demo: MemoryWorkoutRepository?
  public var isDemoMode: Bool { demo != nil }
  private var current: any WorkoutRepository { demo ?? personal }
  public init(personal: any WorkoutRepository) { self.personal = personal }

  public func openDemo(_ archive: WorkoutArchive) throws {
    if demo == nil {
      let unfinished = try personal.workouts().contains { [.active, .paused].contains($0.status) }
      if unfinished { throw TrainingError.invalidState }
    }
    let replacement = MemoryWorkoutRepository()
    _ = try replacement.importArchive(archive)
    demo = replacement
  }
  public func closeDemo() throws -> WorkoutArchive {
    // Read both collections before switching; a failed personal read preserves the demo workspace.
    let snapshot = WorkoutArchive(
      workouts: try personal.workouts(), templates: try personal.templates())
    demo = nil
    return snapshot
  }
  public func workouts() throws -> [Workout] { try current.workouts() }
  public func templates() throws -> [WorkoutTemplate] { try current.templates() }
  public func save(_ workout: Workout) throws { try current.save(workout) }
  public func saveTemplate(_ template: WorkoutTemplate) throws {
    try current.saveTemplate(template)
  }
  public func deleteWorkout(id: UUID) throws { try current.deleteWorkout(id: id) }
  public func deleteTemplate(id: UUID) throws { try current.deleteTemplate(id: id) }
  public func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    try current.importArchive(archive)
  }
}
