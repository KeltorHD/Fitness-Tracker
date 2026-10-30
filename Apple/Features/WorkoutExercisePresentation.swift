import FitnessTrackerCore
import Foundation
import Observation

struct WorkoutSetDraft {
  var weight: String
  var repetitions: String
  private let originalWeightKG: Double
  private let originalText: String
  private let decimalSeparator: String

  init(set: WorkoutSet, unit: WeightUnit, locale: Locale) {
    weight = unit.display(set.weightKG).formatted(
      .number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
    repetitions = String(set.repetitions)
    originalWeightKG = set.weightKG
    originalText = weight
    decimalSeparator = locale.decimalSeparator ?? "."
  }

  func weightInKG(unit: WeightUnit) throws -> Double {
    if weight == originalText {
      try Validation.set(WorkoutSet(repetitions: 1, weightKG: originalWeightKG))
      return originalWeightKG
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
  let exerciseID: UUID
  let set: WorkoutSet
  var stageID: UUID? = nil
}

/// Owns selection and unsaved field drafts. Persistence and training rules stay in AppStore/Core.
@MainActor @Observable final class WorkoutExercisePresentation {
  private(set) var exerciseID: UUID
  private(set) var selectedStageID: UUID?
  var selectedTargetID: UUID? { selectedStageID ?? selectedSetID }
  private(set) var selectedSetID: UUID?
  private(set) var drafts: [UUID: WorkoutSetDraft] = [:]
  let unit: WeightUnit
  private let locale: Locale
  private let workoutID: UUID

  init(workout: Workout, exerciseID: UUID, unit: WeightUnit, locale: Locale) {
    self.exerciseID = exerciseID
    self.unit = unit
    self.locale = locale
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
    selectedSetID = nil
    refresh(workout)
  }
  func select(_ targetID: UUID, in workout: Workout) {
    guard
      let set = exercise(in: workout)?.sets.first(where: {
        $0.stages.contains { $0.id == targetID && $0.completedAt == nil }
      })
    else { return }
    selectedSetID = set.id
    selectedStageID = targetID == set.id ? nil : targetID
  }
  func editWeight(_ text: String, setID: UUID) { drafts[setID]?.weight = text }
  func editRepetitions(_ text: String, setID: UUID) { drafts[setID]?.repetitions = text }
  func refresh(_ workout: Workout) {
    guard workout.id == workoutID else { return }
    if !workout.exercises.contains(where: { $0.id == exerciseID }),
      let first = workout.exercises.first
    {
      exerciseID = first.id
      selectedSetID = nil
    }
    let pending = workout.exercises.flatMap(\.sets).flatMap(\.stages).filter {
      $0.completedAt == nil
    }
    let ids = Set(pending.map(\.id))
    drafts = drafts.filter { ids.contains($0.key) }
    for stage in pending where drafts[stage.id] == nil {
      drafts[stage.id] = WorkoutSetDraft(
        set: WorkoutSet(id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG),
        unit: unit, locale: locale)
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
    return WorkoutSetCompletion(
      exerciseID: row.id, set: try preparedSet(set), stageID: selectedStageID)
  }
  func configuredDropSet(in workout: Workout, adding: Bool) throws -> WorkoutSet {
    guard workout.id == workoutID, workout.status == .active,
      let set = exercise(in: workout)?.sets.first(where: { $0.id == selectedSetID }),
      set.completedAt == nil
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
    return sets.map { set in
      let stages = completedOnly ? set.performedStages : set.stages
      var text = stages.map { stage in
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
