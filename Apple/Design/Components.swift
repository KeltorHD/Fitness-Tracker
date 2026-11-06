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
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var readyFeedback = 0
  @Namespace private var controls
  let workout: Workout
  let cancel: () -> Void
  let addTemplates: () -> Void
  let addExercise: () -> Void
  var body: some View {
    let progress = WorkoutCompletionProgress(workout: workout)
    let shape = WorkoutNavigationShape(rise: 12, shoulderWidth: 44)
    GlassEffectContainer(spacing: 4) {
      HStack(spacing: 4) {
        leadingActions.frame(maxWidth: .infinity)
        finishButton(progress: progress)
        trailingActions.frame(maxWidth: .infinity)
      }
      .controlSize(.regular)
      .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 8)
      .background {
        if reduceTransparency { shape.fill(FitTheme.paper) }
      }
      .glassEffect(.regular, in: shape)
      .themeGlow(in: shape)
      .overlay {
        if contrast == .increased {
          shape.stroke(FitTheme.muted, lineWidth: 1).allowsHitTesting(false)
        }
      }
    }
    .padding(.horizontal, 4).padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sessionControls")
    .onChange(of: workout) { old, new in
      // Reopening or replacing a restored session never announces a new success.
      guard old.id == new.id, !WorkoutCompletionProgress(workout: old).isComplete,
        WorkoutCompletionProgress(workout: new).isComplete
      else { return }
      readyFeedback += 1
    }
    .sensoryFeedback(.success, trigger: readyFeedback)
  }

  private var leadingActions: some View {
    HStack(spacing: 4) {
      Button(role: .destructive, action: cancel) {
        controlImage("xmark")
      }
      .buttonStyle(.glass).buttonBorderShape(.circle)
      .frame(width: 44, height: 52).contentShape(.rect)
      .glassEffectID("cancel", in: controls)
      .accessibilityLabel(L10n.text("Отменить тренировку", locale: locale))
      .accessibilityIdentifier("cancelWorkout")
      pauseButton
    }
  }

  private var trailingActions: some View {
    HStack(spacing: 4) {
      Button(action: addTemplates) {
        controlImage("rectangle.stack.badge.plus")
      }
      .buttonStyle(.glass).buttonBorderShape(.circle)
      .frame(width: 44, height: 52).contentShape(.rect)
      .glassEffectID("addTemplates", in: controls)
      .disabled(workout.status != .active)
      .accessibilityLabel(L10n.text("Добавить шаблоны", locale: locale))
      .accessibilityIdentifier("addWorkoutTemplates")
      addExerciseButton
    }
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
      controlImage(workout.status == .paused ? "play.fill" : "pause.fill")
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .frame(width: 44, height: 52).contentShape(.rect)
    .glassEffectID("pause", in: controls)
    .accessibilityLabel(
      L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
    )
    .accessibilityIdentifier("pauseWorkout")
  }
  private var addExerciseButton: some View {
    Button(action: addExercise) {
      controlImage("plus")
    }
    .buttonStyle(.glass).buttonBorderShape(.circle)
    .frame(width: 44, height: 52).contentShape(.rect)
    .glassEffectID("addExercise", in: controls)
    .disabled(workout.status != .active)
    .accessibilityLabel(L10n.text("Добавить упражнение", locale: locale))
    .accessibilityIdentifier("addExercise")
  }

  private func controlImage(_ symbol: String) -> some View {
    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
      .frame(width: 20, height: 20).accessibilityHidden(true)
  }

  private func finishButton(progress: WorkoutCompletionProgress) -> some View {
    Button {
      store.finish()
    } label: {
      Group {
        if reduceMotion {
          Image(systemName: progress.isComplete ? "checkmark.seal.fill" : "checkmark")
        } else {
          Image(systemName: progress.isComplete ? "checkmark.seal.fill" : "checkmark")
            .symbolEffect(.bounce, value: readyFeedback)
        }
      }
      .font(.system(size: 28, weight: .bold))
      .foregroundStyle(FitTheme.accentForeground)
      .frame(width: 48, height: 48).accessibilityHidden(true)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle).tint(colorTheme.accent)
    .frame(width: 72, height: 72).contentShape(.circle)
    .glassEffectID("finish", in: controls)
    .glassEffectTransition(.matchedGeometry)
    .themeGlow(in: Circle(), emphasized: true)
    .overlay { WorkoutCompletionRing(progress: progress).padding(5) }
    .disabled(workout.completedSets == 0)
    .accessibilityLabel(
      L10n.text(
        progress.isComplete ? "Завершить и сохранить тренировку" : "Завершить тренировку",
        locale: locale)
    )
    .accessibilityValue(
      progress.isComplete
        ? L10n.text("Все упражнения выполнены", locale: locale)
        : L10n.format(
          "Выполнено этапов: %@ из %@", String(progress.completed), String(progress.total),
          locale: locale)
    )
    .accessibilityHint(
      workout.completedSets == 0
        ? L10n.text("Для завершения отметьте хотя бы один выполненный подход.", locale: locale) : ""
    )
    .accessibilityIdentifier("finishWorkout")
    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: progress.isComplete)
  }
}

/// Shared stage progress for the workout and exercise completion circles.
struct WorkoutCompletionRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  let progress: WorkoutCompletionProgress

  var body: some View {
    ZStack {
      Circle().stroke(
        FitTheme.accentForeground.opacity(contrast == .increased ? 0.55 : 0.18),
        lineWidth: contrast == .increased ? 2 : 1)
      Circle().trim(from: 0, to: progress.fraction)
        .stroke(
          FitTheme.accentForeground.opacity(contrast == .increased ? 1 : 0.85),
          style: StrokeStyle(lineWidth: contrast == .increased ? 3 : 2, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: progress.fraction)
    .allowsHitTesting(false).accessibilityHidden(true)
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
