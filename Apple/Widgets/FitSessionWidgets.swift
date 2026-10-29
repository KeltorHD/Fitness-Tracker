import ActivityKit
import SwiftUI
import WidgetKit

private struct WeeklyEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot?
}
private struct WeeklyProvider: TimelineProvider {
  func placeholder(in context: Context) -> WeeklyEntry { WeeklyEntry(date: .now, snapshot: .empty) }
  func getSnapshot(in context: Context, completion: @escaping (WeeklyEntry) -> Void) {
    completion(
      WeeklyEntry(date: .now, snapshot: context.isPreview ? .empty : WidgetSnapshot.read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyEntry>) -> Void) {
    let now = Date()
    let snapshot = WidgetSnapshot.read()
    let nextWeek =
      Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end ?? now.addingTimeInterval(86400)
    completion(
      Timeline(
        entries: [
          WeeklyEntry(date: now, snapshot: snapshot),
          WeeklyEntry(date: nextWeek, snapshot: snapshot),
        ], policy: .atEnd))
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
        Text("Включите сводку виджета в настройках FitSession.").font(.caption).foregroundStyle(
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
