import Foundation

/// Anatomical parts and explicitly labelled training regions; original catalog muscle IDs stay stable.
public enum ExerciseMuscleRegion: String, Codable, CaseIterable, Sendable {
  case chestUpper
  case chestMiddle
  case chestLower
  case deltoidAnterior
  case deltoidLateral
  case deltoidPosterior
  case rotatorCuff
  case trapeziusUpper
  case trapeziusMiddle
  case trapeziusLower
  case rectusAbdominisUpper
  case rectusAbdominisLower
  case obliques
  case transversusAbdominis
  case bicepsLong
  case bicepsShort
  case tricepsLong
  case tricepsLateral
  case tricepsMedial
  case rectusFemoris
  case vastusLateralis
  case vastusMedialis
  case vastusIntermedius
  case bicepsFemoris
  case semitendinosus
  case semimembranosus
  case gluteusMaximus
  case gluteusMedius
  case gluteusMinimus
  case gastrocnemius
  case soleus

  public var muscle: ExerciseMuscle {
    switch self {
    case .chestUpper, .chestMiddle, .chestLower: .chest
    case .deltoidAnterior, .deltoidLateral, .deltoidPosterior, .rotatorCuff: .shoulders
    case .trapeziusUpper, .trapeziusMiddle, .trapeziusLower: .traps
    case .rectusAbdominisUpper, .rectusAbdominisLower, .obliques, .transversusAbdominis: .abdominals
    case .bicepsLong, .bicepsShort: .biceps
    case .tricepsLong, .tricepsLateral, .tricepsMedial: .triceps
    case .rectusFemoris, .vastusLateralis, .vastusMedialis, .vastusIntermedius: .quadriceps
    case .bicepsFemoris, .semitendinosus, .semimembranosus: .hamstrings
    case .gluteusMaximus, .gluteusMedius, .gluteusMinimus: .glutes
    case .gastrocnemius, .soleus: .calves
    }
  }

  public var title: String {
    switch self {
    case .chestUpper: "Верх груди · ключичная часть"
    case .chestMiddle: "Середина груди · грудино-рёберная область"
    case .chestLower: "Низ груди · нижняя область"
    case .deltoidAnterior: "Передняя дельта"
    case .deltoidLateral: "Средняя дельта"
    case .deltoidPosterior: "Задняя дельта"
    case .rotatorCuff: "Вращательная манжета плеча"
    case .trapeziusUpper: "Верхняя часть трапеции"
    case .trapeziusMiddle: "Средняя часть трапеции"
    case .trapeziusLower: "Нижняя часть трапеции"
    case .rectusAbdominisUpper: "Прямая мышца живота · верхняя область"
    case .rectusAbdominisLower: "Прямая мышца живота · нижняя область"
    case .obliques: "Косые мышцы живота · наружные и внутренние"
    case .transversusAbdominis: "Поперечная мышца живота"
    case .bicepsLong: "Бицепс · длинная головка"
    case .bicepsShort: "Бицепс · короткая головка"
    case .tricepsLong: "Трицепс · длинная головка"
    case .tricepsLateral: "Трицепс · латеральная головка"
    case .tricepsMedial: "Трицепс · медиальная головка"
    case .rectusFemoris: "Прямая мышца бедра"
    case .vastusLateralis: "Латеральная широкая мышца бедра"
    case .vastusMedialis: "Медиальная широкая мышца бедра"
    case .vastusIntermedius: "Промежуточная широкая мышца бедра"
    case .bicepsFemoris: "Двуглавая мышца бедра"
    case .semitendinosus: "Полусухожильная мышца"
    case .semimembranosus: "Полуперепончатая мышца"
    case .gluteusMaximus: "Большая ягодичная мышца"
    case .gluteusMedius: "Средняя ягодичная мышца"
    case .gluteusMinimus: "Малая ягодичная мышца"
    case .gastrocnemius: "Икроножная мышца · обе головки"
    case .soleus: "Камбаловидная мышца"
    }
  }

  public static func inMuscle(_ muscle: ExerciseMuscle) -> [Self] {
    allCases.filter { $0.muscle == muscle }
  }
}

extension ExerciseLibraryEntry {
  public var muscleRegions: [ExerciseMuscleRegion] { trainingRegions ?? [] }
}
