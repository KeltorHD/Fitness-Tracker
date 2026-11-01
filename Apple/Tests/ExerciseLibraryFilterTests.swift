import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

@MainActor final class ExerciseLibraryFilterTests: XCTestCase {
  func testBodySelectionCombinesWithSearchEquipmentAndLanguage() {
    let model = ExerciseLibraryViewModel()
    model.search = "жим"
    model.equipment = [.barbell]
    model.groups = [.chest]
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(model.results.allSatisfy { $0.group == .chest && $0.equipment == .barbell })
    let selectedIDs = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), selectedIDs)
    model.groups = []
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.equipment, [.barbell])
    XCTAssertTrue(selectedIDs.isSubset(of: Set(model.results.map(\.id))))
    model.reset()
    XCTAssertTrue(model.groups.isEmpty)
    XCTAssertTrue(model.equipment.isEmpty)
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}

extension ExerciseLibraryFilterTests {
  func testTemplateGroupsAreActiveImmediatelyAndCanBeChangedOrReset() {
    let groups: Set<MuscleGroup> = [.chest, .arms]
    let model = ExerciseLibraryViewModel(groups: groups)
    XCTAssertEqual(model.groups, groups)
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertEqual(Set(model.results.map(\.group)), groups)
    model.search = "жим"
    model.equipment = [.barbell]
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(
      model.results.allSatisfy { groups.contains($0.group) && $0.equipment == .barbell })
    let selectedIDs = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), selectedIDs)
    model.groups = [.legs]
    XCTAssertEqual(model.groups, [.legs])
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.equipment, [.barbell])
    model.reset()
    XCTAssertTrue(model.groups.isEmpty)
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}

extension ExerciseLibraryFilterTests {
  func testMultipleEquipmentSelectionCanBeChangedAndClearedIndependently() {
    let model = ExerciseLibraryViewModel(groups: [.chest])
    model.search = "жим"
    model.equipment = [.barbell, .dumbbell]
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertEqual(Set(model.results.map(\.equipment)), [.barbell, .dumbbell])
    XCTAssertTrue(model.results.allSatisfy { $0.group == .chest })
    let ids = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), ids)
    model.equipment.remove(.barbell)
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(model.results.allSatisfy { $0.equipment == .dumbbell })
    model.equipment = []
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.groups, [.chest])
    XCTAssertTrue(ids.isSubset(of: Set(model.results.map(\.id))))
    model.equipment = [.bodyWeight, .bands]
    model.reset()
    XCTAssertTrue(model.equipment.isEmpty)
    XCTAssertTrue(model.groups.isEmpty)
    XCTAssertEqual(model.search, "")
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}

extension ExerciseLibraryFilterTests {
  func testIndividualMusclePreferencesAreActiveImmediatelyAndCombineWithOtherFilters() {
    let model = ExerciseLibraryViewModel(muscles: [.biceps])
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(model.results.allSatisfy { $0.primaryMuscleIDs.contains(.biceps) })
    model.search = "curl"
    model.equipment = [.barbell, .dumbbell]
    XCTAssertFalse(model.results.isEmpty)
    let ids = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), ids)
    model.muscleSelection.set(MuscleGroup.arms, selected: true)
    XCTAssertTrue(ids.isSubset(of: Set(model.results.map(\.id))))
    model.muscleSelection.set(.biceps, selected: false)
    XCTAssertEqual(model.muscleSelection.state(of: .arms), .partial)
    XCTAssertTrue(model.results.allSatisfy { !$0.primaryMuscleIDs.contains(.biceps) })
    XCTAssertEqual(model.search, "curl")
    XCTAssertEqual(model.equipment, [.barbell, .dumbbell])
    model.reset()
    XCTAssertTrue(model.muscleSelection.isEmpty)
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}
