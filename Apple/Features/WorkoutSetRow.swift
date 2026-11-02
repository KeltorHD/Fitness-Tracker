import FitnessTrackerCore
import SwiftUI

private enum WorkoutSetTableLayout {
  static let indexWidth: CGFloat = 44
  static let noteWidth: CGFloat = 44
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
        Color.clear.frame(width: WorkoutSetTableLayout.indexWidth, height: 1)
        Text(L10n.format("Вес, %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
          .frame(maxWidth: .infinity)
        Text(L10n.text("Повторения", locale: locale)).frame(maxWidth: .infinity)
        Image(systemName: "note.text").frame(width: WorkoutSetTableLayout.noteWidth)
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
  let unit: WeightUnit
  let editable: Bool
  let selected: Bool
  let weight: String
  let repetitions: String
  let numberPad: WorkoutNumberPadModel
  let edit: (WorkoutSetField) -> Void
  let select: () -> Void
  var openNote: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: WorkoutSetTableLayout.spacing) {
        VStack(spacing: 0) {
          Group {
            if editable {
              Button(action: select) { indexLabel }.buttonStyle(.plain)
            } else {
              indexLabel
            }
          }
          .accessibilityLabel(
            L10n.format(
              marker == nil ? "Подход %@" : "Снижение веса %@", String(index + 1), locale: locale)
          )
          .accessibilityAddTraits(selected ? .isSelected : [])
          .accessibilityValue(
            L10n.text(set.completedAt != nil ? "Подход выполнен" : "Не выполнено", locale: locale))
        }.frame(width: WorkoutSetTableLayout.indexWidth)
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
        Group {
          if set.note != nil, let openNote {
            Button(action: openNote) {
              Image(systemName: "note.text").font(.caption).frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(colorTheme.accent)
              .accessibilityLabel(L10n.text("Заметка к подходу", locale: locale))
              .accessibilityIdentifier("setNote_\(set.id)")
          } else {
            Color.clear.frame(height: 44).accessibilityHidden(true)
          }
        }.frame(width: WorkoutSetTableLayout.noteWidth)
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
      selected
        ? colorTheme.accent.opacity(0.09)
        : set.completedAt != nil ? colorTheme.accent.opacity(0.04) : Color.clear,
      in: .rect(cornerRadius: 16)
    )
  }

  private var indexLabel: some View {
    Text(marker ?? String(index + 1))
      .font(.callout.weight(selected || set.completedAt != nil ? .semibold : .regular))
      .monospacedDigit()
      .foregroundStyle(selected || set.completedAt != nil ? colorTheme.accent : FitTheme.muted)
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(.rect)
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
    .foregroundStyle(set.completedAt != nil || selected ? Color.primary : .secondary)
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
    .foregroundStyle(set.completedAt != nil || selected ? Color.primary : .secondary)
  }

  private func valueButton(_ value: String, field: WorkoutSetField) -> some View {
    let active = numberPad.field == field
    return Button {
      edit(field)
    } label: {
      Text(value.isEmpty ? "0" : value)
        .foregroundStyle(
          (active && numberPad.replacesOnInput) || value.isEmpty
            ? FitTheme.muted : selected ? Color.primary : Color.secondary
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
