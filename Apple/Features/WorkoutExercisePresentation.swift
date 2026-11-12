import FitLifeCore
import Foundation
import Observation

struct WorkoutSetDraft {
  var weight: String {
    get { weightText }
    set {
      weightText = newValue
      weightWasEdited = true
    }
  }
  var repetitions: String {
    get { repetitionText }
    set {
      repetitionText = newValue
      repetitionsWereEdited = true
    }
  }
  private var completedAt: Date?
  private var weightText = ""
  private var repetitionText = ""
  private var weightWasEdited = false
  private var repetitionsWereEdited = false
  private var uneditedWeightKG: Double?
  private let decimalSeparator: String

  init(set: WorkoutSet, unit: WeightUnit, locale: Locale, previous: DropSetStage? = nil) {
    decimalSeparator = locale.decimalSeparator ?? "."
    refresh(set: set, previous: previous, unit: unit, locale: locale)
  }

  /// History is a temporary fallback. Even an explicit clear is a user edit and wins on refresh.
  mutating func refresh(
    set: WorkoutSet, previous: DropSetStage?, unit: WeightUnit, locale: Locale
  ) {
    if completedAt != set.completedAt {
      weightWasEdited = false
      repetitionsWereEdited = false
      completedAt = set.completedAt
    }
    if !weightWasEdited {
      let isEmpty = set.completedAt == nil && set.repetitions == 0 && set.weightKG == 0
      let kilograms = isEmpty ? previous?.weightKG : set.weightKG
      uneditedWeightKG = kilograms
      weightText =
        kilograms.map {
          unit.display($0).formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
        } ?? ""
    }
    if !repetitionsWereEdited {
      let count = set.repetitions > 0 ? set.repetitions : previous?.repetitions
      repetitionText = count.map(String.init) ?? ""
    }
  }

  func weightInKG(unit: WeightUnit) throws -> Double {
    if !weightWasEdited, let uneditedWeightKG {
      try Validation.set(WorkoutSet(repetitions: 1, weightKG: uneditedWeightKG))
      return uneditedWeightKG
    }
    let input = weight.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.count <= 20 else { throw TrainingError.invalidWeight }
    var normalized = ""
    for character in input {
      if let digit = character.wholeNumberValue, (0...9).contains(digit) {
        normalized += String(digit)
      } else if character == "." || character == "," || String(character) == decimalSeparator {
        normalized += "."
      } else {
        throw TrainingError.invalidWeight
      }
    }
    guard let displayed = Double(normalized) else { throw TrainingError.invalidWeight }
    let kilograms = unit.kilograms(from: displayed)
    try Validation.set(WorkoutSet(repetitions: 1, weightKG: kilograms))
    return kilograms
  }
  func repetitionCount() throws -> Int {
    let input = repetitions.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.count <= 4, input.allSatisfy({ $0.isASCII && $0.isNumber }),
      let count = Int(input), (1...1000).contains(count)
    else { throw TrainingError.invalidRepetitions }
    return count
  }
  func validatedSet(from set: WorkoutSet, unit: WeightUnit) throws -> WorkoutSet {
    var result = set
    result.weightKG = try weightInKG(unit: unit)
    result.repetitions = try repetitionCount()
    try Validation.set(
      WorkoutSet(
        repetitions: result.repetitions, weightKG: result.weightKG, isWarmup: result.isWarmup,
        loadMultiplier: result.loadMultiplier))
    return result
  }

  /// Persist complete valid pairs; an absent weight must never turn into an implicit zero load.
  func pendingValues(unit: WeightUnit) -> WorkoutSetInputValues? {
    guard weightWasEdited || repetitionsWereEdited,
      let weight = try? weightInKG(unit: unit), let repetitions = try? repetitionCount()
    else { return nil }
    return WorkoutSetInputValues(repetitions: repetitions, weightKG: weight)
  }
}

/// Session-owned text survives dismissal, including explicit clears and unfinished decimals.
@MainActor @Observable final class WorkoutExerciseDraftStore {
  let workoutID: UUID
  let unit: WeightUnit
  var values: [UUID: WorkoutSetDraft] = [:]

  init(workoutID: UUID, unit: WeightUnit) {
    self.workoutID = workoutID
    self.unit = unit
  }
}

struct WorkoutSetCompletion {
  let requestID = UUID()
  let workoutID: UUID
  let exerciseID: UUID
  let set: WorkoutSet
  var stageID: UUID? = nil
}

enum WorkoutExerciseAdvance { case stay, moved, finished }

/// Owns selection and unsaved field drafts. Persistence and training rules stay in AppStore/Core.
@MainActor @Observable final class WorkoutExercisePresentation {
  private(set) var exerciseID: UUID
  private(set) var selectedStageID: UUID?
  var selectedTargetID: UUID? { selectedStageID ?? selectedSetID }
  private(set) var selectedSetID: UUID?
  private let draftStore: WorkoutExerciseDraftStore
  private(set) var drafts: [UUID: WorkoutSetDraft] {
    get { draftStore.values }
    set { draftStore.values = newValue }
  }
  private(set) var previousValues: PreviousWorkoutValues?
  @ObservationIgnored private var history: [Workout] = []
  @ObservationIgnored private var pendingCompletionID: UUID?
  let unit: WeightUnit
  private let locale: Locale
  private let workoutID: UUID

  init(
    workout: Workout, exerciseID: UUID, unit: WeightUnit, locale: Locale, history: [Workout] = [],
    draftStore: WorkoutExerciseDraftStore? = nil
  ) {
    self.exerciseID = exerciseID
    self.unit = unit
    self.locale = locale
    self.history = history
    workoutID = workout.id
    if let draftStore, draftStore.workoutID == workout.id, draftStore.unit == unit {
      self.draftStore = draftStore
    } else {
      self.draftStore = WorkoutExerciseDraftStore(workoutID: workout.id, unit: unit)
    }
    refresh(workout)
    focusPendingSuperset(in: workout)
  }
  func exercise(in workout: Workout) -> WorkoutExercise? {
    guard workout.id == workoutID else { return nil }
    return workout.exercises.first { $0.id == exerciseID }
  }
  func index(in workout: Workout) -> Int? {
    guard workout.id == workoutID else { return nil }
    return workout.exercises.firstIndex { $0.id == exerciseID }
  }
  func move(_ offset: Int, in workout: Workout) {
    guard workout.id == workoutID else { return }
    let groups = workout.exerciseGroups
    guard let index = groups.firstIndex(where: { $0.exercises.contains { $0.id == exerciseID } }),
      groups.indices.contains(index + offset), let row = groups[index + offset].exercises.first
    else {
      return
    }
    showExercise(row.id, in: workout)
    focusPendingSuperset(in: workout)
  }
  func showExercise(_ id: UUID, in workout: Workout) {
    guard workout.id == workoutID, let row = workout.exercises.first(where: { $0.id == id }) else {
      return
    }
    exerciseID = id
    pendingCompletionID = nil
    selectedSetID = row.sets.first { !$0.isFullyCompleted }?.id
    selectedStageID = nil
    refresh(workout)
  }
  func select(_ targetID: UUID, in workout: Workout) {
    guard
      workout.id == workoutID,
      let row = workout.supersetRows(for: exerciseID).first(where: { row in
        row.sets.contains { $0.stages.contains { $0.id == targetID && $0.completedAt == nil } }
      }),
      let set = row.sets.first(where: {
        $0.stages.contains { $0.id == targetID && $0.completedAt == nil }
      })
    else { return }
    let changesExercise = exerciseID != row.id
    exerciseID = row.id
    pendingCompletionID = nil
    selectedSetID = set.id
    selectedStageID = targetID == set.id ? nil : targetID
    if changesExercise { refresh(workout) }
  }
  func editWeight(_ text: String, setID: UUID) { drafts[setID]?.weight = text }
  func editRepetitions(_ text: String, setID: UUID) { drafts[setID]?.repetitions = text }
  func inheritInput(from sourceID: UUID, for targetID: UUID, in workout: Workout) {
    guard workout.id == workoutID else { return }
    let source = drafts[sourceID]
    refresh(workout)
    guard let source, drafts[targetID] != nil else { return }
    drafts[targetID] = source
  }
  func pendingValues(in workout: Workout, includingCompleted: Bool = false) -> [UUID:
    WorkoutSetInputValues]
  {
    guard workout.id == workoutID else { return [:] }
    var values: [UUID: WorkoutSetInputValues] = [:]
    for stage in workout.exercises.flatMap(\.sets).flatMap(\.stages)
    where includingCompleted || stage.completedAt == nil {
      guard let input = drafts[stage.id]?.pendingValues(unit: unit),
        input.weightKG.map({ $0 != stage.weightKG }) == true
          || input.repetitions.map({ $0 != stage.repetitions }) == true
      else { continue }
      values[stage.id] = input
    }
    return values
  }
  func updateHistory(_ history: [Workout], for workout: Workout) {
    guard workout.id == workoutID else { return }
    self.history = history
    refresh(workout)
  }
  private func focusPendingSuperset(in workout: Workout) {
    guard workout.id == workoutID,
      workout.groupContaining(exerciseID: exerciseID)?.isSuperset == true,
      let next = workout.nextPendingSet(inGroupContaining: exerciseID)
    else { return }
    showExercise(next.exerciseID, in: workout)
    if let set = exercise(in: workout)?.sets.first(where: { $0.id == next.setID }),
      let stage = set.stages.first(where: { $0.completedAt == nil })
    {
      select(stage.id, in: workout)
    }
  }
  func refresh(_ workout: Workout) {
    guard workout.id == workoutID else { return }
    if workout.status != .active { pendingCompletionID = nil }
    if !workout.exercises.contains(where: { $0.id == exerciseID }),
      let first = workout.exercises.first
    {
      exerciseID = first.id
      selectedSetID = nil
    }
    if exercise(in: workout)?.sets.contains(where: {
      $0.id == selectedSetID && !$0.isFullyCompleted
    }) != true,
      let group = workout.groupContaining(exerciseID: exerciseID), group.isSuperset,
      let next = group.nextPendingSet
    {
      exerciseID = next.exerciseID
      selectedSetID = next.setID
      selectedStageID = nil
    }
    previousValues = PreviousWorkoutValues(exerciseRowID: exerciseID, in: workout, history: history)
    let pending = workout.exercises.flatMap(\.sets).flatMap(\.stages)
    let ids = Set(pending.map(\.id))
    drafts = drafts.filter { ids.contains($0.key) }
    for row in workout.exercises {
      let previous = PreviousWorkoutValues(exerciseRowID: row.id, in: workout, history: history)
      for stage in row.sets.flatMap(\.stages) {
        let set = WorkoutSet(
          id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG,
          completedAt: stage.completedAt)
        if drafts[stage.id] == nil {
          drafts[stage.id] = WorkoutSetDraft(
            set: set, unit: unit, locale: locale, previous: previous?.stages[stage.id])
        } else {
          drafts[stage.id]?.refresh(
            set: set, previous: previous?.stages[stage.id], unit: unit, locale: locale)
        }
      }
    }
    let sets = exercise(in: workout)?.sets ?? []
    if !sets.contains(where: { $0.id == selectedSetID && !$0.isFullyCompleted }) {
      selectedSetID = sets.first { !$0.isFullyCompleted }?.id
      selectedStageID = nil
    }
    if let set = sets.first(where: { $0.id == selectedSetID }) {
      if !set.stages.contains(where: { $0.id == selectedTargetID && $0.completedAt == nil }) {
        let target = set.stages.first { $0.completedAt == nil }?.id
        selectedStageID = target == set.id ? nil : target
      }
    } else {
      selectedStageID = nil
    }
  }
  private func preparedSet(_ set: WorkoutSet) throws -> WorkoutSet {
    var prepared = set
    if set.completedAt == nil, let draft = drafts[set.id] {
      prepared = try draft.validatedSet(from: set, unit: unit)
    }
    if let stages = set.dropStages {
      prepared.dropStages = try stages.map { stage in
        guard stage.completedAt == nil, let draft = drafts[stage.id] else { return stage }
        let value = try draft.validatedSet(
          from: WorkoutSet(
            id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG,
            completedAt: stage.completedAt),
          unit: unit)
        return DropSetStage(id: stage.id, repetitions: value.repetitions, weightKG: value.weightKG)
      }
    }
    try Validation.set(prepared)
    return prepared
  }
  func completion(in workout: Workout) throws -> WorkoutSetCompletion {
    guard workout.id == workoutID, workout.status == .active else {
      throw TrainingError.invalidState
    }
    guard let row = exercise(in: workout) else { throw TrainingError.missingExercise }
    guard let set = row.sets.first(where: { $0.id == selectedSetID }), !set.isFullyCompleted else {
      throw TrainingError.missingSet
    }
    guard set.stages.first(where: { $0.completedAt == nil })?.id == selectedTargetID else {
      throw TrainingError.invalidDropStageOrder
    }
    let completion = WorkoutSetCompletion(
      workoutID: workoutID, exerciseID: row.id, set: try preparedSet(set), stageID: selectedStageID)
    pendingCompletionID = completion.requestID
    return completion
  }

  /// The caller invokes this only after saving the exact requested completion successfully.
  /// It advances presentation; finishing the workout remains a separate explicit action.
  func advance(afterSaving completion: WorkoutSetCompletion, in workout: Workout)
    -> WorkoutExerciseAdvance
  {
    guard workout.id == workoutID, completion.workoutID == workoutID,
      workout.status == .active, completion.requestID == pendingCompletionID,
      exerciseID == completion.exerciseID,
      let index = workout.exercises.firstIndex(where: { $0.id == completion.exerciseID }),
      let saved = workout.exercises[index].sets.first(where: { $0.id == completion.set.id })
    else { return .stay }
    var beforeCompletion = saved
    if let stageID = completion.stageID {
      guard let stageIndex = beforeCompletion.dropStages?.firstIndex(where: { $0.id == stageID }),
        beforeCompletion.dropStages?[stageIndex].completedAt != nil,
        completion.set.dropStages?.first(where: { $0.id == stageID })?.completedAt == nil
      else { return .stay }
      beforeCompletion.dropStages?[stageIndex].completedAt = nil
    } else {
      guard saved.completedAt != nil, completion.set.completedAt == nil else { return .stay }
      beforeCompletion.completedAt = nil
    }
    guard beforeCompletion == completion.set else { return .stay }
    pendingCompletionID = nil
    if saved.isFullyCompleted,
      workout.groupContaining(exerciseID: completion.exerciseID)?.isSuperset == true,
      let next = workout.nextPendingSet(inGroupContaining: completion.exerciseID)
    {
      let moved = exerciseID != next.exerciseID
      showExercise(next.exerciseID, in: workout)
      if let nextSet = exercise(in: workout)?.sets.first(where: { $0.id == next.setID }),
        let target = nextSet.stages.first(where: { $0.completedAt == nil })
      {
        select(target.id, in: workout)
      }
      return moved ? .moved : .stay
    }
    refresh(workout)
    guard WorkoutCompletionProgress(exercise: workout.exercises[index]).isComplete else {
      return .stay
    }
    let candidates =
      Array(workout.exercises.indices.dropFirst(index + 1))
      + Array(workout.exercises.indices.prefix(index))
    if let next = candidates.first(where: {
      let progress = WorkoutCompletionProgress(exercise: workout.exercises[$0])
      return progress.completed < progress.total
    }) {
      showExercise(workout.exercises[next].id, in: workout)
      focusPendingSuperset(in: workout)
      return .moved
    }
    return .finished
  }
  func configuredDropSet(in workout: Workout, adding: Bool, setID: UUID? = nil) throws -> WorkoutSet
  {
    guard workout.id == workoutID, workout.status == .active,
      let set = exercise(in: workout)?.sets.first(where: { $0.id == (setID ?? selectedSetID) }),
      set.completedAt == nil || (adding && set.isDropSet && !set.isFullyCompleted)
    else { throw TrainingError.invalidState }
    if !adding {
      var plain = set
      plain.dropStages = nil
      if let draft = drafts[set.id] { plain = try draft.validatedSet(from: plain, unit: unit) }
      try Validation.set(plain)
      return plain
    }
    var result = try preparedSet(set)
    guard !set.isWarmup, (result.dropStages ?? []).count < 5,
      let last = result.stages.last, last.weightKG > 0
    else { throw TrainingError.invalidDropSet }
    result.dropStages =
      (result.dropStages ?? []) + [
        DropSetStage(repetitions: last.repetitions, weightKG: last.weightKG * 0.8)
      ]
    try Validation.set(result)
    return result
  }

}

enum WorkoutExerciseSummary {
  static func text(
    _ row: WorkoutExercise, completedOnly: Bool, unit: WeightUnit, locale: Locale,
    numberLocale: Locale
  ) -> String {
    let sets = completedOnly ? row.sets.filter { $0.completedAt != nil } : row.sets
    guard !sets.isEmpty else { return L10n.text("Нет выполненных подходов", locale: locale) }
    if sets.allSatisfy({ $0.completedAt == nil && $0.repetitions == 0 && $0.weightKG == 0 }) {
      return L10n.countText(sets.count, kind: "set", locale: locale)
    }
    return sets.map { set in
      let stages = completedOnly ? set.performedStages : set.stages
      var text = stages.map { stage in
        if stage.completedAt == nil, stage.repetitions == 0, stage.weightKG == 0 { return "—" }
        let weight = unit.display(stage.weightKG).formatted(
          .number.locale(numberLocale).precision(.fractionLength(0...1)))
        return "\(weight) \(L10n.text(unit.rawValue, locale: locale)) × \(stage.repetitions)"
      }.joined(separator: " → ")
      if set.isDropSet { text = L10n.text("Дропсет", locale: locale) + ": " + text }
      if let factor = set.loadMultiplier, factor > 1 {
        text = L10n.format("%@ · множитель %@", text, String(factor), locale: locale)
      }
      if set.isWarmup { text += " · " + L10n.text("Разминка", locale: locale) }
      return text
    }.joined(separator: ", ")
  }
}
