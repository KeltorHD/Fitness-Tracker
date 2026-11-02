import FitnessTrackerCore
import SwiftUI

struct ActiveWorkoutView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  // Keep the saved preference: previously hidden cards now open in compact form.
  @AppStorage("showWorkoutHeartRate") private var heartRateExpanded = true
  @State private var insertion: InsertionRequest?
  @State private var pendingRemoval: RemovalRequest?
  @State private var selectedExercise: WorkoutExercise?
  @State private var confirmCancel = false
  @State private var renaming = false
  @State private var workoutName = ""
  private struct InsertionRequest: Identifiable {
    let id = UUID()
    let workoutID: UUID
    let position: WorkoutExerciseInsertion
  }

  private struct RemovalRequest {
    let workoutID: UUID
    let row: WorkoutExercise
  }

  var body: some View {
    NavigationStack {
      if let workout = store.active {
        overview(workout)
          .navigationTitle("").navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) { SessionControls(workout: workout) }
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button(L10n.text("Свернуть", locale: locale), systemImage: "chevron.down") {
                dismiss()
              }.labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .principal) {
              VStack(spacing: 1) {
                HStack(spacing: 6) {
                  Image(systemName: "dumbbell.fill").accessibilityHidden(true)
                  Text(workout.name)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    .accessibilityIdentifier("activeWorkoutTitle")
                }
                .font(.headline)
                Text(workout.startedAt, format: .dateTime.weekday(.wide).hour().minute())
                  .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
              }
              .foregroundStyle(.primary)
              .accessibilityElement(children: .combine)
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("activeWorkoutHeader")
            }
            ToolbarItem(placement: .topBarTrailing) {
              Menu {
                Button(L10n.text("Изменить название", locale: locale), systemImage: "textformat") {
                  workoutName = workout.name
                  renaming = true
                }
                Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
                  insertion = InsertionRequest(workoutID: workout.id, position: .end)
                }.disabled(workout.status != .active)
                if !store.isDemoMode {
                  Button(
                    L10n.text(
                      heartRateExpanded ? "Свернуть карточку пульса" : "Развернуть карточку пульса",
                      locale: locale),
                    systemImage: heartRateExpanded ? "chevron.up" : "chevron.down"
                  ) { heartRateExpanded.toggle() }
                  .accessibilityIdentifier("toggleWorkoutHeartRate")
                }
                Button(
                  L10n.text("Отменить тренировку", locale: locale), systemImage: "trash",
                  role: .destructive
                ) { confirmCancel = true }
              } label: {
                Image(systemName: "ellipsis").foregroundStyle(.primary)
              }
              .accessibilityLabel(L10n.text("Действия тренировки", locale: locale))
            }
          }
          .alert(L10n.text("Название тренировки", locale: locale), isPresented: $renaming) {
            TextField(L10n.text("Название", locale: locale), text: $workoutName)
            Button(L10n.text("Сохранить", locale: locale)) {
              store.mutate { $0.name = workoutName }
            }
            Button(L10n.text("Отмена", locale: locale), role: .cancel) {}
          }
          .sheet(item: $insertion) { request in
            ExercisePicker { exercise in
              store.mutate { current in
                guard current.id == request.workoutID else { throw TrainingError.invalidState }
                try WorkoutEngine.addExercise(exercise, to: &current, position: request.position)
              }
            }
          }
          .sheet(item: $selectedExercise) { row in
            WorkoutExerciseSheet(workout: workout, exerciseID: row.id, unit: unit)
          }
          .confirmationDialog(
            L10n.text("Удалить упражнение из тренировки?", locale: locale),
            isPresented: Binding(
              get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible, presenting: pendingRemoval
          ) { request in
            Button(L10n.text("Удалить упражнение", locale: locale), role: .destructive) {
              pendingRemoval = nil
              store.mutate { current in
                guard current.id == request.workoutID else { throw TrainingError.invalidState }
                try WorkoutEngine.removeExercise(id: request.row.id, from: &current)
              }
            }.accessibilityIdentifier("confirmRemoveWorkoutExercise")
            Button(L10n.text("Отмена", locale: locale), role: .cancel) { pendingRemoval = nil }
          } message: { request in
            Text(
              L10n.exerciseName(request.row.exercise, locale: locale) + "\n"
                + L10n.text(
                  request.row.sets.contains { !$0.performedStages.isEmpty }
                    ? "Записанные подходы этого упражнения тоже будут удалены."
                    : "Будет удалено только это упражнение из текущей тренировки.",
                  locale: locale))
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
    .archiveTransferPresenter(
      when: selectedExercise == nil && insertion == nil && !renaming && !confirmCancel
        && pendingRemoval == nil && !store.showingBodyWeightEditor
    )
    .onChange(of: store.active?.id) { _, id in
      if insertion?.workoutID != id { insertion = nil }
      if pendingRemoval?.workoutID != id { pendingRemoval = nil }
    }
    .alert(
      L10n.text("Ошибка", locale: locale),
      isPresented: Binding(
        get: {
          store.error != nil && selectedExercise == nil && insertion == nil && !renaming
            && !confirmCancel
            && pendingRemoval == nil && !store.archiveTransfer.isPresented
            && !store.showingBodyWeightEditor
        },
        set: { if !$0 { store.error = nil } })
    ) {
      Button(L10n.text("Понятно", locale: locale), role: .cancel) { store.error = nil }
    } message: {
      Text(L10n.text(store.error ?? "", locale: locale))
    }
  }
  private func overview(_ workout: Workout) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        VStack(spacing: 0) {
          WorkoutSessionSummary(workout: workout, unit: unit).padding(.vertical, 16)
          if !store.isDemoMode {
            WorkoutLiveHeartRateChart(
              workoutID: workout.id, isExpanded: heartRateExpanded,
              onToggle: { heartRateExpanded.toggle() }
            )
            .padding(.horizontal, FitTheme.cardPadding)
            .padding(.vertical, heartRateExpanded ? FitTheme.cardPadding : 4)
            .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
            .padding(.bottom, 16)
            .accessibilityIdentifier("workoutHeartRateCard")
          }
          if let end = workout.restEndsAt, end > .now {
            HStack {
              RestPill(end: end)
              Button(L10n.text("Пропустить отдых", locale: locale)) {
                store.mutate {
                  _ = try WorkoutLiveAction.skipRest(expectedEnd: end).apply(
                    to: &$0, expectedWorkoutID: workout.id)
                }
              }
            }.padding(.bottom, 12)
          }
          if workout.status == .paused {
            Label(L10n.text("Тренировка на паузе", locale: locale), systemImage: "pause.circle")
              .font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 12)
          }
          if workout.exercises.isEmpty {
            ContentUnavailableView(
              L10n.text("Добавьте первое упражнение", locale: locale), systemImage: "dumbbell",
              description: Text(
                L10n.text("Откройте упражнение из списка, чтобы записать подходы.", locale: locale))
            )
          }
          ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, row in
            Button {
              selectedExercise = row
            } label: {
              WorkoutExerciseListRow(row: row, index: index, unit: unit, completedOnly: false)
            }.buttonStyle(.plain).accessibilityIdentifier("openWorkoutExercise")
              .contextMenu {
                Button(L10n.text("Добавить перед", locale: locale), systemImage: "arrow.up.to.line")
                {
                  insertion = InsertionRequest(workoutID: workout.id, position: .before(row.id))
                }
                .disabled(workout.status != .active)
                .accessibilityIdentifier("insertWorkoutExerciseBefore")
                Button(
                  L10n.text("Добавить после", locale: locale), systemImage: "arrow.down.to.line"
                ) {
                  insertion = InsertionRequest(workoutID: workout.id, position: .after(row.id))
                }
                .disabled(workout.status != .active)
                .accessibilityIdentifier("insertWorkoutExerciseAfter")
                Divider()
                Button(
                  L10n.text("Удалить упражнение", locale: locale), systemImage: "trash",
                  role: .destructive
                ) {
                  pendingRemoval = RemovalRequest(workoutID: workout.id, row: row)
                }
                .disabled(workout.status != .active)
                .accessibilityIdentifier("removeWorkoutExercise")
              }
            Divider().padding(.leading, 34)
          }
          Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus.circle") {
            insertion = InsertionRequest(workoutID: workout.id, position: .end)
          }
          .disabled(workout.status != .active).accessibilityIdentifier("addExercise")
          .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
          VStack(spacing: 16) {
            WorkoutBodyWeightRow(workout: workout).fitCard()
            TextField(
              L10n.text("Заметка о тренировке", locale: locale),
              text: Binding(
                get: { store.active?.notes ?? "" },
                set: { text in store.mutate { $0.notes = text } }), axis: .vertical
            )
            .padding().background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
            Button(L10n.text("Отменить тренировку", locale: locale), role: .destructive) {
              confirmCancel = true
            }
          }
        }.padding(.horizontal, 16).padding(.bottom, 20)
      }
    }.background(FitTheme.paper).scrollDismissesKeyboard(.interactively)
      .accessibilityIdentifier("activeWorkoutScroll")
  }
}

struct ExercisePicker: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var custom = false
  var initialGroups: Set<MuscleGroup> = []
  var initialMuscles: Set<ExerciseMuscle> = []
  let select: (Exercise) -> Void
  var body: some View {
    NavigationStack {
      ExerciseLibraryView(initialGroups: initialGroups, initialMuscles: initialMuscles) {
        exercise in
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
          .accessibilityIdentifier("customExerciseName")
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
            .accessibilityIdentifier("saveCustomExercise")
          }
        }
    }
  }
}
