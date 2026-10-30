import XCTest

@testable import FitnessTracker

final class AppCapabilitiesTests: XCTestCase {
  func testCloudAvailabilityFailsClosedForMissingOrUnexpandedConfiguration() {
    for info: [String: Any] in [
      [:], ["FitnessTrackerCloudSyncAvailable": "NO"],
      ["FitnessTrackerCloudSyncAvailable": "$(FITNESS_TRACKER_CLOUD_SYNC_AVAILABLE)"],
      ["FitnessTrackerCloudSyncAvailable": true],
    ] {
      XCTAssertFalse(AppCapabilities(info: info).supportsCloudSync)
    }
    XCTAssertTrue(
      AppCapabilities(info: ["FitnessTrackerCloudSyncAvailable": "YES"]).supportsCloudSync)
  }

  @MainActor func testUnavailableCloudServiceFailsBeforeAccessingAContainer() async {
    let service = CloudKitService(available: false, containerIdentifier: nil)
    do {
      _ = try await service.accountStatus()
      XCTFail("A Personal Team build must not access CloudKit")
    } catch {
      XCTAssertTrue(error is ServiceError)
    }
  }
}
