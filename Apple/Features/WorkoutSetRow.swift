import FitnessTrackerCore
import SwiftUI

struct WorkoutSetRow: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 34
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
      HStack(spacing: 12) {
        Button(action: select) {
          Text(marker ?? String(index + 1)).font(.body).monospacedDigit()
            .frame(minWidth: 32, minHeight: 36)
            .foregroundStyle(selected ? FitTheme.accent : FitTheme.muted)
            .background(
              selected ? FitTheme.accent.opacity(0.12) : FitTheme.card, in: .rect(cornerRadius: 12))
        }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).disabled(!editable)
          .accessibilityLabel(
            L10n.format(
              marker == nil ? "Подход %@" : "Снижение веса %@", String(index + 1), locale: locale)
          )
          .accessibilityAddTraits(selected ? .isSelected : [])
        Group {
          if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
              weightField
              repetitionsField
            }
          } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              weightField
              separator
              repetitionsField
            }
          }
        }.frame(maxWidth: .infinity)
        if set.completedAt != nil {
          Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(FitTheme.accent)
            .accessibilityLabel(L10n.text("Подход выполнен", locale: locale))
        }
      }
      if set.isWarmup || set.isDropSet || (set.loadMultiplier ?? 1) > 1 {
        HStack {
          if set.isWarmup {
            Label(L10n.text("Разминка", locale: locale), systemImage: "flame")
              .foregroundStyle(FitTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
              .background(FitTheme.accent.opacity(0.1), in: .capsule).accessibilityIdentifier(
                "warmupSet")
          }
          if set.isDropSet {
            Text(L10n.format("Дропсет · этапов: %@", String(set.stages.count), locale: locale))
              .foregroundStyle(FitTheme.accent).padding(.horizontal, 8).padding(.vertical, 4)
              .background(FitTheme.accent.opacity(0.1), in: .capsule)
          }
          if let multiplier = set.loadMultiplier, multiplier > 1 {
            Text(L10n.format("Множитель веса: %@", String(multiplier), locale: locale))
          }
        }.font(.caption).foregroundStyle(.secondary).padding(.leading, 44)
      }
    }
    .padding(.vertical, typeSize.isAccessibilitySize ? 16 : 12)
    .contextMenu {
      if editable && showsWarmupAction && !set.isDropSet {
        Button(
          L10n.text(set.isWarmup ? "Рабочий подход" : "Разминочный подход", locale: locale),
          action: toggleWarmup)
      }
    }
  }
  private var separator: some View {
    Text("×").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
  }
  private var weightField: some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      if editable {
        valueButton(weight, field: .weight(set.id))
          .accessibilityIdentifier("setWeight_\(set.id)")
          .accessibilityLabel(
            L10n.format("Вес в %@", L10n.text(unit.rawValue, locale: locale), locale: locale))
      } else {
        Text(
          unit.display(set.weightKG),
          format: .number.locale(L10n.numberLocale).precision(.fractionLength(0...2))
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      Text(L10n.text(unit.rawValue, locale: locale)).font(.body).foregroundStyle(.secondary)
    }.font(.system(size: numberSize, weight: .regular)).monospacedDigit()
  }
  private var repetitionsField: some View {
    Group {
      if editable {
        valueButton(repetitions, field: .repetitions(set.id))
          .accessibilityIdentifier("setRepetitions_\(set.id)")
          .accessibilityLabel(L10n.text("Повторения", locale: locale))
      } else {
        Text(String(set.repetitions)).frame(maxWidth: .infinity, alignment: .leading)
      }
    }.font(.system(size: numberSize, weight: .regular)).monospacedDigit()
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
          if active { Capsule().fill(FitTheme.accent).frame(height: 3) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: field.isWeight ? .trailing : .leading)
        .contentShape(.rect)
    }.buttonStyle(.plain).lineLimit(1).minimumScaleFactor(0.65)
      .accessibilityValue(value.isEmpty ? "0" : value)
      .accessibilityHint(L10n.text("Открыть цифровую панель", locale: locale))
      .accessibilityAddTraits(active ? .isSelected : [])
  }

}
