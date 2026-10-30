import FitnessTrackerCore
import SwiftUI

struct LiveWorkoutHeartRateControls: View {
  @Environment(\.locale) private var locale
  let model: TrackerViewModel
  @State private var request = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      FreshHeartRateValue(reading: model.live.reading, isActive: model.live.state == .running)
      Text(L10n.text(model.live.state.message, locale: locale)).font(.caption).foregroundStyle(
        .secondary)
      if model.startingLive { ProgressView() }
      if model.hasLiveSession || model.startingLive {
        Button(L10n.text("Остановить приём пульса", locale: locale)) { model.stopLiveHeartRate() }
          .accessibilityIdentifier("stopLiveHeartRate")
      } else {
        Button(L10n.text("Включить приём пульса", locale: locale)) { request += 1 }
          .disabled(!model.canStartLive).accessibilityIdentifier("startLiveHeartRate")
      }
      if model.attachedWorkoutStatus == nil {
        Text(L10n.text("Сначала начните тренировку в FitnessTracker.", locale: locale)).font(
          .footnote
        ).foregroundStyle(.secondary)
      } else if model.attachedWorkoutStatus == .paused {
        Text(L10n.text("Продолжите тренировку, чтобы записывать пульс.", locale: locale)).font(
          .footnote
        ).foregroundStyle(.secondary)
      }
    }
    .task(id: request) { if request > 0 { await model.startLiveHeartRate() } }
  }
}

extension LiveHeartRateState {
  var message: String {
    switch self {
    case .idle, .stopped: "Приём пульса выключен."
    case .starting: "Подготовка приёма пульса…"
    case .running:
      "Приём пульса включён. Если измерения нет, проверьте посадку AirPods и доступ к пульсу."
    case .paused: "Приём пульса на паузе."
    case .failed: "Не удалось получить пульс. Проверьте AirPods и разрешения, затем повторите."
    }
  }
}
