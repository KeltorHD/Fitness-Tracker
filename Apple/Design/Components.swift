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
  @ScaledMetric(relativeTo: .headline) private var actionRowHeight: CGFloat = 56
  @State private var readyFeedback = 0
  @Namespace private var controls
  let workout: Workout
  let cancel: () -> Void
  let addTemplates: () -> Void
  let addExercise: () -> Void
  var body: some View {
    let progress = WorkoutCompletionProgress(workout: workout)
    GlassEffectContainer(spacing: 4) {
      ViewThatFits(in: .horizontal) {
        actionRow(progress: progress, height: actionRowHeight, horizontalPadding: 8)
          .frame(minWidth: WorkoutControlSizing.regularMinimumWidth(for: actionRowHeight))
        actionRow(
          progress: progress, height: WorkoutControlSizing.compactRowHeight, horizontalPadding: 0)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 8)
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

  private func actionRow(
    progress: WorkoutCompletionProgress, height: CGFloat, horizontalPadding: CGFloat
  ) -> some View {
    WorkoutActionSurface(horizontalPadding: horizontalPadding) {
      Button(role: .destructive, action: cancel) {
        controlImage("xmark", height: height)
      }
      .foregroundStyle(.red)
      .accessibilityLabel(L10n.text("Отменить тренировку", locale: locale))
      .accessibilityIdentifier("cancelWorkout")
      pauseButton(height: height)
      finishButton(
        progress: progress, diameter: WorkoutControlSizing.primaryDiameter(for: height)
      ).zIndex(1)
      Button(action: addTemplates) {
        controlImage("rectangle.stack.badge.plus", height: height)
      }
      .disabled(workout.status != .active)
      .accessibilityLabel(L10n.text("Добавить шаблоны", locale: locale))
      .accessibilityIdentifier("addWorkoutTemplates")
      addExerciseButton(height: height)
    }
    .foregroundStyle(.primary)
    .accessibilityIdentifier("sessionActionBlock")
  }

  private func pauseButton(height: CGFloat) -> some View {
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
      controlImage(workout.status == .paused ? "play.fill" : "pause.fill", height: height)
    }
    .accessibilityLabel(
      L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
    )
    .accessibilityIdentifier("pauseWorkout")
  }
  private func addExerciseButton(height: CGFloat) -> some View {
    Button(action: addExercise) {
      controlImage("plus", height: height)
    }
    .disabled(workout.status != .active)
    .accessibilityLabel(L10n.text("Добавить упражнение", locale: locale))
    .accessibilityIdentifier("addExercise")
  }

  private func controlImage(_ symbol: String, height: CGFloat) -> some View {
    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
      .frame(minWidth: 60, maxWidth: .infinity, minHeight: height)
      .contentShape(.rect).accessibilityHidden(true)
  }

  private func finishButton(progress: WorkoutCompletionProgress, diameter: CGFloat) -> some View {
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
      .frame(width: diameter, height: diameter)
      .glassEffect(.regular.tint(colorTheme.accent).interactive(), in: .circle)
      .glassEffectID("finish", in: controls)
      .glassEffectTransition(.matchedGeometry)
      .overlay { WorkoutCompletionRing(progress: progress).padding(5) }
      .contentShape(.circle).accessibilityHidden(true)
    }
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

enum WorkoutControlSizing {
  static let compactRowHeight: CGFloat = 52

  static func primaryDiameter(for rowHeight: CGFloat) -> CGFloat {
    rowHeight + (rowHeight >= 56 ? 16 : 12)
  }

  static func regularMinimumWidth(for rowHeight: CGFloat) -> CGFloat {
    288 + rowHeight
  }
}

/// The overview and exercise share the same raised center, padding and bottom alignment.
struct WorkoutActionSurface<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private let horizontalPadding: CGFloat
  private let content: Content

  init(horizontalPadding: CGFloat = 8, @ViewBuilder content: () -> Content) {
    self.horizontalPadding = horizontalPadding
    self.content = content()
  }

  var body: some View {
    let shape = WorkoutNavigationShape(rise: 16, shoulderWidth: 48)
    HStack(alignment: .bottom, spacing: 0) { content }
      .buttonStyle(WorkoutControlPressStyle())
      .padding(.horizontal, horizontalPadding).padding(.top, 4).padding(.bottom, 8)
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
      .accessibilityElement(children: .contain)
  }
}

/// Consistent touch feedback for the workout overview and exercise controls.
struct WorkoutControlPressStyle: ButtonStyle {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let isPressed = isEnabled && configuration.isPressed
    return configuration.label
      .background {
        Capsule()
          .fill(colorTheme.accent.opacity(isPressed ? (contrast == .increased ? 0.26 : 0.14) : 0))
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      .scaleEffect(reduceMotion ? 1 : isPressed ? 0.94 : 1)
      .opacity(isEnabled ? (isPressed ? 0.86 : 1) : 0.4)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76), value: isPressed)
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
