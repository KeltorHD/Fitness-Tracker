import FitSessionCore
import Foundation
import Observation

@MainActor @Observable final class ExerciseLibraryViewModel {
  var search = "" { didSet { refresh() } }
  var group: MuscleGroup? { didSet { refresh() } }
  var equipment: ExerciseEquipment? { didSet { refresh() } }
  private(set) var results: [ExerciseLibraryEntry]
  let loadingError = ExerciseLibrary.loadingError
  @ObservationIgnored private let find:
    (String, MuscleGroup?, ExerciseEquipment?) -> [ExerciseLibraryEntry]

  init(
    find: @escaping (String, MuscleGroup?, ExerciseEquipment?) -> [ExerciseLibraryEntry] =
      ExerciseLibrary.search
  ) {
    self.find = find
    results = find("", nil, nil)
  }
  func reset() {
    search = ""
    group = nil
    equipment = nil
  }
  private func refresh() { results = find(search, group, equipment) }
}
