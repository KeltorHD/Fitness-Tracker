import FitSessionCore
import SwiftUI

@main struct FitSessionWatchApp: App {
  @State private var store = WatchStore()
  var body: some Scene {
    WindowGroup { WatchWorkoutView().environment(store) }
  }
}

struct WatchWorkoutView: View {
  @Environment(WatchStore.self) private var store
  @State private var reps = 8
  @State private var weight = 0.0
  @State private var cancel = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          if let workout = store.active {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              Text(
                Duration.seconds(workout.duration(at: timeline.date)).formatted(
                  .time(pattern: .hourMinuteSecond))
              )
              .font(.title2.monospacedDigit())
            }
            Text("\(workout.completedSets)/\(workout.totalSets) подходов").font(.caption)
            if workout.status == .paused { Text("На паузе").foregroundStyle(.secondary) }
            if let exercise = workout.exercises.first(where: {
              $0.sets.contains { $0.completedAt == nil }
            }),
              let set = exercise.sets.first(where: { $0.completedAt == nil })
            {
              Text(exercise.exercise.name).font(.headline)
              Stepper("\(reps) повторений", value: $reps, in: 1...1000)
              Stepper("\(weight.formatted()) кг", value: $weight, in: 0...1500, step: 2.5)
              Button("Готово", systemImage: "checkmark") {
                store.update {
                  try WorkoutEngine.completeSet(
                    in: &$0, exerciseID: exercise.id,
                    setID: set.id, repetitions: reps, weightKG: weight)
                }
              }.buttonStyle(.glassProminent).disabled(workout.status != .active)
                .onChange(of: set.id, initial: true) {
                  reps = set.repetitions
                  weight = set.weightKG
                }
            }
            if let end = workout.restEndsAt, end > .now {
              Text(timerInterval: Date.now...end, countsDown: true).font(.headline)
                .monospacedDigit()
            }
            Button(workout.status == .paused ? "Продолжить" : "Пауза") {
              store.update { value in
                if value.status == .paused {
                  try WorkoutEngine.resume(&value)
                } else {
                  try WorkoutEngine.pause(&value)
                }
              }
            }.buttonStyle(.glass)
            Button("Завершить") { store.finish() }.disabled(workout.completedSets == 0)
            Button("Отменить", role: .destructive) { cancel = true }
          } else {
            Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(.mint)
            Text("Ваш следующий подход").font(.headline)
            Button("Начать · Всё тело A") { store.start() }.buttonStyle(.glassProminent)
            Text("\(store.pending.count) ожидают передачи на iPhone").font(.caption)
            Button("Повторить передачу") { store.sync() }.disabled(store.pending.isEmpty)
          }
        }.padding(.horizontal, 8)
      }.navigationTitle("FitSession")
        .confirmationDialog("Отменить тренировку?", isPresented: $cancel) {
          Button("Отменить", role: .destructive) {
            store.cancel()
          }
        }
        .alert(
          "FitSession",
          isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
          Button("Понятно") { store.error = nil }
        } message: {
          Text(store.error ?? "")
        }
    }
  }
}
