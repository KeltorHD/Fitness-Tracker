import FitLifeCore
import SwiftUI

struct WorkoutSessionSummary: View {
  @Environment(\.locale) private var locale
  let workout: Workout
  let unit: WeightUnit
  var showsDuration = true
  var bodyWeightKG: Double?
  var editBodyWeight: (() -> Void)?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      WorkoutSummaryCard(
        metrics: (showsDuration
          ? [
            (
              title: L10n.text("Время", locale: locale),
              value: [.active, .paused].contains(workout.status)
                ? workout.duration(at: timeline.date).formattedWorkoutDuration(locale: locale)
                : workout.formattedRecordedDuration(locale: locale)
            )
          ] : []) + [
            (
              title: L10n.text("Объём", locale: locale),
              value:
                "\(unit.display(workout.volume).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0)))) \(L10n.text(unit.rawValue, locale: locale))"
            ),
            (
              title: L10n.text("Подходы", locale: locale),
              value: workout.status == .completed
                ? String(workout.completedSets)
                : "\(workout.fullyCompletedSets)/\(workout.totalSets)"
            ),
          ]
          + (editBodyWeight != nil
            ? [
              (
                title: L10n.text("Вес тела", locale: locale),
                value: bodyWeightKG.map {
                  "\(unit.display($0).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))) \(L10n.text(unit.rawValue, locale: locale))"
                } ?? "—"
              )
            ] : []),
        metricAction: editBodyWeight.map {
          WorkoutSummaryCard.MetricAction(
            index: showsDuration ? 3 : 2, identifier: "editWorkoutBodyWeight",
            hint: L10n.text("Изменить вес", locale: locale), perform: $0)
        })
    }
  }
}

struct WorkoutExerciseListRow: View {
  @Environment(\.locale) private var locale
  let row: WorkoutExercise
  let index: Int
  let unit: WeightUnit
  let completedOnly: Bool
  var showsThumbnail = true
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Text(String(index + 1)).font(.body).monospacedDigit().foregroundStyle(.secondary)
        .frame(minWidth: 20).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 7) {
        Text(L10n.exerciseName(row.exercise, locale: locale)).font(.title3.weight(.semibold))
        Text(
          WorkoutExerciseSummary.text(
            row, completedOnly: completedOnly, unit: unit, locale: locale,
            numberLocale: L10n.numberLocale)
        )
        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if showsThumbnail { WorkoutExerciseThumbnail(exercise: row.exercise) }
    }.foregroundStyle(.primary).padding(.vertical, 16).contentShape(.rect)
  }
}

struct WorkoutExerciseThumbnail: View {
  @Environment(AppStore.self) private var store
  let exercise: Exercise
  var body: some View {
    if let entry = ExerciseLibrary.entry(
      for: PersonalExercises.catalogID(for: exercise.id, links: store.exerciseLinks)),
      let path = entry.generatedMedia?.poster ?? entry.generatedIllustration ?? entry.images.first
    {
      ExercisePhoto(path: path).frame(width: 46, height: 46)
        .background(FitTheme.paper, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FitTheme.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
  }
}
