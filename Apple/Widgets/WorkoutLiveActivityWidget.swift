import ActivityKit
import FitnessTrackerCore
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        Label(context.attributes.name, systemImage: "dumbbell.fill").font(.headline).lineLimit(1)
        HStack {
          WorkoutElapsedTime(state: context.state).environment(
            \.locale, context.state.presentationLocale)
          Spacer()
          SetProgress(state: context.state).environment(\.locale, context.state.presentationLocale)
        }.font(.subheadline)
        WorkoutActivityHeartRate(state: context.state, isStale: context.isStale)
        NextWorkoutSet(state: context.state).environment(\.locale, context.state.presentationLocale)
        WorkoutActivityControls(context: context).environment(
          \.locale, context.state.presentationLocale)
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
            context.state.paused
              ? L10n.text("Пауза", locale: context.state.presentationLocale)
              : L10n.text("Тренировка", locale: context.state.presentationLocale),
            systemImage: context.state.paused ? "pause.fill" : "dumbbell.fill"
          )
          .font(.caption).foregroundStyle(Color("AccentOnDark"))
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 4) {
            WorkoutActivityHeartRate(state: context.state, isStale: context.isStale)
            SetProgress(state: context.state).environment(
              \.locale, context.state.presentationLocale
            )
            .font(.caption)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              NextWorkoutSet(state: context.state).environment(
                \.locale, context.state.presentationLocale)
              Spacer(minLength: 8)
              WorkoutElapsedTime(state: context.state).environment(
                \.locale, context.state.presentationLocale
              ).font(.caption)
            }
            WorkoutActivityControls(context: context).environment(
              \.locale, context.state.presentationLocale)
          }
        }
      } compactLeading: {
        Image(
          systemName: hasCurrentHeartRate(context)
            ? "heart.fill"
            : (context.state.paused ? "pause.fill" : "dumbbell.fill")
        )
        .foregroundStyle(Color("AccentOnDark")).accessibilityLabel(
          hasCurrentHeartRate(context)
            ? L10n.text("Пульс", locale: context.state.presentationLocale)
            : (context.state.paused
              ? L10n.text("На паузе", locale: context.state.presentationLocale)
              : L10n.text("Тренировка", locale: context.state.presentationLocale)))
      } compactTrailing: {
        if hasCurrentHeartRate(context) {
          WorkoutActivityHeartRate(state: context.state, isStale: context.isStale, compact: true)
        } else if context.state.restEndsAt != nil {
          WorkoutRestTime(state: context.state).environment(
            \.locale, context.state.presentationLocale
          ).frame(width: 46)
        } else {
          WorkoutElapsedTime(state: context.state).environment(
            \.locale, context.state.presentationLocale
          ).frame(width: 60)
        }
      } minimal: {
        if hasCurrentHeartRate(context) {
          WorkoutActivityHeartRate(state: context.state, isStale: context.isStale, compact: true)
        } else if context.state.paused {
          Image(systemName: "pause.fill").foregroundStyle(Color("AccentOnDark")).accessibilityLabel(
            L10n.text("На паузе", locale: context.state.presentationLocale))
        } else {
          ZStack {
            Circle().stroke(Color("AccentOnDark").opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: context.state.progress)
              .stroke(Color("AccentOnDark"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: "dumbbell.fill").font(.system(size: 10))
          }.padding(3).accessibilityLabel(
            L10n.format(
              "Выполнено %@ из %@ подходов", String(context.state.completedSets),
              String(context.state.totalSets),
              locale: context.state.presentationLocale))
        }
      }
      .widgetURL(context.attributes.workoutURL)
      .keylineTint(Color("AccentOnDark"))
    }
  }
}

private func hasCurrentHeartRate(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> Bool
{
  !context.isStale && context.state.heartRate?.isFresh(at: .now) == true
}

private struct WorkoutActivityHeartRate: View {
  let state: WorkoutLiveState
  let isStale: Bool
  var compact = false

  private var reading: HeartRateReading? {
    guard !isStale, let value = state.heartRate, value.isFresh(at: .now) else { return nil }
    return value
  }
  var body: some View {
    HStack(spacing: 4) {
      if !compact { Image(systemName: "heart.fill").foregroundStyle(Color("AccentOnDark")) }
      if let reading {
        Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0)))
          .monospacedDigit().contentTransition(.numericText())
      } else {
        Text("—")
      }
      if !compact { Text(L10n.text("уд/мин", locale: state.presentationLocale)).font(.caption) }
    }
    .font(compact ? .caption.bold() : .subheadline.bold())
    .environment(\.locale, state.presentationLocale)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("Пульс", locale: state.presentationLocale))
    .accessibilityValue(
      reading.map {
        L10n.format(
          "%@ уд/мин", String(Int($0.beatsPerMinute.rounded())), locale: state.presentationLocale)
      } ?? L10n.text("Нет свежих данных пульса", locale: state.presentationLocale))
  }
}

private struct WorkoutElapsedTime: View {
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState
  var body: some View {
    // The system ticks this archived Text while the containing app is suspended.
    Text(
      timerInterval: state.timerStart...state.timerEnd,
      pauseTime: state.timerPausedAt, countsDown: false, showsHours: false
    )
    .monospacedDigit().accessibilityLabel(L10n.text("Активное время тренировки", locale: locale))
  }
}

private struct WorkoutRestTime: View {
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState
  var body: some View {
    if let start = state.restStartsAt, let end = state.restEndsAt {
      // Stable endpoints: stops at zero; never starts counting upwards after rest.
      Text(timerInterval: start...end, countsDown: true, showsHours: false)
        .monospacedDigit().accessibilityLabel(L10n.text("Осталось отдыхать", locale: locale))
    }
  }
}

private struct SetProgress: View {
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState
  var body: some View {
    Text(
      L10n.format(
        "%@/%@ подходов", String(state.completedSets),
        String(state.totalSets), locale: locale)
    )
    .monospacedDigit().contentTransition(.numericText())
    .accessibilityLabel(
      L10n.format(
        "Выполнено %@ из %@ подходов", String(state.completedSets),
        String(state.totalSets), locale: locale))
  }
}

private struct NextWorkoutSet: View {
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let name = state.nextExerciseName, let number = state.nextSetNumber {
        Text(name).font(.subheadline.bold()).lineLimit(1)
        if let stage = state.nextDropStageNumber, let count = state.nextDropStageCount {
          Text(L10n.format("Дропсет · этап %@/%@", String(stage), String(count), locale: locale))
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(L10n.format("Далее: подход %@", String(number), locale: locale)).font(
            .caption
          ).foregroundStyle(.secondary)
        }
      } else {
        Text(
          state.totalSets == 0
            ? L10n.text("Добавьте упражнения в FitnessTracker", locale: locale)
            : L10n.text("Все подходы записаны", locale: locale)
        )
        .font(.caption).lineLimit(1)
      }
    }
  }
}

private struct WorkoutActivityControls: View {
  @Environment(\.locale) private var locale
  let context: ActivityViewContext<WorkoutActivityAttributes>
  var body: some View {
    HStack(spacing: 8) {
      Button(
        intent: SetWorkoutPausedIntent(
          workoutID: context.attributes.workoutID, paused: !context.state.paused)
      ) {
        Label(
          context.state.paused
            ? L10n.text("Продолжить", locale: locale) : L10n.text("Пауза", locale: locale),
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
        }.accessibilityLabel(L10n.text("Пропустить отдых", locale: locale))
      }
      Spacer(minLength: 0)
    }
    .buttonStyle(.bordered).controlSize(.small).tint(Color("AccentOnDark"))
  }
}
