import Charts
import FitSessionCore
import SwiftUI

struct ProgressScreen: View {
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
            SectionHeading(title: "История", symbol: "clock")
            TrainingMonthCard(date: model.month, summary: model.report.month, move: model.moveMonth)
          }
          if let record = model.selectedRecord {
            VStack(spacing: 14) {
              HStack {
                SectionHeading(title: record.exercise.name, symbol: "dumbbell")
                Menu {
                  ForEach(model.report.records) { item in
                    Button(item.exercise.name) { model.selectedExerciseID = item.id }
                  }
                } label: {
                  Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
              }
              VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                  Text("Объём за тренировку, \(unit.rawValue)").font(.subheadline).foregroundStyle(
                    .secondary)
                  Spacer()
                  Label(
                    "\(unit.display(record.weightKG).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)",
                    systemImage: "trophy.fill"
                  )
                  .font(.headline).foregroundStyle(FitTheme.accent)
                }
                Chart(model.points) { point in
                  BarMark(
                    x: .value("Дата", point.date),
                    y: .value("Объём", unit.display(point.volume))
                  )
                  .foregroundStyle(FitTheme.accent).cornerRadius(3)
                }.frame(height: 215).chartYAxis { AxisMarks(position: .trailing) }
                  .accessibilityLabel("Объём упражнения по тренировкам")
              }.fitCard()
            }
          }
          VStack(spacing: 14) {
            SectionHeading(title: "Общий объём", symbol: "chart.bar")
            VStack(alignment: .leading, spacing: 16) {
              Text("За 26 недель, \(unit.rawValue)").font(.subheadline).foregroundStyle(.secondary)
              Chart(model.report.weeks) { week in
                BarMark(
                  x: .value("Неделя", week.week, unit: .weekOfYear),
                  y: .value("Объём", unit.display(week.volume))
                )
                .foregroundStyle(FitTheme.accent).cornerRadius(3)
              }.frame(height: 180).chartYAxis { AxisMarks(position: .trailing) }
            }.fitCard()
          }
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Личные рекорды", symbol: "trophy")
            if model.report.records.isEmpty {
              ContentUnavailableView(
                "Пока нет рекордов", systemImage: "trophy",
                description: Text("Они появятся после рабочих подходов с добавленным весом."))
            }
            ForEach(model.report.records) { record in
              VStack(spacing: 10) {
                Text(record.exercise.name).font(.headline).frame(
                  maxWidth: .infinity, alignment: .leading)
                LabeledContent(
                  "Максимальный вес",
                  value:
                    "\(unit.display(record.weightKG).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
                )
                if record.estimatedOneRepMax > 0 {
                  LabeledContent(
                    "Расчётный 1ПМ",
                    value:
                      "\(unit.display(record.estimatedOneRepMax).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
                  )
                }
              }.fitCard()
            }
            Text(
              "1ПМ — оценка по формуле Эпли для 1–12 повторений. Собственный вес не включается в объём внешнего отягощения."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
      }.background(FitTheme.paper).navigationTitle("Результаты")
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
            Button("Начать тренировку", systemImage: "plus") { store.start() }.foregroundStyle(
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
