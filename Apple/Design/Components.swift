import FitSessionCore
import SwiftUI

extension MuscleGroup {
  var title: String {
    switch self {
    case .chest: "Грудь"
    case .back: "Спина"
    case .legs: "Ноги"
    case .shoulders: "Плечи"
    case .arms: "Руки"
    case .core: "Пресс"
    case .fullBody: "Всё тело"
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
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var controls
  let workout: Workout
  var body: some View {
    // Requires Xcode validation: morphing, touch response, accessibility contrast.
    GlassEffectContainer(spacing: 20) {
      HStack(spacing: 20) {
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
            workout.status == .paused ? "Продолжить" : "Пауза",
            systemImage: workout.status == .paused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(.glass)
        .glassEffectID("pause", in: controls)
        if workout.completedSets > 0 {
          Button("Завершить", systemImage: "checkmark") { store.finish() }
            .buttonStyle(.glassProminent)
            .glassEffectID("finish", in: controls)
            .glassEffectTransition(.matchedGeometry)
            .accessibilityIdentifier("finishWorkout")
        }
      }
      .controlSize(.large)
    }
    .padding()
  }
}

struct RestPill: View {
  let end: Date
  var body: some View {
    HStack {
      Image(systemName: "timer")
      Text("Отдых")
      Text(timerInterval: Date.now...max(.now, end), countsDown: true).monospacedDigit()
    }
    .font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
    .glassEffect()
    .accessibilityLabel("Таймер отдыха")
  }
}
