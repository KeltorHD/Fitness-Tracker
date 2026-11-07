import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseDock: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .headline) private var actionRowHeight = 56
  let workout: Workout
  let exerciseIndex: Int
  var navigationIndex: Int? = nil
  var navigationCount: Int? = nil
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
          .frame(
            minWidth: isOngoing
              ? WorkoutControlSizing.regularMinimumWidth(for: actionRowHeight) : 240)
        controls(height: WorkoutControlSizing.compactRowHeight, navigationWidth: 52, plusWidth: 56)
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
      .disabled((navigationIndex ?? exerciseIndex) == 0)
      .accessibilityIdentifier("previousWorkoutExercise")
      actionBlock(height: height, plusWidth: plusWidth)
      navigationButton(
        forward: true, height: height + (height >= 56 ? 12 : 8), width: navigationWidth,
        action: next
      )
      .disabled(
        (navigationIndex ?? exerciseIndex) >= (navigationCount ?? workout.exercises.count) - 1
      )
      .accessibilityIdentifier("nextWorkoutExercise")
    }
  }

  private func actionBlock(height: CGFloat, plusWidth: CGFloat) -> some View {
    WorkoutActionSurface {
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
      primaryAction(height: WorkoutControlSizing.primaryDiameter(for: height)).zIndex(1)
      if isOngoing {
        Button(action: add) {
          Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
            .frame(minWidth: plusWidth, maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
        }
        .disabled(
          workout.status != .active
            || (currentGroup?.roundCount ?? 30) >= 30
        )
        .accessibilityLabel(
          L10n.text(
            currentGroup?.isSuperset == true ? "Добавить круг" : "Добавить подход", locale: locale)
        )
        .accessibilityIdentifier("addWorkoutSet")
      } else {
        Spacer(minLength: 0)
      }
    }
    .font(.system(size: 18, weight: .semibold))
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
      .themeGlow(in: Circle(), emphasized: true)
      .overlay {
        if isOngoing {
          WorkoutCompletionRing(progress: stageProgress).padding(5)
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

  private var stageProgress: WorkoutCompletionProgress {
    guard workout.exercises.indices.contains(exerciseIndex) else {
      return WorkoutCompletionProgress()
    }
    let row = workout.exercises[exerciseIndex]
    if let group = workout.groupContaining(exerciseID: row.id), group.isSuperset {
      return WorkoutCompletionProgress(group: group)
    }
    return WorkoutCompletionProgress(exercise: row)
  }

  private var currentGroup: WorkoutExerciseGroup? {
    guard workout.exercises.indices.contains(exerciseIndex) else { return nil }
    return workout.groupContaining(exerciseID: workout.exercises[exerciseIndex].id)
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
