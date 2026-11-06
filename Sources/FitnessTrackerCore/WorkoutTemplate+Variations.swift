import Foundation

/// An alternative exercise plan belonging to the same template and schedule.
public struct WorkoutTemplateVariation: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var exercises: [TemplateExercise]

  public init(id: UUID = UUID(), name: String, exercises: [TemplateExercise]) {
    self.id = id
    self.name = name
    self.exercises = exercises
  }
}

extension WorkoutTemplate {
  public func variation(id: UUID) -> WorkoutTemplateVariation? {
    variations.first { $0.id == id }
  }

  /// Resolves only the selected plan; changing the start selection never edits the saved template.
  public func resolvedVariation(id: UUID?) throws -> WorkoutTemplate {
    var result = self
    if let id, id != self.id {
      guard let selected = variation(id: id) else { throw TrainingError.missingTemplateVariation }
      result.exercises = selected.exercises
    }
    result.variations = []
    try Validation.template(result)
    return result
  }

  /// Creates an editable alternative with independent row, stage and superset identities.
  /// Empty editor drafts can be copied; saving still validates every complete variation.
  public func makeVariation(name: String, copying variationID: UUID? = nil) throws
    -> WorkoutTemplateVariation
  {
    try Validation.name(name)
    let source: [TemplateExercise]
    if let variationID, variationID != id {
      guard let variation = variation(id: variationID) else {
        throw TrainingError.missingTemplateVariation
      }
      source = variation.exercises
    } else {
      source = exercises
    }
    var groups: [UUID: UUID] = [:]
    let rows = source.map { row in
      TemplateExercise(
        exercise: row.exercise, setCount: row.setCount,
        repetitions: row.repetitions, weightKG: row.weightKG,
        loadMultiplier: row.loadMultiplier,
        plannedSets: row.plannedSets?.map { $0.freshCopy() },
        supersetID: row.supersetID.map { id in
          if let existing = groups[id] { return existing }
          let new = UUID()
          groups[id] = new
          return new
        })
    }
    return WorkoutTemplateVariation(name: name, exercises: rows)
  }
}

extension TemplateExercise {
  /// Removing or moving draft rows dissolves groups that no longer form a contiguous superset.
  public static func normalizingSupersets(_ rows: [TemplateExercise]) -> [TemplateExercise] {
    let invalid = SupersetStructure.invalidIDs(in: rows.map(\.supersetID))
    return rows.map { row in
      var copy = row
      if let id = row.supersetID, invalid.contains(id) { copy.supersetID = nil }
      return copy
    }
  }
}
