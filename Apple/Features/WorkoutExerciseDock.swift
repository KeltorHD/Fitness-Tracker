import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseDock: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .headline) private var actionRowHeight = 56
  let workout: Workout
  let exerciseIndex: Int
  let canComplete: Bool
  var completingDrop = false
  var completionTrigger: ContinuousClock.Instant? = nil
  let previous: () -> Void
  let next: () -> Void
  let add: () -> Void
  let complete: () -> Void
  let pause: () -> Void
  let close: () -> Void
  @Namespace private var controlsGlass
  private var isOngoing: Bool { [.active, .paused].contains(workout.status) }

  var body: some View {
    GlassEffectContainer(spacing: 4) {
      ViewThatFits(in: .horizontal) {
        controls(height: actionRowHeight, navigationWidth: 64, plusWidth: 60)
          .frame(minWidth: isOngoing ? 288 + actionRowHeight : 240)
        controls(height: 52, navigationWidth: 52, plusWidth: 56)
      }
    }
    .padding(.vertical, 8)
    .sensoryFeedback(.success, trigger: completionTrigger)
  }

  private func controls(height: CGFloat, navigationWidth: CGFloat, plusWidth: CGFloat) -> some View
  {
    HStack(alignment: .bottom, spacing: 4) {
      navigationButton(
        forward: false, height: height + (height >= 56 ? 12 : 8), width: navigationWidth,
        action: previous
      )
      .disabled(exerciseIndex == 0).accessibilityIdentifier("previousWorkoutExercise")
      actionBlock(height: height, plusWidth: plusWidth)
      navigationButton(
        forward: true, height: height + (height >= 56 ? 12 : 8), width: navigationWidth,
        action: next
      )
      .disabled(exerciseIndex >= workout.exercises.count - 1)
      .accessibilityIdentifier("nextWorkoutExercise")
    }
  }

  private func actionBlock(height: CGFloat, plusWidth: CGFloat) -> some View {
    HStack(alignment: .bottom, spacing: 0) {
      if isOngoing {
        Button(action: pause) {
          Image(systemName: workout.status == .paused ? "play.fill" : "pause.fill")
            .frame(minWidth: plusWidth, maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
        }
        .accessibilityLabel(
          L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
        )
        .accessibilityIdentifier("pauseExerciseWorkout")
      } else {
        Spacer(minLength: 0)
      }
      primaryAction(height: height + (height >= 56 ? 16 : 12)).zIndex(1)
      if isOngoing {
        Button(action: add) {
          Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
            .frame(minWidth: plusWidth, maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
        }
        .disabled(
          workout.status != .active
            || (workout.exercises.indices.contains(exerciseIndex)
              && workout.exercises[exerciseIndex].sets.count >= 30)
        )
        .accessibilityLabel(L10n.text("Добавить подход", locale: locale))
        .accessibilityIdentifier("addWorkoutSet")
      } else {
        Spacer(minLength: 0)
      }
    }
    .font(.system(size: 18, weight: .semibold)).buttonStyle(WorkoutControlPressStyle())
    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
    .glassEffect(.regular, in: WorkoutNavigationShape(rise: 16, shoulderWidth: 48))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exerciseActionBlock")
  }

  private func primaryAction(height: CGFloat) -> some View {
    Button(action: isOngoing ? complete : close) {
      Group {
        if isOngoing && !reduceMotion {
          Image(systemName: "checkmark").symbolEffect(.bounce, value: completionTrigger)
        } else {
          Image(systemName: isOngoing ? "checkmark" : "chevron.down")
        }
      }
      .font(.system(size: isOngoing ? 27 : 22, weight: .bold))
      .foregroundStyle(FitTheme.accentForeground)
      .frame(width: height, height: height)
      .glassEffect(.regular.tint(colorTheme.accent).interactive(), in: .circle)
      .glassEffectID("completeSet", in: controlsGlass)
      .glassEffectTransition(.matchedGeometry)
      .overlay {
        if isOngoing {
          ZStack {
            Circle().stroke(FitTheme.accentForeground.opacity(0.18), lineWidth: 1)
            Circle().trim(from: 0, to: stageProgress.fraction)
              .stroke(
                FitTheme.accentForeground.opacity(0.85),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
              )
              .rotationEffect(.degrees(-90))
          }.padding(5).allowsHitTesting(false).accessibilityHidden(true)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: stageProgress.fraction)
        }
      }
      .contentShape(.circle)
    }
    .disabled(isOngoing && !canComplete).accessibilityLabel(actionTitle)
    .accessibilityValue(
      isOngoing
        ? L10n.format(
          "Выполнено этапов: %@ из %@", String(stageProgress.completed),
          String(stageProgress.total), locale: locale) : ""
    )
    .accessibilityIdentifier("completeSet")
  }

  private var stageProgress: (completed: Int, total: Int, fraction: Double) {
    guard workout.exercises.indices.contains(exerciseIndex) else { return (0, 0, 0) }
    let sets = workout.exercises[exerciseIndex].sets
    let total = sets.reduce(0) { $0 + $1.stages.count }
    let completed = sets.reduce(0) { $0 + $1.performedStages.count }
    return (completed, total, total > 0 ? Double(completed) / Double(total) : 0)
  }

  private var actionTitle: String {
    L10n.text(
      isOngoing
        ? (completingDrop ? "Выполнить этап дропсета" : "Выполнить подход") : "К списку упражнений",
      locale: locale)
  }

  private func navigationButton(
    forward: Bool, height: CGFloat, width: CGFloat, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: forward ? "chevron.right" : "chevron.left")
        .font(.system(size: 16, weight: .semibold))
        .frame(width: width, height: height).contentShape(.capsule)
    }
    .buttonStyle(WorkoutControlPressStyle()).glassEffect(.regular.interactive(), in: .capsule)
    .accessibilityLabel(
      L10n.text(forward ? "Следующее упражнение" : "Предыдущее упражнение", locale: locale))
  }
}

private struct WorkoutControlPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.94 : 1)
      .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76),
        value: configuration.isPressed)
  }
}
