import FitSessionCore
import SwiftUI

struct TrainingMonthCard: View {
  let date: Date
  let summary: TrainingMonthSummary
  let move: (Int) -> Void
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 12) {
        HStack {
          Button("Предыдущий месяц", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
          Text(date, format: .dateTime.month(.wide)).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Следующий месяц", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly)
        }.font(.caption).foregroundStyle(.secondary)
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 6
        ) {
          ForEach(summary.days) { day in
            Text(day.date, format: .dateTime.day()).font(.caption)
              .fontWeight(day.hasWorkout ? .semibold : .regular)
              .foregroundStyle(
                day.hasWorkout
                  ? Color.white : day.isInMonth ? Color.primary : Color.secondary.opacity(0.5)
              )
              .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
              .background(day.hasWorkout ? FitTheme.accent : .clear, in: .circle)
              .overlay(
                Circle().stroke(
                  day.isInMonth && !day.hasWorkout ? Color.gray.opacity(0.25) : .clear, lineWidth: 1
                )
              )
              .accessibilityLabel(
                "\(day.date.formatted(date: .complete, time: .omitted))\(day.hasWorkout ? ", была тренировка" : "")"
              )
          }
        }
      }
      Rectangle().fill(.gray.opacity(0.18)).frame(width: 1)
      VStack(spacing: 14) {
        Text("Всего").font(.subheadline).foregroundStyle(.secondary)
        Text("\(summary.workoutCount)").font(.largeTitle.weight(.medium)).monospacedDigit()
        Divider()
        ZStack {
          Circle().stroke(.gray.opacity(0.15), lineWidth: 13)
          Circle().trim(
            from: 0,
            to: summary.trainingDayFraction
          )
          .stroke(FitTheme.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round))
          .rotationEffect(.degrees(-90))
        }.frame(width: 48, height: 48).padding(.top, 5).accessibilityLabel(
          "Дни с тренировками в выбранном месяце")
      }.frame(width: 68)
    }.fixedSize(horizontal: false, vertical: true).fitCard()
  }
}
