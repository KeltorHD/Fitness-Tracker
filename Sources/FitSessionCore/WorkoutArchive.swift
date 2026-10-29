import Foundation

/// The .json and .fitsession extensions share this versioned, UTF-8 JSON payload.
public struct WorkoutArchive: Codable, Equatable, Sendable {
  public static let formatIdentifier = "com.fitsession.archive"
  public static let currentVersion = 1
  public let format: String
  public let version: Int
  public let exportedAt: Date
  public let workouts: [Workout]
  public let templates: [WorkoutTemplate]

  public init(workouts: [Workout], templates: [WorkoutTemplate], exportedAt: Date = Date()) {
    format = Self.formatIdentifier
    version = Self.currentVersion
    self.exportedAt = exportedAt
    self.workouts = workouts
    self.templates = templates
  }
}

public enum WorkoutArchiveError: Error, Equatable, LocalizedError, Sendable {
  case invalidFile, unsupportedVersion, tooLarge, tooManyRecords, duplicateID

  public var errorDescription: String? {
    switch self {
    case .invalidFile: "Файл повреждён или не содержит данные FitSession."
    case .unsupportedVersion:
      "Версия формата файла не поддерживается. Попробуйте обновить FitSession."
    case .tooLarge: "Файл превышает допустимый размер 20 МБ."
    case .tooManyRecords: "В одном файле допускается до 10 000 тренировок и 1 000 планов."
    case .duplicateID: "В файле обнаружены повторяющиеся записи. Импорт не выполнен."
    }
  }
}

public enum WorkoutArchiveCodec {
  public static let maximumBytes = 20 * 1024 * 1024

  public static func encode(_ archive: WorkoutArchive) throws -> Data {
    try validate(archive)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    // Numeric Unix seconds preserve subsecond pause intervals, unlike the old ISO-8601 export.
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(archive)
    guard data.count <= maximumBytes else { throw WorkoutArchiveError.tooLarge }
    return data
  }

  public static func decode(_ data: Data) throws -> WorkoutArchive {
    guard data.count <= maximumBytes else { throw WorkoutArchiveError.tooLarge }
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw WorkoutArchiveError.invalidFile
      }
      let archive: WorkoutArchive
      if object["format"] != nil || object["version"] != nil || object["workouts"] != nil {
        guard object["format"] as? String == WorkoutArchive.formatIdentifier else {
          throw WorkoutArchiveError.invalidFile
        }
        guard object["version"] as? Int == WorkoutArchive.currentVersion else {
          throw WorkoutArchiveError.unsupportedVersion
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        archive = try decoder.decode(WorkoutArchive.self, from: data)
      } else {
        // Compatibility with WorkoutDocument's original single-workout JSON export.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workout = try decoder.decode(Workout.self, from: data)
        archive = WorkoutArchive(workouts: [workout], templates: [], exportedAt: workout.startedAt)
      }
      try validate(archive)
      return archive
    } catch let error as WorkoutArchiveError {
      throw error
    } catch {
      // A malformed file must never expose decoder paths or partially reach persistence.
      throw WorkoutArchiveError.invalidFile
    }
  }

  public static func validate(_ archive: WorkoutArchive) throws {
    guard archive.format == WorkoutArchive.formatIdentifier else {
      throw WorkoutArchiveError.invalidFile
    }
    guard archive.version == WorkoutArchive.currentVersion else {
      throw WorkoutArchiveError.unsupportedVersion
    }
    guard archive.exportedAt.timeIntervalSince1970.isFinite else {
      throw WorkoutArchiveError.invalidFile
    }
    guard archive.workouts.count <= 10_000, archive.templates.count <= 1_000 else {
      throw WorkoutArchiveError.tooManyRecords
    }
    guard Set(archive.workouts.map(\.id)).count == archive.workouts.count,
      Set(archive.templates.map(\.id)).count == archive.templates.count
    else { throw WorkoutArchiveError.duplicateID }
    for workout in archive.workouts { try Validation.workout(workout) }
    for template in archive.templates { try Validation.template(template) }
  }
}

public struct ArchiveImportSummary: Equatable, Sendable {
  public let addedWorkouts: Int
  public let addedTemplates: Int
  public let skippedExisting: Int
  public let skippedUnfinished: Int
  public var hasChanges: Bool { addedWorkouts + addedTemplates > 0 }
}

/// Additive merge: existing IDs are never overwritten and at most one unfinished session is restored.
public struct ArchiveImportPlan: Sendable {
  public let workouts: [Workout]
  public let templates: [WorkoutTemplate]
  public let summary: ArchiveImportSummary

  public init(
    archive: WorkoutArchive, existingWorkouts: [Workout], existingTemplates: [WorkoutTemplate]
  ) throws {
    try WorkoutArchiveCodec.validate(archive)
    let workoutIDs = Set(existingWorkouts.map(\.id))
    let templateIDs = Set(existingTemplates.map(\.id))
    var hasUnfinished = existingWorkouts.contains { [.active, .paused].contains($0.status) }
    var skippedExisting = 0
    var skippedUnfinished = 0
    var added: [Workout] = []
    let ordered = archive.workouts.sorted {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt
    }
    for workout in ordered {
      if workoutIDs.contains(workout.id) {
        skippedExisting += 1
      } else if [.active, .paused].contains(workout.status) {
        if hasUnfinished {
          skippedUnfinished += 1
        } else {
          added.append(workout)
          hasUnfinished = true
        }
      } else {
        added.append(workout)
      }
    }
    workouts = added
    templates = archive.templates.filter { !templateIDs.contains($0.id) }
    skippedExisting += archive.templates.count - templates.count
    summary = ArchiveImportSummary(
      addedWorkouts: workouts.count, addedTemplates: templates.count,
      skippedExisting: skippedExisting, skippedUnfinished: skippedUnfinished)
  }
}
