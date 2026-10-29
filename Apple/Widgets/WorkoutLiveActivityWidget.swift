import ActivityKit
import FitSessionCore
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        Label(context.attributes.name, systemImage: "dumbbell.fill").font(.headline).lineLimit(1)
        HStack {
          WorkoutElapsedTime(state: context.state)
          Spacer()
          SetProgress(state: context.state)
        }.font(.subheadline)
        NextWorkoutSet(state: context.state)
        WorkoutActivityControls(context: context)
      }
      .padding(12)
      .activityBackgroundTint(.black.opacity(0.85))
      .activitySystemActionForegroundColor(.white)
      .foregroundStyle(.white)
      .widgetURL(context.attributes.workoutURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(
            context.state.paused ? "Пауза" : "Тренировка",
            systemImage: context.state.paused ? "pause.fill" : "dumbbell.fill"
          )
          .font(.caption).foregroundStyle(Color.accentColor)
        }
        DynamicIslandExpandedRegion(.trailing) { SetProgress(state: context.state).font(.caption) }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              NextWorkoutSet(state: context.state)
              Spacer(minLength: 8)
              WorkoutElapsedTime(state: context.state).font(.caption)
            }
            WorkoutActivityControls(context: context)
          }
        }
      } compactLeading: {
        Image(systemName: context.state.paused ? "pause.fill" : "dumbbell.fill")
          .foregroundStyle(Color.accentColor).accessibilityLabel(
            context.state.paused ? "На паузе" : "Тренировка")
      } compactTrailing: {
        if context.state.restEndsAt != nil {
          WorkoutRestTime(state: context.state).frame(width: 46)
        } else {
          WorkoutElapsedTime(state: context.state).frame(width: 60)
        }
      } minimal: {
        if context.state.paused {
          Image(systemName: "pause.fill").foregroundStyle(Color.accentColor).accessibilityLabel(
            "На паузе")
        } else {
          ZStack {
            Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: context.state.progress)
              .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: "dumbbell.fill").font(.system(size: 10))
          }.padding(3).accessibilityLabel(
            "Выполнено \(context.state.completedSets) из \(context.state.totalSets) подходов")
        }
      }
      .widgetURL(context.attributes.workoutURL)
      .keylineTint(Color.accentColor)
    }
  }
}

private struct WorkoutElapsedTime: View {
  let state: WorkoutLiveState
  var body: some View {
    // The system ticks this archived Text while the containing app is suspended.
    Text(
      timerInterval: state.timerStart...state.timerEnd,
      pauseTime: state.timerPausedAt, countsDown: false, showsHours: false
    )
    .monospacedDigit().accessibilityLabel("Активное время тренировки")
  }
}

private struct WorkoutRestTime: View {
  let state: WorkoutLiveState
  var body: some View {
    if let start = state.restStartsAt, let end = state.restEndsAt {
      // Stable endpoints: stops at zero; never starts counting upwards after rest.
      Text(timerInterval: start...end, countsDown: true, showsHours: false)
        .monospacedDigit().accessibilityLabel("Осталось отдыхать")
    }
  }
}

private struct SetProgress: View {
  let state: WorkoutLiveState
  var body: some View {
    Text("\(state.completedSets)/\(state.totalSets) подходов")
      .monospacedDigit().contentTransition(.numericText())
      .accessibilityLabel("Выполнено \(state.completedSets) из \(state.totalSets) подходов")
  }
}

private struct NextWorkoutSet: View {
  let state: WorkoutLiveState
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let name = state.nextExerciseName, let number = state.nextSetNumber {
        Text(name).font(.subheadline.bold()).lineLimit(1)
        Text("Далее: подход \(number)").font(.caption).foregroundStyle(.secondary)
      } else {
        Text(state.totalSets == 0 ? "Добавьте упражнения в FitSession" : "Все подходы записаны")
          .font(.caption).lineLimit(1)
      }
    }
  }
}

private struct WorkoutActivityControls: View {
  let context: ActivityViewContext<WorkoutActivityAttributes>
  var body: some View {
    HStack(spacing: 8) {
      Button(
        intent: SetWorkoutPausedIntent(
          workoutID: context.attributes.workoutID, paused: !context.state.paused)
      ) {
        Label(
          context.state.paused ? "Продолжить" : "Пауза",
          systemImage: context.state.paused ? "play.fill" : "pause.fill")
      }
      if let restEnd = context.state.restEndsAt, !context.state.paused {
        HStack(spacing: 4) {
          Image(systemName: "timer")
          WorkoutRestTime(state: context.state).frame(width: 46)
        }.font(.caption)
        Button(
          intent: SkipWorkoutRestIntent(
            workoutID: context.attributes.workoutID, restEndsAt: restEnd)
        ) {
          Image(systemName: "forward.end.fill")
        }.accessibilityLabel("Пропустить отдых")
      }
      Spacer(minLength: 0)
    }
    .buttonStyle(.bordered).controlSize(.small).tint(Color.accentColor)
  }
}
