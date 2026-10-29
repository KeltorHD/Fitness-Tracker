import FitSessionCore
import Foundation

/// Immutable lookups in native String Catalog output. No Bundle swizzling or global mutable state.
enum L10n {
  static var selection: AppLanguage {
    let defaults: UserDefaults
    if Bundle.main.bundleURL.pathExtension == "appex",
      let group = Bundle.main.object(forInfoDictionaryKey: "FitSessionAppGroup") as? String,
      let shared = UserDefaults(suiteName: group)
    {
      defaults = shared
    } else {
      defaults = .standard
    }
    return AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "system") ?? .system
  }

  static var language: AppLanguage { selection.resolved() }
  static var locale: Locale { selection.locale() }
  static var numberLocale: Locale { .current }

  static func text(_ key: String, locale: Locale? = nil, bundle: Bundle = .main) -> String {
    let locale = locale ?? Self.locale
    let code = AppLanguage.system.resolved(preferredLanguages: [locale.identifier]).rawValue
    let localized: Bundle
    if let path = bundle.path(forResource: code, ofType: "lproj"),
      let languageBundle = Bundle(path: path)
    {
      localized = languageBundle
    } else {
      localized = bundle
    }
    return localized.localizedString(forKey: key, value: key, table: "Localizable")
  }

  static func format(_ key: String, _ arguments: String..., locale: Locale? = nil) -> String {
    let locale = locale ?? Self.locale
    return String(
      format: text(key, locale: locale), locale: locale, arguments: arguments.map { $0 as CVarArg })
  }

  static func workoutCount(_ count: Int, locale: Locale? = nil) -> String {
    countText(count, kind: "workout", locale: locale)
  }

  static func countText(_ count: Int, kind: String, locale: Locale? = nil) -> String {
    let locale = locale ?? Self.locale
    let language = AppLanguage.system.resolved(preferredLanguages: [locale.identifier])
    return format(
      kind + ".count." + language.pluralCategory(for: count).rawValue, String(count), locale: locale
    )
  }

  static func exerciseName(_ exercise: Exercise, locale: Locale? = nil) -> String {
    let language = AppLanguage.system.resolved(preferredLanguages: [
      (locale ?? Self.locale).identifier
    ])
    return ExerciseLibrary.entry(for: exercise.id, language: language)?.name ?? exercise.name
  }
}

extension WorkoutLiveState {
  var presentationLocale: Locale {
    (AppLanguage(rawValue: languageCode ?? "system") ?? .system).locale()
  }
}
