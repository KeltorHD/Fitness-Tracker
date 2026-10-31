import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class ExerciseLibraryViewModel {
  var search = "" { didSet { refresh() } }
  var groups: Set<MuscleGroup> { didSet { refresh() } }
  var equipment: ExerciseEquipment? { didSet { refresh() } }
  var language: AppLanguage = .russian { didSet { refresh() } }
  private(set) var results: [ExerciseLibraryEntry]
  private(set) var loadingError = ExerciseLibrary.loadingError
  @ObservationIgnored private let find:
    (String, Set<MuscleGroup>, ExerciseEquipment?, AppLanguage) -> [ExerciseLibraryEntry]

  init(
    groups: Set<MuscleGroup> = [],
    find:
      @escaping (String, Set<MuscleGroup>, ExerciseEquipment?, AppLanguage) ->
      [ExerciseLibraryEntry] =
      {
        ExerciseLibrary.search($0, groups: $1, equipment: $2, language: $3)
      }
  ) {
    self.find = find
    self.groups = groups
    results = find("", groups, nil, .russian)
  }
  func reset() {
    search = ""
    groups = []
    equipment = nil
  }
  private func refresh() {
    do {
      _ = try ExerciseLibrary.document(language: language)
      loadingError = nil
      results = find(search, groups, equipment, language)
    } catch {
      loadingError = error.localizedDescription
      results = []
    }
  }
}
