import FitSessionCore
import SwiftUI

struct HistoryWorkoutRow: View {
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
          .foregroundStyle(FitTheme.accent)
        Rectangle().fill(FitTheme.card).frame(width: 3).frame(minHeight: 30)
      }.frame(width: 26)
      VStack(alignment: .leading, spacing: 8) {
        Text(workout.startedAt.formatted(.dateTime.weekday(.wide)).localizedCapitalized)
          .font(.subheadline)
        Button {
          onSelect()
        } label: {
          VStack(alignment: .leading, spacing: 7) {
            Text(workout.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            Text(
              "\(workout.duration().workoutDuration)  \(unit.display(workout.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)  · \(workout.completedSets) подх."
            )
            .font(.subheadline).foregroundStyle(.primary)
          }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
        }.buttonStyle(.plain)
          .contextMenu {
            Button("Повторить", systemImage: "arrow.counterclockwise") {
              onRepeat()
            }
            Button("Удалить", systemImage: "trash", role: .destructive) {
              onDelete()
            }
          }
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
}
