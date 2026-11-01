import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func detailedMusclesCoverEveryBundledSourceLabelInBothLanguages() throws {
  let russian = try ExerciseLibrary.entries(language: .russian)
  let english = try ExerciseLibrary.entries(language: .english)
  #expect(ExerciseMuscle.allCases.count == 17)
  #expect(Set(english.flatMap(\.primaryMuscles)) == Set(ExerciseMuscle.allCases.map(\.rawValue)))
  let englishByID = Dictionary(uniqueKeysWithValues: english.map { ($0.id, $0) })
  for entry in russian {
    let translated = try #require(englishByID[entry.id])
    #expect(entry.primaryMuscleIDs.count == entry.primaryMuscles.count)
    #expect(entry.secondaryMuscleIDs.count == entry.secondaryMuscles.count)
    #expect(entry.primaryMuscleIDs == translated.primaryMuscleIDs)
    #expect(entry.secondaryMuscleIDs == translated.secondaryMuscleIDs)
    #expect(entry.primaryMuscleIDs.first?.group == entry.group)
  }
  #expect(Set(ExerciseMuscle.inGroup(.arms)) == [.biceps, .triceps, .forearms])
  #expect(Set(ExerciseMuscle.inGroup(.shoulders)) == [.shoulders, .neck])
}

@Test func deselectingOneMuscleFromWholeGroupRetainsItsSiblingsAndOtherGroups() {
  var selection = ExerciseMuscleSelection(groups: [.arms, .back])
  #expect(selection.state(of: .arms) == .all)
  #expect(selection.contains(.biceps) && selection.contains(.triceps))
  selection.set(.biceps, selected: false)
  #expect(!selection.contains(.biceps))
  #expect(selection.muscles == [.triceps, .forearms])
  #expect(selection.groups == [.back])
  #expect(selection.state(of: .arms) == .partial)
  selection.set(.forearms, selected: false)
  #expect(selection.muscles == [.triceps])
  selection.set(MuscleGroup.arms, selected: false)
  #expect(selection.state(of: .arms) == .none)
  #expect(selection.groups == [.back] && selection.muscles.isEmpty)
}

@Test func explicitMusclesKeepTheirIdentityAndGroupActionsAreIndependent() {
  var selection = ExerciseMuscleSelection(muscles: [.biceps, .triceps, .forearms, .glutes])
  #expect(selection.groups.isEmpty)
  #expect(selection.state(of: .arms) == .all)
  selection.set(MuscleGroup.arms, selected: true)
  #expect(selection.groups == [.arms])
  #expect(selection.muscles == [.glutes])
  selection.set(.biceps, selected: true)
  #expect(selection.muscles == [.glutes])
  selection.set(MuscleGroup.arms, selected: false)
  #expect(selection.muscles == [.glutes] && selection.groups.isEmpty)
  let legacy = ExerciseMuscleSelection(groups: [.fullBody])
  #expect(!legacy.isEmpty && legacy.state(of: .fullBody) == .all)
}

@Test func specificMuscleSearchUsesPrimaryMusclesAndExcludesSecondaryOnlyMatches() throws {
  let selection = ExerciseMuscleSelection(muscles: [.triceps])
  let results = ExerciseLibrary.search(muscleSelection: selection)
  #expect(!results.isEmpty)
  #expect(results.allSatisfy { $0.primaryMuscleIDs.contains(.triceps) })
  let bench = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Bench_Press_-_Medium_Grip" })
  #expect(bench.secondaryMuscleIDs.contains(.triceps))
  #expect(!selection.matches(bench))
  #expect(!results.contains { $0.id == bench.id })
  let biceps = ExerciseLibrary.search(muscleSelection: ExerciseMuscleSelection(muscles: [.biceps]))
  #expect(!biceps.isEmpty)
  #expect(biceps.allSatisfy { $0.primaryMuscleIDs == [.biceps] })
}

@Test func mixedGroupAndMuscleSearchCombinesWithQueryEquipmentAndLanguage() {
  let selection = ExerciseMuscleSelection(groups: [.back], muscles: [.biceps, .triceps])
  let equipment: Set<ExerciseEquipment> = [.barbell, .dumbbell]
  let results = ExerciseLibrary.search("curl", muscleSelection: selection, equipment: equipment)
  let expected = ExerciseLibrary.search("curl", equipment: equipment).filter {
    $0.group == .back || $0.primaryMuscleIDs.contains(.biceps)
      || $0.primaryMuscleIDs.contains(.triceps)
  }
  #expect(!results.isEmpty)
  #expect(results == expected)
  let translated = ExerciseLibrary.search(
    "curl", muscleSelection: selection, equipment: equipment, language: .english)
  #expect(Set(results.map(\.id)) == Set(translated.map(\.id)))
  let wholeArms = ExerciseLibrary.search(muscleSelection: ExerciseMuscleSelection(groups: [.arms]))
  #expect(wholeArms == ExerciseLibrary.search(group: .arms))
  #expect(
    ExerciseLibrary.search(muscleSelection: ExerciseMuscleSelection()).count
      == ExerciseLibrary.entries.count)
}

@Test @MainActor func templateDetailedMusclesSurviveArchiveRepositoryAndClearing() throws {
  var template = ExerciseCatalog.starterTemplates[0]
  let originalIDs = template.exercises.map(\.exercise.id)
  template.muscleSelection = ExerciseMuscleSelection(
    groups: [.back], muscles: [.biceps, .forearms])
  template.preferredWeekdays = [.monday, .friday]
  template.restSeconds = 120
  let archive = WorkoutArchive(workouts: [], templates: [template])
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive))
  #expect(restored.templates == [template])
  let repository = MemoryWorkoutRepository()
  try repository.saveTemplate(try #require(restored.templates.first))
  #expect(try repository.templates() == [template])
  #expect(try template.start().exercises.map(\.exercise.id) == originalIDs)
  template.muscleSelection = ExerciseMuscleSelection()
  try repository.saveTemplate(template)
  #expect(try repository.templates().first?.muscles.isEmpty == true)
  #expect(try repository.templates().first?.muscleGroups.isEmpty == true)
}

@Test func legacyTemplateWithoutDetailedMusclesKeepsExistingGroupSelection() throws {
  let template = WorkoutTemplate(
    name: "Руки", exercises: ExerciseCatalog.starterTemplates[0].exercises, muscleGroups: [.arms])
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
  object.removeValue(forKey: "muscles")
  let restored = try JSONDecoder().decode(
    WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(restored == template)
  #expect(restored.muscleSelection.state(of: .arms) == .all)
  #expect(restored.muscleSelection.contains(.forearms))
}

@Test func libraryRejectsUnknownMusclesInsteadOfSilentlyDroppingThemFromFilters() throws {
  let document = try #require(ExerciseLibrary.document)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
  var entries = try #require(object["entries"] as? [[String: Any]])
  entries[0]["primaryMuscles"] = ["Unknown muscle"]
  object["entries"] = entries
  let data = try JSONSerialization.data(withJSONObject: object)
  #expect(throws: ExerciseLibraryError.invalidDocument) { try ExerciseLibrary.decode(data) }
}
