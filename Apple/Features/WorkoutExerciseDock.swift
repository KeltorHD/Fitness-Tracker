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
  private var isOngoing: Bool { [.active, .paused].contains(workout.status) }
  var body: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 8) {
        icon("chevron.left", title: "Предыдущее упражнение", action: previous)
          .disabled(exerciseIndex == 0).accessibilityIdentifier("previousWorkoutExercise")
        Spacer(minLength: 0)
        if isOngoing {
          icon("plus", title: "Добавить подход", action: add).disabled(workout.status != .active)
            .accessibilityIdentifier("addWorkoutSet")
          Spacer(minLength: 0)
          Button(action: complete) {
            Image(systemName: "checkmark").font(.system(size: 28, weight: .semibold)).frame(
              minWidth: 52, minHeight: 52)
          }.buttonStyle(.glassProminent).buttonBorderShape(.circle)
            .disabled(!canComplete).accessibilityLabel(
              L10n.text(
                completingDrop ? "Выполнить этап дропсета" : "Выполнить подход", locale: locale)
            )
            .accessibilityIdentifier("completeSet")
          Spacer(minLength: 0)
          icon(
            workout.status == .paused ? "play" : "pause",
            title: workout.status == .paused ? "Продолжить" : "Пауза", action: pause
          )
          .accessibilityIdentifier("pauseExerciseWorkout")
          Spacer(minLength: 0)
        } else {
          Button(action: close) {
            Image(systemName: "chevron.down").font(.system(size: 28)).frame(
              minWidth: 52, minHeight: 52)
          }
          .buttonStyle(.glassProminent).buttonBorderShape(.circle)
          .accessibilityLabel(L10n.text("К списку упражнений", locale: locale))
          Spacer(minLength: 0)
        }
        icon("chevron.right", title: "Следующее упражнение", action: next)
          .disabled(exerciseIndex >= workout.exercises.count - 1).accessibilityIdentifier(
            "nextWorkoutExercise")
      }.controlSize(.large)
    }.padding(.vertical, 8)
  }
  private func icon(_ name: String, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: name).font(.system(size: 20)).frame(minWidth: 28, minHeight: 32)
    }
    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(
      L10n.text(title, locale: locale))
  }
}
