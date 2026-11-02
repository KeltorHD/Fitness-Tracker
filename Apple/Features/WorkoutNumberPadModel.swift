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
    self.field = field
    selection = NSRange(location: (text as NSString).length, length: 0)
    clearFeedback()
  }
  func dismiss() {
    field = nil
    selection = NSRange(location: 0, length: 0)
    clearFeedback()
  }
  func reconcile(_ workout: Workout?) {
    guard let field else { return }
    guard let workout, fields(in: workout).contains(field) else {
      dismiss()
      return
    }
    selectText(selection)
  }
  func selectText(_ range: NSRange) {
    let count = (text as NSString).length
    let start = min(range.location, count)
    let newSelection = NSRange(location: start, length: min(range.length, count - start))
    if selection != newSelection { selection = newSelection }
  }
  func digit(_ digit: Int) {
    guard (0...9).contains(digit) else { return }
    let range =
      text == "0" && selection == NSRange(location: 1, length: 0)
      ? NSRange(location: 0, length: 1) : selection
    replaceCharacters(in: range, with: String(digit))
  }
  func decimal() {
    guard field?.isWeight == true else { return }
    let remaining = (text as NSString).replacingCharacters(in: selection, with: "")
    guard !remaining.contains(where: { String($0) == decimalSeparator }) else { return }
    let prefix = (text as NSString).substring(to: selection.location)
    replaceCharacters(in: selection, with: (prefix.isEmpty ? "0" : "") + decimalSeparator)
  }
  func delete() {
    guard field != nil else { return }
    if selection.length > 0 {
      replaceCharacters(in: selection, with: "")
    } else if selection.location > 0 {
      let range = (text as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1)
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
    let value = original.replacingCharacters(in: range, with: normalized)
    guard value.count <= (field.isWeight ? 20 : 4),
      value.filter({ String($0) == decimalSeparator }).count <= 1
    else {
      error =
        (field.isWeight ? TrainingError.invalidWeight : .invalidRepetitions).localizedDescription
      return
    }
    write(value, cursor: range.location + (normalized as NSString).length)
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
    guard workout.status == .active, let row = editor.exercise(in: workout) else { return [] }
    return row.sets.flatMap(\.stages).filter { $0.completedAt == nil }.flatMap {
      [WorkoutSetField.weight($0.id), .repetitions($0.id)]
    }
  }
  private func recipients(in workout: Workout) -> [WorkoutSetField] {
    guard let field else { return [] }
    let ordered = fields(in: workout)
    guard let index = ordered.firstIndex(of: field) else { return [] }
    // Equal weights cannot be propagated into a decreasing-load chain.
    let normalSets = Set(
      (editor.exercise(in: workout)?.sets ?? []).filter { !$0.isDropSet }.map(\.id))
    return ordered.dropFirst(index + 1).filter {
      $0.isWeight == field.isWeight && (!field.isWeight || normalSets.contains($0.setID))
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
