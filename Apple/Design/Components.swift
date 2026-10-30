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
      Image(systemName: symbol).foregroundStyle(Color.accentColor)
      Text(value).font(.title2.bold()).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    .accessibilityElement(children: .combine)
  }
}

struct SessionControls: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var controls
  let workout: Workout
  var body: some View {
    // Requires Xcode validation: narrow screens, keyboard, Dynamic Type and glass contrast.
    VStack(spacing: 8) {
      GlassEffectContainer(spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            pauseButton
            finishButton
          }
          VStack(spacing: 12) {
            finishButton
            pauseButton
          }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
      }
      if workout.completedSets == 0 {
        Text(L10n.text("Для завершения отметьте хотя бы один выполненный подход.", locale: locale))
          .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
          .accessibilityIdentifier("finishWorkoutHint")
      }
    }
    .frame(maxWidth: .infinity).padding().background(FitTheme.paper)
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
      Label(
        workout.status == .paused
          ? L10n.text("Продолжить", locale: locale) : L10n.text("Пауза", locale: locale),
        systemImage: workout.status == .paused ? "play.fill" : "pause.fill")
    }
    .buttonStyle(.glass)
    .glassEffectID("pause", in: controls)
    .accessibilityIdentifier("pauseWorkout")
  }
  private var finishButton: some View {
    Button(L10n.text("Завершить тренировку", locale: locale), systemImage: "checkmark") {
      store.finish()
    }
    .buttonStyle(.glassProminent)
    .glassEffectID("finish", in: controls)
    .glassEffectTransition(.matchedGeometry)
    .disabled(workout.completedSets == 0)
    .accessibilityIdentifier("finishWorkout")
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
    .accessibilityLabel(L10n.text("Таймер отдыха", locale: locale))
  }
}
