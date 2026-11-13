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
  /// Save a weigh-in and its optional ongoing-session snapshot together, or change neither.
  func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws
  func deleteBodyWeight(id: UUID) throws
  /// Remove a shared weigh-in and update its optional session snapshot atomically.
  func deleteBodyWeight(id: UUID, updating workout: Workout?) throws
  /// Validate the complete archive, then add new records in a single transaction or change nothing.
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary
}

extension WorkoutRepository {
  public func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws {
    // A repository without multi-record transactions must reject before making the first write.
    guard workout == nil else { throw TrainingError.invalidState }
    try saveBodyWeight(entry)
  }
  public func deleteBodyWeight(id: UUID, updating workout: Workout?) throws {
    guard workout == nil else { throw TrainingError.invalidState }
    try deleteBodyWeight(id: id)
  }
}

@MainActor public protocol HealthWorkoutExporting {
  func requestAuthorization() async throws
  func export(_ workout: Workout) async throws
}

@MainActor public final class MemoryWorkoutRepository: TrainingAccountRepository {
  public private(set) var trainingAccountSelection = TrainingAccountSelection()
  private var accountJournals: [String: TrainingJournalSnapshot] = [:]
  private var sessions: [UUID: Workout] = [:]
  private var routines: [UUID: WorkoutTemplate] = [:]
  private var nutrition = MemoryNutritionRepository()
  private var accountNutrition: [String: MemoryNutritionRepository] = [:]
  private var measurements: [UUID: BodyWeightEntry] = [:]
  public init() {}

  public func activateTrainingAccount(_ namespace: String) throws {
    try TrainingAccountSelection(firstAccountID: namespace, currentAccountID: namespace).validate()
    guard trainingAccountSelection.currentAccountID != namespace else { return }
    if trainingAccountSelection.firstAccountID == nil {
      trainingAccountSelection = TrainingAccountSelection(
        firstAccountID: namespace, currentAccountID: namespace)
      return
    }
    guard !sessions.values.contains(where: { [.active, .paused].contains($0.status) }) else {
      throw TrainingSyncError.activeWorkout
    }
    if let previous = trainingAccountSelection.currentAccountID {
      accountNutrition[previous] = nutrition
      accountJournals[previous] = TrainingJournalSnapshot(
        workouts: Array(sessions.values), templates: Array(routines.values),
        bodyWeights: Array(measurements.values))
    }
    let journal =
      accountJournals[namespace]
      ?? TrainingJournalSnapshot(workouts: [], templates: [], bodyWeights: [])
    nutrition = accountNutrition[namespace] ?? MemoryNutritionRepository()
    sessions = Dictionary(uniqueKeysWithValues: journal.workouts.map { ($0.id, $0) })
    routines = Dictionary(uniqueKeysWithValues: journal.templates.map { ($0.id, $0) })
    measurements = Dictionary(uniqueKeysWithValues: journal.bodyWeights.map { ($0.id, $0) })
    trainingAccountSelection.currentAccountID = namespace
  }

  public func applyTrainingChanges(_ changes: [TrainingChange]) throws {
    let next = try TrainingJournalSnapshot(
      workouts: workouts(), templates: templates(), bodyWeights: bodyWeights()
    ).applying(changes)
    try nutrition.applyTrainingChanges(changes.filter { $0.key.kind.isNutrition })
    sessions = Dictionary(uniqueKeysWithValues: next.workouts.map { ($0.id, $0) })
    routines = Dictionary(uniqueKeysWithValues: next.templates.map { ($0.id, $0) })
    measurements = Dictionary(uniqueKeysWithValues: next.bodyWeights.map { ($0.id, $0) })
  }
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
  public func saveBodyWeight(_ entry: BodyWeightEntry, updating workout: Workout?) throws {
    try Validation.bodyWeightEntry(entry)
    if let workout { try Validation.workout(workout) }
    // All throwing validation precedes both writes.
    measurements[entry.id] = entry
    if let workout { sessions[workout.id] = workout }
  }
  public func deleteBodyWeight(id: UUID) throws { measurements[id] = nil }
  public func deleteBodyWeight(id: UUID, updating workout: Workout?) throws {
    if let workout { try Validation.workout(workout) }
    measurements[id] = nil
    if let workout { sessions[workout.id] = workout }
  }
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

// Used by UI tests with the same nutrition contract as the production repository.
extension MemoryWorkoutRepository: NutritionRepository {
  public func foodEntries() throws -> [FoodEntry] { try nutrition.foodEntries() }
  public func saveFoodEntry(_ entry: FoodEntry) throws { try nutrition.saveFoodEntry(entry) }
  public func saveFoodEntries(_ entries: [FoodEntry]) throws {
    try nutrition.saveFoodEntries(entries)
  }
  public func deleteFoodEntry(id: UUID) throws { try nutrition.deleteFoodEntry(id: id) }
  public func nutritionGoal() throws -> NutritionGoal? { try nutrition.nutritionGoal() }
  public func saveNutritionGoal(_ goal: NutritionGoal?) throws {
    try nutrition.saveNutritionGoal(goal)
  }
  public func waterEntries() throws -> [WaterEntry] { try nutrition.waterEntries() }
  public func saveWaterEntry(_ entry: WaterEntry) throws { try nutrition.saveWaterEntry(entry) }
  public func deleteWaterEntry(id: UUID) throws { try nutrition.deleteWaterEntry(id: id) }
  public func supplementEntries() throws -> [SupplementEntry] { try nutrition.supplementEntries() }
  public func saveSupplementEntry(_ entry: SupplementEntry) throws {
    try nutrition.saveSupplementEntry(entry)
  }
  public func deleteSupplementEntry(id: UUID) throws {
    try nutrition.deleteSupplementEntry(id: id)
  }
  public func supplementPlans() throws -> [SupplementPlan] { try nutrition.supplementPlans() }
  public func saveSupplementPlan(_ plan: SupplementPlan) throws {
    try nutrition.saveSupplementPlan(plan)
  }
  public func deleteSupplementPlan(id: UUID) throws { try nutrition.deleteSupplementPlan(id: id) }
  public func favoriteFoodProducts() throws -> [FoodProduct] {
    try nutrition.favoriteFoodProducts()
  }
  public func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws {
    try nutrition.setFavoriteFoodProduct(product, isFavorite: isFavorite)
  }
}
