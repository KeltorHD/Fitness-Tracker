import Foundation
import Testing

@testable import FitLifeCore

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
  "videoURL", "variantGroup",
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
  case "videoURL": entries[0]["techniqueVideoURL"] = "https://example.com/video"
  case "variantGroup": entries[0]["variantGroup"] = ["id": "invalid", "title": ""]
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
      "techniqueVideoURL", "variantGroup",
    ] {
      entries[index].removeValue(forKey: key)
    }
  }
  object["entries"] = entries
  let decoded = try ExerciseLibrary.decode(JSONSerialization.data(withJSONObject: object))
  #expect(decoded.entries.count == 100)
  #expect(decoded.entries.allSatisfy { $0.generatedMedia == nil && $0.translationAutomatic == nil })
}

@Test func benchPressVariationsKeepTheirIdentityAndCanBeFoundByOldNames() throws {
  let cases: [(String, String, String)] = [
    ("Barbell_Bench_Press_-_Medium_Grip", "Жим штанги лёжа обычным хватом", "Жим лёжа"),
    ("Close-Grip_Barbell_Bench_Press", "Жим штанги лёжа узким хватом", "Жим штанги узким хватом"),
    (
      "Wide-Grip_Barbell_Bench_Press", "Жим штанги лёжа широким хватом",
      "Жим штанги лежа широким хватом"
    ),
    ("Dumbbell_Bench_Press", "Жим гантелей лёжа на плоской скамье", "Жим гантелей лёжа"),
    ("Butterfly", "Бабочка", "Сведение рук в тренажёре"),
  ]
  for (sourceID, name, oldName) in cases {
    let entry = try #require(ExerciseLibrary.entries.first { $0.sourceID == sourceID })
    #expect(entry.name == name)
    #expect(ExerciseLibrary.search(oldName).contains { $0.id == entry.id })
    #expect(entry.images.count == 2)
    #expect(!entry.primaryMuscleIDs.isEmpty)
    #expect(entry.steps.count >= 3)
  }
  let wide = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Wide-Grip_Barbell_Bench_Press" })
  #expect(wide.translationAutomatic == false)
}

@Test func sitUpsAreNotMisidentifiedAsSquats() throws {
  let full = try #require(ExerciseLibrary.entries.first { $0.sourceID == "Sit-Up" })
  let partial = try #require(ExerciseLibrary.entries.first { $0.sourceID == "3_4_Sit-Up" })
  #expect(full.name == "Подъём корпуса лёжа на полу")
  #expect(partial.name == "Подъём корпуса лёжа с неполным опусканием")
  #expect(!ExerciseLibrary.search("приседания").contains { $0.id == full.id || $0.id == partial.id })
  #expect(ExerciseLibrary.search("подъём корпуса").contains { $0.id == full.id })
  #expect(ExerciseLibrary.search("3/4 Sit-Up").contains { $0.id == partial.id })
}

@Test func reviewedStretchDoesNotRepeatThePrimaryMuscleAsSecondary() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "All_Fours_Quad_Stretch" })
    #expect(entry.primaryMuscleIDs == [.quadriceps])
    #expect(entry.secondaryMuscles.isEmpty)
  }
}

@Test func renegadeRowUsesKettlebellsRatherThanDumbbells() throws {
  let row = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Alternating_Renegade_Row" })
  #expect(row.name == "Попеременная тяга гирь в упоре лёжа")
  #expect(row.equipment == .kettlebell)
  #expect(ExerciseLibrary.search("тяга гирь в планке").contains { $0.id == row.id })
  #expect(!ExerciseLibrary.search("тяга гантелей в упоре лёжа").contains { $0.id == row.id })
}

@Test func cablePushdownVariantsShareAGroupWithoutSharingIdentity() throws {
  let original = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Triceps_Pushdown" })
  let russian = ExerciseLibrary.variants(for: original.id, language: .russian)
  let english = ExerciseLibrary.variants(for: original.id, language: .english)
  let expected: Set<String> = [
    "Triceps_Pushdown", "Triceps_Pushdown_-_Rope_Attachment",
    "Triceps_Pushdown_-_V-Bar_Attachment", "Reverse_Grip_Triceps_Pushdown",
    "Cable_One_Arm_Tricep_Extension",
  ]
  #expect(Set(russian.map(\.sourceID)) == expected)
  #expect(Set(russian.map(\.id)).count == expected.count)
  #expect(russian.map(\.id) == english.map(\.id))
  #expect(russian.allSatisfy { $0.variantGroup?.title == "Разгибание рук на верхнем блоке" })
  #expect(english.allSatisfy { $0.variantGroup?.title == "Cable triceps pushdown" })
  #expect(russian.allSatisfy { $0.equipment == .cable && $0.images.count == 2 })
  #expect(russian.allSatisfy { ExerciseLibrary.variants(for: $0.id, language: .russian) == russian })
  #expect(ExerciseLibrary.variants(for: UUID(), language: .russian).isEmpty)
}

@Test func benchPressGripVariantsAreGrouped() throws {
  let bench = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Bench_Press_-_Medium_Grip" })
  let variants = ExerciseLibrary.variants(for: bench.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Barbell_Bench_Press_-_Medium_Grip", "Close-Grip_Barbell_Bench_Press",
    "Wide-Grip_Barbell_Bench_Press", "Bench_Press_-_Powerlifting",
    "Bench_Press_with_Chains", "Board_Press",
  ])
}

@Test func bandBenchPressDoesNotBecomeABarbellExercise() throws {
  let band = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Bench_Press_-_With_Bands" })
  #expect(band.equipment == .bands)
  #expect(band.name == "Жим эспандера лёжа на плоской скамье")
  #expect(band.variantGroup == nil)
}

@Test func pulloverDoesNotRepeatItsPrimaryMuscleAsSecondary() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first {
        $0.sourceID == "Bent-Arm_Barbell_Pullover"
      })
    #expect(entry.primaryMuscleIDs == [.lats])
    #expect(!entry.secondaryMuscleIDs.contains(.lats))
  }
}

@Test func bandHipAdductionMatchesTheOriginalNameAndPhotos() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Band_Hip_Adductions" })
  #expect(entry.name == "Приведение ноги стоя с резиновой петлёй")
  #expect(entry.primaryMuscleIDs == [.adductors])
  #expect(entry.steps.contains { $0.contains("к средней линии") })
  #expect(ExerciseLibrary.search("приведение бедра с эспандером").contains { $0.id == entry.id })
}

@Test func rolloutVariantsShareOneGroupButKeepSeparateIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Ab_Rollout" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Barbell_Ab_Rollout", "Barbell_Ab_Rollout_-_On_Knees", "Barbell_Rollout_from_Bench",
  ])
  #expect(Set(variants.map(\.id)).count == 3)
}

@Test func bandAssistedPullUpsAppearUnderBandEquipment() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Band_Assisted_Pull-Up" })
  #expect(entry.equipment == .bands)
  #expect(ExerciseLibrary.search(equipment: .bands).contains { $0.id == entry.id })
}

@Test func barbellStepUpDoesNotRepeatQuadricepsAsSecondary() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Barbell_Step_Ups" })
    #expect(entry.primaryMuscleIDs == [.quadriceps])
    #expect(!entry.secondaryMuscleIDs.contains(.quadriceps))
  }
}

@Test func walkingLungeVariantsKeepEquipmentAndSeparateIdentity() throws {
  let bodyweight = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Bodyweight_Walking_Lunge" })
  let variants = ExerciseLibrary.variants(for: bodyweight.id, language: .russian)
  #expect(bodyweight.equipment == .bodyWeight)
  #expect(Set(variants.map(\.sourceID)) == ["Bodyweight_Walking_Lunge", "Barbell_Walking_Lunge"])
  #expect(Set(variants.map(\.equipment)) == [.bodyWeight, .barbell])
  #expect(Set(variants.map(\.id)).count == 2)
}

@Test func cableHipAdductionUsesAdductorsInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Cable_Hip_Adduction" })
    #expect(entry.primaryMuscleIDs == [.adductors])
    #expect(entry.muscleRegions.isEmpty)
    #expect(
      ExerciseLibrary.search(
        muscleSelection: ExerciseMuscleSelection(muscles: [.adductors]), language: language
      ).contains { $0.id == entry.id })
    #expect(
      !ExerciseLibrary.search(
        muscleSelection: ExerciseMuscleSelection(muscles: [.quadriceps]), language: language
      ).contains { $0.id == entry.id })
  }
}

@Test func standingCableShoulderPressVariantsKeepSeparateIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Cable_Shoulder_Press" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Cable_Shoulder_Press", "Alternating_Cable_Shoulder_Press",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
}

@Test func plateSteeringExerciseDoesNotAppearAsBarbellEquipment() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Car_Drivers" })
    #expect(entry.equipment == .other)
    #expect(!ExerciseLibrary.search(equipment: [.barbell], language: language).contains {
      $0.id == entry.id
    })
  }
}

@Test func closeGripCurlVariantsDistinguishEzBarFromStraightBar() throws {
  let ezCurl = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Close-Grip_EZ_Bar_Curl" })
  let variants = ExerciseLibrary.variants(for: ezCurl.id, language: .russian)
  #expect(ezCurl.equipment == .ezBar)
  #expect(Set(variants.map(\.sourceID)) == [
    "Close-Grip_EZ_Bar_Curl", "Close-Grip_Standing_Barbell_Curl",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
  #expect(Set(variants.map(\.equipment)) == [.ezBar, .barbell])
}

@Test func conventionalDeadliftVariationsKeepSeparateHistoryIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Deadlift" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Barbell_Deadlift", "Deadlift_with_Bands", "Deadlift_with_Chains", "Deficit_Deadlift",
  ])
  #expect(Set(variants.map(\.id)).count == 4)
  #expect(ExerciseLibrary.search("Становая тяга").contains { $0.id == entry.id })
}

@Test func alternatingKettlebellCleansStayIndividuallyIdentifiable() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Alternating_Hang_Clean" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Alternating_Hang_Clean", "Double_Kettlebell_Alternating_Hang_Clean",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
}

@Test func neutralGripDumbbellPressIsGroupedWithFlatDumbbellPress() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Dumbbell_Bench_Press" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Dumbbell_Bench_Press", "Dumbbell_Bench_Press_with_Neutral_Grip",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
  #expect(ExerciseLibrary.search("Жим гантелей лёжа").contains { $0.id == entry.id })
}

@Test func exerciseBallCrunchVariantsDescribeDifferentPositions() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Exercise_Ball_Crunch" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Exercise_Ball_Crunch", "Crunch_-_Legs_On_Exercise_Ball",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
  #expect(variants.allSatisfy { $0.equipment == .exerciseBall })
}

@Test func shoulderRotationVariantsRetainEquipmentAndIdentity() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "External_Rotation" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "External_Rotation", "External_Rotation_with_Band", "External_Rotation_with_Cable",
  ])
  #expect(Set(variants.map(\.equipment)) == [.dumbbell, .bands, .cable])
  #expect(Set(variants.map(\.id)).count == 3)
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
