import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseDock: View {
  @Environment(\.locale) private var locale
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
        HStack(spacing: 12) {
          Button(action: isOngoing ? complete : close) {
            ViewThatFits(in: .horizontal) {
              Label(actionTitle, systemImage: isOngoing ? "checkmark" : "chevron.down")
                .fixedSize()
              Label(
                L10n.text(isOngoing ? "Готово" : "Закрыть", locale: locale),
                systemImage: isOngoing ? "checkmark" : "chevron.down"
              )
              .fixedSize()
              Image(systemName: isOngoing ? "checkmark" : "chevron.down")
            }.font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
          .disabled(isOngoing && !canComplete).accessibilityLabel(actionTitle)
          .accessibilityIdentifier("completeSet")
          if isOngoing {
            icon("plus", title: "Добавить подход", action: add)
              .disabled(
                workout.status != .active
                  || (workout.exercises.indices.contains(exerciseIndex)
                    && workout.exercises[exerciseIndex].sets.count >= 30)
              )
              .accessibilityIdentifier("addWorkoutSet")
            icon(
              workout.status == .paused ? "play.fill" : "pause.fill",
              title: workout.status == .paused ? "Продолжить" : "Пауза", action: pause
            ).accessibilityIdentifier("pauseExerciseWorkout")
            icon("stop.fill", title: "Завершить тренировку", action: finish)
              .disabled(workout.completedSets == 0).accessibilityIdentifier("finishWorkout")
          }
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
