import FitnessTrackerCore
import Foundation
import Observation

@MainActor @Observable final class ExerciseLibraryViewModel {
  var search = "" { didSet { refresh() } }
  var muscleSelection: ExerciseMuscleSelection { didSet { refresh() } }
  var groups: Set<MuscleGroup> {
    get { muscleSelection.groups }
    set {
      muscleSelection = ExerciseMuscleSelection(groups: newValue, muscles: muscleSelection.muscles)
    }
  }
  var equipment: Set<ExerciseEquipment> = [] { didSet { refresh() } }
  var language: AppLanguage = .russian { didSet { refresh() } }
  private(set) var results: [ExerciseLibraryEntry]
  private(set) var loadingError = ExerciseLibrary.loadingError
  @ObservationIgnored private let find:
    (String, ExerciseMuscleSelection, Set<ExerciseEquipment>, AppLanguage) -> [ExerciseLibraryEntry]

  init(
    groups: Set<MuscleGroup> = [], muscles: Set<ExerciseMuscle> = [],
    find:
      @escaping (String, ExerciseMuscleSelection, Set<ExerciseEquipment>, AppLanguage) ->
      [ExerciseLibraryEntry] =
      {
        ExerciseLibrary.search($0, muscleSelection: $1, equipment: $2, language: $3)
      }
  ) {
    self.find = find
    let selection = ExerciseMuscleSelection(groups: groups, muscles: muscles)
    muscleSelection = selection
    results = find("", selection, [], .russian)
  }
  func reset() {
    search = ""
    muscleSelection = ExerciseMuscleSelection()
    equipment = []
  }
  private func refresh() {
    do {
      _ = try ExerciseLibrary.document(language: language)
      loadingError = nil
      results = find(search, muscleSelection, equipment, language)
    } catch {
      loadingError = error.localizedDescription
      results = []
    }
  }
}
