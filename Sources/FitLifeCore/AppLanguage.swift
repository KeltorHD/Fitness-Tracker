import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
  case system
  case russian = "ru"
  case english = "en"
  public var id: String { rawValue }

  public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
    guard self == .system else { return self }
    for identifier in preferredLanguages {
      let code = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first
        .map(String.init)
      if let code, let language = Self(rawValue: code.lowercased()), language != .system {
        return language
      }
    }
    return .english
  }

  public func locale(
    preferredLanguages: [String] = Locale.preferredLanguages,
    regionCode: String? = Locale.current.region?.identifier
  ) -> Locale {
    let language = resolved(preferredLanguages: preferredLanguages)
    return Locale(
      identifier: language.rawValue + "_" + (regionCode ?? (language == .russian ? "RU" : "US")))
  }

  public enum PluralCategory: String, Sendable { case one, few, many, other }
  public func pluralCategory(
    for count: Int, preferredLanguages: [String] = Locale.preferredLanguages
  ) -> PluralCategory {
    guard resolved(preferredLanguages: preferredLanguages) == .russian else {
      return count == 1 || count == -1 ? .one : .other
    }
    let lastTwo = abs(count % 100)
    let last = abs(count % 10)
    if (11...14).contains(lastTwo) { return .many }
    if last == 1 { return .one }
    if (2...4).contains(last) { return .few }
    return .many
  }
}
