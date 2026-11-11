import OSLog
import SwiftUI
import WidgetKit

private struct WeeklyEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot?
  var loadFailed = false
  var colorThemeID: String?
}
private struct WeeklyProvider: TimelineProvider {
  func placeholder(in context: Context) -> WeeklyEntry { WeeklyEntry(date: .now, snapshot: .empty) }
  func getSnapshot(in context: Context, completion: @escaping (WeeklyEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : loadEntry(at: .now))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyEntry>) -> Void) {
    let now = Date()
    let entry = loadEntry(at: now)
    let calendar = Calendar.current
    let nextWeek =
      calendar.dateInterval(of: .weekOfYear, for: now)?.end
      ?? calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(3600)
    completion(
      Timeline(
        entries: [
          entry,
          WeeklyEntry(
            date: nextWeek, snapshot: entry.snapshot, loadFailed: entry.loadFailed,
            colorThemeID: entry.colorThemeID),
        ], policy: .atEnd))
  }
  private func loadEntry(at date: Date) -> WeeklyEntry {
    do {
      return WeeklyEntry(
        date: date, snapshot: try WidgetSnapshot.read(),
        colorThemeID: try WidgetSnapshot.colorThemeID())
    } catch {
      let diagnostic = error as NSError
      Logger(subsystem: "FitLife", category: "Widget").error(
        "Snapshot unavailable: \(diagnostic.domain, privacy: .public), code \(diagnostic.code)")
      return WeeklyEntry(date: date, snapshot: nil, loadFailed: true)
    }
  }
}
private struct WeeklyWidgetView: View {
  @Environment(\.locale) private var locale
  let entry: WeeklyEntry
  private var colorTheme: FitnessColorTheme { .resolved(entry.colorThemeID) }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("FitLife", systemImage: "figure.strengthtraining.traditional").font(
        .caption.bold()
      ).foregroundStyle(colorTheme.accent)
      if let snapshot = entry.snapshot {
        let sameWeek =
          Calendar.current.dateInterval(of: .weekOfYear, for: entry.date)?.contains(
            snapshot.updatedAt) == true
        let count = sameWeek ? snapshot.workoutsThisWeek : 0
        Text("\(count) / \(snapshot.weeklyGoal)").font(.largeTitle.bold()).privacySensitive()
        Text(L10n.text("тренировок за неделю", locale: locale)).font(.caption).foregroundStyle(
          .secondary)
        ProgressView(value: Double(count), total: Double(max(count, snapshot.weeklyGoal)))
          .tint(colorTheme.accent)
      } else {
        Text(L10n.text("Ваша неделя", locale: locale)).font(.headline)
        Text(
          entry.loadFailed
            ? L10n.text("Откройте FitLife, чтобы обновить сводку.", locale: locale)
            : L10n.text("Включите сводку виджета в настройках FitLife.", locale: locale)
        ).font(.caption).foregroundStyle(
          .secondary)
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
    .widgetURL(URL(string: "fitlife://today"))
  }
}
struct WeeklyWorkoutWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: AppIdentifiers.weeklyWidgetKind, provider: WeeklyProvider()) {
      WeeklyWidgetView(entry: $0).environment(\.locale, L10n.locale)
    }
    .configurationDisplayName("Ваша неделя").description("Прогресс к недельной цели.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
@main struct FitLifeWidgetBundle: WidgetBundle {
  var body: some Widget {
    WeeklyWorkoutWidget()
    WorkoutLiveActivityWidget()
  }
}
