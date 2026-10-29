import FitSessionCore
import SwiftUI

struct HistoryView: View {
  @Environment(AppStore.self) private var store
  @State private var pendingDelete: Workout?
  var body: some View {
    NavigationStack {
      List {
        if store.completed.isEmpty {
          ContentUnavailableView(
            "История начинается с вас", systemImage: "clock",
            description: Text("Завершённые тренировки появятся здесь."))
        }
        ForEach(store.completed) { workout in
          NavigationLink {
            WorkoutDetailView(workout: workout)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(workout.name).font(.headline)
              Text(workout.startedAt, format: .dateTime.day().month(.wide).year()).foregroundStyle(
                .secondary)
              Text("\(workout.completedSets) подходов · \(Int(workout.duration() / 60)) мин").font(
                .caption)
            }.padding(.vertical, 6)
          }
          .swipeActions { Button("Удалить", role: .destructive) { pendingDelete = workout } }
        }
      }
      .navigationTitle("История")
      .refreshable { store.reload() }
      .confirmationDialog(
        "Удалить тренировку? Это удалит её и из iCloud, если синхронизация включена.",
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible
      ) {
        Button("Удалить", role: .destructive) {
          if let workout = pendingDelete { store.delete(workout: workout) }
          pendingDelete = nil
        }
      }
    }
  }
}

struct WorkoutDetailView: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var exporting = false
  let workout: Workout
  var body: some View {
    List {
      Section {
        LabeledContent(
          "Дата", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent(
          "Время",
          value: Duration.seconds(workout.duration()).formatted(.time(pattern: .hourMinute)))
        LabeledContent(
          "Объём",
          value:
            "\(unit.display(workout.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)"
        )
      }
      ForEach(workout.exercises) { exercise in
        Section(exercise.exercise.name) {
          ForEach(exercise.sets.filter { $0.completedAt != nil }) { set in
            LabeledContent(
              set.isWarmup ? "Разминка" : "Подход",
              value:
                "\(unit.display(set.weightKG).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) × \(set.repetitions)"
            )
          }
        }
      }
      if !workout.notes.isEmpty { Section("Заметки") { Text(workout.notes) } }
      Section {
        Button("Экспорт в «Здоровье»", systemImage: "heart") {
          exporting = true
          Task {
            await store.exportHealth(workout)
            exporting = false
          }
        }.disabled(exporting)
        ShareLink(
          "Экспорт JSON", item: WorkoutDocument(workout: workout),
          preview: SharePreview(workout.name))
      } footer: {
        Text(
          "HealthKit получает тип и длительность тренировки. Вес снаряда и повторения остаются в FitSession. Удаление в FitSession не удаляет запись в «Здоровье»."
        )
      }
    }.navigationTitle(workout.name).navigationBarTitleDisplayMode(.inline)
  }
}
