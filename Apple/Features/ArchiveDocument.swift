import CoreTransferable
import FitnessTrackerCore
import Foundation
import UniformTypeIdentifiers

extension UTType {
  static let fitnessTracker = UTType(
    exportedAs: WorkoutArchive.formatIdentifier, conformingTo: .json)
  static let legacyWorkoutArchive = UTType(
    exportedAs: WorkoutArchive.legacyFormatIdentifier, conformingTo: .json)
}

enum ArchiveExportFormat: String, CaseIterable, Identifiable, Sendable {
  case fitnessTracker, json
  var id: Self { self }
  var title: String { self == .json ? "JSON (.json)" : "FitnessTracker (.fitnesstracker)" }
  var contentType: UTType { self == .json ? .json : .fitnessTracker }
}

struct ArchiveDocument: Transferable, Sendable {
  let archive: WorkoutArchive
  let files: any ArchiveFileHandling
  let format: ArchiveExportFormat

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .fitnessTracker) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitnessTracker.fitnesstracker").exportingCondition {
      $0.format == .fitnessTracker
    }
    DataRepresentation(exportedContentType: .json) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitnessTracker.json").exportingCondition { $0.format == .json }
  }
}
