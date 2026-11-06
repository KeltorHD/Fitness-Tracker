import FitnessTrackerCore
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
  private(set) var drafts: [UUID: WorkoutSetDraft] = [:]
  private(set) var previousValues: PreviousWorkoutValues?
  @ObservationIgnored private var history: [Workout] = []
  @ObservationIgnored private var pendingCompletionID: UUID?
  let unit: WeightUnit
  private let locale: Locale
  private let workoutID: UUID

  init(
    workout: Workout, exerciseID: UUID, unit: WeightUnit, locale: Locale, history: [Workout] = []
  ) {
    self.exerciseID = exerciseID
    self.unit = unit
    self.locale = locale
    self.history = history
    workoutID = workout.id
    refresh(workout)
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
    guard let index = index(in: workout), workout.exercises.indices.contains(index + offset) else {
      return
    }
    exerciseID = workout.exercises[index + offset].id
    pendingCompletionID = nil
    selectedSetID = nil
    refresh(workout)
  }
  func showExercise(_ id: UUID, in workout: Workout) {
    guard workout.id == workoutID, workout.exercises.contains(where: { $0.id == id }) else {
      return
    }
    exerciseID = id
    pendingCompletionID = nil
    selectedSetID = nil
    selectedStageID = nil
    refresh(workout)
  }
  func select(_ targetID: UUID, in workout: Workout) {
    guard
      let set = exercise(in: workout)?.sets.first(where: {
        $0.stages.contains { $0.id == targetID && $0.completedAt == nil }
      })
    else { return }
    pendingCompletionID = nil
    selectedSetID = set.id
    selectedStageID = targetID == set.id ? nil : targetID
  }
  func editWeight(_ text: String, setID: UUID) { drafts[setID]?.weight = text }
  func editRepetitions(_ text: String, setID: UUID) { drafts[setID]?.repetitions = text }
  func updateHistory(_ history: [Workout], for workout: Workout) {
    guard workout.id == workoutID else { return }
    self.history = history
    refresh(workout)
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
    previousValues = PreviousWorkoutValues(exerciseRowID: exerciseID, in: workout, history: history)
    let pending = workout.exercises.flatMap(\.sets).flatMap(\.stages).filter {
      $0.completedAt == nil
    }
    let ids = Set(pending.map(\.id))
    drafts = drafts.filter { ids.contains($0.key) }
    for stage in pending {
      let set = WorkoutSet(id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG)
      let previous = previousValues?.stages[stage.id]
      if drafts[stage.id] == nil {
        drafts[stage.id] = WorkoutSetDraft(
          set: set, unit: unit, locale: locale, previous: previous)
      } else {
        drafts[stage.id]?.refresh(set: set, previous: previous, unit: unit, locale: locale)
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
          from: WorkoutSet(id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG),
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
