import Charts
import FitnessTrackerCore
import SwiftUI

struct HealthChartsView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store

  var body: some View {
    @Bindable var model = store.healthCharts
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        CurrentHeartRateView(tracker: store.tracker, health: model).fitCard()
        Toggle(L10n.text("Пульс и шаги из «Здоровья»", locale: locale), isOn: $model.enabled)
          .accessibilityIdentifier("enableHealthCharts")
        Text(
          L10n.text(
            "Показываем доступные источники: Apple Watch, AirPods, приложения браслетов и iPhone. Частота обновлений зависит от устройства и синхронизации с «Здоровьем».",
            locale: locale)
        ).font(.footnote).foregroundStyle(.secondary)
        NavigationLink(L10n.text("Трекер", locale: locale)) { TrackerView(model: store.tracker) }
        if model.enabled {
          DatePicker(
            L10n.text("День", locale: locale), selection: $model.day, in: ...Date(),
            displayedComponents: .date)
          if model.loading { ProgressView(L10n.text("Чтение показателей…", locale: locale)) }
          if let snapshot = model.snapshot {
            if model.points.isEmpty && snapshot.steps.allSatisfy({ $0.steps == nil }) {
              Text(
                L10n.text(
                  "Нет доступных данных. Проверьте синхронизацию приложения трекера и разрешения FitnessTracker в «Здоровье».",
                  locale: locale)
              ).font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
              Label(L10n.text("Пульс за день", locale: locale), systemImage: "heart.fill")
                .font(.headline)
              if model.points.isEmpty {
                Text(L10n.text("Нет записанных измерений пульса.", locale: locale))
                  .foregroundStyle(.secondary)
              } else {
                HeartRateLineChart(points: model.points).frame(height: 200)
                  .accessibilityIdentifier("dailyHeartRateChart")
              }
              Text(
                L10n.text("Разрывы графика означают отсутствие измерений.", locale: locale)
              ).font(.caption).foregroundStyle(.secondary)
            }.fitCard()
            VStack(alignment: .leading, spacing: 14) {
              Label(L10n.text("Шаги за 7 дней", locale: locale), systemImage: "figure.walk")
                .font(.headline)
              if snapshot.steps.allSatisfy({ $0.steps == nil }) {
                Text(L10n.text("Нет доступных данных о шагах.", locale: locale))
                  .foregroundStyle(.secondary)
              } else {
                Chart(snapshot.steps) { day in
                  if let count = day.steps {
                    BarMark(
                      x: .value(L10n.text("День", locale: locale), day.date, unit: .day),
                      y: .value(L10n.text("Шаги", locale: locale), count)
                    )
                    .foregroundStyle(FitTheme.accent)
                  }
                }.frame(height: 200).accessibilityIdentifier("dailyStepsChart")
                ForEach(snapshot.steps) { day in
                  LabeledContent {
                    Text(day.steps.map { $0.formatted(.number.locale(locale)) } ?? "—")
                  } label: {
                    Text(day.date, format: .dateTime.day().month(.abbreviated))
                  }.font(.subheadline)
                }
              }
              Text(
                L10n.text(
                  "Прочерк означает отсутствие доступных данных, а не ноль шагов.", locale: locale)
              ).font(.caption).foregroundStyle(.secondary)
            }.fitCard()
          }
          if let error = model.error {
            Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
            Button(L10n.text("Повторить", locale: locale)) { model.retry() }
          }
          Button(L10n.text("Обновить показатели", locale: locale)) { model.retry() }
            .disabled(model.loading)
        }
      }.padding(16)
    }
    .background(FitTheme.paper).navigationTitle(L10n.text("Пульс и шаги", locale: locale))
  }
}

struct HeartRateLineChart: View {
  @Environment(\.locale) private var locale
  let points: [HeartRateChartPoint]
  var body: some View {
    Chart(points) { point in
      LineMark(
        x: .value(L10n.text("Время", locale: locale), point.reading.date),
        y: .value(L10n.text("уд/мин", locale: locale), point.reading.beatsPerMinute),
        series: .value("Segment", point.segment))
      PointMark(
        x: .value(L10n.text("Время", locale: locale), point.reading.date),
        y: .value(L10n.text("уд/мин", locale: locale), point.reading.beatsPerMinute)
      )
      .symbolSize(8)
    }
    .foregroundStyle(FitTheme.accent)
    .chartYScale(domain: .automatic(includesZero: false))
    .accessibilityLabel(L10n.text("Пульс", locale: locale))
  }
}

struct CurrentHeartRateView: View {
  @Environment(\.locale) private var locale
  let tracker: TrackerViewModel
  let health: HealthChartsViewModel

  private var reading: HeartRateReading? {
    if tracker.mode == .bluetooth, tracker.bluetooth.connection == .connected {
      return tracker.bluetooth.reading
    }
    if tracker.live.state == .running { return tracker.live.reading }
    return health.snapshot?.latestHeartRate
  }
  private var source: String? {
    if tracker.mode == .bluetooth, tracker.bluetooth.connection == .connected {
      return tracker.bluetooth.deviceName ?? L10n.text("Bluetooth-пульсометр", locale: locale)
    }
    if tracker.live.state == .running {
      return L10n.text("Пульс во время тренировки", locale: locale)
    }
    return health.snapshot?.heartRateSource
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      VStack(alignment: .leading, spacing: 8) {
        Label(L10n.text("Текущий пульс", locale: locale), systemImage: "heart.fill").font(.headline)
        if let reading {
          HStack(alignment: .firstTextBaseline) {
            Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0)))
              .font(.title2.bold()).monospacedDigit()
            Text(L10n.text("уд/мин", locale: locale))
          }
          let fresh =
            reading.isFresh(at: timeline.date)
            && (tracker.bluetooth.connection == .connected || tracker.live.state == .running
              || health.observing)
          Text(L10n.text(fresh ? "Свежее измерение" : "Последнее измерение", locale: locale))
            .font(.caption).foregroundStyle(fresh ? FitTheme.accent : FitTheme.muted)
          Text(reading.date, format: .dateTime.day().month(.abbreviated).hour().minute().second())
            .font(.caption).foregroundStyle(.secondary)
          if let source { Text(source).font(.caption).foregroundStyle(.secondary) }
        } else {
          Text(L10n.text("Нет свежего измерения", locale: locale)).foregroundStyle(.secondary)
        }
      }.accessibilityElement(children: .combine).accessibilityIdentifier("currentHeartRate")
    }
  }
}

struct WorkoutLiveHeartRateChart: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  let workoutID: UUID
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CurrentHeartRateView(tracker: store.tracker, health: store.healthCharts)
      if store.tracker.recording?.workoutID == workoutID, !store.tracker.chartPoints.isEmpty {
        HeartRateLineChart(points: store.tracker.chartPoints).frame(height: 120)
          .accessibilityIdentifier("liveWorkoutHeartRateChart")
      } else if !store.healthCharts.workoutPoints.isEmpty {
        HeartRateLineChart(points: store.healthCharts.workoutPoints).frame(height: 120)
          .accessibilityIdentifier("liveWorkoutHeartRateChart")
      }
      NavigationLink(L10n.text("Пульс и шаги", locale: locale)) {
        HealthChartsView().toolbar(.visible, for: .navigationBar)
      }
      .accessibilityIdentifier("openHealthCharts")
    }
  }
}
