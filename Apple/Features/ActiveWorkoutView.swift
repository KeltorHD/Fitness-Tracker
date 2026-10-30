import FitnessTrackerCore
import SwiftUI

struct ActiveWorkoutView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var pickingExercise = false
  @State private var confirmCancel = false
  @State private var renaming = false
  @State private var workoutName = ""
  var body: some View {
    NavigationStack {
      if let workout = store.active {
        List {
          WorkoutHero(title: workout.name, date: workout.startedAt)
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
          Section {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              HStack(spacing: 8) {
                SummaryMetric(
                  title: L10n.text("Время", locale: locale),
                  value: Duration.seconds(workout.duration(at: timeline.date)).formatted(
                    .time(pattern: .hourMinuteSecond)))
                SummaryMetric(
                  title: L10n.text("Объём", locale: locale),
                  value:
                    "\(unit.display(workout.volume).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0)))) \(L10n.text(unit.rawValue, locale: locale))"
                )
                SummaryMetric(
                  title: L10n.text("Подходы", locale: locale),
                  value: "\(workout.completedSets)/\(workout.totalSets)")
              }
            }
            if workout.status == .paused {
              Label(L10n.text("Тренировка на паузе", locale: locale), systemImage: "pause.circle")
            }
            if let end = workout.restEndsAt, end > .now {
              RestPill(end: end)
              Button(L10n.text("Пропустить отдых", locale: locale)) {
                store.mutate {
                  _ = try WorkoutLiveAction.skipRest(expectedEnd: end).apply(
                    to: &$0, expectedWorkoutID: workout.id)
                }
              }
            }
          }
          ForEach(workout.exercises) { exercise in
            Section {
              NavigationLink {
                ExerciseDetailView(exercise: exercise.exercise)
              } label: {
                Label(
                  L10n.text("Техника выполнения", locale: locale),
                  systemImage: "figure.strengthtraining.traditional")
              }
              NavigationLink {
                ExerciseProgressScreen(
                  exercise: exercise.exercise, workoutID: workout.id, showsDemoBanner: false)
              } label: {
                Label(
                  L10n.text("Прогресс упражнения", locale: locale), systemImage: "chart.xyaxis.line"
                )
              }
              .accessibilityLabel(
                L10n.format(
                  "Прогресс упражнения: %@", L10n.exerciseName(exercise.exercise, locale: locale),
                  locale: locale)
              )
              .accessibilityIdentifier("openExerciseProgress")
              ForEach(exercise.sets) { set in
                SetEditor(exerciseID: exercise.id, set: set, disabled: workout.status != .active)
              }
              Button(L10n.text("Добавить подход", locale: locale), systemImage: "plus") {
                store.mutate { try WorkoutEngine.addSet(exerciseID: exercise.id, to: &$0) }
              }.disabled(workout.status != .active)
            } header: {
              Text(L10n.exerciseName(exercise.exercise, locale: locale))
            }
          }
          if !store.isDemoMode { Section { WorkoutTrackerCard(tracker: store.tracker) } }
          Section {
            Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus.circle") {
              pickingExercise = true
            }
            .disabled(workout.status != .active).accessibilityIdentifier("addExercise")
            TextField(
              L10n.text("Заметка о тренировке", locale: locale),
              text: Binding(
                get: { store.active?.notes ?? "" },
                set: { text in store.mutate { $0.notes = text } }), axis: .vertical)
          }
          Section {
            Button(L10n.text("Отменить тренировку", locale: locale), role: .destructive) {
              confirmCancel = true
            }
          }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(FitTheme.paper)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FitTheme.accent, for: .navigationBar).toolbarBackground(
          .visible, for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { SessionControls(workout: workout) }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(L10n.text("Свернуть", locale: locale), systemImage: "chevron.down") { dismiss() }
          }
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button(L10n.text("Изменить название", locale: locale), systemImage: "textformat") {
                workoutName = workout.name
                renaming = true
              }
              Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
                pickingExercise = true
              }
              Button(
                L10n.text("Отменить тренировку", locale: locale), systemImage: "trash",
                role: .destructive
              ) {
                confirmCancel = true
              }
            } label: {
              Image(systemName: "ellipsis.circle.fill").foregroundStyle(.white)
            }
          }
        }
        .alert(L10n.text("Название тренировки", locale: locale), isPresented: $renaming) {
          TextField(L10n.text("Название", locale: locale), text: $workoutName)
          Button(L10n.text("Сохранить", locale: locale)) { store.mutate { $0.name = workoutName } }
          Button(L10n.text("Отмена", locale: locale), role: .cancel) {}
        }
        .sheet(isPresented: $pickingExercise) {
          ExercisePicker { exercise in
            store.mutate { try WorkoutEngine.addExercise(exercise, to: &$0) }
          }
        }
        .confirmationDialog(
          L10n.text(
            "Отменить тренировку? Выполненные подходы не попадут в статистику.", locale: locale),
          isPresented: $confirmCancel, titleVisibility: .visible
        ) {
          Button(L10n.text("Отменить тренировку", locale: locale), role: .destructive) {
            store.cancel()
          }
        }
      } else {
        ContentUnavailableView(
          L10n.text("Нет активной тренировки", locale: locale), systemImage: "dumbbell")
      }
    }
    .archiveTransferPresenter(when: !pickingExercise && !renaming && !confirmCancel)
    .alert(
      L10n.text("Ошибка", locale: locale),
      isPresented: Binding(
        get: {
          store.error != nil && !pickingExercise && !renaming && !confirmCancel
            && !store.archiveTransfer.isPresented
        },
        set: { if !$0 { store.error = nil } })
    ) {
      Button(L10n.text("Понятно", locale: locale), role: .cancel) { store.error = nil }
    } message: {
      Text(L10n.text(store.error ?? "", locale: locale))
    }
  }
}

private struct SetEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  let exerciseID: UUID
  let set: WorkoutSet
  let disabled: Bool
  @State private var weight = ""
  @State private var reps = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(L10n.text(unit.rawValue, locale: locale), text: $weight).keyboardType(.decimalPad)
          .accessibilityLabel(
            L10n.format(
              "Вес в %@", String(L10n.text(unit.rawValue, locale: locale)),
              locale: locale))
        Text(L10n.text(unit.rawValue, locale: locale)).foregroundStyle(.secondary)
        TextField(L10n.text("Повторы", locale: locale), text: $reps).keyboardType(.numberPad)
          .accessibilityLabel(L10n.text("Повторения", locale: locale))
        Button {
          complete()
        } label: {
          Image(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill").font(
            .title2)
        }
        .buttonStyle(.borderless).disabled(disabled || set.completedAt != nil)
        .accessibilityLabel(
          set.completedAt == nil
            ? L10n.text("Выполнить подход", locale: locale)
            : L10n.text("Подход выполнен", locale: locale)
        )
        .accessibilityIdentifier("completeSet")
      }
      .disabled(set.completedAt != nil)
      if set.completedAt == nil {
        Toggle(
          L10n.text("Разминочный подход", locale: locale),
          isOn: Binding(
            get: { set.isWarmup },
            set: { warmup in
              store.mutate { workout in
                try WorkoutEngine.setWarmup(
                  warmup, in: &workout, exerciseID: exerciseID, setID: set.id)
              }
            })
        ).font(.caption).disabled(disabled)
      } else if set.isWarmup {
        Text(L10n.text("Разминочный подход", locale: locale)).font(.caption).foregroundStyle(
          .secondary)
      }
    }
    .onAppear {
      weight = unit.display(set.weightKG).formatted(
        .number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))
      reps = String(set.repetitions)
    }
  }
  private func complete() {
    let formatter = NumberFormatter()
    formatter.locale = L10n.numberLocale
    formatter.numberStyle = .decimal
    guard let value = formatter.number(from: weight)?.doubleValue, let repetitions = Int(reps)
    else {
      store.error = L10n.text("Введите вес и число повторений.", locale: locale)
      return
    }
    withAnimation(reduceMotion ? nil : .smooth) {
      _ = store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: exerciseID, setID: set.id,
          repetitions: repetitions, weightKG: unit.kilograms(from: value))
      }
    }
  }
}

struct ExercisePicker: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var custom = false
  let select: (Exercise) -> Void
  var body: some View {
    NavigationStack {
      ExerciseLibraryView { exercise in
        select(exercise)
        dismiss()
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button(L10n.text("Своё упражнение", locale: locale), systemImage: "plus") {
            custom = true
          }
        }
      }
      .sheet(isPresented: $custom) {
        CustomExerciseView { exercise in
          select(exercise)
          dismiss()
        }
      }
    }
  }
}

private struct CustomExerciseView: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var muscle: MuscleGroup = .fullBody
  @State private var message: String?
  let select: (Exercise) -> Void
  var body: some View {
    NavigationStack {
      Form {
        TextField(L10n.text("Название", locale: locale), text: $name)
        Picker(L10n.text("Группа мышц", locale: locale), selection: $muscle) {
          ForEach(MuscleGroup.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if let message { Text(L10n.text(message, locale: locale)).foregroundStyle(.red) }
      }.navigationTitle(L10n.text("Своё упражнение", locale: locale))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(L10n.text("Отмена", locale: locale)) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Добавить", locale: locale)) {
              do {
                try Validation.name(name)
                select(Exercise(name: name, muscle: muscle))
                dismiss()
              } catch { message = error.localizedDescription }
            }
          }
        }
    }
  }
}
