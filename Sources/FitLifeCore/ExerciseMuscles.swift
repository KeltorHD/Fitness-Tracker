import Foundation

/// Stable IDs are source or FitLife muscle names, not localized display strings.
public enum ExerciseMuscle: String, Codable, CaseIterable, Sendable {
  case chest
  case lats
  case middleBack = "middle back"
  case lowerBack = "lower back"
  case traps
  case quadriceps, hamstrings, glutes, calves, abductors, adductors
  case tibialisAnterior = "tibialis anterior"
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
    case .tibialisAnterior: "Передняя большеберцовая мышца"
    case .abductors: "Отводящие мышцы бедра"
    case .adductors: "Приводящие мышцы бедра"
    case .shoulders: "Мышцы плечевого сустава"
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
    case .quadriceps, .hamstrings, .glutes, .calves, .tibialisAnterior, .abductors, .adductors:
      .legs
    case .shoulders, .neck: .shoulders
    case .biceps, .triceps, .forearms: .arms
    case .abdominals: .core
    }
  }

  public static func inGroup(_ group: MuscleGroup) -> [Self] {
    allCases.filter { $0.group == group }
  }

  private static let libraryNames: [String: Self] = {
    var names = Dictionary(
      uniqueKeysWithValues: allCases.flatMap { [($0.rawValue, $0), ($0.title, $0)] })
    names["Дельтовидные мышцы"] = .shoulders
    names["Мышцы голени"] = .calves
    return names
  }()

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
  public private(set) var regions: Set<ExerciseMuscleRegion>

  public init(
    groups: Set<MuscleGroup> = [], muscles: Set<ExerciseMuscle> = [],
    regions: Set<ExerciseMuscleRegion> = []
  ) {
    self.groups = groups
    self.muscles = muscles
    self.regions = regions
    normalize()
  }

  public var isEmpty: Bool { groups.isEmpty && muscles.isEmpty && regions.isEmpty }

  public func contains(_ muscle: ExerciseMuscle) -> Bool {
    groups.contains(muscle.group) || muscles.contains(muscle)
  }

  public func state(of group: MuscleGroup) -> GroupState {
    if groups.contains(group) { return .all }
    let children = ExerciseMuscle.inGroup(group)
    let selectedCount = children.filter { state(ofMuscle: $0) == .all }.count
    if selectedCount == 0 && !children.contains(where: { state(ofMuscle: $0) == .partial }) {
      return .none
    }
    return selectedCount == children.count ? .all : .partial
  }

  public mutating func set(_ group: MuscleGroup, selected: Bool) {
    if selected { groups.insert(group) } else { groups.remove(group) }
    muscles = muscles.filter { $0.group != group }
    regions = regions.filter { $0.muscle.group != group }
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
    regions = regions.filter { $0.muscle != muscle }
    normalize()
  }

  public func contains(_ region: ExerciseMuscleRegion) -> Bool {
    contains(region.muscle) || regions.contains(region)
  }

  public func state(ofMuscle muscle: ExerciseMuscle) -> GroupState {
    if contains(muscle) { return .all }
    let children = ExerciseMuscleRegion.inMuscle(muscle)
    let count = children.filter { regions.contains($0) }.count
    if count == 0 { return .none }
    return count == children.count ? .all : .partial
  }

  public mutating func set(_ region: ExerciseMuscleRegion, selected: Bool) {
    if selected {
      regions.insert(region)
    } else {
      let parent = region.muscle
      if groups.remove(parent.group) != nil {
        muscles.formUnion(ExerciseMuscle.inGroup(parent.group))
      }
      if muscles.remove(parent) != nil {
        regions.formUnion(ExerciseMuscleRegion.inMuscle(parent))
      }
      regions.remove(region)
    }
    normalize()
  }

  public func matches(_ entry: ExerciseLibraryEntry) -> Bool {
    isEmpty || groups.contains(entry.group) || entry.primaryMuscleIDs.contains(where: contains)
      || entry.muscleRegions.contains(where: contains)
  }

  private mutating func normalize() {
    muscles = muscles.filter { !groups.contains($0.group) }
    regions = regions.filter { !contains($0.muscle) }
  }
}
