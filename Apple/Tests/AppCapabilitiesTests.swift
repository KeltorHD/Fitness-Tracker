import XCTest

@testable import FitSession

final class AppCapabilitiesTests: XCTestCase {
  func testCloudAvailabilityFailsClosedForMissingOrUnexpandedConfiguration() {
    for info: [String: Any] in [
      [:], ["FitSessionCloudSyncAvailable": "NO"],
      ["FitSessionCloudSyncAvailable": "$(FITSESSION_CLOUD_SYNC_AVAILABLE)"],
      ["FitSessionCloudSyncAvailable": true],
    ] {
      XCTAssertFalse(AppCapabilities(info: info).supportsCloudSync)
    }
    XCTAssertTrue(AppCapabilities(info: ["FitSessionCloudSyncAvailable": "YES"]).supportsCloudSync)
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
