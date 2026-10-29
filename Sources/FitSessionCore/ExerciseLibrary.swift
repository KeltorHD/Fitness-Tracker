import Foundation

public enum ExerciseEquipment: String, Codable, CaseIterable, Sendable {
  case barbell, dumbbell, cable, machine, other
  case bodyWeight = "body only"
  case kettlebell = "kettlebells"
  case ezBar = "e-z curl bar"

  public var title: String {
    switch self {
    case .barbell: "Штанга"
    case .dumbbell: "Гантели"
    case .cable: "Блочный тренажёр"
    case .machine: "Тренажёр"
    case .other: "Другое оборудование"
    case .bodyWeight: "Собственный вес"
    case .kettlebell: "Гиря"
    case .ezBar: "EZ-гриф"
    }
  }
}

public enum ExerciseDifficulty: String, Codable, CaseIterable, Sendable {
  case beginner, intermediate, expert
  public var title: String {
    switch self {
    case .beginner: "Начальный"
    case .intermediate: "Средний"
    case .expert: "Продвинутый"
    }
  }
}

public struct ExerciseLibrarySource: Codable, Hashable, Sendable {
  public let name: String
  public let repositoryURL: String
  public let revision: String
  public let licenseName: String
  public let licenseText: String
}

public struct ExerciseLibraryEntry: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let sourceID: String
  public let name: String
  public let englishName: String
  public let aliases: [String]
  public let group: MuscleGroup
  public let equipment: ExerciseEquipment
  public let level: ExerciseDifficulty
  public let primaryMuscles: [String]
  public let secondaryMuscles: [String]
  public let steps: [String]
  /// Paths relative to the iOS-only ExerciseMedia folder; no runtime network requests.
  public let images: [String]

  public var exercise: Exercise {
    Exercise(id: id, name: name, muscle: group, instructions: steps.joined(separator: "\n"))
  }
}

public struct ExerciseLibraryDocument: Codable, Sendable {
  public let schemaVersion: Int
  public let locale: String
  public let source: ExerciseLibrarySource
  public let entries: [ExerciseLibraryEntry]
}

public enum ExerciseLibraryError: Error, LocalizedError {
  case missingResource, invalidDocument
  public var errorDescription: String? {
    switch self {
    case .missingResource: "Не найден файл библиотеки упражнений."
    case .invalidDocument: "Повреждён файл библиотеки упражнений."
    }
  }
}

public enum ExerciseLibrary {
  private static let result: Result<ExerciseLibraryDocument, any Error> = Result {
    guard let url = Bundle.module.url(forResource: "ExerciseLibrary.ru", withExtension: "json")
    else {
      throw ExerciseLibraryError.missingResource
    }
    return try decode(Data(contentsOf: url))
  }
  public static var document: ExerciseLibraryDocument? { try? result.get() }
  public static let entries: [ExerciseLibraryEntry] = document?.entries ?? []
  public static var loadingError: String? {
    if case .failure(let error) = result { return error.localizedDescription }
    return nil
  }

  public static func decode(_ data: Data) throws -> ExerciseLibraryDocument {
    let value = try JSONDecoder().decode(ExerciseLibraryDocument.self, from: data)
    guard value.schemaVersion == 1, value.locale == "ru", !value.entries.isEmpty,
      !value.source.licenseText.isEmpty,
      Set(value.entries.map(\.id)).count == value.entries.count,
      Set(value.entries.map(\.sourceID)).count == value.entries.count
    else {
      throw ExerciseLibraryError.invalidDocument
    }
    for entry in value.entries {
      try Validation.name(entry.name)
      guard !entry.sourceID.isEmpty, entry.steps.count >= 3,
        entry.steps.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
        !entry.primaryMuscles.isEmpty, entry.images.count == 2,
        Set(entry.images).count == 2,
        entry.images.allSatisfy({ path in
          !path.contains("..") && !path.contains("\\") && !path.hasPrefix("/")
            && path.hasPrefix(entry.sourceID + "/") && path.hasSuffix(".jpg")
            && path.split(separator: "/").count == 2
        })
      else { throw ExerciseLibraryError.invalidDocument }
    }
    return value
  }

  public static func entry(for id: UUID) -> ExerciseLibraryEntry? {
    entries.first { $0.id == id }
  }

  public static func search(
    _ query: String = "", group: MuscleGroup? = nil, equipment: ExerciseEquipment? = nil
  ) -> [ExerciseLibraryEntry] {
    let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    return entries.filter { entry in
      guard group == nil || entry.group == group,
        equipment == nil || entry.equipment == equipment
      else { return false }
      let fields =
        [entry.name, entry.englishName, entry.equipment.title]
        + entry.aliases + entry.primaryMuscles + entry.secondaryMuscles
      let text = normalize(fields.joined(separator: " "))
      return tokens.allSatisfy { text.contains($0) }
    }.sorted { $0.name.compare($1.name, locale: Locale(identifier: "ru_RU")) == .orderedAscending }
  }

  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
  }
}
