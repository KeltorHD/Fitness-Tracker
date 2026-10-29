import OSLog
import SwiftUI
import WidgetKit

private struct WeeklyEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot?
  var loadFailed = false
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
          WeeklyEntry(date: nextWeek, snapshot: entry.snapshot, loadFailed: entry.loadFailed),
        ], policy: .atEnd))
  }
  private func loadEntry(at date: Date) -> WeeklyEntry {
    do { return WeeklyEntry(date: date, snapshot: try WidgetSnapshot.read()) } catch {
      let diagnostic = error as NSError
      Logger(subsystem: "FitSession", category: "Widget").error(
        "Snapshot unavailable: \(diagnostic.domain, privacy: .public), code \(diagnostic.code)")
      return WeeklyEntry(date: date, snapshot: nil, loadFailed: true)
    }
  }
}
private struct WeeklyWidgetView: View {
  let entry: WeeklyEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("FitSession", systemImage: "figure.strengthtraining.traditional").font(.caption.bold())
      if let snapshot = entry.snapshot {
        let sameWeek =
          Calendar.current.dateInterval(of: .weekOfYear, for: entry.date)?.contains(
            snapshot.updatedAt) == true
        let count = sameWeek ? snapshot.workoutsThisWeek : 0
        Text("\(count) / \(snapshot.weeklyGoal)").font(.largeTitle.bold()).privacySensitive()
        Text("тренировок за неделю").font(.caption).foregroundStyle(.secondary)
        ProgressView(value: Double(count), total: Double(max(count, snapshot.weeklyGoal)))
          .tint(Color.accentColor)
      } else {
        Text("Ваша неделя").font(.headline)
        Text(
          entry.loadFailed
            ? "Откройте FitSession, чтобы обновить сводку."
            : "Включите сводку виджета в настройках FitSession."
        ).font(.caption).foregroundStyle(
          .secondary)
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
    .widgetURL(URL(string: "fitsession://today"))
  }
}
struct WeeklyWorkoutWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "FitSession.Weekly", provider: WeeklyProvider()) {
      WeeklyWidgetView(entry: $0)
    }
    .configurationDisplayName("Ваша неделя").description("Прогресс к недельной цели.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
@main struct FitSessionWidgetBundle: WidgetBundle {
  var body: some Widget {
    WeeklyWorkoutWidget()
    WorkoutLiveActivityWidget()
  }
}
