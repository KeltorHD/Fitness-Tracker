import FitSessionCore
import SwiftUI

struct ActiveWorkoutView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var pickingExercise = false
  @State private var confirmCancel = false
  var body: some View {
    NavigationStack {
      if let workout = store.active {
        List {
          Section {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              HStack {
                Label(
                  Duration.seconds(workout.duration(at: timeline.date)).formatted(
                    .time(pattern: .hourMinuteSecond)), systemImage: "stopwatch")
                Spacer()
                Text("\(workout.completedSets)/\(workout.totalSets)").monospacedDigit()
              }.font(.headline)
            }
            if workout.status == .paused {
              Label("Тренировка на паузе", systemImage: "pause.circle")
            }
            if let end = workout.restEndsAt, end > .now {
              RestPill(end: end)
              Button("Пропустить отдых") { store.mutate { $0.restEndsAt = nil } }
            }
          }
          ForEach(workout.exercises) { exercise in
            Section {
              if !exercise.exercise.instructions.isEmpty {
                Text(exercise.exercise.instructions).font(.caption).foregroundStyle(.secondary)
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
        .navigationTitle(workout.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { SessionControls(workout: workout) }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Свернуть", systemImage: "chevron.down") { dismiss() }
          }
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
    .alert(
      "Ошибка",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
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
                guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == set.id })
                else { return }
                workout.exercises[e].sets[s].isWarmup = warmup
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
      store.mutate {
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: exerciseID, setID: set.id,
          repetitions: repetitions, weightKG: unit.kilograms(from: value))
      }
    }
  }
}

struct ExercisePicker: View {
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var custom = false
  let select: (Exercise) -> Void
  var body: some View {
    NavigationStack {
      List(
        ExerciseCatalog.all.filter {
          search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }
      ) { exercise in
        Button {
          select(exercise)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).foregroundStyle(.primary)
            Text(exercise.muscle.title).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .searchable(text: $search, prompt: "Найти упражнение").navigationTitle("Упражнения")
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
