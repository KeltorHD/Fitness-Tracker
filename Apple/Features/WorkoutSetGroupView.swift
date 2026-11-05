import FitnessTrackerCore
import SwiftUI

struct WorkoutSetGroupView: View {
  @Environment(\.locale) private var locale
  let set: WorkoutSet
  let index: Int
  let workout: Workout
  let model: WorkoutExercisePresentation
  let numberPad: WorkoutNumberPadModel
  let notesExpanded: Bool
  let toggleWarmup: () -> Void
  let configureDrop: (Bool) -> Void
  let addAfter: () -> Void
  let remove: () -> Void
  let removeStage: (UUID) -> Void
  let editCompleted: (WorkoutSet) -> Void
  let openNote: () -> Void

  var body: some View {
    Section {
      if set.isDropSet {
        HStack(spacing: 8) {
          Text(L10n.format("Дропсет · этапов: %@", String(set.stages.count), locale: locale))
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          if workout.status == .active, !set.isFullyCompleted {
            Button {
              configureDrop(true)
            } label: {
              Image(systemName: "plus").frame(width: 44, height: 44)
            }.disabled((set.dropStages ?? []).count >= 5)
              .accessibilityLabel(L10n.text("Добавить снижение веса", locale: locale))
              .accessibilityIdentifier("appendDropStage_\(set.id)")
          }
          Menu {
            contextActions(for: set, isChild: false)
            Section { SettingsLink() }
          } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
          }.accessibilityLabel(L10n.text("Действия группы дропсета", locale: locale))
        }
        .buttonStyle(.plain).padding(.leading, 10)
        .listRowSeparator(.hidden)
        .listRowBackground(
          UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).fill(FitTheme.paper))
      }
      row(set, index: index)
        .accessibilityIdentifier(set.isDropSet ? "dropSetGroup" : "workoutSetGroup")
      if let stages = set.dropStages {
        ForEach(Array(stages.enumerated()), id: \.element.id) { offset, stage in
          row(
            WorkoutSet(
              id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG,
              completedAt: stage.completedAt), index: offset, marker: "↳\(offset + 1)"
          )
          .accessibilityIdentifier("dropStage")
        }
        Color.clear.frame(height: 6).listRowSeparator(.hidden)
          .listRowBackground(
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(
              FitTheme.paper))
      }
    }
    .listRowInsets(EdgeInsets())
  }

  private func row(_ value: WorkoutSet, index: Int, marker: String? = nil) -> some View {
    let child = marker != nil
    return WorkoutSetRow(
      set: value, index: index, marker: marker, unit: model.unit, notesExpanded: notesExpanded,
      editable: workout.status == .active && value.completedAt == nil,
      showsDropMetadata: false, canCorrectCompleted: [.active, .paused].contains(workout.status),
      selected: value.id == model.selectedTargetID && workout.status == .active,
      previous: model.previousValues?.stages[value.id],
      showsPrevious: [.active, .paused].contains(workout.status) && model.previousValues != nil,
      weight: model.drafts[value.id]?.weight ?? "",
      repetitions: model.drafts[value.id]?.repetitions ?? "",
      numberPad: numberPad, edit: { numberPad.begin($0, in: workout) },
      select: {
        numberPad.dismiss()
        model.select(value.id, in: workout)
      },
      advance: { numberPad.advance(in: workout) }, editCompleted: { editCompleted(value) },
      openNote: child ? nil : openNote,
      contextActions: { contextActions(for: value, isChild: child) }
    )
    .listRowBackground(set.isDropSet ? FitTheme.paper : Color.clear)
    .listRowSeparator(set.isDropSet ? .hidden : .automatic)
    .id("number-\(value.id.uuidString)")
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if workout.status == .active, numberPad.field == nil {
        Button(action: addAfter) {
          Label(L10n.text("Добавить подход после", locale: locale), systemImage: "plus")
        }.disabled((model.exercise(in: workout)?.sets.count ?? 30) >= 30)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if workout.status == .active, numberPad.field == nil {
        Button {
          if child { removeStage(value.id) } else { remove() }
        } label: {
          Label(
            L10n.text(
              child
                ? "Удалить этап дропсета"
                : set.isDropSet ? "Удалить группу дропсета" : "Удалить подход", locale: locale),
            systemImage: "trash")
        }.tint(.red).disabled(!child && (model.exercise(in: workout)?.sets.count ?? 0) <= 1)
          .accessibilityIdentifier("removeSetTarget_\(value.id)")
      }
    }
  }

  @ViewBuilder private func contextActions(for value: WorkoutSet, isChild: Bool) -> some View {
    Button(action: openNote) {
      Label(L10n.text("Заметка к подходу", locale: locale), systemImage: "note.text")
    }
    if value.completedAt != nil, [.active, .paused].contains(workout.status) {
      Button(L10n.text("Изменить выполненный подход", locale: locale)) { editCompleted(value) }
    }
    if workout.status == .active {
      Button(action: addAfter) {
        Label(L10n.text("Добавить подход после", locale: locale), systemImage: "plus")
      }
      .disabled((model.exercise(in: workout)?.sets.count ?? 30) >= 30)
      if set.completedAt == nil {
        if !set.isDropSet {
          Button(
            L10n.text(set.isWarmup ? "Рабочий подход" : "Разминочный подход", locale: locale),
            action: toggleWarmup
          )
          .accessibilityIdentifier("toggleSetWarmup")
        } else {
          Button(L10n.text("Убрать дропсет", locale: locale)) { configureDrop(false) }
            .accessibilityIdentifier("removeDropSet")
        }
      }
      if !set.isWarmup, !set.isFullyCompleted {
        Button(
          L10n.text(set.isDropSet ? "Добавить снижение веса" : "Сделать дропсетом", locale: locale)
        ) { configureDrop(true) }
        .disabled((set.dropStages ?? []).count >= 5).accessibilityIdentifier("addDropStage")
      }
      if isChild {
        Button(L10n.text("Удалить этап дропсета", locale: locale), role: .destructive) {
          removeStage(value.id)
        }
      }
      Button(
        L10n.text(set.isDropSet ? "Удалить группу дропсета" : "Удалить подход", locale: locale),
        role: .destructive, action: remove
      )
      .disabled((model.exercise(in: workout)?.sets.count ?? 0) <= 1)
    }
  }
}
