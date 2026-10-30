import Charts
import FitnessTrackerCore
import SwiftUI

struct WorkoutHeartRateView: View {
  @Environment(\.locale) private var locale
  let workout: Workout
  @State private var model: WorkoutHeartRateViewModel
  @State private var request = 0
  @State private var importHealth = false
  init(workout: Workout, tracker: TrackerViewModel) {
    self.workout = workout
    _model = State(initialValue: WorkoutHeartRateViewModel(tracker: tracker))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(L10n.text("Пульс", locale: locale), systemImage: "heart.fill").font(.headline)
      if model.loading { ProgressView() }
      if let record = model.recording, !model.points.isEmpty {
        HStack {
          if let average = record.average {
            Text(
              L10n.format(
                "Средний: %@", average.formatted(.number.precision(.fractionLength(0))),
                locale: locale))
          }
          Spacer()
          if let maximum = record.maximum {
            Text(
              L10n.format(
                "Максимум: %@", maximum.formatted(.number.precision(.fractionLength(0))),
                locale: locale))
          }
        }.font(.subheadline)
        Chart(model.points) { point in
          LineMark(
            x: .value(L10n.text("Время", locale: locale), point.reading.date),
            y: .value(L10n.text("уд/мин", locale: locale), point.reading.beatsPerMinute),
            series: .value("Segment", point.segment)
          )
          .foregroundStyle(FitTheme.accent)
        }.frame(height: 170).accessibilityLabel(
          L10n.text("Пульс во время тренировки", locale: locale))
        Text(
          L10n.text(
            record.origin == .liveHealthKit
              ? "Источник: пульс во время тренировки"
              : record.mode == .bluetooth
                ? "Источник: Bluetooth-пульсометр" : "Источник: Apple «Здоровье»", locale: locale)
        )
        .font(.caption).foregroundStyle(.secondary)
      } else if !model.loading {
        Text(L10n.text("Нет записанных измерений пульса.", locale: locale)).foregroundStyle(
          .secondary)
      }
      if let error = model.error {
        Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
        Button(L10n.text("Повторить", locale: locale)) { request += 1 }.disabled(model.loading)
      }
      if model.recording?.isLiveSensorRecording != true {
        Button(L10n.text("Загрузить пульс из «Здоровья»", locale: locale)) {
          importHealth = true
          request += 1
        }.disabled(model.loading)
      }
      Text(
        L10n.text(
          "Разрывы графика означают отсутствие измерений. Средний пульс рассчитан по сохранённым точкам.",
          locale: locale)
      )
      .font(.caption).foregroundStyle(.secondary)
    }.fitCard()
      .task(id: request) { await model.load(workout, importHealth: importHealth) }
  }
}
