import Charts
import FitnessTrackerCore
import SwiftUI

struct ExerciseProgressSection: View {
  @Environment(\.locale) private var locale
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @Bindable var model: ExerciseProgressViewModel
  var showsExercisePicker = true

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      if showsExercisePicker, !model.histories.isEmpty {
        Picker(L10n.text("Упражнение", locale: locale), selection: $model.selectedExerciseID) {
          ForEach(model.histories) { history in
            Text(L10n.exerciseName(history.exercise, locale: locale)).tag(Optional(history.id))
          }
        }
        .pickerStyle(.menu).accessibilityIdentifier("selectProgressExercise")
      }
      Picker(L10n.text("Период графиков", locale: locale), selection: $model.period) {
        ForEach(ExerciseProgressPeriod.allCases) { period in
          Text(L10n.text(period.title, locale: locale)).tag(period)
        }
      }
      .pickerStyle(.menu).accessibilityIdentifier("exerciseProgressPeriod")
      if model.points.isEmpty {
        ContentUnavailableView(
          L10n.text("Нет данных за выбранный период", locale: locale),
          systemImage: "chart.xyaxis.line",
          description: Text(
            L10n.text(
              "Выберите другой период или завершите тренировку с рабочими подходами этого упражнения.",
              locale: locale)))
      } else {
        Text(
          L10n.text(
            "Каждая точка — одна завершённая тренировка. Нажмите на график, чтобы посмотреть значения.",
            locale: locale)
        ).font(.footnote).foregroundStyle(.secondary)
        ForEach(ExerciseProgressMetric.allCases) { metric in
          ExerciseMetricChart(
            metric: metric, points: model.series[metric] ?? [],
            displayedPoint: model.displayedPoint, selectedPoint: model.selectedPoint,
            selectedDate: $model.selectedDate, unit: unit)
        }
      }
      Text(
        L10n.text(
          "Учитываются только выполненные рабочие подходы. Разминка не включается. Вес тела не добавляется к отягощению.",
          locale: locale)
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct ExerciseMetricChart: View {
  @Environment(\.locale) private var locale
  let metric: ExerciseProgressMetric
  let points: [ExerciseMetricPoint]
  let displayedPoint: ExerciseProgressPoint?
  let selectedPoint: ExerciseProgressPoint?
  @Binding var selectedDate: Date?
  let unit: WeightUnit

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text(metric.title, locale: locale)).font(.headline)
      if let displayedPoint {
        VStack(alignment: .leading, spacing: 4) {
          Text(formatted(metric.value(in: displayedPoint))).font(.title2.bold()).monospacedDigit()
          Text(displayedPoint.date, format: .dateTime.day().month().year().hour().minute())
            .font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
      }
      if points.isEmpty {
        Text(
          L10n.text(
            "Для расчёта 1ПМ нужны рабочие подходы с весом на 1–12 повторений.", locale: locale)
        )
        .font(.subheadline).foregroundStyle(.secondary)
      } else {
        Chart {
          ForEach(points) { point in
            if metric.usesLine {
              LineMark(
                x: .value(L10n.text("Дата", locale: locale), point.date),
                y: .value(L10n.text(metric.title, locale: locale), display(point.value))
              ).foregroundStyle(FitTheme.accent).accessibilityHidden(true)
              PointMark(
                x: .value(L10n.text("Дата", locale: locale), point.date),
                y: .value(L10n.text(metric.title, locale: locale), display(point.value))
              )
              .foregroundStyle(FitTheme.accent)
              .accessibilityLabel(
                Text(point.date, format: .dateTime.day().month().year().hour().minute())
              )
              .accessibilityValue(Text(formatted(point.value)))
            } else {
              BarMark(
                x: .value(L10n.text("Дата", locale: locale), point.date),
                y: .value(L10n.text(metric.title, locale: locale), display(point.value))
              )
              .foregroundStyle(FitTheme.accent).cornerRadius(3)
              .accessibilityLabel(
                Text(point.date, format: .dateTime.day().month().year().hour().minute())
              )
              .accessibilityValue(Text(formatted(point.value)))
            }
          }
          if let selectedPoint {
            RuleMark(x: .value(L10n.text("Дата", locale: locale), selectedPoint.date))
              .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
              .accessibilityHidden(true)
          }
        }
        .frame(height: 190)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.day().month())
          }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .accessibilityLabel(L10n.text(metric.title, locale: locale))
      }
      if metric == .oneRepMax {
        Text(
          L10n.text(
            "1ПМ — расчётная оценка по формуле Эпли, а не рекомендация нагрузки.", locale: locale)
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .fitCard().accessibilityIdentifier("exerciseChart_\(metric.rawValue)")
  }

  private func display(_ value: Double) -> Double {
    metric.usesWeight ? unit.display(value) : value
  }
  private func formatted(_ value: Double?) -> String {
    guard let value else { return "—" }
    let number = display(value).formatted(
      .number.locale(L10n.numberLocale).precision(.fractionLength(0...(metric.usesWeight ? 1 : 0))))
    return metric.usesWeight ? "\(number) \(L10n.text(unit.rawValue, locale: locale))" : number
  }
}

extension ExerciseProgressPeriod {
  fileprivate var title: String {
    switch self {
    case .fourWeeks: "4 недели"
    case .twelveWeeks: "12 недель"
    case .twentySixWeeks: "26 недель"
    case .allTime: "Всё время"
    }
  }
}

extension ExerciseProgressMetric {
  fileprivate var title: String {
    switch self {
    case .maximumWeight: "Максимальный рабочий вес"
    case .volume: "Рабочий объём"
    case .oneRepMax: "Расчётный 1ПМ"
    case .repetitions: "Рабочие повторения"
    case .sets: "Рабочие подходы"
    }
  }
}

struct ExerciseProgressScreen: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @Environment(AppStore.self) private var store
  let exercise: Exercise
  let showsDemoBanner: Bool
  @State private var model: ExerciseProgressViewModel

  init(exercise: Exercise, workoutID: UUID? = nil, showsDemoBanner: Bool = true) {
    self.exercise = exercise
    self.showsDemoBanner = showsDemoBanner
    _model = State(
      initialValue: ExerciseProgressViewModel(
        exerciseID: exercise.id, workoutID: workoutID, period: .allTime))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(L10n.text("История упражнения по завершённым тренировкам", locale: locale))
          .font(.subheadline).foregroundStyle(.secondary)
        ExerciseProgressSection(model: model, showsExercisePicker: false)
      }.padding(16)
    }
    .background(FitTheme.paper)
    .safeAreaInset(edge: .top) {
      if store.isDemoMode && showsDemoBanner { DemoModeBanner() }
    }
    .navigationTitle(L10n.exerciseName(exercise, locale: locale))
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("exerciseProgressScreen")
    .onChange(of: store.workouts, initial: true) { refresh() }
    .onChange(of: calendar) { refresh() }
    .onChange(of: phase) { if phase == .active { refresh() } }
  }

  private func refresh() { model.refresh(workouts: store.workouts, calendar: calendar) }
}
