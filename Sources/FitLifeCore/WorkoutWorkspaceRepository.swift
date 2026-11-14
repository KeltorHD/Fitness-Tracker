import Foundation

/// One personal repository/context; an optional disposable memory workspace for demonstrations.
@MainActor public final class WorkoutWorkspaceRepository: WorkoutRepository {
  private let personal: any WorkoutRepository
  private var demo: MemoryWorkoutRepository?
  public var onTrainingChange: (@MainActor () -> Void)?
  public var personalWritesSuspended = false
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
    // Read every collection before switching; any failed read preserves the demo workspace.
    let snapshot = WorkoutArchive(
      workouts: try personal.workouts(), templates: try personal.templates(),
      bodyWeights: try personal.bodyWeights())
    demo = nil
    return snapshot
  }
  public func workouts() throws -> [Workout] { try current.workouts() }
  public func templates() throws -> [WorkoutTemplate] { try current.templates() }
  public func bodyWeights() throws -> [BodyWeightEntry] { try current.bodyWeights() }
  public func exerciseLinks() throws -> [ExerciseLink] { try current.exerciseLinks() }
  public func personalExerciseLinks() throws -> [ExerciseLink] { try personal.exerciseLinks() }
  public func saveExerciseLink(_ link: ExerciseLink) throws {
    try allowWrite()
    try current.saveExerciseLink(link)
    notifyChange()
  }
  public func deleteExerciseLink(id: UUID) throws {
    try allowWrite()
    try current.deleteExerciseLink(id: id)
    notifyChange()
  }
  public func saveBodyWeight(_ entry: BodyWeightEntry) throws {
    try allowWrite()
    try current.saveBodyWeight(entry)
    notifyChange()
  }
  public func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws {
    try allowWrite()
    try current.saveBodyWeight(entry, updating: workout)
    notifyChange()
  }
  public func deleteBodyWeight(id: UUID) throws {
    try allowWrite()
    try current.deleteBodyWeight(id: id)
    notifyChange()
  }
  public func deleteBodyWeight(id: UUID, updating workout: Workout?) throws {
    try allowWrite()
    try current.deleteBodyWeight(id: id, updating: workout)
    notifyChange()
  }
  public func save(_ workout: Workout) throws {
    try allowWrite()
    try current.save(workout)
    notifyChange()
  }
  public func saveTemplate(_ template: WorkoutTemplate) throws {
    try allowWrite()
    try current.saveTemplate(template)
    notifyChange()
  }
  public func deleteWorkout(id: UUID) throws {
    try allowWrite()
    try current.deleteWorkout(id: id)
    notifyChange()
  }
  public func deleteTemplate(id: UUID) throws {
    try allowWrite()
    try current.deleteTemplate(id: id)
    notifyChange()
  }
  public func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    try allowWrite()
    let result = try current.importArchive(archive)
    if result.hasChanges { notifyChange() }
    return result
  }
  public var trainingAccountSelection: TrainingAccountSelection? {
    (personal as? any TrainingAccountRepository)?.trainingAccountSelection
  }
  public func activateTrainingAccount(_ namespace: String) throws {
    guard demo == nil, let scoped = personal as? any TrainingAccountRepository else {
      throw TrainingSyncError.unsupportedStore
    }
    try scoped.activateTrainingAccount(namespace)
  }
  public func applyTrainingChanges(_ changes: [TrainingChange]) throws {
    guard demo == nil, let scoped = personal as? any TrainingAccountRepository else {
      throw TrainingSyncError.unsupportedStore
    }
    try scoped.applyTrainingChanges(changes)
  }
  private func notifyChange() {
    if demo == nil { onTrainingChange?() }
  }
  private func allowWrite() throws {
    if demo == nil && personalWritesSuspended { throw TrainingSyncError.accountMismatch }
  }
}
