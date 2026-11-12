import FitnessTrackerCore
import SwiftUI

struct TrainingDiaryInsightsView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.dynamicTypeSize) private var typeSize
  @AppStorage("trainingDiaryInsightsExpanded") private var expanded = true
  @AppStorage("weeklyGoal") private var goal = 3
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  let summary: DiaryTrainingSummary

  var body: some View {
    DiaryDisclosureCard(
      title: L10n.text("Ритм тренировок", locale: locale),
      summary: L10n.workoutCount(summary.workouts, locale: locale),
      identifier: "expandTrainingInsights", expanded: $expanded
    ) {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 18) {
          ring
          headline
        }
      } else {
        HStack(spacing: 20) {
          ring
          headline.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      HStack(alignment: .top, spacing: 12) {
        metric("Рабочие подходы", value: String(summary.workingSets), symbol: "checkmark.circle")
        metric(
          "Объём",
          value: unit.display(summary.volumeKG).formatted(
            .number.precision(.fractionLength(0)).locale(locale))
            + " " + L10n.text(unit.rawValue, locale: locale), symbol: "scalemass")
        metric(
          "Записанное время",
          value: summary.duration?.formattedWorkoutDuration(locale: locale) ?? "—",
          symbol: "clock")
      }
      HStack(spacing: 4) {
        ForEach(TrainingJournal.weekDays(containing: summary.start, calendar: calendar), id: \.self)
        {
          day in
          let trained = summary.trainedDays.contains(calendar.startOfDay(for: day))
          VStack(spacing: 6) {
            Image(systemName: trained ? "checkmark.circle.fill" : "circle")
              .font(.title3).foregroundStyle(trained ? theme.accent : .secondary.opacity(0.35))
            Text(day, format: .dateTime.weekday(.narrow)).font(.caption2)
              .foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              day.formatted(.dateTime.locale(locale).weekday(.wide).day().month())
            )
            .accessibilityValue(
              L10n.text(trained ? "Тренировка завершена" : "Без тренировки", locale: locale))
        }
      }
      Text(L10n.text("За выбранную неделю · только завершённые тренировки", locale: locale))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var ring: some View {
    ZStack {
      DiaryProgressRing(progress: summary.progress(goal: max(1, goal)), color: theme.accent)
      VStack(spacing: 2) {
        Text(summary.workouts, format: .number).font(
          .system(.largeTitle, design: .rounded).bold()
        )
        .monospacedDigit().contentTransition(.numericText())
        Text(L10n.format("из %@", String(max(1, goal)), locale: locale))
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }.frame(width: 132, height: 132)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.text("Недельная цель тренировок", locale: locale))
      .accessibilityValue("\(summary.workouts) / \(max(1, goal))")
      .accessibilityIdentifier("trainingGoalRing")
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("Недельная цель", locale: locale)).font(.subheadline).foregroundStyle(
        .secondary)
      Text(L10n.workoutCount(max(1, goal), locale: locale)).font(.title3.bold())
      Group {
        if summary.workouts >= max(1, goal) {
          Text(L10n.text("Цель достигнута", locale: locale))
        } else {
          Text(summary.progress(goal: max(1, goal)), format: .percent.precision(.fractionLength(0)))
            .monospacedDigit()
        }
      }.font(.subheadline).foregroundStyle(theme.accent)
        .fixedSize(horizontal: false, vertical: true)
      Text(summary.start, format: .dateTime.day().month(.abbreviated))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func metric(_ title: String, value: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: symbol).foregroundStyle(theme.accent)
      Text(value).font(.headline).monospacedDigit().contentTransition(.numericText())
      Text(L10n.text(title, locale: locale)).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
}
