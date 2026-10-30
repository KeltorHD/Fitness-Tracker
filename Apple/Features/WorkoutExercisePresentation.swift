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

  func validatedSet(from set: WorkoutSet, unit: WeightUnit) throws -> WorkoutSet {
    var result = set
    if weight == originalText {
      result.weightKG = originalWeightKG
    } else {
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
      result.weightKG = unit.kilograms(from: displayed)
    }
    let input = repetitions.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.count <= 4, input.allSatisfy({ $0.isASCII && $0.isNumber }),
      let count = Int(input)
    else { throw TrainingError.invalidRepetitions }
    result.repetitions = count
    try Validation.set(result)
    return result
  }
}

struct WorkoutSetCompletion {
  let exerciseID: UUID
  let set: WorkoutSet
}

/// Owns selection and unsaved field drafts. Persistence and training rules stay in AppStore/Core.
@MainActor @Observable final class WorkoutExercisePresentation {
  private(set) var exerciseID: UUID
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
  func select(_ setID: UUID, in workout: Workout) {
    guard let set = exercise(in: workout)?.sets.first(where: { $0.id == setID }),
      set.completedAt == nil
    else { return }
    selectedSetID = setID
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
    let pending = workout.exercises.flatMap(\.sets).filter { $0.completedAt == nil }
    let ids = Set(pending.map(\.id))
    drafts = drafts.filter { ids.contains($0.key) }
    for set in pending where drafts[set.id] == nil {
      drafts[set.id] = WorkoutSetDraft(set: set, unit: unit, locale: locale)
    }
    let sets = exercise(in: workout)?.sets ?? []
    if !sets.contains(where: { $0.id == selectedSetID && $0.completedAt == nil }) {
      selectedSetID = sets.first { $0.completedAt == nil }?.id
    }
  }
  func completion(in workout: Workout) throws -> WorkoutSetCompletion {
    guard workout.id == workoutID, workout.status == .active else {
      throw TrainingError.invalidState
    }
    guard let exercise = exercise(in: workout) else { throw TrainingError.missingExercise }
    guard let set = exercise.sets.first(where: { $0.id == selectedSetID }), set.completedAt == nil,
      let draft = drafts[set.id]
    else { throw TrainingError.missingSet }
    return WorkoutSetCompletion(
      exerciseID: exercise.id, set: try draft.validatedSet(from: set, unit: unit))
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
      let weight = unit.display(set.weightKG).formatted(
        .number.locale(numberLocale).precision(.fractionLength(0...1)))
      var text = "\(weight) \(L10n.text(unit.rawValue, locale: locale)) × \(set.repetitions)"
      if let factor = set.loadMultiplier, factor > 1 {
        text = L10n.format("%@ · множитель %@", text, String(factor), locale: locale)
      }
      if set.isWarmup { text += " · " + L10n.text("Разминка", locale: locale) }
      return text
    }.joined(separator: ", ")
  }
}
