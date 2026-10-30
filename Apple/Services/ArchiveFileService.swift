import FitnessTrackerCore
import Foundation

protocol ArchiveFileHandling: Sendable {
  func read(_ url: URL) async throws -> WorkoutArchive
  func encode(_ archive: WorkoutArchive) async throws -> Data
}

enum ArchiveFileError: Error, LocalizedError {
  case unsupportedFile, unreadable
  var errorDescription: String? {
    switch self {
    case .unsupportedFile: "Выберите файл .fitnesstracker или .json."
    case .unreadable: "Не удалось прочитать файл. Проверьте, что он доступен на устройстве."
    }
  }
}

/// The actor owns coordinated file access and JSON work; only value types reach MainActor.
actor ArchiveFileService: ArchiveFileHandling {
  func read(_ url: URL) async throws -> WorkoutArchive {
    try Task.checkCancellation()
    guard url.isFileURL,
      ["json", WorkoutArchive.fileExtension, WorkoutArchive.legacyFileExtension].contains(
        url.pathExtension.lowercased())
    else {
      throw ArchiveFileError.unsupportedFile
    }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<Data, any Error> = .failure(ArchiveFileError.unreadable)
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      coordinatedURL in
      result = Result { try Self.readBounded(coordinatedURL) }
    }
    if let coordinationError { throw coordinationError }
    let data = try result.get()
    try Task.checkCancellation()
    let archive = try WorkoutArchiveCodec.decode(data)
    try Task.checkCancellation()
    return archive
  }

  func encode(_ archive: WorkoutArchive) async throws -> Data {
    try Task.checkCancellation()
    let data = try WorkoutArchiveCodec.encode(archive)
    try Task.checkCancellation()
    return data
  }

  private static func readBounded(_ url: URL) throws -> Data {
    let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard metadata.isRegularFile == true else { throw ArchiveFileError.unreadable }
    if let size = metadata.fileSize, size > WorkoutArchiveCodec.maximumBytes {
      throw WorkoutArchiveError.tooLarge
    }
    let file = try FileHandle(forReadingFrom: url)
    defer {
      do { try file.close() } catch { AppErrorReporter.record(error, operation: "closeImportFile") }
    }
    var data = Data()
    while true {
      try Task.checkCancellation()
      let remaining = WorkoutArchiveCodec.maximumBytes + 1 - data.count
      let chunk = try file.read(upToCount: min(64 * 1024, remaining)) ?? Data()
      if chunk.isEmpty { return data }
      data.append(chunk)
      guard data.count <= WorkoutArchiveCodec.maximumBytes else {
        throw WorkoutArchiveError.tooLarge
      }
    }
  }
}
