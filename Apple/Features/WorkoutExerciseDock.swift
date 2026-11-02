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
  let finish: () -> Void
  private var isOngoing: Bool { [.active, .paused].contains(workout.status) }

  var body: some View {
    GlassEffectContainer(spacing: 4) {
      ViewThatFits(in: .horizontal) {
        controls(height: actionRowHeight, navigationWidth: 64, plusWidth: 60)
          .frame(minWidth: isOngoing ? 292 + actionRowHeight : 240)
        controls(height: 52, navigationWidth: 44, plusWidth: 56)
      }
    }
    .padding(.vertical, 8)
    .sensoryFeedback(.success, trigger: completionTrigger)
  }

  private func controls(height: CGFloat, navigationWidth: CGFloat, plusWidth: CGFloat) -> some View
  {
    HStack(spacing: 4) {
      navigationButton(forward: false, height: height + 8, width: navigationWidth, action: previous)
        .disabled(exerciseIndex == 0).accessibilityIdentifier("previousWorkoutExercise")
      actionBlock(height: height, plusWidth: plusWidth)
      navigationButton(forward: true, height: height + 8, width: navigationWidth, action: next)
        .disabled(exerciseIndex >= workout.exercises.count - 1)
        .accessibilityIdentifier("nextWorkoutExercise")
    }
  }

  private func actionBlock(height: CGFloat, plusWidth: CGFloat) -> some View {
    HStack(spacing: 0) {
      if isOngoing {
        Button(action: pause) {
          Image(systemName: workout.status == .paused ? "play.fill" : "pause.fill")
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
        }
        .accessibilityLabel(
          L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
        )
        .accessibilityIdentifier("pauseExerciseWorkout")
        Button(action: finish) {
          Image(systemName: "stop.fill")
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: height).contentShape(.rect)
        }
        .disabled(workout.completedSets == 0)
        .accessibilityLabel(L10n.text("Завершить тренировку", locale: locale))
        .accessibilityHint(
          workout.completedSets == 0
            ? L10n.text("Для завершения отметьте хотя бы один выполненный подход.", locale: locale)
            : ""
        )
        .accessibilityIdentifier("finishWorkout")
      }
      primaryAction(height: height).frame(maxWidth: .infinity)
      if isOngoing {
        Button(action: add) {
          Image(systemName: "plus").font(.system(size: 21, weight: .semibold))
            .frame(minWidth: plusWidth, maxWidth: .infinity, minHeight: height)
            .background(colorTheme.accent.opacity(0.08), in: .capsule)
            .contentShape(.capsule)
        }
        .disabled(
          workout.status != .active
            || (workout.exercises.indices.contains(exerciseIndex)
              && workout.exercises[exerciseIndex].sets.count >= 30)
        )
        .accessibilityLabel(L10n.text("Добавить подход", locale: locale))
        .accessibilityIdentifier("addWorkoutSet")
      }
    }
    .font(.system(size: 16, weight: .semibold)).buttonStyle(.plain)
    .padding(4)
    .glassEffect(.regular.interactive(), in: .capsule)
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
      .foregroundStyle(colorTheme.accent)
      .frame(width: height, height: height)
      .background(colorTheme.accent.opacity(0.18), in: .circle).contentShape(.circle)
    }
    .disabled(isOngoing && !canComplete).accessibilityLabel(actionTitle)
    .accessibilityIdentifier("completeSet")
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
    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule)
    .accessibilityLabel(
      L10n.text(forward ? "Следующее упражнение" : "Предыдущее упражнение", locale: locale))
  }
}
