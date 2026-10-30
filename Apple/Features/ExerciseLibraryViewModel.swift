import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class ExerciseLibraryViewModel {
  var search = "" { didSet { refresh() } }
  var group: MuscleGroup? { didSet { refresh() } }
  var equipment: ExerciseEquipment? { didSet { refresh() } }
  var language: AppLanguage = .russian { didSet { refresh() } }
  private(set) var results: [ExerciseLibraryEntry]
  private(set) var loadingError = ExerciseLibrary.loadingError
  @ObservationIgnored private let find:
    (String, MuscleGroup?, ExerciseEquipment?, AppLanguage) -> [ExerciseLibraryEntry]

  init(
    find:
      @escaping (String, MuscleGroup?, ExerciseEquipment?, AppLanguage) -> [ExerciseLibraryEntry] =
      {
        ExerciseLibrary.search($0, group: $1, equipment: $2, language: $3)
      }
  ) {
    self.find = find
    results = find("", nil, nil, .russian)
  }
  func reset() {
    search = ""
    group = nil
    equipment = nil
  }
  private func refresh() {
    do {
      _ = try ExerciseLibrary.document(language: language)
      loadingError = nil
      results = find(search, group, equipment, language)
    } catch {
      loadingError = error.localizedDescription
      results = []
    }
  }
}
