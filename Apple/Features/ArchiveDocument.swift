import CoreTransferable
import FitLifeCore
import Foundation
import UniformTypeIdentifiers

extension UTType {
  static let fitLife = UTType(
    exportedAs: WorkoutArchive.formatIdentifier, conformingTo: .json)
}

enum ArchiveExportFormat: String, CaseIterable, Identifiable, Sendable {
  case fitLife, json
  var id: Self { self }
  var title: String { self == .json ? "JSON (.json)" : "FitLife (.fitlife)" }
  var contentType: UTType { self == .json ? .json : .fitLife }
}

struct ArchiveDocument: Transferable, Sendable {
  let archive: WorkoutArchive
  let files: any ArchiveFileHandling
  let format: ArchiveExportFormat

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .fitLife) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitLife.fitlife").exportingCondition {
      $0.format == .fitLife
    }
    DataRepresentation(exportedContentType: .json) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitLife.json").exportingCondition { $0.format == .json }
  }
}
