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
struct WorkoutLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 10) {
        Label(context.attributes.name, systemImage: "dumbbell.fill").font(.headline)
        HStack {
          Text("\(context.state.completedSets) / \(context.state.totalSets) подходов")
          Spacer()
          ActivityStatus(state: context.state)
        }.font(.subheadline)
      }.padding().activityBackgroundTint(.black.opacity(0.8)).activitySystemActionForegroundColor(
        .white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "dumbbell.fill").foregroundStyle(.mint)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(context.state.completedSets)/\(context.state.totalSets)").monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack {
            Text(context.attributes.name).font(.headline)
            ActivityStatus(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill").foregroundStyle(.mint)
      } compactTrailing: {
        Text("\(context.state.completedSets)").monospacedDigit()
      } minimal: {
        Image(systemName: "dumbbell.fill")
      }
      .widgetURL(URL(string: "fitsession://workout"))
    }
  }
}
private struct ActivityStatus: View {
  let state: WorkoutActivityAttributes.ContentState
  var body: some View {
    if state.paused {
      Text("На паузе")
    } else if let end = state.restEndsAt, end > .now {
      Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().frame(maxWidth: 85)
    } else {
      Text("Тренировка")
    }
  }
}
@main struct FitSessionWidgetBundle: WidgetBundle {
  var body: some Widget {
    WeeklyWorkoutWidget()
    WorkoutLiveActivityWidget()
  }
}
