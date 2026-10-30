import FitnessTrackerCore
import UniformTypeIdentifiers
import XCTest

@testable import FitnessTracker

private struct ArchiveFileStub: ArchiveFileHandling {
  let result: Result<WorkoutArchive, any Error>
  func read(_ url: URL) async throws -> WorkoutArchive { try result.get() }
  func encode(_ archive: WorkoutArchive) async throws -> Data {
    try WorkoutArchiveCodec.encode(archive)
  }
}

@MainActor private final class ControlledArchiveFiles: ArchiveFileHandling {
  private(set) var requests: [CheckedContinuation<WorkoutArchive, any Error>] = []
  private var waiter: CheckedContinuation<Void, Never>?
  func read(_ url: URL) async throws -> WorkoutArchive {
    try await withCheckedThrowingContinuation { continuation in
      requests.append(continuation)
      waiter?.resume()
      waiter = nil
    }
  }
  func encode(_ archive: WorkoutArchive) async throws -> Data {
    try WorkoutArchiveCodec.encode(archive)
  }
  func waitForRead(count: Int) async {
    while requests.count < count { await withCheckedContinuation { waiter = $0 } }
  }
}

@MainActor final class ArchiveTransferTests: XCTestCase {
  func testCSVFileHasPreviewAndRequiresConfirmationBeforeSaving() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("fixture.csv")
    let header = FitSessionCSVColumn.allCases.map(\.header).joined(separator: ";")
    try Data((header + "\n29.10.26;18:30;CSV fixture;Custom;;10;2;;8;;;").utf8).write(to: url)
    let repository = MemoryWorkoutRepository()
    let model = ArchiveTransferViewModel(
      files: ArchiveFileService(), snapshot: { WorkoutArchive(workouts: [], templates: []) },
      plan: {
        try ArchiveImportPlan(
          archive: $0, existingWorkouts: repository.workouts(), existingTemplates: []
        ).summary
      },
      commit: { try repository.importArchive($0) })
    model.selectFile(url)
    await model.load(try XCTUnwrap(model.request))
    XCTAssertEqual(model.preview?.unknownDurationCount, 1)
    XCTAssertEqual(model.preview?.summary.addedWorkouts, 1)
    XCTAssertTrue(try repository.workouts().isEmpty)
    model.requestImport()
    await model.confirmImport()
    XCTAssertEqual(try repository.workouts().first?.volume, 160)
    XCTAssertEqual(try repository.workouts().first?.durationIsKnown, false)
  }
  private func makeArchive() -> WorkoutArchive {
    WorkoutArchive(
      workouts: [Workout(name: "Импорт", startedAt: Date(timeIntervalSince1970: 100))],
      templates: [])
  }

  func testImportRequiresExplicitConfirmationAndUpdatesRepositoryOnce() async throws {
    let repository = MemoryWorkoutRepository()
    let archive = makeArchive()
    let model = ArchiveTransferViewModel(
      files: ArchiveFileStub(result: .success(archive)),
      snapshot: {
        WorkoutArchive(workouts: try repository.workouts(), templates: try repository.templates())
      },
      plan: {
        try ArchiveImportPlan(
          archive: $0, existingWorkouts: repository.workouts(),
          existingTemplates: repository.templates()
        ).summary
      },
      commit: { try repository.importArchive($0) })
    model.openFile(URL(fileURLWithPath: "/fixture.fitnesstracker"))
    await model.load(try XCTUnwrap(model.request))
    XCTAssertEqual(model.preview?.summary.addedWorkouts, 1)
    XCTAssertTrue(try repository.workouts().isEmpty)
    await model.confirmImport()
    XCTAssertTrue(try repository.workouts().isEmpty)
    model.requestImport()
    await model.confirmImport()
    XCTAssertEqual(try repository.workouts(), archive.workouts)
    XCTAssertNotNil(model.notice)
    XCTAssertNil(model.preview)
    XCTAssertNil(model.commitRequestID)
    await model.confirmImport()
    XCTAssertEqual(try repository.workouts().count, 1)
  }

  func testImportRechecksRepositoryChangesAfterPreview() async throws {
    let repository = MemoryWorkoutRepository()
    let archive = makeArchive()
    let model = ArchiveTransferViewModel(
      files: ArchiveFileStub(result: .success(archive)), snapshot: { archive },
      plan: {
        try ArchiveImportPlan(
          archive: $0, existingWorkouts: repository.workouts(), existingTemplates: []
        ).summary
      },
      commit: { try repository.importArchive($0) })
    model.selectFile(URL(fileURLWithPath: "/fixture.json"))
    await model.load(try XCTUnwrap(model.request))
    var existing = try XCTUnwrap(archive.workouts.first)
    existing.notes = "Изменено после предпросмотра"
    try repository.save(existing)
    model.requestImport()
    await model.confirmImport()
    XCTAssertEqual(try repository.workouts(), [existing])
    XCTAssertNil(model.errorMessage)
  }

  func testFailedImportKeepsPreviewForExplicitRetryAndHidesPrivateDiagnostics() async throws {
    let archive = makeArchive()
    var attempts = 0
    let model = ArchiveTransferViewModel(
      files: ArchiveFileStub(result: .success(archive)), snapshot: { archive },
      plan: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      },
      commit: { _ in
        attempts += 1
        throw NSError(
          domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private diagnostic"])
      })
    model.selectFile(URL(fileURLWithPath: "/fixture.json"))
    await model.load(try XCTUnwrap(model.request))
    model.requestImport()
    await model.confirmImport()
    XCTAssertEqual(attempts, 1)
    XCTAssertNotNil(model.preview)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.errorMessage?.contains("private diagnostic") ?? true)
    await model.confirmImport()
    XCTAssertEqual(attempts, 1)
    model.requestImport()
    await model.confirmImport()
    XCTAssertEqual(attempts, 2)
  }

  func testStaleFileReadCannotReplaceTheLatestPreviewOrStopItsLoadingState() async throws {
    let files = ControlledArchiveFiles()
    let archive = makeArchive()
    let model = ArchiveTransferViewModel(
      files: files, snapshot: { archive },
      plan: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      },
      commit: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      })
    model.selectFile(URL(fileURLWithPath: "/old.json"))
    let oldRequest = try XCTUnwrap(model.request)
    let first = Task { await model.load(oldRequest) }
    await files.waitForRead(count: 1)
    model.selectFile(URL(fileURLWithPath: "/new.fitnesstracker"))
    let newRequest = try XCTUnwrap(model.request)
    let second = Task { await model.load(newRequest) }
    await files.waitForRead(count: 2)
    files.requests[0].resume(returning: archive)
    await first.value
    XCTAssertTrue(model.isLoading)
    XCTAssertNil(model.preview)
    files.requests[1].resume(returning: archive)
    await second.value
    XCTAssertFalse(model.isLoading)
    XCTAssertEqual(model.preview?.fileName, "new.fitnesstracker")
  }

  func testReadCancellationDoesNotShowAnErrorOrPreview() async throws {
    let archive = makeArchive()
    let model = ArchiveTransferViewModel(
      files: ArchiveFileStub(result: .failure(CancellationError())), snapshot: { archive },
      plan: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      },
      commit: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      })
    model.selectFile(URL(fileURLWithPath: "/fixture.json"))
    await model.load(try XCTUnwrap(model.request))
    XCTAssertNil(model.preview)
    XCTAssertNil(model.errorMessage)
    XCTAssertFalse(model.isLoading)
  }

  func testExportSnapshotCoversWholeArchiveOrSelectedWorkoutAndCancelDoesNotAnnounceSuccess() throws
  {
    let archive = WorkoutArchive(
      workouts: makeArchive().workouts, templates: ExerciseCatalog.starterTemplates)
    let model = ArchiveTransferViewModel(
      files: ArchiveFileStub(result: .success(archive)), snapshot: { archive },
      plan: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      },
      commit: {
        try ArchiveImportPlan(archive: $0, existingWorkouts: [], existingTemplates: []).summary
      })
    model.present()
    model.prepareExport()
    XCTAssertEqual(model.exportDocument?.archive, archive)
    model.exportCancelled()
    XCTAssertNil(model.notice)
    model.showingExporter = false
    model.present(workout: try XCTUnwrap(archive.workouts.first), format: .json)
    model.prepareExport()
    XCTAssertEqual(model.exportDocument?.archive.workouts, archive.workouts)
    XCTAssertTrue(try XCTUnwrap(model.exportDocument).archive.templates.isEmpty)
    XCTAssertEqual(model.format, .json)
    XCTAssertEqual(UTType.fitnessTracker.preferredFilenameExtension, "fitnesstracker")
    XCTAssertTrue(UTType.fitnessTracker.conforms(to: .json))
  }

  func testFileServiceReadsBothExtensionsAndRejectsOversizedOrUnsupportedFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: directory) } catch {
        XCTFail("Failed to clean archive fixtures: \(error)")
      }
    }
    let files = ArchiveFileService()
    let archive = makeArchive()
    let data = try await files.encode(archive)
    for suffix in ["json", "fitnesstracker", "FITNESS_TRACKER"] {
      let url = directory.appendingPathComponent("fixture.\(suffix)")
      try data.write(to: url)
      let restored = try await files.read(url)
      XCTAssertEqual(restored.workouts, archive.workouts)
    }
    let oversized = directory.appendingPathComponent("large.fitnesstracker")
    try Data(repeating: 0, count: WorkoutArchiveCodec.maximumBytes + 1).write(to: oversized)
    do {
      _ = try await files.read(oversized)
      XCTFail("Oversized archive was accepted")
    } catch { XCTAssertEqual(error as? WorkoutArchiveError, .tooLarge) }
    do {
      _ = try await files.read(directory.appendingPathComponent("unsupported.txt"))
      XCTFail("Unsupported extension was accepted")
    } catch { XCTAssertTrue(error is ArchiveFileError) }
  }
}
