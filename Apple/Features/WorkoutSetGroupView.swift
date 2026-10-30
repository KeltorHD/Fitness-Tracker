import FitnessTrackerCore
import SwiftUI

struct WorkoutSetGroupView: View {
  @Environment(\.locale) private var locale
  let set: WorkoutSet
  let index: Int
  let workout: Workout
  let model: WorkoutExercisePresentation
  let numberPad: WorkoutNumberPadModel
  let toggleWarmup: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      row(set, index: index)
      if let stages = set.dropStages {
        ForEach(Array(stages.enumerated()), id: \.element.id) { offset, stage in
          Divider().padding(.leading, 52)
          row(
            WorkoutSet(
              id: stage.id, repetitions: stage.repetitions, weightKG: stage.weightKG,
              completedAt: stage.completedAt), index: offset, marker: "↓\(offset + 1)"
          )
          .padding(.leading, 12).accessibilityIdentifier("dropStage")
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
    .padding(.horizontal, set.isDropSet ? 8 : 0)
    .background(set.isDropSet ? FitTheme.card.opacity(0.5) : .clear, in: .rect(cornerRadius: 16))
    .accessibilityIdentifier(set.isDropSet ? "dropSetGroup" : "workoutSetGroup")
  }
  private func row(_ value: WorkoutSet, index: Int, marker: String? = nil) -> some View {
    WorkoutSetRow(
      set: value, index: index, marker: marker, showsWarmupAction: marker == nil,
      unit: model.unit, editable: workout.status == .active && value.completedAt == nil,
      selected: value.id == model.selectedTargetID && workout.status == .active,
      weight: model.drafts[value.id]?.weight ?? "",
      repetitions: model.drafts[value.id]?.repetitions ?? "",
      numberPad: numberPad, edit: { numberPad.begin($0, in: workout) },
      select: {
        numberPad.dismiss()
        model.select(value.id, in: workout)
      }, toggleWarmup: toggleWarmup
    )
    .id("number-\(value.id.uuidString)")
  }
}
