import FitnessTrackerCore
import Foundation
import OSLog

enum AppErrorReporter {
  /// Do not log localized descriptions, URLs, workout names or other private payloads.
  static func record(_ error: any Error, operation: String) {
    let diagnostic = error as NSError
    Logger(subsystem: "FitnessTracker", category: "Services").error(
      "Operation \(operation, privacy: .public) failed: \(diagnostic.domain, privacy: .public), code \(diagnostic.code)"
    )
  }

  static func message(for error: any Error, operation: String, fallback: String) -> String {
    record(error, operation: operation)
    if let error = error as? FitSessionCSVError {
      switch error {
      case .invalidValue(let line, let column):
        return L10n.format(
          "Строка %@: проверьте поле «%@».", String(line), L10n.text(column.header))
      case .malformed(let line):
        return L10n.format(
          "Строка %@: нарушен формат CSV. Проверьте кавычки и разделители.", String(line))
      case .unsupportedMeasurement(let line):
        return L10n.format(
          "Строка %@: подходы с дистанцией или временем пока не поддерживаются.", String(line))
      default: return L10n.text(error.localizedDescription)
      }
    }
    if let error = error as? TrainingError { return error.localizedDescription }
    if let error = error as? ServiceError { return error.localizedDescription }
    if let error = error as? WorkoutArchiveError { return error.localizedDescription }
    if let error = error as? ArchiveFileError { return error.localizedDescription }
    return fallback
  }
}
