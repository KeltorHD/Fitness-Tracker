import UIKit
import XCTest

@testable import FitSession

private struct ImageDataStub: ExerciseImageLoading {
  let result: Result<Data, any Error>
  func data(for path: String) async throws -> Data { try result.get() }
}

@MainActor final class ExerciseImageTests: XCTestCase {
  func testImageLoadingReportsInvalidDataAndIgnoresCancellation() async throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
    let data = renderer.pngData { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    let success = ExercisePhotoViewModel(loader: ImageDataStub(result: .success(data)))
    await success.load(path: "exercise/0.jpg")
    XCTAssertNotNil(success.image)
    XCTAssertFalse(success.failed)
    let failure = ExercisePhotoViewModel(loader: ImageDataStub(result: .success(Data())))
    await failure.load(path: "exercise/0.jpg")
    XCTAssertTrue(failure.failed)
    XCTAssertNil(failure.image)
    let cancelled = ExercisePhotoViewModel(
      loader: ImageDataStub(result: .failure(CancellationError())))
    await cancelled.load(path: "exercise/0.jpg")
    XCTAssertFalse(cancelled.failed)
  }

  func testLocalLoaderReadsBundledShapeAndRejectsTraversalAndSymlinks() async throws {
    let files = FileManager.default
    let temporary = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = temporary.appendingPathComponent("ExerciseMedia")
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      do { try files.removeItem(at: temporary) } catch {
        XCTFail("Failed to clean image fixture: \(error)")
      }
    }
    let fixture = Data([1, 2, 3])
    try fixture.write(to: directory.appendingPathComponent("fixture.jpg"))
    try fixture.write(to: temporary.appendingPathComponent("outside.jpg"))
    try files.createSymbolicLink(
      at: directory.appendingPathComponent("link.jpg"),
      withDestinationURL: temporary.appendingPathComponent("outside.jpg"))
    let loader = ExerciseImageLoader(directory: directory)
    let data = try await loader.data(for: "fixture.jpg")
    XCTAssertEqual(data, fixture)
    for path in ["../outside.jpg", "/outside.jpg", "link.jpg", ""] {
      do {
        _ = try await loader.data(for: path)
        XCTFail("Unsafe path was accepted")
      } catch { XCTAssertTrue(error is ExerciseImageError) }
    }
    do {
      _ = try await loader.data(for: "missing.jpg")
      XCTFail("Missing resource was accepted")
    } catch {
      XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
      XCTAssertEqual((error as NSError).code, NSFileReadNoSuchFileError)
    }
  }
}
