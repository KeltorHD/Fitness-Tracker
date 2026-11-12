import FitnessTrackerCore
import ImageIO
import UIKit
import XCTest

@testable import FitnessTracker

@MainActor final class NutritionTests: XCTestCase {
  func testNewNutritionRecordsAndBatchValidationPreserveStoredHistory() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let product = FoodProduct(id: "12345678", name: "Food", per100Units: Nutrients(calories: 200))
    let entry = FoodEntry(title: "Food", portions: [FoodPortion(product: product)])
    try repository.saveFoodEntry(entry)
    try repository.setFavoriteFoodProduct(product, isFavorite: true)
    let water = WaterEntry(milliliters: 250)
    try repository.saveWaterEntry(water)
    XCTAssertEqual(try repository.waterEntries(), [water])
    XCTAssertEqual(try repository.favoriteFoodProducts(), [product])
    let copy = entry.repeated(on: entry.date)
    var invalid = copy.repeated(on: entry.date)
    invalid.portions[0].amount = -1
    XCTAssertThrowsError(try repository.saveFoodEntries([copy, invalid]))
    XCTAssertEqual(try repository.foodEntries(), [entry])
    try repository.saveFoodEntries([copy])
    XCTAssertEqual(try repository.foodEntries().count, 2)
    try repository.deleteWaterEntry(id: water.id)
    XCTAssertTrue(try repository.waterEntries().isEmpty)
    try repository.deleteFoodEntry(id: entry.id)
    XCTAssertEqual(try repository.favoriteFoodProducts(), [product])
    try repository.setFavoriteFoodProduct(product, isFavorite: false)
    XCTAssertTrue(try repository.favoriteFoodProducts().isEmpty)
  }

  func testSwiftDataFoodAndGoalRoundTripWithoutChangingWorkoutRecords() throws {
    let repository = try SwiftDataWorkoutRepository(inMemory: true)
    let workout = Workout(name: "Workout")
    try repository.save(workout)
    let product = FoodProduct(
      name: "Food", per100Units: Nutrients(calories: 120, protein: 5, fat: 4, carbohydrates: 16))
    var entry = FoodEntry(title: "Snack", portions: [FoodPortion(product: product, amount: 150)])
    try repository.saveFoodEntry(entry)
    entry.note = "Edited"
    try repository.saveFoodEntry(entry)
    XCTAssertEqual(try repository.foodEntries(), [entry])
    var invalid = entry
    invalid.portions[0].amount = -1
    XCTAssertThrowsError(try repository.saveFoodEntry(invalid))
    XCTAssertEqual(try repository.foodEntries(), [entry])
    let goal = NutritionGoal(calories: 2100, protein: 120)
    try repository.saveNutritionGoal(goal)
    XCTAssertEqual(try repository.nutritionGoal(), goal)
    try repository.saveNutritionGoal(nil)
    XCTAssertNil(try repository.nutritionGoal())
    try repository.deleteFoodEntry(id: entry.id)
    XCTAssertTrue(try repository.foodEntries().isEmpty)
    XCTAssertEqual(try repository.workouts(), [workout])
  }

  func testPhotoIsResizedAndReencodedWithoutLocationMetadata() async throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1600))
    let image = renderer.image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1600))
    }
    let input = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
    let original = try XCTUnwrap(CGImageSourceCreateWithData(input as CFData, nil))
    let tagged = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(tagged as CFMutableData, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(
      destination, original, 0,
      [
        kCGImagePropertyGPSDictionary: [
          kCGImagePropertyGPSLatitude: 12.0,
          kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 34.0,
          kCGImagePropertyGPSLongitudeRef: "E",
        ]
      ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let output = try await MealPhotoProcessor().jpeg(from: tagged as Data)
    XCTAssertLessThanOrEqual(output.count, 600_000)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 1280)
    XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), 1280)
    let entry = FoodEntry(title: "Photo", photo: output)
    try entry.validate()
    XCTAssertTrue(entry.needsNutrition)
    do {
      _ = try await MealPhotoProcessor().jpeg(from: Data([1, 2, 3]))
      XCTFail("Expected corrupt photo rejection")
    } catch is NutritionError {
      // Expected invalid image rejection.
    }
  }

  func testFoodEditorCancellationDoesNotMutatePersistedEntry() throws {
    let repository = MemoryNutritionRepository()
    let product = FoodProduct(name: "Food", per100Units: Nutrients(calories: 100))
    let entry = FoodEntry(title: "Original", portions: [FoodPortion(product: product)])
    try repository.saveFoodEntry(entry)
    let editor = FoodEntryEditorModel(entry: entry)
    editor.entry.title = "Draft"
    try editor.add(product, amount: 150)
    XCTAssertEqual(try repository.foodEntries(), [entry])
    XCTAssertEqual(try editor.validatedEntry().nutrients.calories, 250)
  }
}
