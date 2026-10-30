import FitnessTrackerCore
import SwiftUI

@main struct FitnessTrackerWatchApp: App {
  @State private var store = WatchStore()
  var body: some Scene {
    WindowGroup { WatchWorkoutView().environment(store).environment(\.locale, L10n.locale) }
  }
}

struct WatchWorkoutView: View {
  @Environment(\.locale) private var locale
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
            Text(
              L10n.format(
                "%@/%@ подходов", String(workout.completedSets),
                String(workout.totalSets), locale: locale)
            ).font(.caption)
            if workout.status == .paused {
              Text(L10n.text("На паузе", locale: locale)).foregroundStyle(.secondary)
            }
            if let exercise = workout.exercises.first(where: {
              $0.sets.contains { $0.completedAt == nil }
            }),
              let set = exercise.sets.first(where: { $0.completedAt == nil })
            {
              Text(L10n.exerciseName(exercise.exercise, locale: locale)).font(.headline)
              Stepper(
                L10n.countText(reps, kind: "rep", locale: locale),
                value: $reps, in: 1...1000)
              Stepper(
                L10n.format(
                  "%@ кг",
                  String(weight.formatted(.number.locale(L10n.numberLocale))),
                  locale: locale),
                value: $weight, in: 0...1500, step: 2.5)
              Button(L10n.text("Готово", locale: locale), systemImage: "checkmark") {
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
            Button(
              workout.status == .paused
                ? L10n.text("Продолжить", locale: locale) : L10n.text("Пауза", locale: locale)
            ) {
              store.update { value in
                if value.status == .paused {
                  try WorkoutEngine.resume(&value)
                } else {
                  try WorkoutEngine.pause(&value)
                }
              }
            }.buttonStyle(.glass)
            Button(L10n.text("Завершить", locale: locale)) { store.finish() }.disabled(
              workout.completedSets == 0)
            Button(L10n.text("Отменить", locale: locale), role: .destructive) { cancel = true }
          } else {
            Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
            Text(L10n.text("Ваш следующий подход", locale: locale)).font(.headline)
            Button(L10n.text("Начать · Всё тело A", locale: locale)) { store.start() }.buttonStyle(
              .glassProminent)
            Text(
              L10n.format(
                "%@ ожидают передачи на iPhone", String(store.pending.count),
                locale: locale)
            ).font(.caption)
            Button(L10n.text("Повторить передачу", locale: locale)) { store.sync() }.disabled(
              store.pending.isEmpty)
          }
        }.padding(.horizontal, 8)
      }.navigationTitle("FitnessTracker")
        .confirmationDialog(L10n.text("Отменить тренировку?", locale: locale), isPresented: $cancel)
      {
        Button(L10n.text("Отменить", locale: locale), role: .destructive) {
          store.cancel()
        }
      }
        .alert(
          "FitnessTracker",
          isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
          Button(L10n.text("Понятно", locale: locale)) { store.error = nil }
        } message: {
          Text(L10n.text(store.error ?? "", locale: locale))
        }
    }
  }
}
