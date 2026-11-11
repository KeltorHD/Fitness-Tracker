import Charts
import FitLifeCore
import SwiftUI

struct ExerciseProgressSection: View {
  @Environment(\.locale) private var locale
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @Bindable var model: ExerciseProgressViewModel
  var showsExercisePicker = true
  @State private var expandedGroups: Set<ExerciseChartGroup> = []

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
        ForEach(ExerciseChartGroup.allCases) { group in
          DisclosureGroup(
            isExpanded: Binding(
              get: { expandedGroups.contains(group) },
              set: { expanded in
                if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
              })
          ) {
            if expandedGroups.contains(group) {
              VStack(spacing: 16) {
                ForEach(group.metrics) { metric in
                  ExerciseMetricChart(
                    metric: metric, points: model.series[metric] ?? [],
                    displayedPoint: model.displayedPoint, selectedPoint: model.selectedPoint,
                    selectedDate: $model.selectedDate, unit: unit)
                }
              }.padding(.top, 12)
            }
          } label: {
            Text(L10n.text(group.title, locale: locale)).font(.headline).foregroundStyle(.primary)
          }
          .resultsCard().accessibilityIdentifier("exerciseChartGroup_\(group.rawValue)")
        }
      }
      Text(
        L10n.text(
          "Учитываются только выполненные рабочие подходы. Разминка не включается. Вес тела не добавляется к отягощению.",
          locale: locale)
      ).font(.caption).foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Этапы дропсета включаются в объём и повторы. 1ПМ рассчитывается по основному этапу.",
          locale: locale)
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .onChange(of: model.selectedExerciseID) { expandedGroups = [] }
  }
}

private enum ExerciseChartGroup: String, CaseIterable, Identifiable {
  case strength, volume, repetitions
  var id: String { rawValue }
  var title: String {
    switch self {
    case .strength: "Вес и сила"
    case .volume: "Объём"
    case .repetitions: "Подходы и повторы"
    }
  }
  var metrics: [ExerciseProgressMetric] {
    switch self {
    case .strength: [.maximumWeight, .oneRepMax]
    case .volume: [.volume]
    case .repetitions: [.sets, .repetitions]
    }
  }
}

private struct ExerciseMetricChart: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
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
              ).foregroundStyle(colorTheme.accent).accessibilityHidden(true)
              PointMark(
                x: .value(L10n.text("Дата", locale: locale), point.date),
                y: .value(L10n.text(metric.title, locale: locale), display(point.value))
              )
              .foregroundStyle(colorTheme.accent)
              .accessibilityLabel(
                Text(point.date, format: .dateTime.day().month().year().hour().minute())
              )
              .accessibilityValue(Text(formatted(point.value)))
            } else {
              BarMark(
                x: .value(L10n.text("Дата", locale: locale), point.date),
                y: .value(L10n.text(metric.title, locale: locale), display(point.value))
              )
              .foregroundStyle(colorTheme.accent).cornerRadius(3)
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
    .resultsCard(glowing: false).accessibilityIdentifier("exerciseChart_\(metric.rawValue)")
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
  @State private var section = ExerciseHistorySection.history

  init(exercise: Exercise, workoutID: UUID? = nil, showsDemoBanner: Bool = true) {
    self.exercise = exercise
    self.showsDemoBanner = showsDemoBanner
    _model = State(
      initialValue: ExerciseProgressViewModel(
        exerciseID: exercise.id, workoutID: workoutID, period: .allTime))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        Picker(L10n.text("История упражнения", locale: locale), selection: $section) {
          Text(L10n.text("История", locale: locale)).tag(ExerciseHistorySection.history)
          Text(L10n.text("Графики", locale: locale)).tag(ExerciseHistorySection.charts)
        }
        .pickerStyle(.segmented).accessibilityIdentifier("exerciseHistorySection")
        Text(L10n.text("История упражнения по завершённым тренировкам", locale: locale))
          .font(.subheadline).foregroundStyle(.secondary)
        switch section {
        case .history:
          if !model.historyEntries.isEmpty {
            ExerciseHistoryControls(model: model)
          }
          if model.historyEntries.isEmpty {
            ContentUnavailableView(
              L10n.text("Нет выполненных подходов", locale: locale), systemImage: "clock",
              description: Text(
                L10n.text(
                  "Здесь появятся дата и выполненные подходы после завершения тренировки с этим упражнением.",
                  locale: locale)))
          } else if model.filteredHistoryEntries.isEmpty {
            ContentUnavailableView(
              L10n.text("Нет подходящих занятий", locale: locale),
              systemImage: "line.3.horizontal.decrease",
              description: Text(L10n.text("Измените поиск или сбросьте фильтры.", locale: locale)))
            Button(L10n.text("Сбросить поиск и фильтры", locale: locale)) {
              model.historyFilter = ExerciseWorkoutHistoryFilter()
            }.accessibilityIdentifier("resetExerciseHistoryFilters")
          } else {
            ForEach(model.filteredHistoryEntries) { entry in
              ExerciseWorkoutHistoryCard(entry: entry)
            }
          }
        case .charts:
          ExerciseProgressSection(model: model, showsExercisePicker: false)
        }
      }.padding(16)
    }
    .scrollDismissesKeyboard(.interactively)
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

private enum ExerciseHistorySection: Hashable { case history, charts }

private struct ExerciseHistoryControls: View {
  @Environment(\.locale) private var locale
  @Bindable var model: ExerciseProgressViewModel
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
        TextField(L10n.text("Название занятия", locale: locale), text: $model.historyFilter.query)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($searchFocused).onSubmit { searchFocused = false }
          .submitLabel(.search).accessibilityIdentifier("exerciseHistorySearch")
        if !model.historyFilter.query.isEmpty {
          Button(L10n.text("Очистить поиск", locale: locale), systemImage: "xmark.circle.fill") {
            model.historyFilter.query = ""
          }.labelStyle(.iconOnly).foregroundStyle(.secondary)
        }
      }
      .padding(12).background(FitTheme.card, in: .rect(cornerRadius: 16))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          Menu {
            Section(L10n.text("Период истории", locale: locale)) {
              Picker(
                L10n.text("Период истории", locale: locale), selection: $model.historyFilter.period
              ) {
                ForEach(ExerciseProgressPeriod.allCases) { period in
                  Text(L10n.text(period.title, locale: locale)).tag(period)
                }
              }.pickerStyle(.inline)
            }
            Section(L10n.text("Тип подходов", locale: locale)) {
              Picker(
                L10n.text("Тип подходов", locale: locale), selection: $model.historyFilter.setKind
              ) {
                ForEach(ExerciseWorkoutHistoryFilter.SetKind.allCases, id: \.self) { kind in
                  Text(L10n.text(kind.title, locale: locale)).tag(kind)
                }
              }.pickerStyle(.inline)
            }
          } label: {
            Label(
              L10n.text(
                model.historyFilter.hasFilters ? "Фильтры включены" : "Фильтры", locale: locale),
              systemImage: "line.3.horizontal.decrease")
          }.accessibilityIdentifier("exerciseHistoryFilters")
          Menu {
            Picker(
              L10n.text("Сортировка", locale: locale), selection: $model.historyFilter.sortOrder
            ) {
              ForEach(ExerciseWorkoutHistoryFilter.SortOrder.allCases, id: \.self) { order in
                Text(L10n.text(order.title, locale: locale)).tag(order)
              }
            }.pickerStyle(.inline)
          } label: {
            Label(
              L10n.text(model.historyFilter.sortOrder.title, locale: locale),
              systemImage: "arrow.up.arrow.down")
          }.accessibilityIdentifier("exerciseHistorySort")
          if model.historyFilter.isModified {
            Button(L10n.text("Сбросить", locale: locale), systemImage: "arrow.counterclockwise") {
              model.historyFilter = ExerciseWorkoutHistoryFilter()
            }.accessibilityIdentifier("clearExerciseHistoryFilters")
          }
        }.buttonStyle(.bordered).controlSize(.small).padding(.vertical, 2)
      }
      if model.historyFilter.hasFilters {
        Text(
          L10n.text(model.historyFilter.period.title, locale: locale) + " · "
            + L10n.text(model.historyFilter.setKind.title, locale: locale)
        ).font(.caption).foregroundStyle(.secondary)
      }
      Text(L10n.workoutCount(model.filteredHistoryEntries.count, locale: locale))
        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("exerciseHistoryCount")
    }
  }
}

extension ExerciseWorkoutHistoryFilter.SortOrder {
  fileprivate var title: String {
    switch self {
    case .newest: "Сначала новые"
    case .oldest: "Сначала старые"
    }
  }
}

extension ExerciseWorkoutHistoryFilter.SetKind {
  fileprivate var title: String {
    switch self {
    case .all: "Все подходы"
    case .working: "Рабочие подходы"
    case .warmup: "Разминка"
    case .dropSet: "Дропсеты"
    }
  }
}

private struct ExerciseWorkoutHistoryCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  let entry: ExerciseWorkoutHistoryEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "dumbbell").font(.title3).foregroundStyle(colorTheme.accent)
          .padding(10).background(colorTheme.accent.opacity(0.1), in: .circle)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(entry.name).font(.title3.bold()).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("exerciseHistoryTitle_\(entry.id)")
          Text(entry.date, format: .dateTime.day().month(.wide).year().hour().minute())
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("exerciseHistoryDate_\(entry.id)")
          Text(
            L10n.countText(entry.rows.reduce(0) { $0 + $1.sets.count }, kind: "set", locale: locale)
          )
          .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      ForEach(entry.rows) { row in
        VStack(alignment: .leading, spacing: 12) {
          if entry.rows.count > 1 {
            Text(L10n.format("№ %@", String(row.position), locale: locale) + " · " + row.name)
              .font(.subheadline.weight(.semibold))
          }
          ForEach(row.sets) { recorded in
            setDetails(recorded)
          }
        }.accessibilityIdentifier("exerciseHistoryRow_\(row.id)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .resultsCard(padding: FitTheme.cardPadding)
    .accessibilityIdentifier("exerciseHistoryWorkout_\(entry.id)")
  }

  private func setDetails(_ recorded: ExerciseWorkoutHistorySet) -> some View {
    let set = recorded.set
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(L10n.format("Подход %@", String(recorded.position), locale: locale))
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        if set.isWarmup {
          Label(L10n.text("Разминка", locale: locale), systemImage: "flame")
            .font(.caption).foregroundStyle(.secondary)
        } else if set.isDropSet {
          Text(L10n.text("Дропсет", locale: locale)).font(.caption).foregroundStyle(
            colorTheme.accent)
        }
      }
      ForEach(Array(set.stages.enumerated()), id: \.element.id) { index, stage in
        if let completedAt = stage.completedAt {
          VStack(alignment: .leading, spacing: 2) {
            let weight = unit.display(stage.weightKG).formatted(
              .number.locale(L10n.numberLocale).precision(.fractionLength(0...1)))
            Text(
              (index == 0 ? "" : "↳ ")
                + "\(weight) \(L10n.text(unit.rawValue, locale: locale)) × \(stage.repetitions)"
            )
            .font(index == 0 ? .headline : .subheadline).monospacedDigit()
            Text(completedAt, format: .dateTime.day().month().hour().minute())
              .font(.caption2).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("exerciseHistoryStage_\(stage.id)")
        }
      }
      if let multiplier = set.loadMultiplier, multiplier > 1 {
        Text(L10n.format("Множитель веса: %@", String(multiplier), locale: locale))
          .font(.caption).foregroundStyle(.secondary)
      }
      if let note = set.note, !note.isEmpty {
        Label(note, systemImage: "note.text").font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12).background(FitTheme.paper, in: .rect(cornerRadius: 16))
    .accessibilityIdentifier("exerciseHistorySet_\(set.id)")
  }
}
