import FitnessTrackerCore
import SwiftUI

struct WorkoutExerciseView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var model: WorkoutExercisePresentation
  @State private var error: String?
  @State private var lastCompletion: ContinuousClock.Instant?
  @FocusState private var focus: WorkoutSetField?
  private let workoutID: UUID
  private var workout: Workout? {
    if store.active?.id == workoutID { return store.active }
    return store.workouts.first { $0.id == workoutID }
  }
  init(workout: Workout, exerciseID: UUID, unit: WeightUnit) {
    workoutID = workout.id
    _model = State(
      initialValue: WorkoutExercisePresentation(
        workout: workout, exerciseID: exerciseID, unit: unit, locale: L10n.numberLocale))
  }
  var body: some View {
    ZStack(alignment: .top) {
      FitTheme.grouped.ignoresSafeArea()
      FitTheme.header.frame(height: 230).ignoresSafeArea(edges: .top)
      if let workout, let exercise = model.exercise(in: workout) {
        VStack(spacing: 16) {
          sessionHeader(workout)
          exerciseCard(exercise, workout: workout)
          WorkoutExerciseDock(
            workout: workout, exerciseIndex: model.index(in: workout) ?? 0,
            canComplete: workout.status == .active && model.selectedSetID != nil,
            previous: { move(-1, in: workout) }, next: { move(1, in: workout) },
            add: { addSet(in: workout) }, complete: { complete(in: workout) },
            pause: { pause(workout) }, close: { dismiss() })
          if [.active, .paused].contains(workout.status) {
            Button(
              L10n.text("Завершить тренировку", locale: locale), systemImage: "checkmark.circle"
            ) { finish(workout) }
            .buttonStyle(.glass).disabled(workout.completedSets == 0).accessibilityIdentifier(
              "finishWorkout")
          }
        }.padding(.horizontal, 12).padding(.bottom, 8)
      } else {
        ContentUnavailableView(
          L10n.text("Упражнение не найдено.", locale: locale), systemImage: "dumbbell"
        )
        .overlay(alignment: .bottom) {
          Button(L10n.text("Закрыть", locale: locale)) { dismiss() }.buttonStyle(.glass)
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("Готово", locale: locale)) { focus = nil }
      }
    }
    .tint(FitTheme.accent).accessibilityIdentifier("workoutExerciseScreen")
    .onChange(of: workout) { _, value in if let value { model.refresh(value) } }
    .onChange(of: focus) { _, value in
      if let value, let workout { model.select(value.setID, in: workout) }
    }
  }
  private func sessionHeader(_ workout: Workout) -> some View {
    HStack {
      Text("\((model.index(in: workout) ?? 0) + 1)/\(workout.exercises.count)")
        .font(.body).foregroundStyle(.white.opacity(0.8))
      Spacer()
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        Text(
          workout.durationIsKnown == false
            ? "—"
            : Duration.seconds(workout.duration(at: timeline.date)).formatted(
              .time(pattern: .hourMinuteSecond))
        )
        .font(.largeTitle).monospacedDigit().foregroundStyle(.white).lineLimit(1)
        .minimumScaleFactor(0.6)
      }
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.down").foregroundStyle(.white)
      }
      .frame(minWidth: 44, minHeight: 44).accessibilityLabel(
        L10n.text("К списку упражнений", locale: locale)
      )
      .accessibilityIdentifier("closeWorkoutExercise")
    }.padding(.horizontal, 8).padding(.top, 8)
  }
  private func exerciseCard(_ row: WorkoutExercise, workout: Workout) -> some View {
    VStack(spacing: 16) {
      ScrollView {
        VStack(spacing: 16) {
          HStack(alignment: .top) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "chevron.down").font(.title3.weight(.semibold))
            }
            .frame(minWidth: 44, minHeight: 44).accessibilityLabel(
              L10n.text("К списку упражнений", locale: locale))
            Spacer()
            Menu {
              NavigationLink {
                ExerciseDetailView(exercise: row.exercise).toolbar(.visible, for: .navigationBar)
              } label: {
                Label(L10n.text("Техника выполнения", locale: locale), systemImage: "info.circle")
              }
              if let set = row.sets.first(where: { $0.id == model.selectedSetID }),
                workout.status == .active
              {
                Button(
                  L10n.text(set.isWarmup ? "Рабочий подход" : "Разминочный подход", locale: locale)
                ) { toggleWarmup(set, row: row, workout: workout) }
              }
            } label: {
              Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(
                width: 44, height: 44)
            }
            .accessibilityLabel(L10n.text("Действия упражнения", locale: locale))
          }.foregroundStyle(.secondary)
          VStack(spacing: 10) {
            Text(L10n.exerciseName(row.exercise, locale: locale)).font(.title2.bold())
              .foregroundStyle(
                FitTheme.accent)
            Text(row.exercise.muscle.title).font(.subheadline).foregroundStyle(.secondary).textCase(
              .uppercase)
          }.multilineTextAlignment(.center).padding(.horizontal, 12)
          LazyVStack(spacing: 0) {
            ForEach(Array(row.sets.enumerated()), id: \.element.id) { index, set in
              WorkoutSetRow(
                set: set, index: index, unit: model.unit,
                editable: workout.status == .active && set.completedAt == nil,
                selected: set.id == model.selectedSetID && workout.status == .active,
                weight: Binding(
                  get: { model.drafts[set.id]?.weight ?? "" },
                  set: { model.editWeight($0, setID: set.id) }),
                repetitions: Binding(
                  get: { model.drafts[set.id]?.repetitions ?? "" },
                  set: { model.editRepetitions($0, setID: set.id) }),
                focus: $focus, select: { model.select(set.id, in: workout) },
                toggleWarmup: { toggleWarmup(set, row: row, workout: workout) })
              if index < row.sets.count - 1 { Divider() }
            }
            if let error = error ?? store.error {
              Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red).padding(
                .top, 12)
            }
          }
        }
      }.scrollDismissesKeyboard(.interactively)
      cardFooter(row, workout: workout)
    }.padding(12).background(FitTheme.paper, in: .rect(cornerRadius: FitTheme.exerciseCardRadius))
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
          Image(systemName: "chart.xyaxis.line").font(.title2)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(L10n.text("Прогресс упражнения", locale: locale))
        .accessibilityIdentifier("openExerciseProgress")
        Spacer()
        NavigationLink {
          ExerciseDetailView(exercise: row.exercise).toolbar(.visible, for: .navigationBar)
        } label: {
          HStack {
            WorkoutExerciseThumbnail(exercise: row.exercise)
            Image(systemName: "info").font(.title2)
          }
        }.frame(minHeight: 44).accessibilityLabel(L10n.text("Техника выполнения", locale: locale))
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
    focus = nil
    error = nil
    model.move(offset, in: workout)
  }
  private func mutate(_ workout: Workout, action: (inout Workout) throws -> Void) {
    _ = store.mutate { value in
      guard value.id == workout.id else { throw TrainingError.invalidState }
      try action(&value)
    }
  }
  private func addSet(in workout: Workout) {
    mutate(workout) { try WorkoutEngine.addSet(exerciseID: model.exerciseID, to: &$0) }
  }
  private func toggleWarmup(_ set: WorkoutSet, row: WorkoutExercise, workout: Workout) {
    mutate(workout) {
      try WorkoutEngine.setWarmup(!set.isWarmup, in: &$0, exerciseID: row.id, setID: set.id)
    }
  }
  private func pause(_ workout: Workout) {
    focus = nil
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
    focus = nil
    do {
      let request = try model.completion(in: workout)
      error = nil
      let saved = store.mutate {
        guard $0.id == workout.id else { throw TrainingError.invalidState }
        try WorkoutEngine.completeSet(
          in: &$0, exerciseID: request.exerciseID, setID: request.set.id,
          repetitions: request.set.repetitions, weightKG: request.set.weightKG)
      }
      if saved { lastCompletion = ContinuousClock().now }
    } catch { self.error = error.localizedDescription }
  }
  private func finish(_ workout: Workout) {
    guard store.active?.id == workout.id else {
      error = TrainingError.invalidState.localizedDescription
      return
    }
    store.finish()
  }
}
