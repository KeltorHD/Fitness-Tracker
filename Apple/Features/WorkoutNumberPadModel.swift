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
  private(set) var replacesOnInput = false
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
    self.field = field
    replacesOnInput = true
    clearFeedback()
    editor.select(field.setID, in: workout)
  }
  func dismiss() {
    field = nil
    replacesOnInput = false
    clearFeedback()
  }
  func reconcile(_ workout: Workout?) {
    guard let field else { return }
    guard let workout, fields(in: workout).contains(field) else {
      dismiss()
      return
    }
  }
  func digit(_ digit: Int) {
    guard (0...9).contains(digit), let field, editor.drafts[field.setID] != nil else { return }
    let previous = replacesOnInput ? "" : text
    let value = previous == "0" ? String(digit) : previous + String(digit)
    guard value.count <= (field.isWeight ? 20 : 4) else {
      error =
        (field.isWeight ? TrainingError.invalidWeight : .invalidRepetitions).localizedDescription
      return
    }
    write(value)
  }
  func decimal() {
    guard field?.isWeight == true else { return }
    let previous = replacesOnInput ? "" : text
    guard !previous.contains(where: { $0 == "." || $0 == "," || String($0) == decimalSeparator })
    else { return }
    write((previous.isEmpty ? "0" : previous) + decimalSeparator)
  }
  func delete() {
    guard field != nil else { return }
    write(replacesOnInput ? "" : String(text.dropLast()))
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
  private func write(_ value: String) {
    guard let field, editor.drafts[field.setID] != nil else { return }
    if field.isWeight {
      editor.editWeight(value, setID: field.setID)
    } else {
      editor.editRepetitions(value, setID: field.setID)
    }
    replacesOnInput = false
    clearFeedback()
  }
  private func clearFeedback() {
    error = nil
    copiedRows = nil
  }
}
