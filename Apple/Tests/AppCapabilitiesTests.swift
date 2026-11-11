import XCTest

@testable import FitLife

final class AppCapabilitiesTests: XCTestCase {
  func testCloudAvailabilityFailsClosedForMissingOrUnexpandedConfiguration() {
    for info: [String: Any] in [
      [:], ["FitLifeCloudSyncAvailable": "NO"],
      ["FitLifeCloudSyncAvailable": "$(FITLIFE_CLOUD_SYNC_AVAILABLE)"],
      ["FitLifeCloudSyncAvailable": true],
    ] {
      XCTAssertFalse(AppCapabilities(info: info).supportsCloudSync)
    }
    XCTAssertTrue(
      AppCapabilities(info: ["FitLifeCloudSyncAvailable": "YES"]).supportsCloudSync)
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
