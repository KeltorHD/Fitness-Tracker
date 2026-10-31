import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

@MainActor final class ExerciseLibraryFilterTests: XCTestCase {
  func testBodySelectionCombinesWithSearchEquipmentAndLanguage() {
    let model = ExerciseLibraryViewModel()
    model.search = "жим"
    model.equipment = .barbell
    model.groups = [.chest]
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(model.results.allSatisfy { $0.group == .chest && $0.equipment == .barbell })
    let selectedIDs = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), selectedIDs)
    model.groups = []
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.equipment, .barbell)
    XCTAssertTrue(selectedIDs.isSubset(of: Set(model.results.map(\.id))))
    model.reset()
    XCTAssertTrue(model.groups.isEmpty)
    XCTAssertNil(model.equipment)
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
    model.equipment = .barbell
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(
      model.results.allSatisfy { groups.contains($0.group) && $0.equipment == .barbell })
    let selectedIDs = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), selectedIDs)
    model.groups = [.legs]
    XCTAssertEqual(model.groups, [.legs])
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.equipment, .barbell)
    model.reset()
    XCTAssertTrue(model.groups.isEmpty)
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}
