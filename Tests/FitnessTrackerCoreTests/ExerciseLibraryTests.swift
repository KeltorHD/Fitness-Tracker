import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func bundledLibraryLoadsAndHasRussianContent() throws {
  #expect(ExerciseLibrary.loadingError == nil)
  let document = try #require(ExerciseLibrary.document)
  #expect(document.entries.count == 876)
  #expect(document.locale == "ru")
  #expect(document.source.licenseName == "Unlicense")
  #expect(document.source.revision.count == 40)
  for entry in document.entries {
    #expect(entry.name.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil)
    #expect(entry.steps.isEmpty == (entry.techniqueUnavailable == true))
    #expect(entry.steps.isEmpty || entry.steps.count >= 3)
    #expect(
      entry.steps.allSatisfy { $0.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil })
    #expect(entry.images.isEmpty == (entry.imagesUnavailable == true))
    #expect(entry.images.isEmpty || entry.images.count == 2)
    try Validation.name(entry.exercise.name)
    #expect(entry.exercise.instructions == entry.steps.joined(separator: "\n"))
  }
}

@Test func expandedCatalogPreservesLegacyIDsAndTemplateExercises() {
  #expect(ExerciseCatalog.all.count == 876)
  #expect(Set(ExerciseCatalog.all.map(\.id)).count == 876)
  let expected = (1...8).map {
    UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", $0))!
  }
  #expect(Array(ExerciseCatalog.all.prefix(8)).map(\.id) == expected)
  #expect(
    ExerciseCatalog.starterTemplates[0].exercises.map(\.exercise.id) == Array(expected.prefix(3)))
  #expect(ExerciseLibrary.entry(for: expected[0])?.sourceID == "Barbell_Squat")
}

@Test func russianSearchIgnoresCaseAndYoDiacritic() {
  let result = ExerciseLibrary.search("  ЖИМ   ЛЕЖА ")
  #expect(result.contains { $0.sourceID == "Barbell_Bench_Press_-_Medium_Grip" })
  #expect(ExerciseLibrary.search("несуществующее упражнение").isEmpty)
}

@Test func librarySearchMatchesRussianAliasesAndEnglishSourceNames() {
  #expect(ExerciseLibrary.search("хип-траст").map(\.sourceID) == ["Barbell_Hip_Thrust"])
  #expect(
    Set(ExerciseLibrary.search("Romanian Deadlift").map(\.sourceID)) == [
      "Romanian_Deadlift", "Romanian_Deadlift_from_Deficit",
    ])
  #expect(!ExerciseLibrary.search("молот").isEmpty)
}

@Test func equipmentAndMuscleFiltersCombineWithSearch() {
  let entries = ExerciseLibrary.search("жим", group: .chest, equipment: .dumbbell)
  #expect(!entries.isEmpty)
  #expect(entries.allSatisfy { $0.group == .chest && $0.equipment == .dumbbell })
  let cableLegs = ExerciseLibrary.search(group: .legs, equipment: .cable)
  #expect(cableLegs.contains { $0.sourceID == "Cable_Hip_Adduction" })
  #expect(cableLegs.allSatisfy { $0.group == .legs && $0.equipment == .cable })
  #expect(ExerciseLibrary.search("  ").count == 876)
}

@Test func everyLibraryMetadataLabelIsLocalized() {
  for entry in ExerciseLibrary.entries {
    for label in [entry.equipment.title, entry.level.title] + entry.primaryMuscles
      + entry.secondaryMuscles
    {
      #expect(label.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil)
    }
  }
}

@Test(arguments: [
  "locale", "duplicate", "image", "steps", "version", "animationPath", "animationDuration",
])
func malformedImportedLibraryIsRejected(_ mutation: String) throws {
  let document: ExerciseLibraryDocument = try #require(ExerciseLibrary.document)
  let data = try JSONEncoder().encode(document)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var entries = try #require(object["entries"] as? [[String: Any]])
  switch mutation {
  case "locale": object["locale"] = "en"
  case "duplicate": entries.append(entries[0])
  case "image": entries[0]["images"] = ["../outside.jpg", "Barbell_Squat/1.jpg"]
  case "steps": entries[0]["steps"] = []
  case "animationPath":
    var media = try #require(entries[0]["generatedMedia"] as? [String: Any])
    media["gif"] = "../outside.gif"
    entries[0]["generatedMedia"] = media
  case "animationDuration":
    var media = try #require(entries[0]["generatedMedia"] as? [String: Any])
    media["frameDuration"] = 0
    entries[0]["generatedMedia"] = media
  default: object["schemaVersion"] = 999
  }
  object["entries"] = entries
  let broken = try JSONSerialization.data(withJSONObject: object)
  #expect(throws: (any Error).self) { try ExerciseLibrary.decode(broken) }
}

@Test func oldExercisePayloadStillDecodesWithoutLibraryMetadata() throws {
  let data = Data(
    """
    {"id":"10000000-0000-0000-0000-000000000001","name":"Приседания","muscle":"legs","instructions":"Старое описание"}
    """.utf8)
  let exercise = try JSONDecoder().decode(Exercise.self, from: data)
  #expect(exercise.instructions == "Старое описание")
  #expect(ExerciseLibrary.entry(for: exercise.id)?.steps.count == 3)
}

@Test func fullCatalogRepresentsMissingSourceMaterialsExplicitly() {
  #expect(
    Set(ExerciseLibrary.entries.filter { $0.imagesUnavailable == true }.map(\.sourceID)) == [
      "Kettlebell_Halo", "Kettlebell_Halo_With_Overhead_Extension",
      "Kettlebell_Overhead_Triceps_Extension",
    ])
  #expect(
    Set(ExerciseLibrary.entries.filter { $0.techniqueUnavailable == true }.map(\.sourceID)) == [
      "Iron_Cross", "One-Arm_Kettlebell_Swings", "Push_Press", "Side_Bridge", "Side_Jackknife",
    ])
}

@Test func originalLibraryWithoutOptionalMetadataStillDecodes() throws {
  let data = try JSONEncoder().encode(try #require(ExerciseLibrary.document))
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var entries = Array(try #require(object["entries"] as? [[String: Any]]).prefix(100))
  for index in entries.indices {
    for key in [
      "techniqueUnavailable", "imagesUnavailable", "generatedMedia", "translationAutomatic",
    ] {
      entries[index].removeValue(forKey: key)
    }
  }
  object["entries"] = entries
  let decoded = try ExerciseLibrary.decode(JSONSerialization.data(withJSONObject: object))
  #expect(decoded.entries.count == 100)
  #expect(decoded.entries.allSatisfy { $0.generatedMedia == nil && $0.translationAutomatic == nil })
}

@Test func multipleEquipmentFiltersUseUnionAndIntersectWithMuscleAndSearch() {
  let equipment: Set<ExerciseEquipment> = [.barbell, .dumbbell]
  let combined = ExerciseLibrary.search(equipment: equipment)
  let barbell = ExerciseLibrary.search(equipment: .barbell)
  let dumbbell = ExerciseLibrary.search(equipment: .dumbbell)
  #expect(!barbell.isEmpty && !dumbbell.isEmpty)
  #expect(Set(combined.map(\.id)) == Set((barbell + dumbbell).map(\.id)))
  let groups: Set<MuscleGroup> = [.chest, .shoulders]
  let filtered = ExerciseLibrary.search("жим", groups: groups, equipment: equipment)
  let expected = ExerciseLibrary.search("жим", groups: groups)
    .filter { equipment.contains($0.equipment) }
  #expect(!filtered.isEmpty)
  #expect(Set(filtered.map(\.equipment)) == equipment)
  #expect(filtered == expected)
  let english = ExerciseLibrary.search(
    "жим", groups: groups, equipment: equipment, language: .english)
  #expect(Set(english.map(\.id)) == Set(filtered.map(\.id)))
  #expect(ExerciseLibrary.search(equipment: []).count == ExerciseLibrary.entries.count)
  #expect(
    ExerciseLibrary.search("жим", groups: groups, equipment: [])
      == ExerciseLibrary.search("жим", groups: groups))
}
