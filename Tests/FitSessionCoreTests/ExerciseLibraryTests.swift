import Foundation
import Testing

@testable import FitSessionCore

@Test func bundledLibraryLoadsAndHasRussianContent() throws {
  #expect(ExerciseLibrary.loadingError == nil)
  let document = try #require(ExerciseLibrary.document)
  #expect(document.entries.count == 100)
  #expect(document.locale == "ru")
  #expect(document.source.licenseName == "Unlicense")
  #expect(document.source.revision.count == 40)
  for entry in document.entries {
    #expect(entry.name.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil)
    #expect(entry.steps.count >= 3)
    #expect(
      entry.steps.allSatisfy { $0.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil })
    #expect(entry.images.count == 2)
    try Validation.name(entry.exercise.name)
    #expect(entry.exercise.instructions == entry.steps.joined(separator: "\n"))
  }
}

@Test func expandedCatalogPreservesLegacyIDsAndTemplateExercises() {
  #expect(ExerciseCatalog.all.count == 100)
  #expect(Set(ExerciseCatalog.all.map(\.id)).count == 100)
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
  #expect(ExerciseLibrary.search("Romanian Deadlift").map(\.sourceID) == ["Romanian_Deadlift"])
  #expect(!ExerciseLibrary.search("молот").isEmpty)
}

@Test func equipmentAndMuscleFiltersCombineWithSearch() {
  let entries = ExerciseLibrary.search("жим", group: .chest, equipment: .dumbbell)
  #expect(!entries.isEmpty)
  #expect(entries.allSatisfy { $0.group == .chest && $0.equipment == .dumbbell })
  #expect(ExerciseLibrary.search(group: .legs, equipment: .cable).isEmpty)
  #expect(ExerciseLibrary.search("  ").count == 100)
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

@Test(arguments: ["locale", "duplicate", "image", "steps", "version"])
func malformedImportedLibraryIsRejected(_ mutation: String) throws {
  let data = try JSONEncoder().encode(#require(ExerciseLibrary.document))
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var entries = try #require(object["entries"] as? [[String: Any]])
  switch mutation {
  case "locale": object["locale"] = "en"
  case "duplicate": entries.append(entries[0])
  case "image": entries[0]["images"] = ["../outside.jpg", "Barbell_Squat/1.jpg"]
  case "steps": entries[0]["steps"] = []
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
