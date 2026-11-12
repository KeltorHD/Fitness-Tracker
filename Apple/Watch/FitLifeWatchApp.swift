import FitLifeCore
import SwiftUI
import WatchKit

@main struct FitLifeWatchApp: App {
  @State private var page = 0
  @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var delegate
  var body: some Scene {
    WindowGroup {
      TabView(selection: $page) {
        WatchWorkoutView().tag(0)
        WatchSleepView().tag(1)
        WatchHeartRateView().tag(2)
      }.onChange(of: delegate.store.sleepAlarm.ringing) { _, value in if value { page = 1 } }
        .onChange(of: delegate.store.heartRate.snapshot.state) { _, value in
          if value == .starting || value == .running { page = 2 }
        }
        .environment(delegate.store).environment(\.locale, L10n.locale)
    }
  }
}

private struct WatchHeartRateView: View {
  @Environment(WatchStore.self) private var store
  @Environment(\.locale) private var locale
  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Label(L10n.text("Пульс на iPhone", locale: locale), systemImage: "heart.fill")
          .font(.headline)
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          if store.heartRate.snapshot.state == .running,
            let reading = store.heartRate.snapshot.reading,
            reading.isFreshForDisplay(at: timeline.date)
          {
            Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0)))
              .font(.largeTitle.bold()).monospacedDigit()
          } else {
            Text("—").font(.largeTitle).accessibilityLabel(
              L10n.text("Нет свежего измерения", locale: locale))
          }
        }
        Text(L10n.text("уд/мин", locale: locale)).foregroundStyle(.secondary)
        if [.starting, .running, .paused].contains(store.heartRate.snapshot.state) {
          Text(
            L10n.text(
              store.heartRate.snapshot.state == .paused ? "На паузе" : "Передача пульса на iPhone",
              locale: locale)
          )
          .font(.caption)
          Button(L10n.text("Остановить приём пульса", locale: locale)) { store.heartRate.stop() }
            .watchButtonStyle(prominent: false)
        } else {
          Text(
            L10n.text(
              "Начните тренировку на iPhone, выберите Apple Watch в настройках пульса и включите приём. Оставьте FitLife на часах открытым при запуске.",
              locale: locale)
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
        if let error = store.heartRate.error {
          Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red)
        }
      }.padding(.horizontal, 8)
    }
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
                "%@/%@ подходов", String(workout.fullyCompletedSets),
                String(workout.totalSets), locale: locale)
            ).font(.caption)
            if workout.status == .paused {
              Text(L10n.text("На паузе", locale: locale)).foregroundStyle(.secondary)
            }
            if let next = workout.nextPendingSet,
              let exercise = workout.exercises.first(where: { $0.id == next.exerciseID }),
              let set = exercise.sets.first(where: { $0.id == next.setID }),
              let target = set.stages.first(where: { $0.completedAt == nil })
            {
              Text(L10n.exerciseName(exercise.exercise, locale: locale)).font(.headline)
              if exercise.supersetID != nil {
                Text(
                  L10n.text("Суперсет", locale: locale) + " · "
                    + L10n.format("Круг %@", String(next.roundIndex + 1), locale: locale)
                ).font(.caption).foregroundStyle(.secondary)
              }
              if set.isDropSet {
                Text(
                  L10n.format(
                    "Дропсет · этап %@/%@",
                    String((set.stages.firstIndex { $0.id == target.id } ?? 0) + 1),
                    String(set.stages.count), locale: locale)
                ).font(.caption).foregroundStyle(.secondary)
              }
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
                  if target.id == set.id {
                    try WorkoutEngine.completeSet(
                      in: &$0, exerciseID: exercise.id, setID: set.id, repetitions: reps,
                      weightKG: weight)
                  } else {
                    try WorkoutEngine.completeDropStage(
                      in: &$0, exerciseID: exercise.id, setID: set.id, stageID: target.id,
                      repetitions: reps, weightKG: weight)
                  }
                }
              }.watchButtonStyle().disabled(workout.status != .active)
                .onChange(of: target.id, initial: true) {
                  reps = target.repetitions
                  weight = target.weightKG
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
            }.watchButtonStyle(prominent: false)
            Button(L10n.text("Завершить", locale: locale)) { store.finish() }.disabled(
              workout.completedSets == 0)
            Button(L10n.text("Отменить", locale: locale), role: .destructive) { cancel = true }
          } else {
            Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
            Text(L10n.text("Ваш следующий подход", locale: locale)).font(.headline)
            Button(L10n.text("Начать · Всё тело A", locale: locale)) { store.start() }
              .watchButtonStyle()
            Text(
              L10n.format(
                "%@ ожидают передачи на iPhone", String(store.pending.count),
                locale: locale)
            ).font(.caption)
            Button(L10n.text("Повторить передачу", locale: locale)) { store.sync() }.disabled(
              store.pending.isEmpty)
          }
        }.padding(.horizontal, 8)
      }.navigationTitle("FitLife")
        .confirmationDialog(L10n.text("Отменить тренировку?", locale: locale), isPresented: $cancel)
      {
        Button(L10n.text("Отменить", locale: locale), role: .destructive) {
          store.cancel()
        }
      }
        .alert(
          "FitLife",
          isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
          Button(L10n.text("Понятно", locale: locale)) { store.error = nil }
        } message: {
          Text(L10n.text(store.error ?? "", locale: locale))
        }
    }
  }
}
