import FitSessionCore
import Foundation
import OSLog

enum AppErrorReporter {
  /// Do not log localized descriptions, URLs, workout names or other private payloads.
  static func record(_ error: any Error, operation: String) {
    let diagnostic = error as NSError
    Logger(subsystem: "FitSession", category: "Services").error(
      "Operation \(operation, privacy: .public) failed: \(diagnostic.domain, privacy: .public), code \(diagnostic.code)"
    )
  }

  static func message(for error: any Error, operation: String, fallback: String) -> String {
    record(error, operation: operation)
    if let error = error as? TrainingError { return error.localizedDescription }
    if let error = error as? ServiceError { return error.localizedDescription }
    if let error = error as? WorkoutArchiveError { return error.localizedDescription }
    if let error = error as? ArchiveFileError { return error.localizedDescription }
    return fallback
  }
}
