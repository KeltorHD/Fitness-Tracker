import FitLifeCore
import SwiftUI

struct WorkoutExerciseView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: WorkoutExercisePresentation
  @State private var error: String?
  @State private var noteRequest: SetNoteRequest?
  @State private var mediaExercise: Exercise?
  @State private var removal: DropGroupRemovalRequest?
  @State private var exerciseAction: ExerciseActionRequest?
  @State private var heartRateExpanded = false
  @State private var showingHeartRateSettings = false
  @State private var showingHealthCharts = false
  @AppStorage("exerciseHeartRateVisible") private var showsHeartRate = true
  @State private var movingForward = true
  @State private var lastCompletion: ContinuousClock.Instant?
  @State private var numberPad: WorkoutNumberPadModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  private let workoutID: UUID
  private var workout: Workout? {
    if store.active?.id == workoutID { return store.active }
    return store.workouts.first { $0.id == workoutID }
  }
  init(workout: Workout, presentation: WorkoutExercisePresentation) {
    workoutID = workout.id
    _model = State(initialValue: presentation)
    _numberPad = State(
      initialValue: WorkoutNumberPadModel(editor: presentation, locale: L10n.numberLocale))
  }
  var body: some View {
    ZStack(alignment: .top) {
      FitTheme.grouped.ignoresSafeArea()
      if let workout, let exercise = model.exercise(in: workout) {
        VStack(spacing: 16) {
          sessionHeader(workout)
          ZStack {
            exerciseCard(exercise, workout: workout)
              .id(workout.groupContaining(exerciseID: exercise.id)?.id ?? exercise.id)
              .transition(
                reduceMotion
                  ? .identity
                  : .asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(
                      with: .opacity),
                    removal: .move(edge: movingForward ? .leading : .trailing).combined(
                      with: .opacity)
                  ))
          }.clipped()
          if numberPad.field == nil {
            WorkoutExerciseDock(
              workout: workout, exerciseIndex: model.index(in: workout) ?? 0,
              navigationIndex: navigationIndex(in: workout),
              navigationCount: workout.exerciseGroups.count,
              canComplete: workout.status == .active && model.selectedSetID != nil,
              completingDrop: exercise.sets.first { $0.id == model.selectedSetID }?.isDropSet
                == true, completionTrigger: lastCompletion,
              previous: { move(-1, in: workout) }, next: { move(1, in: workout) },
              add: { addSet(in: workout) }, complete: { complete(in: workout) },
              pause: { pause(workout) })
          }
        }.padding(.horizontal, 8).padding(.bottom, 8)
      } else {
        ContentUnavailableView(
          L10n.text("Упражнение не найдено.", locale: locale), systemImage: "dumbbell"
        )
        .overlay(alignment: .bottom) {
          Button(L10n.text("Закрыть", locale: locale)) { dismiss() }.buttonStyle(.glass)
        }
      }
    }
    .navigationDestination(isPresented: $showingHeartRateSettings) {
      TrackerView(model: store.tracker).toolbar(.visible, for: .navigationBar)
    }
    .navigationDestination(isPresented: $showingHealthCharts) {
      HealthChartsView().toolbar(.visible, for: .navigationBar)
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let workout, numberPad.field != nil {
        WorkoutNumberPad(model: numberPad, workout: workout)
      }
    }
    .tint(colorTheme.accent)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workoutExerciseScreen")
    .onChange(of: workout) { _, value in
      if let value { model.refresh(value) }
      numberPad.reconcile(value)
    }
    .onChange(of: store.workouts, initial: true) { _, history in
      if let workout { model.updateHistory(history, for: workout, links: store.exerciseLinks) }
    }
    .onChange(of: store.exerciseLinks) { _, links in
      if let workout { model.updateHistory(store.workouts, for: workout, links: links) }
    }
    .onDisappear {
      numberPad.dismiss()
      store.saveExerciseInputs(model, workoutID: workoutID)
    }
    .onChange(of: numberPad.field) { _, _ in
      store.saveExerciseInputs(model, workoutID: workoutID)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { store.saveExerciseInputs(model, workoutID: workoutID) }
    }
    .onChange(of: store.tracker.recording?.workoutID) { heartRateExpanded = false }
    .onChange(of: store.tracker.deviceProfile) { heartRateExpanded = false }
    .fullScreenCover(item: $mediaExercise) { ExerciseMediaViewer(exercise: $0) }
    .sheet(item: $exerciseAction) { request in
      ExercisePicker(
        selectionHint: request.kind == .replace
          ? "При замене записанные подходы останутся у прежнего упражнения. Новое упражнение начнётся с начальных параметров."
          : nil
      ) { exercise in
        var replacementID: UUID?
        let saved = store.mutate { current in
          guard current.id == request.workoutID else { throw TrainingError.invalidState }
          switch request.kind {
          case .before:
            try WorkoutEngine.addExercise(exercise, to: &current, position: .before(request.rowID))
          case .after:
            try WorkoutEngine.addExercise(exercise, to: &current, position: .after(request.rowID))
          case .replace:
            replacementID = try WorkoutEngine.replaceExercise(
              id: request.rowID, with: exercise, in: &current)
          }
        }
        if saved, let replacementID, let current = store.active {
          model.showExercise(replacementID, in: current)
        }
      }
    }
    .sheet(item: $noteRequest) { request in
      SetNoteSheet(request: request) { text in
        guard let workout else { return false }
        return mutate(workout) {
          try WorkoutEngine.setNote(
            text, exerciseID: request.exerciseID, setID: request.id, in: &$0)
        }
      }
    }
    .confirmationDialog(
      L10n.text("Удалить группу дропсета?", locale: locale),
      isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
      titleVisibility: .visible, presenting: removal
    ) { request in
      Button(L10n.text("Удалить группу дропсета", locale: locale), role: .destructive) {
        if let workout {
          mutate(workout) {
            try WorkoutEngine.removeSet(
              exerciseID: request.exerciseID, setID: request.setID, from: &$0)
          }
        }
        removal = nil
      }
    } message: { _ in
      Text(L10n.text("Будет удалён весь подход со всеми этапами дропсета.", locale: locale))
    }
  }
  private func primaryMuscleNames(_ exercise: Exercise) -> String {
    let language = AppLanguage.system.resolved(preferredLanguages: [locale.identifier])
    let id = PersonalExercises.catalogID(for: exercise.id, links: store.exerciseLinks)
    return ExerciseLibrary.entry(for: id, language: language)
      .map { $0.primaryMuscles.joined(separator: ", ") } ?? exercise.muscle.title
  }

  private func sessionHeader(_ workout: Workout) -> some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(spacing: 4) {
          workoutClock(workout).frame(maxWidth: .infinity)
          HStack {
            headerLeading(workout)
            exerciseMenu(workout)
          }
        }
      } else {
        // Equal side slots keep the clock centered independently of the counter width.
        HStack(spacing: 0) {
          headerLeading(workout).frame(width: 52)
          workoutClock(workout).frame(maxWidth: .infinity)
          exerciseMenu(workout).frame(width: 52, alignment: .trailing)
        }
      }
    }.buttonStyle(.plain).foregroundStyle(.primary).padding(.horizontal, 4).padding(.top, 8)
  }

  private func headerLeading(_ workout: Workout) -> some View {
    Text("\(navigationIndex(in: workout) + 1)/\(workout.exerciseGroups.count)")
      .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("activeExercisePosition")
  }

  private func workoutClock(_ workout: Workout) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let duration =
        workout.durationIsKnown == false
        ? "—"
        : Duration.seconds(workout.duration(at: timeline.date)).formatted(
          .time(pattern: .hourMinuteSecond(padHourToLength: 2)))
      Text(duration).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1)
        .minimumScaleFactor(0.4)
        .accessibilityLabel(L10n.text("Длительность тренировки", locale: locale))
        .accessibilityValue(duration)
        .accessibilityIdentifier("activeExerciseDuration")
    }
  }

  private func exerciseMenu(_ workout: Workout) -> some View {
    Menu {
      if workout.status == .active {
        Button(L10n.text("Добавить перед", locale: locale), systemImage: "arrow.up.to.line") {
          openExerciseAction(.before, workout: workout)
        }
        .accessibilityIdentifier("addExerciseBeforeCurrent")
        Button(L10n.text("Добавить после", locale: locale), systemImage: "arrow.down.to.line") {
          openExerciseAction(.after, workout: workout)
        }
        .accessibilityIdentifier("addExerciseAfterCurrent")
        Button(
          L10n.text("Заменить упражнение", locale: locale),
          systemImage: "arrow.triangle.2.circlepath"
        ) { openExerciseAction(.replace, workout: workout) }
        .accessibilityIdentifier("replaceCurrentExercise")
      }
      if !store.isDemoMode, store.active?.id == workout.id {
        Button(
          L10n.text(showsHeartRate ? "Скрыть пульс" : "Показать пульс", locale: locale),
          systemImage: "heart"
        ) {
          withAnimation(reduceMotion ? nil : .smooth) {
            showsHeartRate.toggle()
            heartRateExpanded = false
          }
        }
      }
      if let exercise = model.exercise(in: workout)?.exercise {
        NavigationLink {
          ExerciseDetailView(exercise: exercise).toolbar(.visible, for: .navigationBar)
        } label: {
          Label(L10n.text("Техника выполнения", locale: locale), systemImage: "info.circle")
        }
      }
      Section { SettingsLink() }
    } label: {
      Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(.rect)
    }.accessibilityLabel(L10n.text("Действия упражнения", locale: locale))
      .accessibilityIdentifier("activeExerciseActions")
  }

  private func openExerciseAction(_ kind: ExerciseActionRequest.Kind, workout: Workout) {
    numberPad.dismiss()
    exerciseAction = ExerciseActionRequest(
      workoutID: workout.id, rowID: model.exerciseID, kind: kind)
  }

  private func exerciseHeading(_ row: WorkoutExercise, workout: Workout) -> some View {
    VStack(spacing: 8) {
      if let group = workout.groupContaining(exerciseID: row.id), group.isSuperset {
        HStack(spacing: 8) {
          Label(L10n.text("Суперсет", locale: locale), systemImage: "link")
          Spacer(minLength: 0)
          Text(
            L10n.format(
              "Круг %@ из %@",
              String(min(group.completedRounds + 1, group.roundCount)),
              String(group.roundCount), locale: locale))
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(colorTheme.accent)
        .accessibilityIdentifier("activeSupersetHeading")
      }
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.exerciseName(row.exercise, locale: locale)).font(.title2.bold())
            .foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("activeExerciseTitle")
          Text(primaryMuscleNames(row.exercise)).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !store.isDemoMode, store.active?.id == workout.id {
          Button {
            withAnimation(reduceMotion ? nil : .smooth) {
              showsHeartRate.toggle()
              heartRateExpanded = false
            }
          } label: {
            Image(systemName: showsHeartRate ? "heart.fill" : "heart.slash")
              .frame(width: 44, height: 44)
          }.buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(
              L10n.text(showsHeartRate ? "Скрыть пульс" : "Показать пульс", locale: locale)
            )
            .accessibilityIdentifier("toggleExerciseHeartRateVisibility")
        }
      }
      if showsHeartRate, !store.isDemoMode, store.active?.id == workout.id {
        WorkoutLiveHeartRateChart(
          workoutID: workout.id, isExpanded: heartRateExpanded && numberPad.field == nil,
          onToggle: {
            numberPad.dismiss()
            withAnimation(reduceMotion ? nil : .smooth) { heartRateExpanded.toggle() }
          },
          openSettings: {
            numberPad.dismiss()
            showingHeartRateSettings = true
          },
          openCharts: {
            numberPad.dismiss()
            showingHealthCharts = true
          },
          compactHeader: true, chartHeight: 100
        )
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(FitTheme.card, in: .rect(cornerRadius: 18))
        .accessibilityIdentifier("exerciseHeartRateCard")
      }
    }
  }

  private func exerciseCard(_ row: WorkoutExercise, workout: Workout) -> some View {
    VStack(spacing: 12) {
      exerciseHeading(row, workout: workout)
      setTable(row, workout: workout)
      if numberPad.field == nil { cardFooter(row, workout: workout) }
    }.padding(.horizontal, 12).padding(.vertical, FitTheme.cardPadding).background(
      FitTheme.paper, in: .rect(cornerRadius: FitTheme.exerciseCardRadius))
  }
  private func setTable(_ row: WorkoutExercise, workout: Workout) -> some View {
    let notesExpanded = workout.supersetRows(for: row.id).flatMap(\.sets).contains {
      $0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    return VStack(spacing: 0) {
      WorkoutSetTableHeader(unit: model.unit, notesExpanded: notesExpanded).padding(.top, 12)
        .padding(
          .bottom, 8)
      Divider()
      ScrollViewReader { proxy in
        List {
          Group {
            Group {
              if let group = workout.groupContaining(exerciseID: row.id), group.isSuperset {
                supersetRows(group, workout: workout, notesExpanded: notesExpanded)
              } else {
                ForEach(Array(row.sets.enumerated()), id: \.element.id) { index, set in
                  setGroup(
                    set, index: index, row: row, workout: workout, notesExpanded: notesExpanded)
                }
              }
              if let error = error ?? store.error {
                Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red)
                  .padding(
                    .top, 12)
              }
            }
          }
          .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
          .listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workoutExerciseScroll")
        .onChange(of: numberPad.field) { _, field in
          if let field {
            withAnimation(reduceMotion ? nil : .smooth) {
              proxy.scrollTo("number-\(field.setID.uuidString)", anchor: .center)
            }
          }
        }
        .onChange(of: model.selectedSetID) { previousID, setID in
          if let setID, numberPad.field == nil,
            let group = workout.groupContaining(exerciseID: row.id), group.isSuperset
          {
            let rounds = group.exercises.flatMap { member in
              member.sets.enumerated().map { (id: $0.element.id, index: $0.offset) }
            }
            let round = rounds.first { $0.id == setID }?.index
            let previousRound = rounds.first { $0.id == previousID }?.index
            let changesRound = round != previousRound
            withAnimation(reduceMotion ? nil : .smooth) {
              if changesRound, let round {
                proxy.scrollTo("superset-round-\(round)", anchor: .top)
              } else {
                proxy.scrollTo("number-\(setID.uuidString)", anchor: .center)
              }
            }
          }
        }
      }
    }
    .padding(.horizontal, 6).padding(.bottom, 6)
    .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
    .themeGlow(in: RoundedRectangle(cornerRadius: FitTheme.radius))
    .clipShape(.rect(cornerRadius: FitTheme.radius))
    .overlay {
      RoundedRectangle(cornerRadius: FitTheme.radius).stroke(FitTheme.separator, lineWidth: 0.5)
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: notesExpanded)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workoutSetTableCard")
  }

  private func setGroup(
    _ set: WorkoutSet, index: Int, row: WorkoutExercise, workout: Workout, notesExpanded: Bool
  ) -> some View {
    WorkoutSetGroupView(
      set: set, index: index, workout: workout, exerciseID: row.id, model: model,
      numberPad: numberPad,
      notesExpanded: notesExpanded,
      toggleWarmup: { toggleWarmup(set, row: row, workout: workout) },
      configureDrop: { configureDrop(workout, setID: set.id, adding: $0, exerciseID: row.id) },
      addAfter: {
        numberPad.dismiss()
        addSet(in: workout, exerciseID: row.id, after: set.id)
      },
      remove: {
        numberPad.dismiss()
        if set.isDropSet {
          removal = DropGroupRemovalRequest(exerciseID: row.id, setID: set.id)
        } else {
          mutate(workout) {
            try WorkoutEngine.removeSet(exerciseID: row.id, setID: set.id, from: &$0)
          }
        }
      },
      removeStage: { stageID in
        numberPad.dismiss()
        mutate(workout) {
          try WorkoutEngine.removeDropStage(
            in: &$0, exerciseID: row.id, setID: set.id, stageID: stageID)
        }
      },
      openNote: {
        numberPad.dismiss()
        noteRequest = SetNoteRequest(
          id: set.id, exerciseID: row.id, text: set.note ?? "",
          editable: [.active, .paused].contains(workout.status))
      })
  }

  @ViewBuilder private func supersetRows(
    _ group: WorkoutExerciseGroup, workout: Workout, notesExpanded: Bool
  ) -> some View {
    ForEach(0..<group.roundCount, id: \.self) { round in
      HStack {
        Text(L10n.format("Круг %@", String(round + 1), locale: locale))
        Spacer(minLength: 0)
        if group.exercises.allSatisfy({
          !$0.sets.indices.contains(round) || $0.sets[round].isFullyCompleted
        }) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(colorTheme.accent)
            .accessibilityLabel(L10n.text("Круг выполнен", locale: locale))
        }
      }
      .font(.subheadline.weight(.semibold)).padding(.horizontal, 10).padding(.top, 14)
      .listRowSeparator(.hidden)
      .id("superset-round-\(round)")
      .accessibilityIdentifier("supersetRound_\(round)")
      ForEach(Array(group.exercises.enumerated()), id: \.element.id) { member, row in
        if row.sets.indices.contains(round) {
          let set = row.sets[round]
          Button {
            numberPad.dismiss()
            if let target = set.stages.first(where: { $0.completedAt == nil }) {
              model.select(target.id, in: workout)
            }
          } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(String(member + 1)).monospacedDigit()
              Text(L10n.exerciseName(row.exercise, locale: locale))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
              if model.selectedSetID == set.id {
                Image(systemName: "arrow.right.circle.fill")
              }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(model.selectedSetID == set.id ? colorTheme.accent : FitTheme.muted)
            .padding(.horizontal, 10).frame(minHeight: 44).contentShape(.rect)
          }
          .buttonStyle(.plain)
          .disabled(workout.status != .active || set.isFullyCompleted)
          .listRowSeparator(.hidden)
          .accessibilityIdentifier("supersetMember_\(row.id)_\(round)")
          setGroup(
            set, index: round, row: row, workout: workout, notesExpanded: notesExpanded)
        }
      }
    }
  }

  private func cardFooter(_ row: WorkoutExercise, workout: Workout) -> some View {
    VStack(spacing: 12) {
      if let end = workout.restEndsAt, end > .now {
        ViewThatFits(in: .horizontal) {
          HStack {
            RestPill(end: end)
            skipRest(end, workout: workout)
          }
          VStack {
            RestPill(end: end)
            skipRest(end, workout: workout)
          }
        }
      }
      HStack {
        NavigationLink {
          ExerciseProgressScreen(
            exercise: row.exercise, workoutID: workout.id, showsDemoBanner: store.isDemoMode
          )
          .toolbar(.visible, for: .navigationBar)
        } label: {
          Image(systemName: "clock").font(.title2)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(L10n.text("История упражнения", locale: locale))
        .accessibilityIdentifier("openExerciseProgress")
        Spacer()
        if let entry = ExerciseLibrary.entry(
          for: PersonalExercises.catalogID(for: row.exercise.id, links: store.exerciseLinks)),
          entry.generatedMedia != nil || entry.generatedIllustration != nil || !entry.images.isEmpty
        {
          Button {
            numberPad.dismiss()
            mediaExercise = row.exercise
          } label: {
            WorkoutExerciseThumbnail(exercise: row.exercise)
              .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
          }.buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Открыть фото и анимацию упражнения", locale: locale))
            .accessibilityIdentifier("openExerciseMedia")
        }
        NavigationLink {
          ExerciseDetailView(exercise: row.exercise).toolbar(.visible, for: .navigationBar)
        } label: {
          Image(systemName: "info.circle").font(.title2)
        }.frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel(L10n.text("Техника выполнения", locale: locale))
          .accessibilityIdentifier("openExerciseTechnique")
      }.foregroundStyle(.secondary)
    }
  }
  private func skipRest(_ end: Date, workout: Workout) -> some View {
    Button(L10n.text("Пропустить отдых", locale: locale)) {
      mutate(workout) {
        _ = try WorkoutLiveAction.skipRest(expectedEnd: end).apply(
          to: &$0, expectedWorkoutID: workout.id)
      }
    }.font(.caption)
  }
  private func move(_ offset: Int, in workout: Workout) {
    numberPad.dismiss()
    error = nil
    let index = navigationIndex(in: workout)
    guard workout.exerciseGroups.indices.contains(index + offset)
    else { return }
    movingForward = offset > 0
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
      model.move(offset, in: workout)
    }
  }
  private func navigationIndex(in workout: Workout) -> Int {
    workout.exerciseGroups.firstIndex {
      $0.exercises.contains { $0.id == model.exerciseID }
    } ?? 0
  }
  @discardableResult
  private func mutate(_ workout: Workout, action: (inout Workout) throws -> Void) -> Bool {
    store.mutate { value in
      guard value.id == workout.id else { throw TrainingError.invalidState }
      try action(&value)
    }
  }
  private func addSet(in workout: Workout, exerciseID: UUID? = nil, after setID: UUID? = nil) {
    let exerciseID = exerciseID ?? model.exerciseID
    let group = workout.groupContaining(exerciseID: exerciseID)
    let rows =
      setID == nil && group?.isSuperset == true
      ? group?.exercises ?? [] : workout.exercises.filter { $0.id == exerciseID }
    let sources = Dictionary(
      uniqueKeysWithValues: rows.compactMap { row in
        (setID ?? row.sets.last?.id).map { (row.id, $0) }
      })
    let originalIDs = Set(workout.exercises.flatMap(\.sets).map(\.id))
    let saved = mutate(workout) { current in
      let inputs = model.pendingValues(in: current)
      if !inputs.isEmpty { try WorkoutEngine.updatePendingValues(inputs, in: &current) }
      if setID == nil, let group = current.groupContaining(exerciseID: exerciseID),
        group.isSuperset,
        let supersetID = group.supersetID
      {
        try WorkoutEngine.addSupersetRound(supersetID: supersetID, to: &current)
      } else {
        try WorkoutEngine.addSet(exerciseID: exerciseID, to: &current, after: setID)
      }
    }
    guard saved, let current = store.active, current.id == workout.id else { return }
    for row in current.exercises {
      guard let sourceID = sources[row.id] else { continue }
      for set in row.sets where !originalIDs.contains(set.id) {
        model.inheritInput(from: sourceID, for: set.id, in: current)
      }
    }
  }
  private func toggleWarmup(_ set: WorkoutSet, row: WorkoutExercise, workout: Workout) {
    numberPad.dismiss()
    mutate(workout) {
      try WorkoutEngine.setWarmup(!set.isWarmup, in: &$0, exerciseID: row.id, setID: set.id)
    }
  }
  private func pause(_ workout: Workout) {
    numberPad.dismiss()
    mutate(workout) {
      if $0.status == .paused {
        try WorkoutEngine.resume(&$0)
      } else {
        try WorkoutEngine.pause(&$0)
      }
    }
  }
  private func complete(in workout: Workout) {
    let instant = ContinuousClock().now
    if let lastCompletion, lastCompletion.duration(to: instant) < .milliseconds(500) { return }
    numberPad.dismiss()
    do {
      let request = try model.completion(in: workout)
      error = nil
      let saved = store.mutate {
        guard $0.id == workout.id else { throw TrainingError.invalidState }
        if let stageID = request.stageID,
          let stage = request.set.dropStages?.first(where: { $0.id == stageID })
        {
          try WorkoutEngine.completeDropStage(
            in: &$0, exerciseID: request.exerciseID, setID: request.set.id,
            stageID: stageID, repetitions: stage.repetitions, weightKG: stage.weightKG,
            dropStages: request.set.dropStages)
        } else {
          if request.set.isDropSet {
            try WorkoutEngine.configureDropSet(
              in: &$0, exerciseID: request.exerciseID, setID: request.set.id,
              repetitions: request.set.repetitions, weightKG: request.set.weightKG,
              stages: request.set.dropStages ?? [])
          }
          try WorkoutEngine.completeSet(
            in: &$0, exerciseID: request.exerciseID, setID: request.set.id,
            repetitions: request.set.repetitions, weightKG: request.set.weightKG)
        }
      }
      if saved {
        lastCompletion = ContinuousClock().now
        guard let updated = store.active, updated.id == workout.id else { return }
        let previousIndex = model.index(in: updated) ?? 0
        let advance = withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
          let result = model.advance(afterSaving: request, in: updated)
          if case .moved = result {
            movingForward = (model.index(in: updated) ?? previousIndex) > previousIndex
          }
          return result
        }
        if case .finished = advance { dismiss() }
      }
    } catch { self.error = error.localizedDescription }
  }
  private func configureDrop(
    _ workout: Workout, setID: UUID, adding: Bool, exerciseID: UUID? = nil
  ) {
    numberPad.dismiss()
    do {
      if let exerciseID { model.showExercise(exerciseID, in: workout) }
      let set = try model.configuredDropSet(in: workout, adding: adding, setID: setID)
      error = nil
      mutate(workout) {
        try WorkoutEngine.configureDropSet(
          in: &$0, exerciseID: model.exerciseID, setID: set.id,
          repetitions: set.repetitions, weightKG: set.weightKG, stages: set.dropStages ?? [])
      }
    } catch { self.error = error.localizedDescription }
  }

}

struct WorkoutExerciseSheet: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(AppStore.self) private var store
  let workout: Workout
  let exerciseID: UUID
  let unit: WeightUnit
  @State private var presentation: WorkoutExercisePresentation?

  var body: some View {
    NavigationStack {
      if let presentation {
        WorkoutExerciseView(workout: workout, presentation: presentation)
      } else {
        ProgressView()
      }
    }
    .task {
      guard presentation == nil else { return }
      let current = store.workouts.first { $0.id == workout.id } ?? workout
      presentation = WorkoutExercisePresentation(
        workout: current, exerciseID: exerciseID, unit: unit, locale: L10n.numberLocale,
        history: store.workouts, draftStore: store.exerciseDrafts(for: current, unit: unit),
        links: store.exerciseLinks)
    }
    .tint(colorTheme.accent)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
  }
}

private struct SetNoteRequest: Identifiable {
  let id: UUID
  let exerciseID: UUID
  let text: String
  let editable: Bool
}

private struct SetNoteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  let request: SetNoteRequest
  let save: (String) -> Bool
  @State private var text: String
  @State private var failed = false

  init(request: SetNoteRequest, save: @escaping (String) -> Bool) {
    self.request = request
    self.save = save
    _text = State(initialValue: request.text)
  }

  var body: some View {
    NavigationStack {
      Form {
        if request.editable {
          TextEditor(text: $text).frame(minHeight: 180)
            .accessibilityLabel(L10n.text("Заметка к подходу", locale: locale))
            .accessibilityIdentifier("setNoteEditor")
          Text("\(text.count) / 2000").font(.caption).foregroundStyle(
            text.count > 2000 ? .red : .secondary)
        } else {
          Text(text.isEmpty ? L10n.text("Нет заметки", locale: locale) : text)
            .textSelection(.enabled)
        }
        if failed {
          Text(L10n.text("Не удалось сохранить заметку. Попробуйте ещё раз.", locale: locale))
            .foregroundStyle(.red)
        }
      }
      .navigationTitle(L10n.text("Заметка к подходу", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale)) { dismiss() }
        }
        if request.editable {
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Сохранить", locale: locale)) {
              if save(text) { dismiss() } else { failed = true }
            }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count > 2000)
              .accessibilityIdentifier("saveSetNote")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

private struct DropGroupRemovalRequest {
  let exerciseID: UUID
  let setID: UUID
}

private struct ExerciseActionRequest: Identifiable {
  enum Kind { case before, after, replace }
  let id = UUID()
  let workoutID: UUID
  let rowID: UUID
  let kind: Kind
}
