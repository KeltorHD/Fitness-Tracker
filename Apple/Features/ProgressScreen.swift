import Charts
import FitnessTrackerCore
import SwiftUI

struct ProgressScreen: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @State private var model = ProgressViewModel()
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 28) {
          VStack(spacing: 14) {
            HStack {
              SectionHeading(title: L10n.text("История", locale: locale), symbol: "clock")
              Menu {
                Button(L10n.text("Предыдущий месяц", locale: locale)) { model.moveMonth(by: -1) }
                Button(L10n.text("Следующий месяц", locale: locale)) { model.moveMonth(by: 1) }
                Button(L10n.text("Текущий месяц", locale: locale)) { model.showCurrentMonth() }
              } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
              }
              .accessibilityLabel(L10n.text("Период истории", locale: locale))
              .accessibilityIdentifier("historyPeriodMenu")
            }
            TrainingMonthPager(pages: model.monthPages) { [month = model.month] direction in
              guard model.month == month else { return }
              model.moveMonth(by: direction)
            }
            .id(model.month)
          }
          VStack(spacing: 14) {
            HStack {
              SectionHeading(title: L10n.text("Весы", locale: locale), symbol: "scalemass")
              NavigationLink {
                BodyWeightHistoryView()
              } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
              }
              .accessibilityLabel(L10n.text("История веса", locale: locale))
              .accessibilityIdentifier("openBodyWeightHistory")
            }
            BodyWeightCard(model: model.bodyWeight)
          }
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
              title: L10n.text("Прогресс по упражнениям", locale: locale),
              symbol: "chart.xyaxis.line")
            ExerciseProgressSection(model: model.exerciseProgress)
          }
          VStack(spacing: 14) {
            SectionHeading(title: L10n.text("Общий объём", locale: locale), symbol: "chart.bar")
            VStack(alignment: .leading, spacing: 16) {
              Text(
                L10n.format(
                  "За 26 недель, %@",
                  String(L10n.text(unit.rawValue, locale: locale)), locale: locale)
              ).font(.subheadline).foregroundStyle(.secondary)
              Chart(model.report.weeks) { week in
                BarMark(
                  x: .value(L10n.text("Неделя", locale: locale), week.week, unit: .weekOfYear),
                  y: .value(L10n.text("Объём", locale: locale), unit.display(week.volume))
                )
                .foregroundStyle(FitTheme.accent).cornerRadius(3)
              }.frame(height: 180).chartYAxis { AxisMarks(position: .trailing) }
            }.resultsCard()
          }
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: L10n.text("Личные рекорды", locale: locale), symbol: "trophy")
            if model.report.records.isEmpty {
              ContentUnavailableView(
                L10n.text("Пока нет рекордов", locale: locale), systemImage: "trophy",
                description: Text(
                  L10n.text(
                    "Они появятся после рабочих подходов с добавленным весом.", locale: locale)))
            }
            ForEach(model.report.records) { record in
              VStack(spacing: 10) {
                Text(L10n.exerciseName(record.exercise, locale: locale)).font(.headline).frame(
                  maxWidth: .infinity, alignment: .leading)
                LabeledContent(
                  L10n.text("Максимальный вес", locale: locale),
                  value:
                    "\(unit.display(record.weightKG).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...1)))) \(L10n.text(unit.rawValue, locale: locale))"
                )
                if record.estimatedOneRepMax > 0 {
                  LabeledContent(
                    L10n.text("Расчётный 1ПМ", locale: locale),
                    value:
                      "\(unit.display(record.estimatedOneRepMax).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...1)))) \(L10n.text(unit.rawValue, locale: locale))"
                  )
                }
              }.resultsCard()
            }
            Text(
              L10n.text(
                "1ПМ — оценка по формуле Эпли для 1–12 повторений. Собственный вес не включается в объём внешнего отягощения.",
                locale: locale)
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
      }.background(FitTheme.paper).navigationTitle(L10n.text("Результаты", locale: locale))
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              ForEach(model.report.years, id: \.self) { year in
                Button(String(year)) { model.selectYear(year) }
              }
            } label: {
              Text(String(model.year)).foregroundStyle(.primary)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button(L10n.text("Начать тренировку", locale: locale), systemImage: "plus") {
              store.start()
            }.foregroundStyle(
              .primary)
          }
        }
        .onChange(of: store.workouts, initial: true) { refresh() }
        .onChange(of: store.bodyWeights) { refresh() }
        .onChange(of: calendar) { refresh() }
        .onChange(of: phase) { if phase == .active { refresh() } }
    }
  }
  private func refresh() {
    model.refresh(workouts: store.workouts, calendar: calendar, bodyWeights: store.bodyWeights)
  }
}
