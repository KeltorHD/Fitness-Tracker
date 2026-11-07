import FitnessTrackerCore
import SwiftUI

struct ActiveWorkoutView: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var heartRateExpanded = false
  @State private var showingHeartRateSettings = false
  @State private var showingHealthCharts = false
  @AppStorage("workoutHeartRateVisible") private var showsHeartRate = true
  @State private var insertion: InsertionRequest?
  @State private var replacement: ReplacementRequest?
  @State private var supersetRequest: WorkoutSupersetRequest?
  @State private var templateAddition: TemplateAdditionRequest?
  @State private var pendingRemoval: RemovalRequest?
  @State private var reorderRevision = 0
  @State private var selectedExercise: WorkoutExercise?
  @State private var mediaExercise: Exercise?
  @State private var editingBodyWeight = false
  @State private var confirmCancel = false
  @State private var renaming = false
  @State private var workoutName = ""
  private struct InsertionRequest: Identifiable {
    let id = UUID()
    let workoutID: UUID
    let position: WorkoutExerciseInsertion
  }

  private struct TemplateAdditionRequest: Identifiable {
    let id: UUID
  }

  private struct ReplacementRequest: Identifiable {
    let id = UUID()
    let workoutID: UUID
    let rowID: UUID
  }

  private struct RemovalRequest {
    let workoutID: UUID
    let row: WorkoutExercise
  }

  var body: some View {
    NavigationStack {
      if let workout = store.active {
        overview(workout)
          .navigationDestination(isPresented: $showingHeartRateSettings) {
            TrackerView(model: store.tracker).toolbar(.visible, for: .navigationBar)
          }
          .navigationDestination(isPresented: $showingHealthCharts) {
            HealthChartsView().toolbar(.visible, for: .navigationBar)
          }
          .navigationTitle("").navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionControls(
              workout: workout, cancel: { confirmCancel = true },
              addTemplates: { templateAddition = TemplateAdditionRequest(id: workout.id) },
              addExercise: {
                insertion = InsertionRequest(workoutID: workout.id, position: .end)
              }
            )
            .padding(.bottom, 8)
          }
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button(L10n.text("Свернуть", locale: locale), systemImage: "chevron.down") {
                dismiss()
              }.labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .principal) {
              VStack(spacing: 1) {
                Text(workout.name)
                  .font(.headline).lineLimit(1).truncationMode(.tail)
                  .accessibilityIdentifier("activeWorkoutTitle")
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                  let duration =
                    workout.durationIsKnown == false
                    ? "—"
                    : Duration.seconds(workout.duration(at: timeline.date))
                      .formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
                  Text(duration)
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel(L10n.text("Длительность тренировки", locale: locale))
                    .accessibilityValue(duration)
                    .accessibilityIdentifier("activeWorkoutDuration")
                }
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
                Button(L10n.text("Объединить в суперсет", locale: locale), systemImage: "link") {
                  supersetRequest = WorkoutSupersetRequest(workoutID: workout.id)
                }
                .disabled(workout.status != .active || workout.exercises.count < 2)
                .accessibilityIdentifier("groupWorkoutExercises")
                if !store.isDemoMode {
                  Button(
                    L10n.text(
                      showsHeartRate ? "Скрыть пульс" : "Показать пульс",
                      locale: locale),
                    systemImage: showsHeartRate ? "heart.slash" : "heart"
                  ) {
                    showsHeartRate.toggle()
                    heartRateExpanded = false
                  }
                  .accessibilityIdentifier("toggleWorkoutHeartRate")
                }
                Button(
                  L10n.text("Отменить тренировку", locale: locale), systemImage: "trash",
                  role: .destructive
                ) { confirmCancel = true }
                .accessibilityIdentifier("cancelWorkoutMenu")
                Section { SettingsLink() }
              } label: {
                Image(systemName: "ellipsis").foregroundStyle(.primary)
              }
              .accessibilityLabel(L10n.text("Действия тренировки", locale: locale))
              .accessibilityIdentifier("activeWorkoutActions")
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
          .sheet(item: $templateAddition) { request in
            WorkoutStartView(addingToWorkout: true) { selection in
              guard case .templates(let templates) = selection else { return }
              let saved = store.mutate { current in
                guard current.id == request.id else { throw TrainingError.invalidState }
                try WorkoutEngine.addTemplates(templates, to: &current, prefillTargets: false)
              }
              if saved { templateAddition = nil }
            }
          }
          .sheet(item: $replacement) { request in
            ExercisePicker(
              selectionHint:
                "При замене записанные подходы останутся у прежнего упражнения. Новое упражнение начнётся с начальных параметров."
            ) { exercise in
              store.mutate { current in
                guard current.id == request.workoutID else { throw TrainingError.invalidState }
                try WorkoutEngine.replaceExercise(id: request.rowID, with: exercise, in: &current)
              }
            }
          }
          .sheet(item: $selectedExercise) { row in
            WorkoutExerciseSheet(workout: workout, exerciseID: row.id, unit: unit)
          }
          .sheet(item: $supersetRequest) { request in
            WorkoutSupersetEditor(workout: workout, initialRowID: request.initialRowID) { ids in
              let saved = store.mutate { current in
                guard current.id == request.workoutID else { throw TrainingError.invalidState }
                _ = try WorkoutEngine.groupExercises(ids, in: &current)
              }
              return saved
                ? nil
                : store.error ?? "Не удалось сохранить изменения тренировки. Попробуйте ещё раз."
            }
          }
          .sheet(isPresented: $editingBodyWeight) {
            BodyWeightEditor(
              workout: workout, initialWeightKG: store.currentBodyWeightKG, unit: unit)
          }
          .fullScreenCover(item: $mediaExercise) { ExerciseMediaViewer(exercise: $0) }
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
            }.accessibilityIdentifier("confirmCancelWorkout")
            Button(L10n.text("Отмена", locale: locale), role: .cancel) {
              confirmCancel = false
            }.accessibilityIdentifier("dismissCancelWorkout")
          }
      } else {
        ContentUnavailableView(
          L10n.text("Нет активной тренировки", locale: locale), systemImage: "dumbbell")
      }
    }
    .archiveTransferPresenter(
      when: selectedExercise == nil && mediaExercise == nil && !editingBodyWeight
        && insertion == nil && replacement == nil && supersetRequest == nil
        && templateAddition == nil && !renaming
        && !confirmCancel
        && pendingRemoval == nil && !store.showingBodyWeightEditor
    )
    .onChange(of: store.tracker.recording?.workoutID) { heartRateExpanded = false }
    .onChange(of: store.tracker.deviceProfile) { heartRateExpanded = false }
    .onChange(of: store.active?.id) { _, id in
      if insertion?.workoutID != id { insertion = nil }
      if replacement?.workoutID != id { replacement = nil }
      if supersetRequest?.workoutID != id { supersetRequest = nil }
      if templateAddition?.id != id { templateAddition = nil }
      if pendingRemoval?.workoutID != id { pendingRemoval = nil }
    }
    .alert(
      L10n.text("Ошибка", locale: locale),
      isPresented: Binding(
        get: {
          store.error != nil && selectedExercise == nil && mediaExercise == nil
            && !editingBodyWeight && insertion == nil && replacement == nil
            && supersetRequest == nil
            && templateAddition == nil && !renaming
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
    List {
      Section {
        WorkoutSessionSummary(
          workout: workout, unit: unit, showsDuration: false,
          bodyWeightKG: workout.bodyWeightKG ?? store.currentBodyWeightKG,
          editBodyWeight: { editingBodyWeight = true }
        ).padding(.vertical, 16)
        if showsHeartRate, !store.isDemoMode {
          WorkoutLiveHeartRateChart(
            workoutID: workout.id, isExpanded: heartRateExpanded,
            onToggle: { heartRateExpanded.toggle() },
            openSettings: { showingHeartRateSettings = true },
            openCharts: { showingHealthCharts = true }
          )
          .padding(.horizontal, FitTheme.cardPadding)
          .padding(.vertical, 4)
          .padding(.bottom, heartRateExpanded ? FitTheme.cardPadding - 4 : 0)
          .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
          .themeGlow(in: RoundedRectangle(cornerRadius: FitTheme.radius))
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
      }
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      .listRowBackground(FitTheme.paper)
      Section {
        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, row in
          exerciseRow(row, index: index, workout: workout)
        }
        .onMove { source, destination in
          var reordered = workout.exercises
          reordered.move(fromOffsets: source, toOffset: destination)
          let groups = workout.exerciseGroups
          var visited: Set<UUID> = []
          let groupedOrder = reordered.flatMap { row -> [WorkoutExercise] in
            guard let group = groups.first(where: { $0.exercises.contains { $0.id == row.id } }),
              visited.insert(group.id).inserted
            else { return [] }
            return group.exercises
          }
          let saved = store.mutate { current in
            guard current.id == workout.id else { throw TrainingError.invalidState }
            try WorkoutEngine.reorderExercises(groupedOrder.map(\.id), in: &current)
          }
          // Reset the native drag order whenever it tried to split a superset or saving failed.
          if !saved || reordered.map(\.id) != groupedOrder.map(\.id) { reorderRevision += 1 }
        }
      }
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      .listRowBackground(FitTheme.paper)
      Section {
        VStack(spacing: 16) {
          TextField(
            L10n.text("Заметка о тренировке", locale: locale),
            text: Binding(
              get: { store.active?.notes ?? "" },
              set: { text in store.mutate { $0.notes = text } }), axis: .vertical
          )
          .padding().background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
        }
        .padding(.top, 12)
      }
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      .listRowBackground(FitTheme.paper)
    }
    .id(reorderRevision)
    .listStyle(.plain).scrollContentBackground(.hidden)
    .listSectionSpacing(0)
    .background(FitTheme.paper).scrollDismissesKeyboard(.interactively)
    .accessibilityIdentifier("activeWorkoutScroll")
  }
  private func exerciseRow(_ row: WorkoutExercise, index: Int, workout: Workout) -> some View {
    VStack(spacing: 0) {
      if let group = workout.groupContaining(exerciseID: row.id), group.isSuperset,
        group.exercises.first?.id == row.id
      {
        supersetHeading(group, workout: workout)
      }
      HStack(alignment: .top, spacing: 14) {
        Button {
          selectedExercise = row
        } label: {
          WorkoutExerciseListRow(
            row: row, index: index, unit: unit, completedOnly: false, showsThumbnail: false)
        }
        .buttonStyle(.plain).accessibilityIdentifier("openWorkoutExercise")
        if let entry = ExerciseLibrary.entry(for: row.exercise.id),
          entry.generatedMedia != nil || !entry.images.isEmpty
        {
          Button {
            mediaExercise = row.exercise
          } label: {
            WorkoutExerciseThumbnail(exercise: row.exercise)
              .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
          }
          .buttonStyle(.plain).padding(.vertical, 16)
          .accessibilityLabel(L10n.text("Открыть фото и анимацию упражнения", locale: locale))
          .accessibilityValue(L10n.exerciseName(row.exercise, locale: locale))
          .accessibilityIdentifier("openWorkoutExerciseMedia")
        }
      }
    }
    .padding(.horizontal, row.supersetID == nil ? 0 : 12)
    .padding(.bottom, isLastSupersetRow(row, in: workout) ? 12 : 0)
    .listRowBackground(exerciseBackground(row, workout: workout))
    .moveDisabled(
      workout.status != .active
        || (row.supersetID != nil
          && workout.groupContaining(exerciseID: row.id)?.exercises.first?.id != row.id)
    )
    .contextMenu {
      if workout.status == .active {
        Button(L10n.text("Объединить в суперсет", locale: locale), systemImage: "link") {
          supersetRequest = WorkoutSupersetRequest(
            workoutID: workout.id, initialRowID: row.id)
        }.disabled(workout.exercises.count < 2)
          .accessibilityIdentifier("groupWorkoutExercise")
        if let supersetID = row.supersetID {
          Button(L10n.text("Разъединить суперсет", locale: locale), systemImage: "link") {
            ungroup(supersetID, workout: workout)
          }.accessibilityIdentifier("ungroupWorkoutExercises")
        }
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if workout.status == .active {
        Button(L10n.text("Добавить перед", locale: locale), systemImage: "arrow.up.to.line") {
          insertion = InsertionRequest(workoutID: workout.id, position: .before(row.id))
        }.tint(colorTheme.accent).accessibilityIdentifier("insertWorkoutExerciseBefore")
        Button(L10n.text("Добавить после", locale: locale), systemImage: "arrow.down.to.line") {
          insertion = InsertionRequest(workoutID: workout.id, position: .after(row.id))
        }.tint(.secondary).accessibilityIdentifier("insertWorkoutExerciseAfter")
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if workout.status == .active {
        Button(
          L10n.text("Удалить упражнение", locale: locale), systemImage: "trash"
        ) {
          pendingRemoval = RemovalRequest(workoutID: workout.id, row: row)
        }.tint(.red).accessibilityIdentifier("removeWorkoutExercise")
        Button(
          L10n.text("Заменить упражнение", locale: locale),
          systemImage: "arrow.triangle.2.circlepath"
        ) {
          replacement = ReplacementRequest(workoutID: workout.id, rowID: row.id)
        }.tint(colorTheme.accent).accessibilityIdentifier("replaceWorkoutExercise")
      }
    }
  }

  private func supersetHeading(_ group: WorkoutExerciseGroup, workout: Workout) -> some View {
    HStack(spacing: 8) {
      Button {
        selectedExercise = group.exercises.first
      } label: {
        HStack(spacing: 8) {
          Label(L10n.text("Суперсет", locale: locale), systemImage: "link")
            .font(.headline)
          Text("\(group.completedRounds)/\(group.roundCount)")
            .font(.subheadline).monospacedDigit()
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.text("Открыть суперсет", locale: locale))
      .accessibilityValue(
        L10n.format(
          "%@ из %@", String(group.completedRounds), String(group.roundCount), locale: locale)
      )
      .accessibilityIdentifier("openWorkoutSuperset_\(group.id)")
      if workout.status == .active, let supersetID = group.supersetID {
        Menu {
          Button(L10n.text("Добавить в суперсет", locale: locale), systemImage: "plus") {
            supersetRequest = WorkoutSupersetRequest(
              workoutID: workout.id, initialRowID: group.exercises.first?.id)
          }
          Button(L10n.text("Разъединить суперсет", locale: locale), systemImage: "link") {
            ungroup(supersetID, workout: workout)
          }.accessibilityIdentifier("ungroupWorkoutExercises")
        } label: {
          Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel(L10n.text("Действия суперсета", locale: locale))
        .accessibilityIdentifier("workoutSupersetActions_\(group.id)")
      }
    }
    .foregroundStyle(colorTheme.accent).padding(.top, 8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workoutSuperset_\(group.id)")
  }

  private func ungroup(_ supersetID: UUID, workout: Workout) {
    store.mutate { current in
      guard current.id == workout.id else { throw TrainingError.invalidState }
      try WorkoutEngine.ungroupExercises(supersetID: supersetID, in: &current)
    }
  }

  private func isLastSupersetRow(_ row: WorkoutExercise, in workout: Workout) -> Bool {
    guard row.supersetID != nil else { return false }
    return workout.groupContaining(exerciseID: row.id)?.exercises.last?.id == row.id
  }

  @ViewBuilder private func exerciseBackground(_ row: WorkoutExercise, workout: Workout)
    -> some View
  {
    if let group = workout.groupContaining(exerciseID: row.id), group.isSuperset {
      let top = group.exercises.first?.id == row.id
      let bottom = group.exercises.last?.id == row.id
      UnevenRoundedRectangle(
        topLeadingRadius: top ? FitTheme.radius : 0,
        bottomLeadingRadius: bottom ? FitTheme.radius : 0,
        bottomTrailingRadius: bottom ? FitTheme.radius : 0,
        topTrailingRadius: top ? FitTheme.radius : 0
      ).fill(FitTheme.card).padding(.horizontal, 16)
    } else {
      FitTheme.paper
    }
  }

}

struct ExercisePicker: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var custom = false
  var selectionHint: String? = nil
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
      .safeAreaInset(edge: .top, spacing: 0) {
        if let selectionHint {
          Text(L10n.text(selectionHint, locale: locale)).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(FitTheme.paper)
        }
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
