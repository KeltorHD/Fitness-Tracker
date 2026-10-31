import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func legacyTemplatesDecodeWithoutMuscleGroups() throws {
  let original = ExerciseCatalog.starterTemplates[0]
  let encoded = try JSONEncoder().encode(original)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object.removeValue(forKey: "muscleGroups")
  let legacyData = try JSONSerialization.data(withJSONObject: object)
  let restored = try JSONDecoder().decode(WorkoutTemplate.self, from: legacyData)
  #expect(restored == original)
  #expect(restored.muscleGroups.isEmpty)
  #expect(try restored.start().exercises.count == original.exercises.count)
}

@Test @MainActor func templateMuscleGroupsSurviveArchiveAndRepositoryRoundTrip() throws {
  var template = ExerciseCatalog.starterTemplates[0]
  template.muscleGroups = [.chest, .arms]
  let archive = WorkoutArchive(workouts: [], templates: [template])
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive))
  #expect(restored.templates == [template])
  let repository = MemoryWorkoutRepository()
  try repository.saveTemplate(template)
  #expect(try repository.templates() == [template])
  template.muscleGroups = []
  try repository.saveTemplate(template)
  #expect(try repository.templates().first?.muscleGroups.isEmpty == true)
}

@Test func multipleMuscleGroupsFilterByUnionAndCombineWithOtherFilters() {
  let groups: Set<MuscleGroup> = [.chest, .arms]
  let chest = ExerciseLibrary.search("", group: .chest, equipment: nil, language: .russian)
  let arms = ExerciseLibrary.search("", group: .arms, equipment: nil, language: .russian)
  let combined = ExerciseLibrary.search(groups: groups)
  #expect(!chest.isEmpty && !arms.isEmpty)
  #expect(Set(combined.map(\.id)) == Set((chest + arms).map(\.id)))
  let filtered = ExerciseLibrary.search("жим", groups: groups, equipment: .barbell)
  #expect(!filtered.isEmpty)
  #expect(filtered.allSatisfy { groups.contains($0.group) && $0.equipment == .barbell })
  let english = ExerciseLibrary.search(
    "жим", groups: groups, equipment: .barbell, language: .english)
  #expect(Set(english.map(\.id)) == Set(filtered.map(\.id)))
  #expect(ExerciseLibrary.search(groups: []).count == ExerciseLibrary.entries.count)
}
