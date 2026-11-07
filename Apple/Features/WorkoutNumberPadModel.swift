import FitnessTrackerCore
import Foundation
import Observation

enum WorkoutSetField: Hashable, Sendable {
  case weight(UUID)
  case repetitions(UUID)
  var setID: UUID {
    switch self {
    case .weight(let id), .repetitions(let id): id
    }
  }
  var isWeight: Bool {
    if case .weight = self { true } else { false }
  }
}

/// A field editor over the existing unsaved drafts; it never completes or persists a set.
@MainActor @Observable final class WorkoutNumberPadModel {
  private(set) var field: WorkoutSetField?
  private(set) var selection = NSRange(location: 0, length: 0)
  private(set) var error: String?
  private(set) var copiedRows: Int?
  let decimalSeparator: String
  @ObservationIgnored private let editor: WorkoutExercisePresentation
  @ObservationIgnored private var replacesOnFirstInsertion = false

  init(editor: WorkoutExercisePresentation, locale: Locale) {
    self.editor = editor
    decimalSeparator = locale.decimalSeparator ?? "."
  }
  var text: String {
    guard let field, let draft = editor.drafts[field.setID] else { return "" }
    return field.isWeight ? draft.weight : draft.repetitions
  }
  func begin(_ field: WorkoutSetField, in workout: Workout) {
    guard fields(in: workout).contains(field) else { return }
    guard self.field != field else { return }
    if workout.groupContaining(exerciseID: editor.exerciseID)?.isSuperset == true {
      editor.select(field.setID, in: workout)
    }
    self.field = field
    selection = NSRange(location: (text as NSString).length, length: 0)
    replacesOnFirstInsertion = true
    clearFeedback()
  }
  func dismiss() {
    field = nil
    selection = NSRange(location: 0, length: 0)
    replacesOnFirstInsertion = false
    clearFeedback()
  }
  func reconcile(_ workout: Workout?) {
    guard let field else { return }
    guard let workout, fields(in: workout).contains(field) else {
      dismiss()
      return
    }
    let clamped = clampedSelection(selection)
    if clamped != selection { selection = clamped }
  }
  func beginSelectionInteraction() { replacesOnFirstInsertion = false }
  func selectText(_ range: NSRange, userInitiated: Bool = true) {
    guard userInitiated || !replacesOnFirstInsertion else { return }
    let newSelection = clampedSelection(range)
    if userInitiated { beginSelectionInteraction() }
    if selection != newSelection {
      selection = newSelection
    }
  }
  private func clampedSelection(_ range: NSRange) -> NSRange {
    let count = (text as NSString).length
    let start = min(range.location, count)
    return NSRange(location: start, length: min(range.length, count - start))
  }
  func digit(_ digit: Int) {
    guard (0...9).contains(digit) else { return }
    let current = clampedSelection(selection)
    let range =
      text == "0" && current == NSRange(location: 1, length: 0)
      ? NSRange(location: 0, length: 1) : current
    replaceCharacters(in: range, with: String(digit))
  }
  func decimal() {
    guard field?.isWeight == true else { return }
    let range = insertionRange(clampedSelection(selection))
    let remaining = (text as NSString).replacingCharacters(in: range, with: "")
    guard !remaining.contains(where: { String($0) == decimalSeparator }) else { return }
    let prefix = (text as NSString).substring(to: range.location)
    replaceCharacters(in: range, with: (prefix.isEmpty ? "0" : "") + decimalSeparator)
  }
  func delete() {
    guard field != nil else { return }
    let current = clampedSelection(selection)
    if current.length > 0 {
      replaceCharacters(in: current, with: "")
    } else if current.location > 0 {
      let range = (text as NSString).rangeOfComposedCharacterSequence(at: current.location - 1)
      replaceCharacters(in: range, with: "")
    }
  }
  func clear() {
    guard field != nil else { return }
    write("")
  }
  /// Also handles native paste and hardware keyboard edits using UITextInput's UTF-16 ranges.
  func replaceCharacters(in range: NSRange, with replacement: String) {
    guard let field, editor.drafts[field.setID] != nil else { return }
    let original = text as NSString
    guard range.location <= original.length, range.length <= original.length - range.location else {
      return
    }
    var normalized = ""
    for character in replacement {
      if let digit = character.wholeNumberValue, (0...9).contains(digit) {
        normalized += String(digit)
      } else if field.isWeight
        && (character == "." || character == "," || String(character) == decimalSeparator)
      {
        normalized += decimalSeparator
      } else {
        error =
          (field.isWeight ? TrainingError.invalidWeight : .invalidRepetitions).localizedDescription
        return
      }
    }
    let targetRange = normalized.isEmpty ? range : insertionRange(range)
    let value = original.replacingCharacters(in: targetRange, with: normalized)
    guard value.count <= (field.isWeight ? 20 : 4),
      value.filter({ String($0) == decimalSeparator }).count <= 1
    else {
      error =
        (field.isWeight ? TrainingError.invalidWeight : .invalidRepetitions).localizedDescription
      return
    }
    write(value, cursor: targetRange.location + (normalized as NSString).length)
  }
  private func insertionRange(_ range: NSRange) -> NSRange {
    replacesOnFirstInsertion ? NSRange(location: 0, length: (text as NSString).length) : range
  }
  func advance(in workout: Workout) {
    guard let field else { return }
    let ordered = fields(in: workout)
    guard let index = ordered.firstIndex(of: field) else {
      dismiss()
      return
    }
    do {
      try validateField()
      if ordered.indices.contains(index + 1) {
        begin(ordered[index + 1], in: workout)
      } else {
        dismiss()
      }
    } catch { self.error = error.localizedDescription }
  }
  func canCopy(in workout: Workout) -> Bool { !recipients(in: workout).isEmpty }
  func copyDown(in workout: Workout) {
    do {
      try validateField()
      let targets = recipients(in: workout)
      guard !targets.isEmpty else { return }
      let value = text
      for target in targets {
        if target.isWeight {
          editor.editWeight(value, setID: target.setID)
        } else {
          editor.editRepetitions(value, setID: target.setID)
        }
      }
      error = nil
      copiedRows = targets.count
    } catch { self.error = error.localizedDescription }
  }
  private func fields(in workout: Workout) -> [WorkoutSetField] {
    guard workout.status == .active, editor.exercise(in: workout) != nil else { return [] }
    let rows = workout.supersetRows(for: editor.exerciseID)
    let rounds = rows.map { $0.sets.count }.max() ?? 0
    let sets = (0..<rounds).flatMap { index in
      rows.compactMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil }
    }
    return sets.flatMap(\.stages).filter { $0.completedAt == nil }.flatMap {
      [WorkoutSetField.weight($0.id), .repetitions($0.id)]
    }
  }
  private func recipients(in workout: Workout) -> [WorkoutSetField] {
    guard let field else { return [] }
    let ordered = fields(in: workout)
    guard let index = ordered.firstIndex(of: field) else { return [] }
    // Equal weights cannot be propagated into a decreasing-load chain.
    guard
      let owner = workout.exercises.first(where: {
        $0.sets.contains { $0.stages.contains { $0.id == field.setID } }
      })
    else { return [] }
    let ownerTargets = Set(owner.sets.flatMap(\.stages).map(\.id))
    let normalSets = Set(owner.sets.filter { !$0.isDropSet }.map(\.id))
    return ordered.dropFirst(index + 1).filter {
      ownerTargets.contains($0.setID) && $0.isWeight == field.isWeight
        && (!field.isWeight || normalSets.contains($0.setID))
    }
  }
  private func validateField() throws {
    guard let field, let draft = editor.drafts[field.setID] else { throw TrainingError.missingSet }
    if field.isWeight {
      _ = try draft.weightInKG(unit: editor.unit)
    } else {
      _ = try draft.repetitionCount()
    }
  }
  private func write(_ value: String, cursor: Int = 0) {
    guard let field, editor.drafts[field.setID] != nil else { return }
    replacesOnFirstInsertion = false
    if field.isWeight {
      editor.editWeight(value, setID: field.setID)
    } else {
      editor.editRepetitions(value, setID: field.setID)
    }
    selection = NSRange(location: cursor, length: 0)
    clearFeedback()
  }
  private func clearFeedback() {
    error = nil
    copiedRows = nil
  }
}
