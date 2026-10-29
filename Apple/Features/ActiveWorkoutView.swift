import FitSessionCore
import SwiftUI

struct ActiveWorkoutView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
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
                  title: "Время",
                  value: Duration.seconds(workout.duration(at: timeline.date)).formatted(
                    .time(pattern: .hourMinuteSecond)))
                SummaryMetric(
                  title: "Объём",
                  value:
                    "\(unit.display(workout.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)"
                )
                SummaryMetric(
                  title: "Подходы", value: "\(workout.completedSets)/\(workout.totalSets)")
              }
            }
            if workout.status == .paused {
              Label("Тренировка на паузе", systemImage: "pause.circle")
            }
            if let end = workout.restEndsAt, end > .now {
              RestPill(end: end)
              Button("Пропустить отдых") {
                store.mutate {
                  _ = try WorkoutLiveAction.skipRest(expectedEndDate: end).apply(
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
                Label("Техника выполнения", systemImage: "figure.strengthtraining.traditional")
              }
              ForEach(exercise.sets) { set in
                SetEditor(exerciseID: exercise.id, set: set, disabled: workout.status != .active)
              }
              Button("Добавить подход", systemImage: "plus") {
                store.mutate { try WorkoutEngine.addSet(exerciseID: exercise.id, to: &$0) }
              }.disabled(workout.status != .active)
            } header: {
              Text(exercise.exercise.name)
            }
          }
          Section {
            Button("Добавить упражнение", systemImage: "plus.circle") { pickingExercise = true }
              .disabled(workout.status != .active).accessibilityIdentifier("addExercise")
            TextField(
              "Заметка о тренировке",
              text: Binding(
                get: { store.active?.notes ?? "" },
                set: { text in store.mutate { $0.notes = text } }), axis: .vertical)
          }
          Section {
            Button("Отменить тренировку", role: .destructive) { confirmCancel = true }
          }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(FitTheme.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FitTheme.accent, for: .navigationBar).toolbarBackground(
          .visible, for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { SessionControls(workout: workout) }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Свернуть", systemImage: "chevron.down") { dismiss() }
          }
        }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button("Изменить название", systemImage: "textformat") {
                workoutName = workout.name
                renaming = true
              }
              Button("Добавить упражнение", systemImage: "plus") { pickingExercise = true }
              Button("Отменить тренировку", systemImage: "trash", role: .destructive) {
                confirmCancel = true
              }
            } label: {
              Image(systemName: "ellipsis.circle.fill").foregroundStyle(.white)
            }
          }
        }
        .alert("Название тренировки", isPresented: $renaming) {
          TextField("Название", text: $workoutName)
          Button("Сохранить") { store.mutate { $0.name = workoutName } }
          Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $pickingExercise) {
          ExercisePicker { exercise in
            store.mutate { try WorkoutEngine.addExercise(exercise, to: &$0) }
          }
        }
        .confirmationDialog(
          "Отменить тренировку? Выполненные подходы не попадут в статистику.",
          isPresented: $confirmCancel, titleVisibility: .visible
        ) {
          Button("Отменить тренировку", role: .destructive) { store.cancel() }
        }
      } else {
        ContentUnavailableView("Нет активной тренировки", systemImage: "dumbbell")
      }
    }
    .archiveTransferPresenter(when: !pickingExercise && !renaming && !confirmCancel)
    .alert(
      "Ошибка",
      isPresented: Binding(
        get: {
          store.error != nil && !pickingExercise && !renaming && !confirmCancel
            && !store.archiveTransfer.isPresented
        },
        set: { if !$0 { store.error = nil } })
    ) {
      Button("Понятно", role: .cancel) { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
}

private struct SetEditor: View {
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
        TextField(unit.rawValue, text: $weight).keyboardType(.decimalPad)
          .accessibilityLabel("Вес в \(unit.rawValue)")
        Text(unit.rawValue).foregroundStyle(.secondary)
        TextField("Повторы", text: $reps).keyboardType(.numberPad).accessibilityLabel("Повторения")
        Button {
          complete()
        } label: {
          Image(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill").font(
            .title2)
        }
        .buttonStyle(.borderless).disabled(disabled || set.completedAt != nil)
        .accessibilityLabel(set.completedAt == nil ? "Выполнить подход" : "Подход выполнен")
        .accessibilityIdentifier("completeSet")
      }
      .disabled(set.completedAt != nil)
      if set.completedAt == nil {
        Toggle(
          "Разминочный подход",
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
        Text("Разминочный подход").font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear {
      weight = unit.display(set.weightKG).formatted(.number.precision(.fractionLength(0...2)))
      reps = String(set.repetitions)
    }
  }
  private func complete() {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    guard let value = formatter.number(from: weight)?.doubleValue, let repetitions = Int(reps)
    else {
      store.error = "Введите вес и число повторений."
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
        ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
        ToolbarItem(placement: .primaryAction) {
          Button("Своё упражнение", systemImage: "plus") { custom = true }
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
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var muscle: MuscleGroup = .fullBody
  @State private var message: String?
  let select: (Exercise) -> Void
  var body: some View {
    NavigationStack {
      Form {
        TextField("Название", text: $name)
        Picker("Группа мышц", selection: $muscle) {
          ForEach(MuscleGroup.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if let message { Text(message).foregroundStyle(.red) }
      }.navigationTitle("Своё упражнение")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Добавить") {
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
