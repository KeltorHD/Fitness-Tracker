import Foundation

/// The .json and .fitnesstracker extensions share this versioned, UTF-8 JSON payload.
public struct WorkoutArchive: Codable, Equatable, Sendable {
  public static let formatIdentifier = "com.fitnesstracker.archive"
  /// Read-only compatibility with archives created before the product rename.
  public static let legacyFormatIdentifier = "com.fitsession.archive"
  public static let fileExtension = "fitnesstracker"
  public static let legacyFileExtension = "fitsession"
  public static let currentVersion = 3
  public let format: String
  public let version: Int
  public let exportedAt: Date
  public let workouts: [Workout]
  public let templates: [WorkoutTemplate]
  public let bodyWeights: [BodyWeightEntry]

  public init(
    workouts: [Workout], templates: [WorkoutTemplate], bodyWeights: [BodyWeightEntry] = [],
    exportedAt: Date = Date()
  ) {
    format = Self.formatIdentifier
    version = Self.currentVersion
    self.exportedAt = exportedAt
    self.workouts = workouts
    self.templates = templates
    self.bodyWeights = bodyWeights
  }

  private enum CodingKeys: String, CodingKey {
    case format, version, exportedAt, workouts, templates, bodyWeights
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    format = try values.decode(String.self, forKey: .format)
    version = try values.decode(Int.self, forKey: .version)
    exportedAt = try values.decode(Date.self, forKey: .exportedAt)
    workouts = try values.decode([Workout].self, forKey: .workouts)
    templates = try values.decode([WorkoutTemplate].self, forKey: .templates)
    // Explicit v1 migration: these archives did not contain independent weigh-ins.
    if version >= 2 {
      bodyWeights = try values.decode([BodyWeightEntry].self, forKey: .bodyWeights)
    } else {
      bodyWeights = try values.decodeIfPresent([BodyWeightEntry].self, forKey: .bodyWeights) ?? []
    }
  }
}

public enum WorkoutArchiveError: Error, Equatable, LocalizedError, Sendable {
  case invalidFile, unsupportedVersion, tooLarge, tooManyRecords, duplicateID

  public var errorDescription: String? {
    switch self {
    case .invalidFile: "Файл повреждён или не содержит данные FitnessTracker."
    case .unsupportedVersion:
      "Версия формата файла не поддерживается. Попробуйте обновить FitnessTracker."
    case .tooLarge: "Файл превышает допустимый размер 20 МБ."
    case .tooManyRecords:
      "В одном файле допускается до 10 000 тренировок, 1 000 планов и 10 000 записей веса."
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
    let current = WorkoutArchive(
      workouts: archive.workouts, templates: archive.templates, bodyWeights: archive.bodyWeights,
      exportedAt: archive.exportedAt)
    let data = try encoder.encode(current)
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
        guard let format = object["format"] as? String,
          [WorkoutArchive.formatIdentifier, WorkoutArchive.legacyFormatIdentifier].contains(format)
        else {
          throw WorkoutArchiveError.invalidFile
        }
        guard let version = object["version"] as? Int,
          (1...WorkoutArchive.currentVersion).contains(version)
        else {
          throw WorkoutArchiveError.unsupportedVersion
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WorkoutArchive.self, from: data)
        archive = WorkoutArchive(
          workouts: decoded.workouts, templates: decoded.templates,
          bodyWeights: decoded.bodyWeights,
          exportedAt: decoded.exportedAt)
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
    guard
      [WorkoutArchive.formatIdentifier, WorkoutArchive.legacyFormatIdentifier].contains(
        archive.format)
    else {
      throw WorkoutArchiveError.invalidFile
    }
    guard (1...WorkoutArchive.currentVersion).contains(archive.version) else {
      throw WorkoutArchiveError.unsupportedVersion
    }
    guard archive.exportedAt.timeIntervalSince1970.isFinite else {
      throw WorkoutArchiveError.invalidFile
    }
    guard archive.workouts.count <= 10_000, archive.templates.count <= 1_000,
      archive.bodyWeights.count <= 10_000
    else {
      throw WorkoutArchiveError.tooManyRecords
    }
    guard Set(archive.workouts.map(\.id)).count == archive.workouts.count,
      Set(archive.templates.map(\.id)).count == archive.templates.count,
      Set(archive.bodyWeights.map(\.id)).count == archive.bodyWeights.count
    else { throw WorkoutArchiveError.duplicateID }
    for workout in archive.workouts { try Validation.workout(workout) }
    for template in archive.templates { try Validation.template(template) }
    for entry in archive.bodyWeights { try Validation.bodyWeightEntry(entry) }
  }
}

public struct ArchiveImportSummary: Equatable, Sendable {
  public let addedWorkouts: Int
  public let addedTemplates: Int
  public let addedBodyWeights: Int
  public let skippedExisting: Int
  public let skippedUnfinished: Int
  public var hasChanges: Bool { addedWorkouts + addedTemplates + addedBodyWeights > 0 }
}

/// Additive merge: existing IDs are never overwritten and at most one unfinished session is restored.
public struct ArchiveImportPlan: Sendable {
  public let workouts: [Workout]
  public let templates: [WorkoutTemplate]
  public let bodyWeights: [BodyWeightEntry]
  public let summary: ArchiveImportSummary

  public init(
    archive: WorkoutArchive, existingWorkouts: [Workout], existingTemplates: [WorkoutTemplate],
    existingBodyWeights: [BodyWeightEntry] = []
  ) throws {
    try WorkoutArchiveCodec.validate(archive)
    let workoutIDs = Set(existingWorkouts.map(\.id))
    let templateIDs = Set(existingTemplates.map(\.id))
    let bodyWeightIDs = Set(existingBodyWeights.map(\.id))
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
    bodyWeights = archive.bodyWeights.filter { !bodyWeightIDs.contains($0.id) }
    skippedExisting += archive.templates.count - templates.count
    skippedExisting += archive.bodyWeights.count - bodyWeights.count
    summary = ArchiveImportSummary(
      addedWorkouts: workouts.count, addedTemplates: templates.count,
      addedBodyWeights: bodyWeights.count,
      skippedExisting: skippedExisting, skippedUnfinished: skippedUnfinished)
  }
}
