import FitnessTrackerCore
import SwiftUI

struct WorkoutSessionSummary: View {
  @Environment(\.locale) private var locale
  let workout: Workout
  let unit: WeightUnit
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      HStack(spacing: 8) {
        SummaryMetric(
          title: L10n.text("Время", locale: locale),
          value: [.active, .paused].contains(workout.status)
            ? workout.duration(at: timeline.date).formattedWorkoutDuration(locale: locale)
            : workout.formattedRecordedDuration(locale: locale))
        SummaryMetric(
          title: L10n.text("Объём", locale: locale),
          value:
            "\(unit.display(workout.volume).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0)))) \(L10n.text(unit.rawValue, locale: locale))"
        )
        SummaryMetric(
          title: L10n.text("Подходы", locale: locale),
          value: workout.status == .completed
            ? String(workout.completedSets) : "\(workout.fullyCompletedSets)/\(workout.totalSets)")
      }
    }
  }
}

struct WorkoutExerciseListRow: View {
  @Environment(\.locale) private var locale
  let row: WorkoutExercise
  let index: Int
  let unit: WeightUnit
  let completedOnly: Bool
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
      WorkoutExerciseThumbnail(exercise: row.exercise)
    }.foregroundStyle(.primary).padding(.vertical, 16).contentShape(.rect)
  }
}

struct WorkoutExerciseThumbnail: View {
  let exercise: Exercise
  var body: some View {
    if let entry = ExerciseLibrary.entry(for: exercise.id),
      let path = entry.generatedMedia?.poster ?? entry.images.first
    {
      ExercisePhoto(path: path).frame(width: 46, height: 46)
        .background(FitTheme.paper, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FitTheme.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
  }
}
