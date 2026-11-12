import FitLifeCore
import SwiftUI

struct NutritionDiaryInsightsView: View {
  private enum Macro: String, CaseIterable {
    case protein, fat, carbohydrates
    var title: String {
      switch self {
      case .protein: "Белки"
      case .fat: "Жиры"
      case .carbohydrates: "Углеводы"
      }
    }
    var color: Color {
      switch self {
      case .protein: .blue
      case .fat: .orange
      case .carbohydrates: .purple
      }
    }
    func amount(in nutrients: Nutrients) -> Double {
      switch self {
      case .protein: nutrients.protein
      case .fat: nutrients.fat
      case .carbohydrates: nutrients.carbohydrates
      }
    }
    func target(in goal: NutritionGoal?) -> Double? {
      switch self {
      case .protein: goal?.protein
      case .fat: goal?.fat
      case .carbohydrates: goal?.carbohydrates
      }
    }
  }

  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.dynamicTypeSize) private var typeSize
  @AppStorage("nutritionDiaryInsightsExpanded") private var expanded = true
  let day: NutritionDay
  let date: Date
  let goal: NutritionGoal?
  @State private var selected: Macro?
  private var hasTotals: Bool { day.entries.isEmpty || day.entries.count > day.incompleteCount }
  private var calories: String {
    L10n.format("%@ ккал", number(day.total.calories), locale: locale)
  }

  var body: some View {
    DiaryDisclosureCard(
      title: L10n.text("Баланс питания", locale: locale),
      summary: hasTotals ? calories : L10n.text("КБЖУ не заполнены", locale: locale),
      identifier: "expandNutritionInsights", expanded: $expanded
    ) {
      if hasTotals {
        if typeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 16) {
            ring
            energy
          }
        } else {
          HStack(spacing: 16) {
            energy.frame(maxWidth: .infinity, alignment: .leading)
            ring
          }
        }
        if typeSize.isAccessibilitySize {
          VStack(spacing: 8) { macroButtons }
        } else {
          HStack(alignment: .top, spacing: 8) { macroButtons }
        }
        Text(L10n.text("На кольце — соотношение БЖУ в граммах.", locale: locale))
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text(L10n.text("КБЖУ не заполнены", locale: locale)).font(.headline)
      }
      if day.incompleteCount > 0 {
        Label(
          L10n.text("Есть фото без КБЖУ — итог неполный", locale: locale),
          systemImage: "info.circle"
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
    .onChange(of: date) { selected = nil }
  }

  private var ring: some View {
    ZStack {
      if let goal {
        DiaryProgressRing(
          progress: day.total.calories / goal.calories, color: theme.accent, lineWidth: 7)
      }
      DiaryRingChart(
        segments: Macro.allCases.map {
          DiaryRingSegment(id: $0.rawValue, value: $0.amount(in: day.total), color: $0.color)
        }, selectedID: selected?.rawValue,
        onSelect: { selected = Macro(rawValue: $0) }
      ) {
        VStack(spacing: 3) {
          if let selected {
            Text(number(selected.amount(in: day.total))).font(.title3.bold()).monospacedDigit()
            Text(L10n.text(selected.title, locale: locale)).font(.caption2).foregroundStyle(
              .secondary)
            Text(L10n.text("г", locale: locale)).font(.caption2).foregroundStyle(.secondary)
          } else {
            Image(systemName: "fork.knife").font(.title2).foregroundStyle(theme.accent)
          }
        }.padding(20)
      }.padding(goal == nil ? 0 : 13)
    }.frame(width: 148, height: 148)
      .accessibilityLabel(L10n.text("Соотношение БЖУ", locale: locale))
      .accessibilityValue(selected.map { L10n.text($0.title, locale: locale) } ?? calories)
      .accessibilityIdentifier("nutritionMacroRing")
  }

  private var energy: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(calories).font(.system(.title2, design: .rounded).bold()).monospacedDigit()
        .contentTransition(.numericText()).accessibilityIdentifier("nutritionDailyCalories")
      if let goal {
        Text(L10n.format("Цель: %@ ккал", number(goal.calories), locale: locale))
          .font(.caption).foregroundStyle(.secondary)
        Text(
          L10n.format(
            day.total.calories > goal.calories ? "Сверх цели: %@ ккал" : "Осталось: %@ ккал",
            number(abs(goal.calories - day.total.calories)), locale: locale)
        ).font(.subheadline).foregroundStyle(.secondary)
        Text(
          min(day.total.calories / goal.calories, 1), format: .percent.precision(.fractionLength(0))
        )
        .font(.headline).foregroundStyle(theme.accent)
      } else {
        Text(L10n.text("Добавьте цели питания для отслеживания прогресса.", locale: locale))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var macroButtons: some View {
    ForEach(Macro.allCases, id: \.self) { macro in
      Button {
        selected = selected == macro ? nil : macro
      } label: {
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 5) {
            Circle().fill(macro.color).frame(width: 7, height: 7)
            Text(L10n.text(macro.title, locale: locale)).font(.caption)
          }
          Text(L10n.format("%@ г", number(macro.amount(in: day.total)), locale: locale))
            .font(.subheadline.bold()).monospacedDigit().contentTransition(.numericText())
          if let target = macro.target(in: goal) {
            Text(L10n.format("из %@ г", number(target), locale: locale)).font(.caption2)
              .foregroundStyle(.secondary)
            ProgressView(value: min(1, macro.amount(in: day.total) / target)).tint(macro.color)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(8)
        .background(
          selected == macro ? macro.color.opacity(0.1) : .clear, in: .rect(cornerRadius: 14)
        )
        .contentShape(.rect)
      }.buttonStyle(.plain).accessibilityIdentifier("nutritionMacro_\(macro.rawValue)")
        .accessibilityAddTraits(selected == macro ? [.isSelected] : [])
    }
  }

  private func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
  }
}
