import FitLifeCore
import SwiftUI

struct TrainingDiaryInsightsView: View {
  private enum Metric: String, CaseIterable { case workouts, sets, volume }
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("trainingDiaryInsightsExpanded") private var expanded = true
  @AppStorage("weeklyGoal") private var goal = 3
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var selected: Metric?
  let summary: DiaryTrainingSummary
  private var displayedMetric: Metric { selected ?? .workouts }
  private var outerToInnerMetrics: [Metric] {
    Metric.allCases.enumerated().sorted { left, right in
      let leftRange = range(left.element)
      let rightRange = range(right.element)
      return leftRange == rightRange ? left.offset > right.offset : leftRange > rightRange
    }.map(\.element)
  }

  var body: some View {
    DiaryDisclosureCard(
      title: L10n.text("Ритм тренировок", locale: locale),
      summary: L10n.workoutCount(summary.workouts, locale: locale),
      identifier: "expandTrainingInsights", expanded: $expanded
    ) {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 16) {
          rings
          legend
        }
      } else {
        HStack(spacing: 16) {
          rings
          legend
        }
      }
      Text(comparison).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("trainingRingComparison")
      HStack(alignment: .top, spacing: 16) {
        Label(
          summary.duration?.formattedWorkoutDuration(locale: locale) ?? "—", systemImage: "clock"
        )
        .accessibilityLabel(L10n.text("Записанное время", locale: locale))
        .accessibilityValue(summary.duration?.formattedWorkoutDuration(locale: locale) ?? "—")
        Spacer(minLength: 0)
        Label(
          L10n.format("Дней активности: %@", String(summary.trainedDays.count), locale: locale),
          systemImage: "calendar")
      }.font(.caption).foregroundStyle(.secondary)
      Text(L10n.text("За выбранную неделю · только завершённые тренировки", locale: locale))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private var rings: some View {
    let metrics = outerToInnerMetrics
    return ZStack {
      ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
        DiaryProgressRing(progress: progress(metric), color: color(metric), lineWidth: 10)
          .padding(CGFloat(index) * 15).opacity(ringOpacity(metric))
      }
      VStack(spacing: 3) {
        Text(centerValue).font(.system(.title3, design: .rounded).bold()).monospacedDigit()
          .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.65)
        Text(
          L10n.text(
            displayedMetric == .workouts
              ? "Тренировки" : displayedMetric == .sets ? "Подходы" : unit.rawValue,
            locale: locale)
        )
        .font(.caption2).foregroundStyle(.secondary)
      }.padding(40)
    }.frame(width: 156, height: 156)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected)
      .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: metrics)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.text("Три кольца тренировок", locale: locale))
      .accessibilityValue(value(displayedMetric) + ". " + comparison)
      .accessibilityIdentifier("trainingGoalRing")
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Metric.allCases, id: \.self) { metric in
        Button {
          selected = selected == metric ? nil : metric
        } label: {
          HStack(spacing: 7) {
            Circle().fill(color(metric)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
              Text(L10n.text(title(metric), locale: locale)).font(.caption)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              Text(value(metric)).font(.subheadline.bold()).monospacedDigit()
                .foregroundStyle(.primary).contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(minHeight: 44).padding(.horizontal, 6).padding(.vertical, 2)
            .background(
              selected == metric ? color(metric).opacity(0.09) : .clear, in: .rect(cornerRadius: 12)
            )
            .contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("trainingRing_\(metric.rawValue)")
          .accessibilityAddTraits(selected == metric ? [.isSelected] : [])
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var centerValue: String {
    switch displayedMetric {
    case .workouts: "\(summary.workouts)/\(max(1, goal))"
    case .sets: String(summary.workingSets)
    case .volume:
      unit.display(summary.volumeKG).formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
  }
  private func value(_ metric: Metric) -> String {
    switch metric {
    case .workouts: "\(summary.workouts) / \(max(1, goal))"
    case .sets: String(summary.workingSets)
    case .volume:
      unit.display(summary.volumeKG).formatted(.number.precision(.fractionLength(0)).locale(locale))
        + " " + L10n.text(unit.rawValue, locale: locale)
    }
  }
  private func title(_ metric: Metric) -> String {
    switch metric {
    case .workouts: "Тренировки"
    case .sets: "Рабочие подходы"
    case .volume: "Объём"
    }
  }
  private func color(_ metric: Metric) -> Color {
    switch metric {
    case .workouts: theme.accent
    case .sets: .blue
    case .volume: .purple
    }
  }
  private func ringOpacity(_ metric: Metric) -> Double {
    selected == nil || selected == metric ? 1 : 0.25
  }
  /// Compare the full recorded/target range, rather than the percentage filling each ring.
  private func range(_ metric: Metric) -> Double {
    switch metric {
    case .workouts: Double(max(summary.workouts, max(1, goal)))
    case .sets: Double(max(summary.workingSets, summary.previousWorkingSets ?? 0))
    case .volume: max(summary.volumeKG, summary.previousVolumeKG ?? 0)
    }
  }
  private func progress(_ metric: Metric) -> Double {
    switch metric {
    case .workouts: summary.progress(goal: max(1, goal))
    case .sets: summary.setComparison ?? 0
    case .volume: summary.volumeComparison ?? 0
    }
  }
  private var comparison: String {
    switch displayedMetric {
    case .workouts:
      return L10n.format(
        "Недельная цель: %@", L10n.workoutCount(max(1, goal), locale: locale), locale: locale)
    case .sets:
      guard let previous = summary.previousWorkingSets, let ratio = summary.setComparison else {
        return L10n.text("Нет данных прошлой недели для сравнения подходов.", locale: locale)
      }
      return L10n.format(
        "Прошлая неделя: %@ · от неё %@", String(previous),
        ratio.formatted(.percent.precision(.fractionLength(0)).locale(locale)), locale: locale)
    case .volume:
      guard let previous = summary.previousVolumeKG, let ratio = summary.volumeComparison else {
        return L10n.text("Нет данных прошлой недели для сравнения объёма.", locale: locale)
      }
      let amount =
        unit.display(previous).formatted(.number.precision(.fractionLength(0)).locale(locale)) + " "
        + L10n.text(unit.rawValue, locale: locale)
      return L10n.format(
        "Прошлая неделя: %@ · от неё %@", amount,
        ratio.formatted(.percent.precision(.fractionLength(0)).locale(locale)), locale: locale)
    }
  }
}
