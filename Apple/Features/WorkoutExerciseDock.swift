import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseDock: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @ScaledMetric(relativeTo: .headline) private var actionRowHeight = 56
  let workout: Workout
  let exerciseIndex: Int
  let canComplete: Bool
  var completingDrop = false
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
      if isOngoing {
        ViewThatFits(in: .horizontal) {
          balancedControls
          compactControls
        }
      } else {
        HStack(spacing: 8) {
          previousButton(height: 44)
          Spacer(minLength: 0)
          primaryAction(height: actionRowHeight)
          Spacer(minLength: 0)
          nextButton(height: 44)
        }
      }
    }.padding(.vertical, 8)
  }

  private var balancedControls: some View {
    HStack(spacing: 4) {
      Color.clear.overlay(alignment: .leading) {
        HStack(spacing: 4) {
          previousButton(height: actionRowHeight)
          sessionActions(height: actionRowHeight)
        }
      }
      primaryAction(height: actionRowHeight)
      Color.clear.overlay(alignment: .trailing) {
        HStack(spacing: 4) {
          addButton(height: actionRowHeight)
          nextButton(height: actionRowHeight)
        }
      }
    }
    // Symmetric side slots keep the completion button centered on regular phone widths.
    .frame(minWidth: 280 + actionRowHeight, maxWidth: .infinity)
    .frame(height: actionRowHeight)
  }

  private var compactControls: some View {
    HStack(spacing: 4) {
      previousButton(height: 44)
      Spacer(minLength: 0)
      sessionActions(height: 44)
      primaryAction(height: 44)
      addButton(height: 44)
      Spacer(minLength: 0)
      nextButton(height: 44)
    }.frame(height: 44)
  }

  private func previousButton(height: CGFloat) -> some View {
    navigationButton(forward: false, height: height, action: previous)
      .disabled(exerciseIndex == 0).accessibilityIdentifier("previousWorkoutExercise")
  }
  private func nextButton(height: CGFloat) -> some View {
    navigationButton(forward: true, height: height, action: next)
      .disabled(exerciseIndex >= workout.exercises.count - 1)
      .accessibilityIdentifier("nextWorkoutExercise")
  }
  private func addButton(height: CGFloat) -> some View {
    Button(action: add) {
      Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
        .frame(width: height, height: height).contentShape(.circle)
    }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
      .disabled(
        workout.status != .active
          || (workout.exercises.indices.contains(exerciseIndex)
            && workout.exercises[exerciseIndex].sets.count >= 30)
      )
      .accessibilityLabel(L10n.text("Добавить подход", locale: locale))
      .accessibilityIdentifier("addWorkoutSet")
  }

  private func sessionActions(height: CGFloat) -> some View {
    HStack(spacing: 0) {
      Button(action: pause) {
        Image(systemName: workout.status == .paused ? "play.fill" : "pause.fill")
          .frame(width: 44, height: height).contentShape(.rect)
      }
      .accessibilityLabel(
        L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
      )
      .accessibilityIdentifier("pauseExerciseWorkout")
      Button(action: finish) {
        Image(systemName: "stop.fill").frame(width: 44, height: height)
          .contentShape(.rect)
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
    .font(.system(size: 16, weight: .semibold)).buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .capsule)
  }

  private func primaryAction(height: CGFloat) -> some View {
    Button(action: isOngoing ? complete : close) {
      Image(systemName: isOngoing ? "checkmark" : "chevron.down")
        .font(.system(size: 22, weight: .semibold))
        .frame(width: height, height: height).contentShape(.circle)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.tint(colorTheme.accent.opacity(0.3)).interactive(), in: .circle)
    .disabled(isOngoing && !canComplete).accessibilityLabel(actionTitle)
    .accessibilityIdentifier("completeSet")
  }

  private var actionTitle: String {
    L10n.text(
      isOngoing
        ? (completingDrop ? "Выполнить этап дропсета" : "Выполнить подход") : "К списку упражнений",
      locale: locale)
  }

  private func navigationButton(forward: Bool, height: CGFloat, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: forward ? "chevron.right" : "chevron.left")
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 44, height: height).contentShape(.capsule)
    }
    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule)
    .accessibilityLabel(
      L10n.text(forward ? "Следующее упражнение" : "Предыдущее упражнение", locale: locale))
  }
}
