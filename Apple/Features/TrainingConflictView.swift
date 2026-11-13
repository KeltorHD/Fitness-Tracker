import FitLifeCore
import SwiftUI

struct TrainingConflictView: View {
  let model: AccountTrainingViewModel
  let conflict: TrainingConflict
  private var latest: TrainingConflict {
    model.sync.conflicts.first { $0.id == conflict.id } ?? conflict
  }
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var local: TrainingValue?
  @State private var loaded = false
  @State private var pulse: TrainingValue?
  @State private var previewRequest = 0
  @State private var error: String?
  @State private var action: AccountTrainingAction?
  @State private var confirmation: AccountTrainingAction?

  var body: some View {
    Form {
      Section {
        Text(
          L10n.text(
            "Одна запись изменена на разных устройствах. Сравните версии и выберите, какую сохранить.",
            locale: locale))
        if latest.activeWorkoutCollision {
          Text(
            L10n.text(
              "Завершите текущую тренировку перед принятием другой активной тренировки.",
              locale: locale))
        }
      }
      if loaded {
        Section(L10n.text("На устройстве", locale: locale)) {
          TrainingValuePreview(value: local)
          if latest.id.kind == .workout && latest.remote.deleted, let pulse {
            Text(L10n.text("При удалении тренировки будет удалён и её пульс.", locale: locale))
            TrainingValuePreview(value: pulse)
          }
        }
        Section(L10n.text("На сервере", locale: locale)) {
          TrainingValuePreview(value: latest.remote.value)
        }
        Section {
          Button(L10n.text("Сохранить локальную версию на сервере", locale: locale)) {
            prepare(keepLocal: true)
          }
          .buttonStyle(.borderless).accessibilityIdentifier("keepLocalTrainingVersion")
          Button(L10n.text("Принять серверную версию", locale: locale)) {
            prepare(keepLocal: false)
          }
          .buttonStyle(.borderless).accessibilityIdentifier("acceptServerTrainingVersion")
        }.disabled(model.isBusy || model.sync.isSyncing)
      } else {
        ProgressView()
      }
      if let message = error ?? model.sync.errorMessage {
        Section {
          Text(L10n.text(message, locale: locale)).foregroundStyle(.red)
          Button(L10n.text("Обновить предпросмотр", locale: locale)) { previewRequest += 1 }
        }
      }
    }
    .navigationTitle(L10n.text("Расхождение данных", locale: locale))
    .task(id: "\(latest.remote.revision)-\(previewRequest)") {
      loaded = false
      do {
        local = try await store.currentTrainingValue(latest.id)
        pulse =
          latest.id.kind == .workout && latest.remote.deleted
          ? try await store.currentTrainingValue(
            TrainingRecordKey(kind: .heartRate, id: latest.id.id)) : nil
        error = nil
        loaded = true
      } catch {
        self.error = L10n.text(
          "Не удалось прочитать локальную запись. Повторите попытку.", locale: locale)
      }
    }
    .task(id: action) {
      guard let requested = action else { return }
      await model.perform(requested) { _ in throw CancellationError() }
      action = nil
      if !model.sync.conflicts.contains(where: { $0.id == conflict.id }) { dismiss() }
    }
    .confirmationDialog(
      L10n.text("Подтвердите выбор версии", locale: locale),
      isPresented: Binding(
        get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
      ), titleVisibility: .visible
    ) {
      Button(L10n.text("Сохранить выбранную версию", locale: locale), role: .destructive) {
        action = confirmation
        confirmation = nil
      }
      Button(L10n.text("Отменить", locale: locale), role: .cancel) { confirmation = nil }
    } message: {
      Text(
        L10n.text(
          "Другая версия этой записи будет заменена. Если выбранная версия удалена, запись будет удалена на обоих устройствах.",
          locale: locale))
    }
  }
  private func prepare(keepLocal: Bool) {
    do {
      confirmation = try model.resolutionAction(
        latest, local: local, pulse: pulse, keepLocal: keepLocal)
    } catch {
      self.error = L10n.text(
        "Не удалось подготовить выбранную версию. Обновите предпросмотр.", locale: locale)
    }
  }
}

private struct TrainingValuePreview: View {
  let value: TrainingValue?
  @Environment(\.locale) private var locale
  var body: some View {
    if let value {
      if let title = value.title { Text(title).font(.headline) }
      switch value {
      case .workout(let workout):
        Text(workout.startedAt, format: .dateTime.day().month().year().hour().minute())
        Text(L10n.text(status(workout.status), locale: locale))
        if let end = workout.endedAt {
          Text(end, format: .dateTime.day().month().year().hour().minute())
        }
        LabeledContent(
          L10n.text("Длительность", locale: locale),
          value: workout.formattedRecordedDuration(locale: locale))
        LabeledContent(
          L10n.text("Паузы", locale: locale),
          value: workout.pausedSeconds.formattedWorkoutDuration(locale: locale))
        LabeledContent(L10n.text("Отдых", locale: locale), value: String(workout.restSeconds))
        if let rest = workout.restEndsAt { Text(rest, format: .dateTime.hour().minute().second()) }
        if let pause = workout.pausedAt { Text(pause, format: .dateTime.hour().minute().second()) }
        if !workout.pauses.isEmpty {
          DisclosureGroup(L10n.text("Паузы", locale: locale)) {
            ForEach(workout.pauses.indices, id: \.self) { index in
              Text(workout.pauses[index].startedAt, format: .dateTime.hour().minute().second())
              Text(workout.pauses[index].endedAt, format: .dateTime.hour().minute().second())
            }
          }
        }
        if let weight = workout.bodyWeightKG {
          Text(weight, format: .number).accessibilityLabel(
            L10n.text("Вес тела, кг", locale: locale))
        }
        if !workout.notes.isEmpty { Text(workout.notes) }
        ForEach(workout.exercises) { row in
          exercise(row.exercise, sets: row.sets, superset: row.supersetID != nil)
        }
      case .template(let template):
        LabeledContent(L10n.text("Отдых", locale: locale), value: String(template.restSeconds))
        if let base = template.baseVariationName { Text(base) }
        if !template.muscleSelection.isEmpty {
          Text(MuscleSelectionText.summary(template.muscleSelection, locale: locale))
        }
        if !template.preferredWeekdays.isEmpty {
          LabeledContent(
            L10n.text("Расписание", locale: locale),
            value: template.preferredWeekdays
              .sorted { $0.rawValue < $1.rawValue }
              .map { L10n.text($0.title, locale: locale) }.joined(separator: ", "))
        }
        ForEach(template.exercises) { row in templateRow(row) }
        ForEach(template.variations) { variation in
          Text(variation.name).font(.headline)
          ForEach(variation.exercises) { row in templateRow(row) }
        }
      case .bodyWeight(let entry):
        Text(entry.measuredAt, format: .dateTime.day().month().year().hour().minute())
        LabeledContent(L10n.text("Вес тела, кг", locale: locale)) {
          Text(entry.weightKG, format: .number)
        }
      case .heartRate(let recording):
        Text(
          L10n.text(
            recording.mode == .bluetooth ? "Bluetooth-датчик" : "Apple Health", locale: locale))
        LabeledContent(
          L10n.text("Измерения пульса", locale: locale), value: String(recording.readings.count))
        if let average = recording.average {
          LabeledContent(L10n.text("Средний пульс", locale: locale)) {
            Text(average, format: .number.precision(.fractionLength(0...1)))
          }
        }
        if let first = recording.readings.first {
          Text(first.date, format: .dateTime.day().month().year().hour().minute().second())
        }
        if let last = recording.readings.last {
          Text(last.date, format: .dateTime.day().month().year().hour().minute().second())
        }
        DisclosureGroup(L10n.text("Измерения пульса", locale: locale)) {
          ForEach(recording.readings) { reading in
            LabeledContent {
              Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0...2)))
            } label: {
              Text(reading.date, format: .dateTime.hour().minute().second())
            }
          }
        }
      }
    } else {
      Text(L10n.text("Запись удалена", locale: locale)).foregroundStyle(.secondary)
    }
  }
  private func templateRow(_ row: TemplateExercise) -> some View {
    exercise(
      row.exercise,
      sets: row.plannedSets
        ?? (0..<row.setCount).map { _ in
          WorkoutSet(
            repetitions: row.repetitions, weightKG: row.weightKG, loadMultiplier: row.loadMultiplier
          )
        }, superset: row.supersetID != nil)
  }
  private func exercise(_ definition: Exercise, sets: [WorkoutSet], superset: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(definition.name).font(.subheadline.bold())
      if !definition.instructions.isEmpty {
        DisclosureGroup(L10n.text("Описание", locale: locale)) { Text(definition.instructions) }
      }
      if superset { Text(L10n.text("Суперсет", locale: locale)).font(.caption) }
      ForEach(sets) { set in
        HStack {
          Image(systemName: set.isFullyCompleted ? "checkmark.circle.fill" : "circle")
          Text("\(set.repetitions) × \(set.weightKG.formatted(.number.locale(locale)))")
          if let multiplier = set.loadMultiplier { Text("× \(multiplier)") }
          if set.isWarmup { Text(L10n.text("Разминка", locale: locale)) }
        }
        if let date = set.completedAt {
          Text(date, format: .dateTime.hour().minute().second()).font(.caption)
        }
        ForEach(set.dropStages ?? []) { stage in
          Text("↳ \(stage.repetitions) × \(stage.weightKG.formatted(.number.locale(locale)))")
          if let date = stage.completedAt {
            Text(date, format: .dateTime.hour().minute().second()).font(.caption)
          }
        }
        if let note = set.note, !note.isEmpty { Text(note).font(.caption) }
      }
    }.padding(.vertical, 4)
  }
  private func status(_ status: WorkoutStatus) -> String {
    switch status {
    case .active: "Активная тренировка"
    case .paused: "Тренировка на паузе"
    case .completed: "Тренировка завершена"
    case .cancelled: "Тренировка отменена"
    }
  }
}
