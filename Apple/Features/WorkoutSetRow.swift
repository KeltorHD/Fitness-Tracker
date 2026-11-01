import FitnessTrackerCore
import SwiftUI

private enum WorkoutSetTableLayout {
  static let indexWidth: CGFloat = 44
  static let statusWidth: CGFloat = 24
  static let spacing: CGFloat = 12
  static let horizontalPadding: CGFloat = 8
}

struct WorkoutSetTableHeader: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  let unit: WeightUnit

  var body: some View {
    if !typeSize.isAccessibilitySize {
      HStack(spacing: WorkoutSetTableLayout.spacing) {
        Text(L10n.text("Подход", locale: locale)).frame(width: WorkoutSetTableLayout.indexWidth)
        Text(L10n.format("Вес, %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
          .frame(maxWidth: .infinity)
        Text(L10n.text("Повторения", locale: locale)).frame(maxWidth: .infinity)
        Image(systemName: "checkmark").frame(width: WorkoutSetTableLayout.statusWidth)
      }
      .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      .padding(.horizontal, WorkoutSetTableLayout.horizontalPadding)
      .accessibilityHidden(true)
      .accessibilityIdentifier("workoutSetTableHeader")
    }
  }
}

struct WorkoutSetRow: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  let set: WorkoutSet
  let index: Int
  var marker: String? = nil
  var showsWarmupAction = true
  let unit: WeightUnit
  let editable: Bool
  let selected: Bool
  let weight: String
  let repetitions: String
  let numberPad: WorkoutNumberPadModel
  let edit: (WorkoutSetField) -> Void
  let select: () -> Void
  let toggleWarmup: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: WorkoutSetTableLayout.spacing) {
        Button(action: select) {
          Text(marker ?? String(index + 1)).font(.callout.weight(selected ? .semibold : .regular))
            .monospacedDigit().foregroundStyle(selected ? colorTheme.accent : FitTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain).frame(width: WorkoutSetTableLayout.indexWidth).disabled(!editable)
        .accessibilityLabel(
          L10n.format(
            marker == nil ? "Подход %@" : "Снижение веса %@", String(index + 1), locale: locale)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        Group {
          if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(
                  L10n.format("Вес, %@", L10n.text(unit.rawValue, locale: locale), locale: locale)
                )
                .font(.caption).foregroundStyle(.secondary)
                weightField
              }
              VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Повторения", locale: locale)).font(.caption)
                  .foregroundStyle(.secondary)
                repetitionsField
              }
            }
          } else {
            HStack(spacing: WorkoutSetTableLayout.spacing) {
              weightField
              repetitionsField
            }
          }
        }.frame(maxWidth: .infinity)
        Image(systemName: set.completedAt != nil ? "checkmark.circle.fill" : "circle")
          .font(.body)
          .foregroundStyle(
            set.completedAt != nil
              ? FitTheme.muted : selected ? colorTheme.accent : FitTheme.separator
          )
          .frame(width: WorkoutSetTableLayout.statusWidth)
          .accessibilityLabel(
            L10n.text(set.completedAt != nil ? "Подход выполнен" : "Не выполнено", locale: locale))
      }
      if set.isWarmup || set.isDropSet || (set.loadMultiplier ?? 1) > 1 {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { metadata }
          VStack(alignment: .leading, spacing: 6) { metadata }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.leading, WorkoutSetTableLayout.indexWidth + WorkoutSetTableLayout.spacing)
      }
    }
    .padding(.horizontal, WorkoutSetTableLayout.horizontalPadding)
    .padding(.vertical, typeSize.isAccessibilitySize ? 16 : 8)
    .background(
      selected ? colorTheme.accent.opacity(0.09) : Color.clear, in: .rect(cornerRadius: 16)
    )
    .contextMenu {
      if editable && showsWarmupAction && !set.isDropSet {
        Button(
          L10n.text(set.isWarmup ? "Рабочий подход" : "Разминочный подход", locale: locale),
          action: toggleWarmup)
      }
    }
  }

  @ViewBuilder private var metadata: some View {
    if set.isWarmup {
      Label(L10n.text("Разминка", locale: locale), systemImage: "flame")
        .foregroundStyle(colorTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
        .background(colorTheme.accent.opacity(0.1), in: .capsule).accessibilityIdentifier(
          "warmupSet")
    }
    if set.isDropSet {
      Text(L10n.format("Дропсет · этапов: %@", String(set.stages.count), locale: locale))
        .foregroundStyle(colorTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
        .background(colorTheme.accent.opacity(0.1), in: .capsule)
    }
    if let multiplier = set.loadMultiplier, multiplier > 1 {
      Text(L10n.format("Множитель веса: %@", String(multiplier), locale: locale))
    }
  }

  private var weightField: some View {
    Group {
      if editable {
        valueButton(weight, field: .weight(set.id))
          .accessibilityIdentifier("setWeight_\(set.id)")
          .accessibilityLabel(
            L10n.format("Вес в %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
      } else {
        Text(formattedWeight).frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityLabel(
            L10n.format(
              "Вес: %@ %@", formattedWeight, L10n.text(unit.rawValue, locale: locale),
              locale: locale))
      }
    }
    .font(.title2.weight(.medium)).monospacedDigit()
    .foregroundStyle(set.completedAt != nil ? Color.secondary : .primary)
  }

  private var formattedWeight: String {
    unit.display(set.weightKG).formatted(
      .number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))
  }

  private var repetitionsField: some View {
    Group {
      if editable {
        valueButton(repetitions, field: .repetitions(set.id))
          .accessibilityIdentifier("setRepetitions_\(set.id)")
          .accessibilityLabel(L10n.text("Повторения", locale: locale))
      } else {
        Text(String(set.repetitions)).frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityLabel(
            L10n.format("Повторения: %@", String(set.repetitions), locale: locale))
      }
    }
    .font(.title2.weight(.medium)).monospacedDigit()
    .foregroundStyle(set.completedAt != nil ? Color.secondary : .primary)
  }

  private func valueButton(_ value: String, field: WorkoutSetField) -> some View {
    let active = numberPad.field == field
    return Button {
      edit(field)
    } label: {
      Text(value.isEmpty ? "0" : value)
        .foregroundStyle(
          (active && numberPad.replacesOnInput) || value.isEmpty ? FitTheme.muted : Color.primary
        )
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
          if active { Capsule().fill(colorTheme.accent).frame(height: 3) }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }.buttonStyle(.plain).lineLimit(1).minimumScaleFactor(0.65)
      .accessibilityValue(value.isEmpty ? "0" : value)
      .accessibilityHint(L10n.text("Открыть цифровую панель", locale: locale))
      .accessibilityAddTraits(active ? .isSelected : [])
  }
}
