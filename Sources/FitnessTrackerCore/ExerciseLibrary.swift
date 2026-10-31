import Foundation

public enum ExerciseEquipment: String, Codable, CaseIterable, Sendable {
  case barbell, dumbbell, cable, machine, other
  case bodyWeight = "body only"
  case kettlebell = "kettlebells"
  case ezBar = "e-z curl bar"
  case bands
  case medicineBall = "medicine ball"
  case exerciseBall = "exercise ball"
  case foamRoll = "foam roll"
  case unspecified

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
    case .bands: "Эспандер"
    case .medicineBall: "Медицинский мяч"
    case .exerciseBall: "Фитбол"
    case .foamRoll: "Массажный ролик"
    case .unspecified: "Не указан"
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

public struct ExerciseGeneratedMedia: Codable, Hashable, Sendable {
  public let poster: String
  public let gif: String
  public let frames: [String]
  public let frameDuration: Double
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
  /// Explicit missing-source metadata, rather than fabricated instructions or broken image paths.
  public let techniqueUnavailable: Bool?
  public let imagesUnavailable: Bool?
  public let generatedMedia: ExerciseGeneratedMedia?
  public let translationAutomatic: Bool?

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
  private static let russianNames = Dictionary(
    uniqueKeysWithValues: entries.map { ($0.id, $0.name) })
  private static let englishResult: Result<ExerciseLibraryDocument, any Error> = Result {
    guard let url = Bundle.module.url(forResource: "ExerciseLibrary.en", withExtension: "json")
    else {
      throw ExerciseLibraryError.missingResource
    }
    return try decode(Data(contentsOf: url))
  }

  public static func document(language: AppLanguage) throws -> ExerciseLibraryDocument {
    try (language.resolved() == .english ? englishResult : result).get()
  }

  public static func entries(language: AppLanguage) throws -> [ExerciseLibraryEntry] {
    try document(language: language).entries
  }

  public static func entry(for id: UUID, language: AppLanguage) -> ExerciseLibraryEntry? {
    switch language.resolved() == .english ? englishResult : result {
    case .success(let document): return document.entries.first { $0.id == id }
    case .failure: return nil  // The library screen exposes the corresponding loading error.
    }
  }
  public static var loadingError: String? {
    if case .failure(let error) = result { return error.localizedDescription }
    return nil
  }

  public static func decode(_ data: Data) throws -> ExerciseLibraryDocument {
    let value = try JSONDecoder().decode(ExerciseLibraryDocument.self, from: data)
    guard value.schemaVersion == 1, ["ru", "en"].contains(value.locale), !value.entries.isEmpty,
      !value.source.licenseText.isEmpty,
      Set(value.entries.map(\.id)).count == value.entries.count,
      Set(value.entries.map(\.sourceID)).count == value.entries.count
    else {
      throw ExerciseLibraryError.invalidDocument
    }
    for entry in value.entries {
      try Validation.name(entry.name)
      if value.locale == "en", entry.name != entry.englishName {
        throw ExerciseLibraryError.invalidDocument
      }
      let missingTechnique = entry.techniqueUnavailable == true
      let missingImages = entry.imagesUnavailable == true
      guard !entry.sourceID.isEmpty,
        missingTechnique
          ? entry.steps.isEmpty : entry.steps.count >= (value.locale == "ru" ? 3 : 1),
        entry.steps.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
        !entry.primaryMuscles.isEmpty,
        missingImages ? entry.images.isEmpty : entry.images.count == 2,
        Set(entry.images).count == entry.images.count,
        entry.images.allSatisfy({ path in
          !path.contains("..") && !path.contains("\\") && !path.hasPrefix("/")
            && path.hasPrefix(entry.sourceID + "/") && path.hasSuffix(".jpg")
            && path.split(separator: "/").count == 2
        })
      else { throw ExerciseLibraryError.invalidDocument }
      if let media = entry.generatedMedia {
        let paths = [media.poster, media.gif] + media.frames
        guard (2...24).contains(media.frames.count), media.frameDuration.isFinite,
          (0.05...2).contains(media.frameDuration), media.poster.hasSuffix(".jpg"),
          media.gif.hasSuffix(".gif"), media.frames.allSatisfy({ $0.hasSuffix(".jpg") }),
          Set(paths).count == paths.count,
          paths.allSatisfy({
            $0.hasPrefix(entry.sourceID + "/ai-") && !$0.contains("..") && !$0.contains("\\")
              && $0.split(separator: "/").count == 2
          })
        else { throw ExerciseLibraryError.invalidDocument }
      }
    }
    return value
  }

  public static func entry(for id: UUID) -> ExerciseLibraryEntry? {
    entries.first { $0.id == id }
  }

  public static func search(
    _ query: String = "", group: MuscleGroup? = nil, equipment: ExerciseEquipment? = nil
  ) -> [ExerciseLibraryEntry] {
    search(query, group: group, equipment: equipment, language: .russian)
  }

  public static func search(
    _ query: String, group: MuscleGroup?, equipment: ExerciseEquipment?, language: AppLanguage
  ) -> [ExerciseLibraryEntry] {
    search(query, groups: group.map { [$0] } ?? [], equipment: equipment, language: language)
  }

  public static func search(
    _ query: String = "", groups: Set<MuscleGroup>, equipment: ExerciseEquipment? = nil,
    language: AppLanguage = .russian
  ) -> [ExerciseLibraryEntry] {
    let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    let candidates: [ExerciseLibraryEntry]
    switch language.resolved() == .english ? englishResult : result {
    case .success(let document): candidates = document.entries
    case .failure: candidates = []
    }
    return candidates.filter { entry in
      guard groups.isEmpty || groups.contains(entry.group),
        equipment == nil || entry.equipment == equipment
      else { return false }
      let fields =
        [
          entry.name, entry.englishName, entry.equipment.title,
          russianNames[entry.id] ?? "",
        ]
        + entry.aliases + entry.primaryMuscles + entry.secondaryMuscles
      let text = normalize(fields.joined(separator: " "))
      return tokens.allSatisfy { text.contains($0) }
    }.sorted { $0.name.compare($1.name, locale: language.locale()) == .orderedAscending }
  }

  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
  }
}
