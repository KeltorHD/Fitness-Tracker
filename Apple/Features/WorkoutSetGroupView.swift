import FitnessTrackerCore
import SwiftUI

struct WorkoutSetGroupView: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  let set: WorkoutSet
  let index: Int
  let workout: Workout
  let model: WorkoutExercisePresentation
  let numberPad: WorkoutNumberPadModel
  let toggleWarmup: () -> Void
  let addAfter: () -> Void
  let remove: () -> Void
  let openNote: () -> Void

  var body: some View {
    Section {
      row(set, index: index)
        .accessibilityIdentifier(set.isDropSet ? "dropSetGroup" : "workoutSetGroup")
      if let stages = set.dropStages {
        ForEach(Array(stages.enumerated()), id: \.element.id) { offset, stage in
          row(
            WorkoutSet(
              id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG,
              completedAt: stage.completedAt), index: offset, marker: "↓\(offset + 1)"
          )
          .accessibilityIdentifier("dropStage")
          if workout.status == .completed, stage.completedAt == nil {
            Text(L10n.text("Не выполнено", locale: locale)).font(.caption).foregroundStyle(
              .secondary
            ).padding(.leading, 64)
          }
        }
        Text(L10n.text("Без отдыха между этапами", locale: locale))
          .font(.caption).foregroundStyle(.secondary).padding(.leading, 52).padding(.bottom, 10)
      }
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    .listRowBackground(Color.clear)
  }
  private func row(_ value: WorkoutSet, index: Int, marker: String? = nil) -> some View {
    WorkoutSetRow(
      set: value, index: index, marker: marker,
      unit: model.unit, editable: workout.status == .active && value.completedAt == nil,
      selected: value.id == model.selectedTargetID && workout.status == .active,
      weight: model.drafts[value.id]?.weight ?? "",
      repetitions: model.drafts[value.id]?.repetitions ?? "",
      numberPad: numberPad, edit: { numberPad.begin($0, in: workout) },
      select: {
        numberPad.dismiss()
        model.select(value.id, in: workout)
      }, openNote: marker == nil ? openNote : nil
    )
    .id("number-\(value.id.uuidString)")
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if workout.status == .active {
        Button(action: addAfter) {
          Label(L10n.text("Добавить подход после", locale: locale), systemImage: "plus")
        }.tint(colorTheme.accent).disabled((model.exercise(in: workout)?.sets.count ?? 30) >= 30)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if workout.status == .active {
        Button(role: .destructive, action: remove) {
          Label(L10n.text("Удалить подход", locale: locale), systemImage: "trash")
        }.disabled((model.exercise(in: workout)?.sets.count ?? 0) <= 1)
      }
    }
    .contextMenu {
      Button(action: openNote) {
        Label(L10n.text("Заметка к подходу", locale: locale), systemImage: "note.text")
      }
      if workout.status == .active {
        Button(action: addAfter) {
          Label(L10n.text("Добавить подход после", locale: locale), systemImage: "plus")
        }.disabled((model.exercise(in: workout)?.sets.count ?? 30) >= 30)
        if value.completedAt == nil, marker == nil, !set.isDropSet {
          Button(
            L10n.text(set.isWarmup ? "Рабочий подход" : "Разминочный подход", locale: locale),
            action: toggleWarmup)
        }
        Button(role: .destructive, action: remove) {
          Label(L10n.text("Удалить подход", locale: locale), systemImage: "trash")
        }.disabled((model.exercise(in: workout)?.sets.count ?? 0) <= 1)
      }
    }
  }
}
