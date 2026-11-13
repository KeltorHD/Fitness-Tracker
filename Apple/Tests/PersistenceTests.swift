import FitLifeCore
import SwiftData
import XCTest

@testable import FitLife

@MainActor final class PersistenceTests: XCTestCase {
  func testAccountNamespacesAdoptTrainingAndNutritionOnceAndKeepAccountsIsolated() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = Workout(name: "Сохранённая", startedAt: Date(timeIntervalSince1970: 100))
    try WorkoutEngine.cancel(&workout, at: Date(timeIntervalSince1970: 200))
    let template = ExerciseCatalog.starterTemplates[0]
    let weight = BodyWeightEntry(weightKG: 75, workoutID: workout.id)
    let food = FoodEntry(
      title: "Food",
      portions: [
        FoodPortion(product: FoodProduct(name: "Food", per100Units: Nutrients(calories: 100)))
      ])
    try repository.save(workout)
    try repository.saveTemplate(template)
    try repository.saveBodyWeight(weight)
    try repository.saveFoodEntry(food)
    try repository.activateTrainingAccount("account-a")
    XCTAssertEqual(try repository.workouts(), [workout])
    try repository.activateTrainingAccount("account-b")
    XCTAssertTrue(try repository.workouts().isEmpty)
    XCTAssertTrue(try repository.templates().isEmpty)
    XCTAssertTrue(try repository.bodyWeights().isEmpty)
    XCTAssertTrue(try repository.foodEntries().isEmpty)
    let other = BodyWeightEntry(weightKG: 82)
    try repository.saveBodyWeight(other)
    try repository.activateTrainingAccount("account-a")
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(try repository.templates(), [template])
    XCTAssertEqual(try repository.bodyWeights(), [weight])
    XCTAssertEqual(try repository.foodEntries(), [food])
    XCTAssertEqual(repository.trainingAccountSelection.firstAccountID, "account-a")
    try repository.activateTrainingAccount("account-b")
    XCTAssertEqual(try repository.bodyWeights(), [other])
  }

  func testNutritionMigrationAdoptsExistingUnscopedDataIntoFirstKnownAccount() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    try repository.activateTrainingAccount("account-a")
    let product = FoodProduct(
      id: "saved-product", name: "Продукт", per100Units: Nutrients(calories: 100))
    let food = FoodEntry(
      title: "Еда", portions: [FoodPortion(product: product)], photo: Data([255, 216, 255]))
    let goal = NutritionGoal(calories: 2100, waterMilliliters: 2000)
    let plan = SupplementPlan(prototype: SupplementEntry(kind: .creatine, amount: 3))
    let intake = plan.intake(scheduledFor: plan.startDate, takenAt: plan.startDate)
    let context = ModelContext(repository.container)
    context.insert(
      StoredRecord(id: food.id, kind: "foodEntry", payload: try JSONEncoder().encode(food)))
    context.insert(
      StoredRecord(
        id: intake.id, kind: "supplementEntry", payload: try JSONEncoder().encode(intake)))
    context.insert(
      StoredRecord(id: UUID(), kind: "nutritionGoal", payload: try JSONEncoder().encode(goal)))
    context.insert(
      StoredRecord(
        id: UUID(), kind: "favoriteFoodProduct", payload: try JSONEncoder().encode(product)))
    try context.save()
    // The first account retains ownership even if another account is selected during upgrade.
    try repository.activateTrainingAccount("account-b")
    XCTAssertTrue(try repository.nutritionSnapshot().values.isEmpty)
    try repository.activateTrainingAccount("account-a")
    XCTAssertEqual(try repository.foodEntries(), [food])
    XCTAssertEqual(try repository.supplementEntries(), [intake])
    XCTAssertEqual(try repository.nutritionGoal(), goal)
    XCTAssertEqual(try repository.favoriteFoodProducts(), [product])
    try repository.activateTrainingAccount("account-b")
    try repository.activateTrainingAccount("account-a")
    XCTAssertEqual(try repository.foodEntries().count, 1)
    let stored = try ModelContext(repository.container).fetch(FetchDescriptor<StoredRecord>())
    XCTAssertFalse(
      stored.contains {
        ["nutritionGoal", "favoriteFoodProduct", "foodEntry", "supplementEntry"].contains($0.kind)
      })
    XCTAssertEqual(stored.filter { $0.kind == "nutritionProfile@account-a" }.count, 1)
  }

  func testNutritionRemoteBatchAndAccountAdoptionRollbackWithoutLosingLocalRecords() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let water = WaterEntry(milliliters: 250)
    try repository.saveWaterEntry(water)
    let context = ModelContext(repository.container)
    let corrupt = StoredRecord(id: UUID(), kind: "template", payload: Data("broken".utf8))
    context.insert(corrupt)
    try context.save()
    XCTAssertThrowsError(try repository.activateTrainingAccount("account-a"))
    XCTAssertNil(repository.trainingAccountSelection.firstAccountID)
    XCTAssertEqual(try repository.waterEntries(), [water])
    let raw = try ModelContext(repository.container).fetch(FetchDescriptor<StoredRecord>())
    XCTAssertTrue(raw.contains { $0.kind == "waterEntry" && $0.recordID == water.id })
    XCTAssertFalse(raw.contains { $0.kind == "waterEntry@account-a" })
    context.delete(corrupt)
    try context.save()
    try repository.activateTrainingAccount("account-a")
    let profile = NutritionProfile(goal: NutritionGoal(calories: 2200), favorites: [])
    try repository.applyTrainingChanges([
      TrainingChange(key: .init(kind: .waterEntry, id: water.id), revision: 1, value: nil),
      TrainingChange(
        key: .init(kind: .nutritionProfile, id: profile.id), revision: 2,
        value: .nutritionProfile(profile)),
    ])
    XCTAssertTrue(try repository.waterEntries().isEmpty)
    XCTAssertEqual(try repository.nutritionGoal(), profile.goal)
  }

  func testCorruptDestinationNutritionPreventsAccountSwitchWithoutChangingCurrentJournal() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    try repository.activateTrainingAccount("account-a")
    let water = WaterEntry(milliliters: 250)
    try repository.saveWaterEntry(water)
    let context = ModelContext(repository.container)
    context.insert(
      StoredRecord(id: UUID(), kind: "supplementPlan@account-b", payload: Data("broken".utf8)))
    try context.save()
    XCTAssertThrowsError(try repository.activateTrainingAccount("account-b"))
    XCTAssertEqual(repository.trainingAccountSelection.currentAccountID, "account-a")
    XCTAssertEqual(try repository.waterEntries(), [water])
  }

  func testFailedAccountAdoptionRollsBackRetaggingAndRemoteBatchKeepsAllRoots() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let active = Workout(name: "Текущая")
    try repository.save(active)
    let invalid = StoredRecord(id: UUID(), kind: "template", payload: Data("broken".utf8))
    repository.container.mainContext.insert(invalid)
    try repository.container.mainContext.save()
    XCTAssertThrowsError(try repository.activateTrainingAccount("account-a"))
    XCTAssertEqual(repository.trainingAccountSelection, TrainingAccountSelection())
    XCTAssertEqual(try repository.workouts(), [active])
    repository.container.mainContext.delete(invalid)
    try repository.container.mainContext.save()
    try repository.activateTrainingAccount("account-a")
    let weight = BodyWeightEntry(weightKG: 70)
    let otherActive = TrainingValue.workout(Workout(name: "Другая"))
    XCTAssertThrowsError(
      try repository.applyTrainingChanges([
        TrainingChange(
          key: TrainingValue.bodyWeight(weight).key, revision: 1, value: .bodyWeight(weight)),
        TrainingChange(key: otherActive.key, revision: 2, value: otherActive),
      ]))
    XCTAssertTrue(try repository.bodyWeights().isEmpty)
    XCTAssertEqual(try repository.workouts(), [active])
    XCTAssertThrowsError(try repository.activateTrainingAccount("account-b"))
    XCTAssertEqual(repository.trainingAccountSelection.currentAccountID, "account-a")
  }

  func testTemplateVariationsAndSupersetMembershipSurvivePersistenceAndArchiveImport() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let groupID = UUID()
    let template = WorkoutTemplate(
      name: "Вариации",
      exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
      variations: [
        WorkoutTemplateVariation(
          name: "Суперсет",
          exercises: [
            TemplateExercise(exercise: ExerciseCatalog.all[1], setCount: 2, supersetID: groupID),
            TemplateExercise(exercise: ExerciseCatalog.all[2], setCount: 2, supersetID: groupID),
          ])
      ], baseVariationName: "Основной жим", muscleRegions: [.chestUpper, .deltoidAnterior])
    let variation = try XCTUnwrap(template.variations.first)
    var workout = try template.resolvedVariation(id: variation.id).start(at: date)
    let first = try XCTUnwrap(workout.exercises.first)
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: first.id, setID: first.sets[0].id,
      repetitions: 8, weightKG: 40, at: date)
    try repository.saveTemplate(template)
    try repository.save(workout)
    XCTAssertEqual(try repository.templates(), [template])
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(workout.nextPendingSet?.exerciseID, workout.exercises[1].id)
    var completionIndex = 1
    for row in workout.exercises {
      for set in row.sets where !set.isFullyCompleted {
        completionIndex += 1
        try WorkoutEngine.completeSet(
          in: &workout, exerciseID: row.id, setID: set.id, repetitions: 8, weightKG: 40,
          at: date.addingTimeInterval(Double(completionIndex)))
      }
    }
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(600))
    let archive = try WorkoutArchiveCodec.decode(
      WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [workout], templates: [template])))
    let restored = try SwiftDataWorkoutRepository(inMemory: true)
    _ = try restored.importArchive(archive)
    XCTAssertEqual(try restored.templates(), [template])
    XCTAssertEqual(try restored.workouts(), [workout])
    XCTAssertEqual(archive.workouts, [workout])
  }

  func testDropStagesAndMixedTemplateTargetsRoundTrip() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let row = WorkoutExercise(
      exercise: Exercise(name: "Drop", muscle: .back),
      sets: [WorkoutSet(repetitions: 10, weightKG: 50, dropStages: [DropSetStage(weightKG: 40)])])
    var workout = Workout(name: "Drop", startedAt: date, exercises: [row])
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id, repetitions: 10, weightKG: 50,
      at: date.addingTimeInterval(1))
    let stage = try XCTUnwrap(row.sets[0].dropStages?.first)
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: row.sets[0].id, stageID: stage.id, repetitions: 8,
      weightKG: 40, at: date.addingTimeInterval(2))
    try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(3))
    let template = try WorkoutEngine.makeTemplate(from: workout)
    try repository.save(workout)
    try repository.saveTemplate(template)
    XCTAssertEqual(try repository.workouts(), [workout])
    XCTAssertEqual(try repository.templates(), [template])
    let archive = try WorkoutArchiveCodec.decode(
      WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [workout], templates: [template])))
    XCTAssertEqual(archive.workouts, [workout])
    XCTAssertEqual(archive.templates, [template])
  }
  func testBodyWeightRoundTripDeleteAndCombinedArchiveImport() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var entry = BodyWeightEntry(measuredAt: Date(timeIntervalSince1970: 100), weightKG: 72.5)
    try repository.saveBodyWeight(entry)
    entry.weightKG = 71.5
    try repository.saveBodyWeight(entry)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    var invalid = entry
    invalid.weightKG = 0
    XCTAssertThrowsError(try repository.saveBodyWeight(invalid))
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    try repository.deleteBodyWeight(id: entry.id)
    let workout = Workout(name: "Weight fixture", bodyWeightKG: 72)
    let archive = WorkoutArchive(workouts: [workout], templates: [], bodyWeights: [entry])
    XCTAssertEqual(try repository.importArchive(archive).addedBodyWeights, 1)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    XCTAssertEqual(try repository.workouts().first?.bodyWeightKG, 72)
    XCTAssertFalse(try repository.importArchive(archive).hasChanges)
  }
  func testSharedBodyWeightAndWorkoutWritesAndDeletionAreAtomic() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = Workout(name: "Atomic weight", startedAt: Date(timeIntervalSince1970: 100))
    try repository.save(workout)
    let entry = BodyWeightEntry(
      measuredAt: Date(timeIntervalSince1970: 200), weightKG: 72.5, workoutID: workout.id)
    try WorkoutEngine.setBodyWeight(entry.weightKG, in: &workout)
    try repository.saveBodyWeight(entry, updating: workout)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    XCTAssertEqual(try repository.workouts(), [workout])
    var changed = entry
    changed.weightKG = 73
    var invalidWorkout = workout
    invalidWorkout.name = ""
    XCTAssertThrowsError(try repository.saveBodyWeight(changed, updating: invalidWorkout))
    var invalidEntry = entry
    invalidEntry.weightKG = 0
    var changedWorkout = workout
    try WorkoutEngine.setBodyWeight(74, in: &changedWorkout)
    XCTAssertThrowsError(try repository.saveBodyWeight(invalidEntry, updating: changedWorkout))
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    XCTAssertEqual(try repository.workouts(), [workout])
    let archive = WorkoutArchive(
      workouts: [workout], templates: [], bodyWeights: [entry],
      exportedAt: Date(timeIntervalSince1970: 300))
    XCTAssertEqual(try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive)), archive)
    try WorkoutEngine.cancel(&workout, at: Date(timeIntervalSince1970: 300))
    try repository.save(workout)
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    var invalidDeletion = workout
    invalidDeletion.name = ""
    XCTAssertThrowsError(try repository.deleteBodyWeight(id: entry.id, updating: invalidDeletion))
    XCTAssertEqual(try repository.bodyWeights(), [entry])
    XCTAssertEqual(try repository.workouts(), [workout])
    workout.bodyWeightKG = nil
    try repository.deleteBodyWeight(id: entry.id, updating: workout)
    XCTAssertTrue(try repository.bodyWeights().isEmpty)
    XCTAssertEqual(try repository.workouts(), [workout])
  }
  func testSwiftDataUpsertRoundTripAndDelete() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = try ExerciseCatalog.starterTemplates[0].start()
    try repository.save(workout)
    workout.notes = "После восстановления"
    try repository.save(workout)
    let restored = try repository.workouts()
    XCTAssertEqual(restored, [workout])
    try repository.deleteWorkout(id: workout.id)
    XCTAssertTrue(try repository.workouts().isEmpty)
  }
  func testTemplateRoundTrip() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let template = ExerciseCatalog.starterTemplates[0]
    try repository.saveTemplate(template)
    XCTAssertEqual(try repository.templates(), [template])
    try repository.deleteTemplate(id: template.id)
    XCTAssertTrue(try repository.templates().isEmpty)
  }
  func testFailedValidationLeavesStoredValueUnchanged() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    var workout = Workout(name: "A")
    try repository.save(workout)
    workout.name = ""
    XCTAssertThrowsError(try repository.save(workout))
    XCTAssertEqual(try repository.workouts().first?.name, "A")
  }
  func testArchiveImportIsAtomicAndIdempotentAcrossBothRecordKinds() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let original = Workout(name: "Текущая тренировка", startedAt: Date(timeIntervalSince1970: 100))
    try repository.save(original)
    let template = ExerciseCatalog.starterTemplates[0]
    var malformed = original
    malformed.id = UUID()
    malformed.name = ""
    XCTAssertThrowsError(
      try repository.importArchive(WorkoutArchive(workouts: [malformed], templates: [template])))
    XCTAssertTrue(try repository.templates().isEmpty)
    XCTAssertEqual(try repository.workouts(), [original])
    var modified = original
    modified.notes = "Не заменяет оригинал"
    let archive = WorkoutArchive(workouts: [modified], templates: [template])
    let first = try repository.importArchive(archive)
    XCTAssertEqual(first.addedTemplates, 1)
    XCTAssertEqual(first.skippedExisting, 1)
    XCTAssertEqual(try repository.workouts(), [original])
    let again = try repository.importArchive(archive)
    XCTAssertFalse(again.hasChanges)
    XCTAssertEqual(try repository.templates(), [template])
  }
}
