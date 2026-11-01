import SwiftUI

/// Cosmetic preferences stay in the Apple layer and never alter workout data.
enum FitnessColorTheme: String, CaseIterable, Sendable {
  case indigo, ocean, forest, rose, amber

  var title: String {
    switch self {
    case .indigo: "Индиго"
    case .ocean: "Океан"
    case .forest: "Лес"
    case .rose: "Роза"
    case .amber: "Янтарь"
    }
  }

  var detail: String {
    switch self {
    case .indigo: "Сине-фиолетовые акценты"
    case .ocean: "Морские синие акценты"
    case .forest: "Зелёные акценты"
    case .rose: "Розовые акценты"
    case .amber: "Тёплые золотистые акценты"
    }
  }

  var accent: Color {
    switch self {
    case .indigo: Color("AccentColor")
    case .ocean: Color("OceanAccent")
    case .forest: Color("ForestAccent")
    case .rose: Color("RoseAccent")
    case .amber: Color("AmberAccent")
    }
  }
}

private struct FitnessColorThemeKey: EnvironmentKey {
  static let defaultValue = FitnessColorTheme.indigo
}

extension EnvironmentValues {
  var fitnessColorTheme: FitnessColorTheme {
    get { self[FitnessColorThemeKey.self] }
    set { self[FitnessColorThemeKey.self] = newValue }
  }
}
