import Charts
import FitSessionCore
import SwiftUI

struct ProgressScreen: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var showPro = false
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
            in: store.completed, count: store.purchases.isPro ? 26 : 8)
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
          if !store.purchases.isPro {
            Button("26 недель с FitSession Pro", systemImage: "sparkles") { showPro = true }
              .buttonStyle(.glass)
          }
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
      .sheet(isPresented: $showPro) { ProView() }
    }
  }
}

struct ProView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "sparkles").font(.system(size: 60)).foregroundStyle(.tint)
        Text("FitSession Pro").font(.largeTitle.bold())
        Text("График объёма за 26 недель. Разовая покупка, без подписки.").multilineTextAlignment(
          .center)
        if store.purchases.isPro {
          Label("Pro активирован", systemImage: "checkmark.seal.fill")
        } else if let product = store.purchases.product {
          Button("Открыть Pro · \(product.displayPrice)") {
            Task { await store.purchases.purchase() }
          }
          .buttonStyle(.glassProminent).controlSize(.large).disabled(store.purchases.isBusy)
        } else {
          Text("Продукт пока недоступен. Проверьте подключение или конфигурацию StoreKit в Xcode.")
            .foregroundStyle(.secondary)
          Button("Повторить загрузку") { Task { await store.purchases.load() } }.buttonStyle(.glass)
        }
        Button("Восстановить покупки") { Task { await store.purchases.restore() } }.disabled(
          store.purchases.isBusy)
        if let message = store.purchases.message { Text(message).font(.footnote) }
      }.padding(28).navigationTitle("Pro").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Закрыть") { dismiss() } }
    }
  }
}
