import Foundation

extension TimeInterval {
  func formattedWorkoutDuration(locale: Locale) -> String {
    let minutes = Int(max(0, self)) / 60
    return minutes >= 60
      ? L10n.format(
        "%@ ч %@ мин", String(minutes / 60), String(minutes % 60), locale: locale)
      : L10n.format("%@ мин", String(minutes), locale: locale)
  }
}
