import FitnessTrackerCore
import XCTest

@testable import FitnessTracker

@MainActor final class ExerciseLibraryFilterTests: XCTestCase {
  func testBodySelectionCombinesWithSearchEquipmentAndLanguage() {
    let model = ExerciseLibraryViewModel()
    model.search = "жим"
    model.equipment = .barbell
    model.group = .chest
    XCTAssertFalse(model.results.isEmpty)
    XCTAssertTrue(model.results.allSatisfy { $0.group == .chest && $0.equipment == .barbell })
    let selectedIDs = Set(model.results.map(\.id))
    model.language = .english
    XCTAssertEqual(Set(model.results.map(\.id)), selectedIDs)
    model.group = nil
    XCTAssertEqual(model.search, "жим")
    XCTAssertEqual(model.equipment, .barbell)
    XCTAssertTrue(selectedIDs.isSubset(of: Set(model.results.map(\.id))))
    model.reset()
    XCTAssertNil(model.group)
    XCTAssertNil(model.equipment)
    XCTAssertEqual(model.results.count, ExerciseLibrary.entries.count)
  }
}
