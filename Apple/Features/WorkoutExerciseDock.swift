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
            Label(
              L10n.text(
                isOngoing
                  ? (completingDrop ? "Выполнить этап дропсета" : "Выполнить подход")
                  : "К списку упражнений", locale: locale),
              systemImage: isOngoing ? "checkmark" : "chevron.down"
            ).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
          .disabled(isOngoing && !canComplete).accessibilityIdentifier("completeSet")
          if isOngoing {
            icon("plus", title: "Добавить подход", action: add)
              .disabled(
                workout.status != .active
                  || (workout.exercises.indices.contains(exerciseIndex)
                    && workout.exercises[exerciseIndex].sets.count >= 30)
              )
              .accessibilityIdentifier("addWorkoutSet")
          }
        }
        HStack(spacing: 12) {
          HStack(spacing: 0) {
            Button(action: previous) {
              Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.disabled(exerciseIndex == 0)
              .accessibilityLabel(L10n.text("Предыдущее упражнение", locale: locale))
              .accessibilityIdentifier("previousWorkoutExercise")
            Text("\(exerciseIndex + 1) / \(workout.exercises.count)")
              .font(.subheadline.weight(.medium)).monospacedDigit().padding(.horizontal, 4)
            Button(action: next) {
              Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.disabled(exerciseIndex >= workout.exercises.count - 1)
              .accessibilityLabel(L10n.text("Следующее упражнение", locale: locale))
              .accessibilityIdentifier("nextWorkoutExercise")
          }.buttonStyle(.plain).glassEffect(.regular, in: .capsule)
          Spacer(minLength: 0)
          if isOngoing {
            icon(
              workout.status == .paused ? "play.fill" : "pause.fill",
              title: workout.status == .paused ? "Продолжить" : "Пауза", action: pause
            )
            .accessibilityIdentifier("pauseExerciseWorkout")
            icon("stop.fill", title: "Завершить тренировку", action: finish)
              .disabled(workout.completedSets == 0).accessibilityIdentifier("finishWorkout")
          }
        }
      }
    }.padding(.vertical, 8)
  }

  private func icon(_ name: String, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: name).font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
    }.buttonStyle(.glass).buttonBorderShape(.circle)
      .accessibilityLabel(L10n.text(title, locale: locale))
  }
}
