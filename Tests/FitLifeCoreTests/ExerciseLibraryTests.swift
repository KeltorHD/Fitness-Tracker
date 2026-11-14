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
  #expect(ExerciseLibrary.entries.allSatisfy { $0.techniqueUnavailable == false })
}

@Test func sideExercisesHaveTechniqueAndCorrectMuscleMapping() throws {
  for language in [AppLanguage.russian, .english] {
    for sourceID in ["Side_Bridge", "Side_Jackknife"] {
      let entry = try #require(
        ExerciseLibrary.entries(language: language).first { $0.sourceID == sourceID })
      #expect(entry.steps.count >= 3)
      #expect(entry.techniqueUnavailable == false)
    }
    let legRaise = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Side_Leg_Raises" })
    #expect(legRaise.primaryMuscleIDs == [.abductors])
  }
  let russian = try #require(
    ExerciseLibrary.entries(language: .russian).first {
      $0.sourceID == "Side_Laterals_to_Front_Raise"
    })
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first {
      $0.sourceID == "Side_Laterals_to_Front_Raise"
    })
  #expect(russian.steps.contains { $0.contains("через стороны") })
  #expect(english.steps.contains { $0.contains("out to the sides") })
}

@Test func oneArmKettlebellSwingHasTechniqueInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first {
        $0.sourceID == "One-Arm_Kettlebell_Swings"
      })
    #expect(entry.techniqueUnavailable == false)
    #expect(entry.steps.count >= 3)
  }
}

@Test func pushPressHasTechniqueAndRearLegRaiseUsesGlutesInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let pushPress = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Push_Press" })
    let legRaise = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Rear_Leg_Raises" })
    #expect(pushPress.techniqueUnavailable == false)
    #expect(pushPress.steps.count >= 3)
    #expect(legRaise.primaryMuscleIDs == [.glutes])
    #expect(legRaise.secondaryMuscleIDs.contains(.hamstrings))
  }
}

@Test func kettlebellFloorPressJoinsRelatedVariantsWithItsOwnID() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "One-Arm_Kettlebell_Floor_Press" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(variants.contains { $0.sourceID == "Floor_Press" })
  #expect(variants.contains { $0.sourceID == "One-Arm_Kettlebell_Floor_Press" })
  #expect(Set(variants.map(\.id)).count == variants.count)
}

@Test func ironCrossUsesUserSelectedNameAndLocallyAuthoredTechnique() throws {
  let russian = try #require(
    ExerciseLibrary.entries(language: .russian).first { $0.sourceID == "Iron_Cross" })
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Iron_Cross" })
  #expect(russian.id == english.id)
  #expect(russian.name == "Приседание с разведением гантелей")
  #expect(ExerciseLibrary.search("Железный крест").contains { $0.id == russian.id })
  #expect(russian.steps.count >= 3 && english.steps.count >= 3)
  #expect(russian.techniqueUnavailable == false && english.techniqueUnavailable == false)
  #expect(russian.equipment == .dumbbell && russian.images.count == 2)
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
    "Bench_Press_with_Chains", "Board_Press", "Reverse_Band_Bench_Press",
    "Reverse_Triceps_Bench_Press", "Smith_Machine_Bench_Press",
    "Smith_Machine_Close-Grip_Bench_Press",
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
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Band_Hip_Adductions" })
  #expect(english.steps.contains { $0.contains("toward the midline") })
  #expect(!english.steps.contains { $0.contains("out to the side as far as you can") })
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
    "Reverse_Band_Deadlift",
  ])
  #expect(Set(variants.map(\.id)).count == 5)
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
    "One_Arm_Dumbbell_Bench_Press",
  ])
  #expect(Set(variants.map(\.id)).count == 3)
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

@Test func alternatingAndSimultaneousFrontRaisesAreSeparateVariants() throws {
  let alternating = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Front_Dumbbell_Raise" })
  let variants = ExerciseLibrary.variants(for: alternating.id, language: .russian)
  #expect(variants.contains { $0.sourceID == "Front_Two-Dumbbell_Raise" })
  #expect(Set(variants.map(\.id)).count == variants.count)
  #expect(ExerciseLibrary.search("Подъёмы гантелей перед собой").contains {
    $0.id == alternating.id
  })
}

@Test func goodMorningVariantsIncludeBarbellAndBands() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Good_Morning" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Good_Morning", "Good_Morning_off_Pins", "Band_Good_Morning",
    "Band_Good_Morning_Pull_Through", "Hanging_Bar_Good_Morning", "Seated_Good_Mornings",
    "Stiff_Leg_Barbell_Good_Morning",
  ])
  #expect(Set(variants.map(\.id)).count == 7)
  #expect(Set(variants.map(\.equipment)) == [.barbell, .bands])
}

@Test func gluteBridgeVariantsKeepLegacySearchAndDifferentEquipment() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Barbell_Glute_Bridge" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Barbell_Glute_Bridge", "Hip_Lift_with_Band", "Pelvic_Tilt_Into_Bridge",
  ])
  #expect(Set(variants.map(\.equipment)) == [.barbell, .bands, .bodyWeight])
  #expect(Set(variants.map(\.id)).count == 3)
  #expect(ExerciseLibrary.search("Ягодичный мост со штангой").contains { $0.id == entry.id })
}

@Test func hurdleHopsDoNotRepeatThePrimaryMuscleAsSecondary() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Hurdle_Hops" })
    #expect(entry.primaryMuscleIDs == [.hamstrings])
    #expect(!entry.secondaryMuscleIDs.contains(.hamstrings))
  }
}

@Test func inclineBenchPullUsesDumbbellsInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Incline_Bench_Pull" })
    #expect(entry.equipment == .dumbbell)
  }
}

@Test func hackSquatAndGluteHamVariantsKeepSeparateIdentities() throws {
  for expected in [
    ["Hack_Squat", "Narrow_Stance_Hack_Squats"],
    ["Floor_Glute-Ham_Raise", "Glute_Ham_Raise", "Natural_Glute_Ham_Raise"],
  ] {
    for language in [AppLanguage.russian, .english] {
      let entry = try #require(
        ExerciseLibrary.entries(language: language).first { $0.sourceID == expected[0] })
      let variants = ExerciseLibrary.variants(for: entry.id, language: language)
      #expect(Set(variants.map(\.sourceID)) == Set(expected))
      #expect(Set(variants.map(\.id)).count == expected.count)
    }
  }
}

@Test func pallofAndBenchWristVariantsKeepSeparateIdentities() throws {
  for expected in [
    ["Pallof_Press", "Pallof_Press_With_Rotation"],
    [
      "Palms-Down_Dumbbell_Wrist_Curl_Over_A_Bench", "Palms-Down_Wrist_Curl_Over_A_Bench",
      "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench", "Palms-Up_Dumbbell_Wrist_Curl_Over_A_Bench",
    ],
    ["Overhead_Squat", "One-Arm_Overhead_Kettlebell_Squats"],
    ["Plyo_Push-up", "Plyo_Kettlebell_Pushups"],
    [
      "Push-Up_Wide", "Push-Ups_-_Close_Triceps_Position", "Push-Ups_With_Feet_On_An_Exercise_Ball",
      "Pushups_Close_and_Wide_Hand_Positions", "Single-Arm_Push-Up",
    ],
    ["Push_Press", "Push_Press_-_Behind_the_Neck"],
    ["Rack_Pulls", "Rack_Pull_with_Bands"],
    ["Parallel_Bar_Dip", "Ring_Dips"],
    ["Romanian_Deadlift", "Romanian_Deadlift_from_Deficit"],
    ["Sled_Push", "Prowler_Sprint"],
    ["Smith_Machine_Upright_Row", "Smith_Machine_One-Arm_Upright_Row"],
    ["Standing_Cable_Lift", "Standing_Cable_Wood_Chop"],
    ["Stiff-Legged_Barbell_Deadlift", "Smith_Machine_Stiff-Legged_Deadlift"],
    ["Sumo_Deadlift_with_Bands", "Reverse_Band_Sumo_Deadlift", "Sumo_Deadlift_with_Chains"],
    ["Supine_One-Arm_Overhead_Throw", "Supine_Two-Arm_Overhead_Throw"],
    ["One-Arm_Kettlebell_Row", "Two-Arm_Kettlebell_Row"],
    [
      "Standing_Alternating_Dumbbell_Press", "Standing_Palm-In_One-Arm_Dumbbell_Press",
      "Standing_Palms-In_Dumbbell_Press",
    ],
    [
      "Barbell_Squat", "Narrow_Stance_Squats", "Speed_Squats", "Squat_with_Bands",
      "Squat_with_Chains",
    ],
    [
      "Standing_Bent-Over_One-Arm_Dumbbell_Triceps_Extension",
      "Standing_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension",
    ],
    [
      "Seated_Bent-Over_One-Arm_Dumbbell_Triceps_Extension",
      "Seated_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension",
    ],
    ["Seated_Dumbbell_Curl", "Seated_Dumbbell_Inner_Biceps_Curl"],
    [
      "Seated_Dumbbell_Palms-Down_Wrist_Curl", "Seated_Dumbbell_Palms-Up_Wrist_Curl",
      "Seated_One-Arm_Dumbbell_Palms-Down_Wrist_Curl",
      "Seated_One-Arm_Dumbbell_Palms-Up_Wrist_Curl",
    ],
  ] {
    for language in [AppLanguage.russian, .english] {
      let entry = try #require(
        ExerciseLibrary.entries(language: language).first { $0.sourceID == expected[0] })
      let variants = ExerciseLibrary.variants(for: entry.id, language: language)
      #expect(Set(variants.map(\.sourceID)) == Set(expected))
      #expect(Set(variants.map(\.id)).count == expected.count)
    }
  }
}

@Test func seatedBandLegCurlUsesBandsInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first {
        $0.sourceID == "Seated_Band_Hamstring_Curl"
      })
    #expect(entry.equipment == .bands)
    #expect(entry.primaryMuscleIDs == [.hamstrings])
  }
}

@Test func inclineShoulderRaiseUsesSmithMachineInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first {
        $0.sourceID == "Smith_Incline_Shoulder_Raise"
      })
    #expect(entry.equipment == .machine)
  }
}

@Test func upperBackStretchDoesNotRepeatItsPrimaryMuscle() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Upper_Back_Stretch" })
    #expect(entry.primaryMuscleIDs == [.middleBack])
    #expect(!entry.secondaryMuscleIDs.contains(.middleBack))
  }
}

@Test func smithSplitSquatOmitsUnsupportedKneePositionClaim() throws {
  let entry = try #require(
    ExerciseLibrary.entries(language: .english).first {
      $0.sourceID == "Smith_Single-Leg_Split_Squat"
    })
  #expect(entry.steps.count >= 3)
  #expect(!entry.steps.joined().contains("knee is past"))
  #expect(entry.equipment == .machine)
}

@Test func barbellSquatKeepsLegacySearchAndCorrectedEnglishTechnique() throws {
  let russian = try #require(
    ExerciseLibrary.entries(language: .russian).first { $0.sourceID == "Barbell_Squat" })
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Barbell_Squat" })
  #expect(russian.id == english.id)
  #expect(ExerciseLibrary.search("Приседания").contains { $0.id == russian.id })
  #expect(!english.steps.joined().contains("knees are past"))
}

@Test func spiderCurlUsesTheDumbbellsShownInItsPhotos() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Spider_Curl" })
    #expect(entry.equipment == .dumbbell)
    #expect(entry.steps.count >= 3)
    #expect(entry.imagesUnavailable == false)
  }
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Spider_Curl" })
  #expect(english.steps.contains { $0.contains("dumbbell") })
}

@Test func suspensionInstructionsUseCorrectMovementCues() throws {
  let row = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Suspended_Row" })
  let crunch = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Suspended_Reverse_Crunch" })
  #expect(row.steps.contains { $0.contains("shoulder blades together") })
  #expect(!crunch.steps.joined().contains("anteriorly tilt"))
}

@Test func inclineDumbbellPressGripVariantsKeepSeparateIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Incline_Dumbbell_Press" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Incline_Dumbbell_Press", "Hammer_Grip_Incline_DB_Bench_Press",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
  #expect(ExerciseLibrary.search("Жим гантелей на наклонной скамье").contains {
    $0.id == entry.id
  })
}

@Test func groinStretchUsesAdductorsInBothLanguages() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first {
        $0.sourceID == "Intermediate_Groin_Stretch"
      })
    #expect(entry.primaryMuscleIDs == [.adductors])
    #expect(entry.secondaryMuscleIDs.contains(.hamstrings))
  }
}

@Test func kettlebellExtensionUsesGeneratedMediaAndKeepsItsIdentity() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Kettlebell_Overhead_Triceps_Extension" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(entry.imagesUnavailable == true)
  #expect(entry.generatedMedia != nil)
  #expect(Set(variants.map(\.sourceID)) == [
    "Kettlebell_Overhead_Triceps_Extension", "Dumbbell_One-Arm_Triceps_Extension",
    "Speed_Band_Overhead_Triceps", "Standing_Dumbbell_Triceps_Extension",
    "Standing_Low-Pulley_One-Arm_Triceps_Extension", "Standing_Overhead_Barbell_Triceps_Extension",
    "Standing_Towel_Triceps_Extension",
    "Triceps_Overhead_Extension_with_Rope",
  ])
  #expect(Set(variants.map(\.id)).count == 8)
}

@Test func kneeRaiseInstructionsMatchTheSourceNameAndPhotosInBothLanguages() throws {
  let russian = try #require(
    ExerciseLibrary.entries(language: .russian).first {
      $0.sourceID == "Knee_Hip_Raise_On_Parallel_Bars"
    })
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first {
      $0.sourceID == "Knee_Hip_Raise_On_Parallel_Bars"
    })
  #expect(russian.steps.contains { $0.contains("согнутые колени") })
  #expect(english.steps.contains { $0.contains("bent knees") })
  #expect(russian.id == english.id)
}

@Test func kettlebellWindmillVariantsKeepSeparateIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Kettlebell_Windmill" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Kettlebell_Windmill", "Double_Kettlebell_Windmill", "Advanced_Kettlebell_Windmill",
  ])
  #expect(Set(variants.map(\.id)).count == 3)
}

@Test func kneelingHighRowsKeepSeparateAttachmentsAndIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Kneeling_High_Pulley_Row" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Kneeling_High_Pulley_Row", "Kneeling_Single-Arm_High_Pulley_Row",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
}

@Test func kneelingHipFlexorDoesNotRepeatItsPrimaryMuscle() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Kneeling_Hip_Flexor" })
    #expect(entry.primaryMuscleIDs == [.quadriceps])
    #expect(!entry.secondaryMuscleIDs.contains(.quadriceps))
  }
}

@Test func leverageDeadliftInstructionsIncludeTheLiftInBothLanguages() throws {
  let russian = try #require(
    ExerciseLibrary.entries(language: .russian).first { $0.sourceID == "Leverage_Deadlift" })
  let english = try #require(
    ExerciseLibrary.entries(language: .english).first { $0.sourceID == "Leverage_Deadlift" })
  #expect(russian.steps.contains { $0.contains("Выпрямите ноги") })
  #expect(english.steps.contains { $0.contains("Extend your knees and hips") })
  #expect(russian.id == english.id)
}

@Test func leverageChestPressVariantsKeepTheirOwnIdentity() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Leverage_Chest_Press" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Leverage_Chest_Press", "Leverage_Decline_Chest_Press", "Leverage_Incline_Chest_Press",
  ])
  #expect(Set(variants.map(\.id)).count == 3)
  #expect(variants.allSatisfy { $0.equipment == .machine })
}

@Test func lyingCableTricepsHandlesKeepSeparateIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Cable_Lying_Triceps_Extension" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Cable_Lying_Triceps_Extension", "Low_Cable_Triceps_Extension",
  ])
  #expect(Set(variants.map(\.id)).count == 2)
  #expect(variants.contains { $0.name.contains("прямой рукоятью") })
  #expect(variants.contains { $0.name.contains("канатом") })
}

@Test func proneBackExtensionUsesLowerBackRatherThanAbdominals() throws {
  for language in [AppLanguage.russian, .english] {
    let entry = try #require(
      ExerciseLibrary.entries(language: language).first { $0.sourceID == "Lower_Back_Curl" })
    #expect(entry.primaryMuscleIDs == [.lowerBack])
  }
}

@Test func lyingDumbbellTricepsGripVariantsKeepDistinctIDs() throws {
  let entry = try #require(
    ExerciseLibrary.entries.first { $0.sourceID == "Lying_Dumbbell_Tricep_Extension" })
  let variants = ExerciseLibrary.variants(for: entry.id, language: .russian)
  #expect(Set(variants.map(\.sourceID)) == [
    "Lying_Dumbbell_Tricep_Extension", "Dumbbell_Tricep_Extension_-Pronated_Grip",
    "One_Arm_Pronated_Dumbbell_Triceps_Extension",
    "One_Arm_Supinated_Dumbbell_Triceps_Extension",
  ])
  #expect(Set(variants.map(\.id)).count == 4)
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
