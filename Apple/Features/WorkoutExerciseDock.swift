import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseDock: View {
  @Environment(\.locale) private var locale
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
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 12) {
        if isOngoing {
          // Equal layout slots keep completion centered independently of the icon counts.
          HStack(spacing: 8) {
            Color.clear.overlay(alignment: .leading) { sessionActions }
            Color.clear.overlay { primaryAction }
            Color.clear.overlay(alignment: .trailing) {
              icon("plus", title: "Добавить подход", action: add)
                .disabled(
                  workout.status != .active
                    || (workout.exercises.indices.contains(exerciseIndex)
                      && workout.exercises[exerciseIndex].sets.count >= 30)
                )
                .accessibilityIdentifier("addWorkoutSet")
            }
          }.frame(height: actionRowHeight)
        } else {
          primaryAction
        }
        HStack(spacing: 10) {
          navigationButton(forward: false, action: previous)
            .disabled(exerciseIndex == 0)
            .accessibilityIdentifier("previousWorkoutExercise")
          Text("\(exerciseIndex + 1) / \(workout.exercises.count)")
            .font(.subheadline.weight(.medium)).monospacedDigit()
            .foregroundStyle(.secondary).fixedSize()
          navigationButton(forward: true, action: next)
            .disabled(exerciseIndex >= workout.exercises.count - 1)
            .accessibilityIdentifier("nextWorkoutExercise")
        }
      }
    }.padding(.vertical, 8)
  }

  private var sessionActions: some View {
    HStack(spacing: 0) {
      Button(action: pause) {
        Image(systemName: workout.status == .paused ? "play.fill" : "pause.fill")
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(
        L10n.text(workout.status == .paused ? "Продолжить" : "Пауза", locale: locale)
      )
      .accessibilityIdentifier("pauseExerciseWorkout")
      Button(action: finish) {
        Image(systemName: "stop.fill").frame(width: 44, height: 44)
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
    .font(.body.weight(.semibold)).buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .capsule)
  }

  private var primaryAction: some View {
    Button(action: isOngoing ? complete : close) {
      ViewThatFits(in: .horizontal) {
        Text(L10n.text(isOngoing ? "Готово" : "К списку упражнений", locale: locale)).fixedSize()
        Image(systemName: isOngoing ? "checkmark" : "chevron.down")
      }
      .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
    .disabled(isOngoing && !canComplete).accessibilityLabel(actionTitle)
    .accessibilityIdentifier("completeSet")
  }

  private var actionTitle: String {
    L10n.text(
      isOngoing
        ? (completingDrop ? "Выполнить этап дропсета" : "Выполнить подход") : "К списку упражнений",
      locale: locale)
  }

  private func navigationButton(forward: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          if !forward { Image(systemName: "chevron.left") }
          Text(L10n.text(forward ? "Далее" : "Назад", locale: locale))
          if forward { Image(systemName: "chevron.right") }
        }
        Image(systemName: forward ? "chevron.right" : "chevron.left")
      }
      .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
      .contentShape(.capsule)
    }
    .buttonStyle(.glass).buttonBorderShape(.capsule)
    .accessibilityLabel(
      L10n.text(forward ? "Следующее упражнение" : "Предыдущее упражнение", locale: locale))
  }

  private func icon(_ name: String, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: name).font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
    }.buttonStyle(.glass).buttonBorderShape(.circle)
      .accessibilityLabel(L10n.text(title, locale: locale))
  }
}
