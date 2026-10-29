import Charts
import FitSessionCore
import SwiftUI

struct ProgressScreen: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text("Ваша последовательность").font(.title2.bold())
          Text(
            "Объём рабочих подходов по неделям, \(unit.rawValue). Разминка и невыполненные подходы не учитываются."
          )
          .font(.subheadline).foregroundStyle(.secondary)
          let weeks = TrainingStatistics.weeks(
            in: store.completed, count: 26)
          Chart(weeks) { week in
            BarMark(
              x: .value("Неделя", week.week, unit: .weekOfYear),
              y: .value("Объём", unit.display(week.volume))
            )
            .foregroundStyle(Color.accentColor.gradient).cornerRadius(5)
          }
          .frame(height: 230)
          .accessibilityLabel("Объём тренировок по неделям")
          .accessibilityValue("\(store.completed.count) завершённых тренировок")
          Text("Личные рекорды").font(.title2.bold())
          let records = TrainingStatistics.records(in: store.completed)
          if records.isEmpty {
            ContentUnavailableView(
              "Всё впереди", systemImage: "chart.bar",
              description: Text(
                "Запишите рабочие подходы с добавленным весом, чтобы увидеть рекорды."))
          }
          ForEach(records) { record in
            VStack(alignment: .leading, spacing: 10) {
              Text(record.exercise.name).font(.headline)
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
            }.font(.subheadline).padding(20)
              .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
          }
          Text(
            "1ПМ — оценка по формуле Эпли для 1–12 повторений, а не рекомендация рабочего веса. Упражнения с собственным весом записываются с 0 кг добавленного веса."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
      }
      .background(Color(.systemGroupedBackground)).navigationTitle("Прогресс")
    }
  }
}
