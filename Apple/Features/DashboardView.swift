import FitSessionCore
import SwiftUI

struct DashboardView: View {
  @Environment(AppStore.self) private var store
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
              .font(.subheadline).foregroundStyle(.secondary)
            Text("Время для себя.").font(.largeTitle.bold())
            Text("Каждый подход — шаг вперёд.").foregroundStyle(.secondary)
          }
          HStack(alignment: .top, spacing: 12) {
            MetricView(
              value: "\(store.completed.count)", title: "тренировок", symbol: "checkmark.seal")
            MetricView(
              value: "\(TrainingStatistics.weeklyStreak(in: store.completed))",
              title: "недель подряд", symbol: "flame")
          }
          VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 44))
              .foregroundStyle(.tint)
            Text(store.active?.name ?? "Ваш следующий шаг").font(.title2.bold())
            Text(
              store.active == nil
                ? "Выберите план или начните свободную тренировку."
                : "Тренировка сохранена. Продолжите с последнего подхода."
            )
            .foregroundStyle(.secondary)
            Button(
              store.active == nil ? "Начать тренировку" : "Продолжить тренировку",
              systemImage: "play.fill"
            ) {
              store.start()
            }
            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier(
              "startWorkout")
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(24)
          .background(
            LinearGradient(
              colors: [Color.accentColor.opacity(0.18), Color(.secondarySystemGroupedBackground)],
              startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 28))
          NavigationLink {
            ExerciseLibraryView()
          } label: {
            Label("Библиотека упражнений", systemImage: "books.vertical").font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading).padding(20)
              .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
          }.buttonStyle(.plain)
          Text("Ваши планы").font(.title2.bold())
          ForEach(store.templates.prefix(2)) { template in
            Button {
              store.start(template: template)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 6) {
                  Text(template.name).font(.headline)
                  Text("\(template.exercises.count) упражнений · отдых \(template.restSeconds) с")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
              }.padding(20).background(
                Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            }.buttonStyle(.plain)
          }
        }.padding(20)
      }
      .background(Color(.systemGroupedBackground)).navigationTitle("FitSession")
    }
  }
}
