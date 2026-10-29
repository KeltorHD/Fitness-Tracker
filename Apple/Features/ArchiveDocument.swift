import CoreTransferable
import FitSessionCore
import Foundation
import UniformTypeIdentifiers

extension UTType {
  static let fitSession = UTType(exportedAs: WorkoutArchive.formatIdentifier, conformingTo: .json)
}

enum ArchiveExportFormat: String, CaseIterable, Identifiable, Sendable {
  case fitSession, json
  var id: Self { self }
  var title: String { self == .json ? "JSON (.json)" : "FitSession (.fitsession)" }
  var contentType: UTType { self == .json ? .json : .fitSession }
}

struct ArchiveDocument: Transferable, Sendable {
  let archive: WorkoutArchive
  let files: any ArchiveFileHandling
  let format: ArchiveExportFormat

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .fitSession) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitSession.fitsession").exportingCondition { $0.format == .fitSession }
    DataRepresentation(exportedContentType: .json) { document in
      try await document.files.encode(document.archive)
    }.suggestedFileName("FitSession.json").exportingCondition { $0.format == .json }
  }
}
