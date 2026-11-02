import FitnessTrackerCore
import SwiftUI

struct HistoryWorkoutRow: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  let workout: Workout
  let unit: WeightUnit
  let onSelect: () -> Void
  let onRepeat: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 6) {
        Circle().fill(.gray.opacity(0.55)).frame(width: 7, height: 7)
        Rectangle().fill(FitTheme.card).frame(width: 3, height: 14)
        Image(systemName: "figure.strengthtraining.traditional").font(.title3)
          .foregroundStyle(colorTheme.accent)
        Rectangle().fill(FitTheme.card).frame(width: 3).frame(minHeight: 30)
      }.frame(width: 26)
      VStack(alignment: .leading, spacing: 8) {
        Text(
          workout.startedAt.formatted(.dateTime.locale(locale).weekday(.wide)).localizedCapitalized
        )
        .font(.subheadline)
        Button {
          onSelect()
        } label: {
          VStack(alignment: .leading, spacing: 7) {
            Text(workout.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            Text(
              L10n.format(
                "workout.row.summary", workout.formattedRecordedDuration(locale: locale),
                String(
                  unit.display(workout.volume).formatted(
                    .number.locale(L10n.numberLocale).precision(.fractionLength(0)))),
                String(L10n.text(unit.rawValue, locale: locale)),
                L10n.countText(workout.completedSets, kind: "set", locale: locale), locale: locale)
            )
            .font(.subheadline).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
        }.buttonStyle(.plain)
          .contextMenu {
            Button(L10n.text("Повторить", locale: locale), systemImage: "arrow.counterclockwise") {
              onRepeat()
            }
            Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive) {
              onDelete()
            }
          }
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
}
