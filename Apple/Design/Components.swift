import FitnessTrackerCore
import SwiftUI

extension MuscleGroup {
  var title: String {
    switch self {
    case .chest: L10n.text("Грудь")
    case .back: L10n.text("Спина")
    case .legs: L10n.text("Ноги")
    case .shoulders: L10n.text("Плечи")
    case .arms: L10n.text("Руки")
    case .core: L10n.text("Пресс")
    case .fullBody: L10n.text("Всё тело")
    }
  }
}

struct MetricView: View {
  let value: String
  let title: String
  let symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: symbol).foregroundStyle(.tint)
      Text(value).font(.title2.bold()).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    .themeGlow(in: RoundedRectangle(cornerRadius: 22))
    .accessibilityElement(children: .combine)
  }
}

struct SessionControls: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var controls
  let workout: Workout
  let cancel: () -> Void
  let addTemplates: () -> Void
  let addExercise: () -> Void
  var body: some View {
    GlassEffectContainer(spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          leadingActions
          finishButton(fixedLabel: true)
          trailingActions
        }
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            leadingActions
            Spacer(minLength: 8)
            trailingActions
          }
          finishButton(fixedLabel: false)
        }
      }
      .font(.subheadline.weight(.semibold))
      .controlSize(.regular)
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
    .background(FitTheme.paper)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sessionControls")
  }

  private var leadingActions: some View {
    HStack(spacing: 8) {
      Button(role: .destructive, action: cancel) {
        Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.glass).buttonBorderShape(.circle)
      .glassEffectID("cancel", in: controls)
      .accessibilityLabel(L10n.text("Отменить тренировку", locale: locale))
      .accessibilityIdentifier("cancelWorkout")
      pauseButton
    }
    .font(.system(size: 20, weight: .semibold))
  }

  private var trailingActions: some View {
    HStack(spacing: 8) {
      Button(action: addTemplates) {
        Image(systemName: "rectangle.stack.badge.plus").frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.glass).buttonBorderShape(.circle)
      .glassEffectID("addTemplates", in: controls)
      .disabled(workout.status != .active)
      .accessibilityLabel(L10n.text("Добавить шаблоны", locale: locale))
      .accessibilityIdentifier("addWorkoutTemplates")
      addExerciseButton
    }
    .font(.system(size: 20, weight: .semibold))
  }

  private var pauseButton: some View {
    Button {
      withAnimation(reduceMotion ? nil : .smooth) {
        store.mutate { value in
          if value.status == .paused {
            try WorkoutEngine.resume(&value)
          } else {
            try WorkoutEngine.pause(&value)
          }
        }
      }
    } label: {
      Label(
        workout.status == .paused
          ? L10n.text("Продолжить", locale: locale) : L10n.text("Пауза", locale: locale),
        systemImage: workout.status == .paused ? "play.fill" : "pause.fill"
      )
      .labelStyle(.iconOnly)
      .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .glassEffectID("pause", in: controls)
    .accessibilityIdentifier("pauseWorkout")
  }
  private var addExerciseButton: some View {
    Button(action: addExercise) {
      Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.glass).buttonBorderShape(.circle)
    .glassEffectID("addExercise", in: controls)
    .disabled(workout.status != .active)
    .accessibilityLabel(L10n.text("Добавить упражнение", locale: locale))
    .accessibilityIdentifier("addExercise")
  }

  private func finishButton(fixedLabel: Bool) -> some View {
    Button {
      store.finish()
    } label: {
      Label(L10n.text("Завершить", locale: locale), systemImage: "checkmark")
        .fixedSize(horizontal: fixedLabel, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.glassProminent)
    .glassEffectID("finish", in: controls)
    .glassEffectTransition(.matchedGeometry)
    .themeGlow(in: Capsule(), emphasized: true)
    .disabled(workout.completedSets == 0)
    .accessibilityLabel(L10n.text("Завершить тренировку", locale: locale))
    .accessibilityHint(
      workout.completedSets == 0
        ? L10n.text("Для завершения отметьте хотя бы один выполненный подход.", locale: locale) : ""
    )
    .accessibilityIdentifier("finishWorkout")
  }
}

struct RestPill: View {
  @Environment(\.locale) private var locale
  let end: Date
  var body: some View {
    HStack {
      Image(systemName: "timer")
      Text(L10n.text("Отдых", locale: locale))
      Text(timerInterval: Date.now...max(.now, end), countsDown: true).monospacedDigit()
    }
    .font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
    .glassEffect()
    .themeGlow(in: Capsule(), emphasized: true)
    .accessibilityLabel(L10n.text("Таймер отдыха", locale: locale))
  }
}
