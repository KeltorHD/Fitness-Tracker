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
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 8) {
        pauseButton
        finishButton
      }
      .font(.subheadline.weight(.semibold))
      .controlSize(.regular)
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
    .background(FitTheme.paper)
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
        systemImage: workout.status == .paused ? "play.fill" : "pause.fill"
      )
      .labelStyle(.iconOnly)
      .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .glassEffectID("pause", in: controls)
    .accessibilityIdentifier("pauseWorkout")
  }
  private var finishButton: some View {
    Button {
      store.finish()
    } label: {
      Label(L10n.text("Завершить", locale: locale), systemImage: "checkmark")
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.glassProminent)
    .glassEffectID("finish", in: controls)
    .glassEffectTransition(.matchedGeometry)
    .disabled(workout.completedSets == 0)
    .accessibilityLabel(L10n.text("Завершить тренировку", locale: locale))
    .accessibilityHint(
      workout.completedSets == 0
        ? L10n.text("Для завершения отметьте хотя бы один выполненный подход.", locale: locale) : ""
    )
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
