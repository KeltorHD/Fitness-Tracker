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
        VStack(alignment: .leading, spacing: 28) {
          VStack(spacing: 14) {
            SectionHeading(title: L10n.text("История", locale: locale), symbol: "clock")
            TrainingMonthCard(date: model.month, summary: model.report.month, move: model.moveMonth)
          }
          if let record = model.selectedRecord {
            VStack(spacing: 14) {
              HStack {
                SectionHeading(
                  title: L10n.exerciseName(record.exercise, locale: locale), symbol: "dumbbell")
                Menu {
                  ForEach(model.report.records) { item in
                    Button(L10n.exerciseName(item.exercise, locale: locale)) {
                      model.selectedExerciseID = item.id
                    }
                  }
                } label: {
                  Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
              }
              VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                  Text(
                    L10n.format(
                      "Объём за тренировку, %@",
                      String(L10n.text(unit.rawValue, locale: locale)), locale: locale
                    )
                  ).font(.subheadline).foregroundStyle(
                    .secondary)
                  Spacer()
                  Label(
                    "\(unit.display(record.weightKG).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...1)))) \(L10n.text(unit.rawValue, locale: locale))",
                    systemImage: "trophy.fill"
                  )
                  .font(.headline).foregroundStyle(FitTheme.accent)
                }
                Chart(model.points) { point in
                  BarMark(
                    x: .value(L10n.text("Дата", locale: locale), point.date),
                    y: .value(L10n.text("Объём", locale: locale), unit.display(point.volume))
                  )
                  .foregroundStyle(FitTheme.accent).cornerRadius(3)
                }.frame(height: 215).chartYAxis { AxisMarks(position: .trailing) }
                  .accessibilityLabel(L10n.text("Объём упражнения по тренировкам", locale: locale))
              }.fitCard()
            }
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
            }.fitCard()
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
              }.fitCard()
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
        .onChange(of: calendar) { refresh() }
        .onChange(of: phase) { if phase == .active { refresh() } }
    }
  }
  private func refresh() { model.refresh(workouts: store.workouts, calendar: calendar) }
}
