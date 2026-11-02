import Foundation

/// Stable IDs are the original free-exercise-db muscle names, not localized display strings.
public enum ExerciseMuscle: String, Codable, CaseIterable, Sendable {
  case chest
  case lats
  case middleBack = "middle back"
  case lowerBack = "lower back"
  case traps
  case quadriceps, hamstrings, glutes, calves, abductors, adductors
  case shoulders, neck, biceps, triceps, forearms, abdominals

  public var title: String {
    switch self {
    case .chest: "Грудные мышцы"
    case .lats: "Широчайшие мышцы спины"
    case .middleBack: "Средняя часть спины"
    case .lowerBack: "Разгибатели спины"
    case .traps: "Трапециевидные мышцы"
    case .quadriceps: "Квадрицепс"
    case .hamstrings: "Задняя поверхность бедра"
    case .glutes: "Ягодичные мышцы"
    case .calves: "Икроножные мышцы"
    case .abductors: "Отводящие мышцы бедра"
    case .adductors: "Приводящие мышцы бедра"
    case .shoulders: "Дельтовидные мышцы"
    case .neck: "Мышцы шеи"
    case .biceps: "Бицепс"
    case .triceps: "Трицепс"
    case .forearms: "Мышцы предплечья"
    case .abdominals: "Мышцы живота"
    }
  }

  public var group: MuscleGroup {
    switch self {
    case .chest: .chest
    case .lats, .middleBack, .lowerBack, .traps: .back
    case .quadriceps, .hamstrings, .glutes, .calves, .abductors, .adductors: .legs
    case .shoulders, .neck: .shoulders
    case .biceps, .triceps, .forearms: .arms
    case .abdominals: .core
    }
  }

  public static func inGroup(_ group: MuscleGroup) -> [Self] {
    allCases.filter { $0.group == group }
  }

  private static let libraryNames: [String: Self] = Dictionary(
    uniqueKeysWithValues: allCases.flatMap { [($0.rawValue, $0), ($0.title, $0)] })

  public init?(libraryName: String) {
    guard let value = Self.libraryNames[libraryName] else { return nil }
    self = value
  }
}

extension ExerciseLibraryEntry {
  public var primaryMuscleIDs: [ExerciseMuscle] {
    primaryMuscles.compactMap { ExerciseMuscle(libraryName: $0) }
  }

  public var secondaryMuscleIDs: [ExerciseMuscle] {
    secondaryMuscles.compactMap { ExerciseMuscle(libraryName: $0) }
  }
}

/// Union of complete groups and individual primary muscles. An empty selection imposes no filter.
public struct ExerciseMuscleSelection: Equatable, Sendable {
  public enum GroupState: Equatable, Sendable { case none, partial, all }
  public private(set) var groups: Set<MuscleGroup>
  public private(set) var muscles: Set<ExerciseMuscle>

  public init(groups: Set<MuscleGroup> = [], muscles: Set<ExerciseMuscle> = []) {
    self.groups = groups
    self.muscles = muscles
    normalize()
  }

  public var isEmpty: Bool { groups.isEmpty && muscles.isEmpty }

  public func contains(_ muscle: ExerciseMuscle) -> Bool {
    groups.contains(muscle.group) || muscles.contains(muscle)
  }

  public func state(of group: MuscleGroup) -> GroupState {
    if groups.contains(group) { return .all }
    let children = ExerciseMuscle.inGroup(group)
    let selectedCount = children.filter { muscles.contains($0) }.count
    if selectedCount == 0 { return .none }
    return selectedCount == children.count ? .all : .partial
  }

  public mutating func set(_ group: MuscleGroup, selected: Bool) {
    if selected { groups.insert(group) } else { groups.remove(group) }
    muscles = muscles.filter { $0.group != group }
  }

  public mutating func set(_ muscle: ExerciseMuscle, selected: Bool) {
    if selected {
      muscles.insert(muscle)
    } else {
      if groups.remove(muscle.group) != nil {
        muscles.formUnion(ExerciseMuscle.inGroup(muscle.group))
      }
      muscles.remove(muscle)
    }
    normalize()
  }

  public func matches(_ entry: ExerciseLibraryEntry) -> Bool {
    isEmpty || groups.contains(entry.group) || entry.primaryMuscleIDs.contains(where: contains)
  }

  private mutating func normalize() {
    muscles = muscles.filter { !groups.contains($0.group) }
  }
}
