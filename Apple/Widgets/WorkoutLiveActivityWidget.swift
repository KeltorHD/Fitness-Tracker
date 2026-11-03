import ActivityKit
import FitnessTrackerCore
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      WorkoutLockScreenActivity(context: context)
        .environment(\.locale, context.state.presentationLocale)
        .environment(\.fitnessColorTheme, .resolved(context.state.colorThemeID))
        .widgetURL(context.attributes.workoutURL)
    } dynamicIsland: { context in
      let theme = FitnessColorTheme.resolved(context.state.colorThemeID)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 4) {
            Label(
              context.state.paused
                ? L10n.text("Пауза", locale: context.state.presentationLocale)
                : L10n.text("Тренировка", locale: context.state.presentationLocale),
              systemImage: context.state.paused ? "pause.fill" : "dumbbell.fill"
            ).font(.caption).foregroundStyle(theme.accentOnDark)
            WorkoutElapsedTime(state: context.state).font(.title2.bold())
              .frame(width: 100, alignment: .leading)
          }
          .foregroundStyle(.white).environment(\.locale, context.state.presentationLocale)
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 6) {
            SetProgress(state: context.state).font(.caption.bold())
            if context.state.heartRate != nil {
              WorkoutActivityHeartRate(state: context.state, isStale: context.isStale)
            }
          }
          .foregroundStyle(.white).environment(\.colorScheme, .dark)
          .environment(\.fitnessColorTheme, theme)
          .environment(\.locale, context.state.presentationLocale)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(context.state.workoutName ?? context.attributes.name)
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            NextWorkoutSet(state: context.state)
            WorkoutRestProgress(state: context.state)
            WorkoutActivityProgress(state: context.state)
            WorkoutActivityControls(context: context)
          }
          .foregroundStyle(.white).environment(\.colorScheme, .dark)
          .environment(\.fitnessColorTheme, theme)
          .environment(\.locale, context.state.presentationLocale)
        }
      } compactLeading: {
        Image(
          systemName: hasCurrentHeartRate(context)
            ? "heart.fill"
            : (context.state.paused ? "pause.fill" : "dumbbell.fill")
        )
        .foregroundStyle(theme.accentOnDark).accessibilityLabel(
          hasCurrentHeartRate(context)
            ? L10n.text("Пульс", locale: context.state.presentationLocale)
            : (context.state.paused
              ? L10n.text("На паузе", locale: context.state.presentationLocale)
              : L10n.text("Тренировка", locale: context.state.presentationLocale)))
      } compactTrailing: {
        Group {
          if hasCurrentHeartRate(context) {
            WorkoutActivityHeartRate(state: context.state, isStale: context.isStale, compact: true)
          } else if context.state.restEndsAt != nil {
            WorkoutRestTime(state: context.state).frame(width: 46)
          } else {
            WorkoutElapsedTime(state: context.state).frame(width: 60)
          }
        }
        .foregroundStyle(theme.accentOnDark).environment(\.colorScheme, .dark)
        .environment(\.fitnessColorTheme, theme)
        .environment(\.locale, context.state.presentationLocale)
      } minimal: {
        Group {
          if hasCurrentHeartRate(context) {
            WorkoutActivityHeartRate(state: context.state, isStale: context.isStale, compact: true)
          } else if context.state.paused {
            Image(systemName: "pause.fill").accessibilityLabel(
              L10n.text("На паузе", locale: context.state.presentationLocale))
          } else {
            ZStack {
              Circle().stroke(theme.accentOnDark.opacity(0.25), lineWidth: 2)
              Circle().trim(from: 0, to: context.state.progress)
                .stroke(theme.accentOnDark, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
              Image(systemName: "dumbbell.fill").font(.system(size: 10))
            }.padding(3).accessibilityLabel(
              L10n.format(
                "Выполнено %@ из %@ подходов", String(context.state.completedSets),
                String(context.state.totalSets), locale: context.state.presentationLocale))
          }
        }
        .foregroundStyle(theme.accentOnDark).environment(\.colorScheme, .dark)
        .environment(\.fitnessColorTheme, theme)
      }
      .widgetURL(context.attributes.workoutURL)
      .keylineTint(theme.accentOnDark)
    }
  }
}

private struct WorkoutLockScreenActivity: View {
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  let context: ActivityViewContext<WorkoutActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: context.state.paused ? "pause.circle.fill" : "dumbbell.fill")
          .foregroundStyle(theme.accent).accessibilityHidden(true)
        Text(context.state.workoutName ?? context.attributes.name)
          .font(.subheadline.bold()).lineLimit(1)
        Spacer(minLength: 0)
        Text(
          L10n.text(
            context.state.paused ? "На паузе" : "Тренировка",
            locale: context.state.presentationLocale)
        )
        .font(.caption2.weight(.medium)).foregroundStyle(theme.accent)
      }
      HStack(alignment: .center, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.text("Время", locale: context.state.presentationLocale))
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          WorkoutElapsedTime(state: context.state).font(.title2.bold())
        }.frame(width: 100, alignment: .leading)
        VStack(alignment: .leading, spacing: 5) {
          NextWorkoutSet(state: context.state)
          WorkoutRestProgress(state: context.state)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 10) {
        WorkoutActivityProgress(state: context.state)
        SetProgress(state: context.state).font(.caption2.weight(.semibold)).fixedSize()
      }
      HStack(spacing: 8) {
        WorkoutActivityControls(context: context)
        if context.state.heartRate != nil {
          WorkoutActivityHeartRate(state: context.state, isStale: context.isStale)
        }
      }
    }
    .foregroundStyle(.primary).padding(14)
    .background {
      ContainerRelativeShape().fill(
        LinearGradient(
          colors: [theme.accent.opacity(0.12), .clear], startPoint: .topLeading,
          endPoint: .bottomTrailing))
    }
    .overlay {
      ContainerRelativeShape()
        .stroke(
          LinearGradient(
            colors: [
              theme.accent.opacity(0.9), theme.accent.opacity(0.25), theme.accent.opacity(0.6),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: contrast == .increased ? 2 : 1
        )
        .shadow(color: theme.accent.opacity(luminanceReduced ? 0 : 0.2), radius: 3)
        .padding(1).allowsHitTesting(false).accessibilityHidden(true)
    }
    .activityBackgroundTint(Color("ResultsSurface"))
    .activitySystemActionForegroundColor(theme.accent)
  }
}

private struct WorkoutActivityProgress: View {
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState

  var body: some View {
    ProgressView(value: state.progress).tint(theme.accent)
      .accessibilityLabel(L10n.text("Подходы", locale: locale))
      .accessibilityValue(
        L10n.format(
          "Выполнено %@ из %@ подходов", String(state.completedSets),
          String(state.totalSets), locale: locale))
  }
}

private struct WorkoutRestProgress: View {
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState

  var body: some View {
    if let start = state.restStartsAt, let end = state.restEndsAt, !state.paused {
      // System-rendered progress keeps moving while the app is suspended, then stops at zero.
      ProgressView(timerInterval: start...end, countsDown: true)
        .tint(theme.accent).labelsHidden()
        .accessibilityLabel(L10n.text("Осталось отдыхать", locale: locale))
    }
  }
}

private func hasCurrentHeartRate(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> Bool
{
  !context.isStale && context.state.heartRate?.isFresh(at: .now) == true
}

private struct WorkoutActivityHeartRate: View {
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  let state: WorkoutLiveState
  let isStale: Bool
  var compact = false

  private var reading: HeartRateReading? {
    guard !isStale, let value = state.heartRate, value.isFresh(at: .now) else { return nil }
    return value
  }
  var body: some View {
    HStack(spacing: 4) {
      if !compact { Image(systemName: "heart.fill").foregroundStyle(theme.accent) }
      if let reading {
        Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0)))
          .monospacedDigit().contentTransition(
            reduceMotion || luminanceReduced ? .identity : .numericText())
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  @Environment(\.locale) private var locale
  let state: WorkoutLiveState
  var body: some View {
    Text(
      L10n.format(
        "%@/%@ подходов", String(state.completedSets),
        String(state.totalSets), locale: locale)
    )
    .monospacedDigit().contentTransition(
      reduceMotion || luminanceReduced ? .identity : .numericText()
    )
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
  @Environment(\.fitnessColorTheme) private var theme
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
    .buttonStyle(.bordered).controlSize(.small).tint(theme.accent)
  }
}
