import FitnessTrackerCore
import SwiftUI

enum WorkoutSetField: Hashable {
  case weight(UUID)
  case repetitions(UUID)
  var setID: UUID {
    switch self {
    case .weight(let id), .repetitions(let id): id
    }
  }
}

struct WorkoutSetRow: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 34
  let set: WorkoutSet
  let index: Int
  let unit: WeightUnit
  let editable: Bool
  let selected: Bool
  @Binding var weight: String
  @Binding var repetitions: String
  var focus: FocusState<WorkoutSetField?>.Binding
  let select: () -> Void
  let toggleWarmup: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button(action: select) {
          Text(String(index + 1)).font(.body).monospacedDigit()
            .frame(minWidth: 32, minHeight: 36)
            .foregroundStyle(selected ? FitTheme.accent : FitTheme.muted)
            .background(
              selected ? FitTheme.accent.opacity(0.12) : FitTheme.card, in: .rect(cornerRadius: 12))
        }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).disabled(!editable)
          .accessibilityLabel(L10n.format("Подход %@", String(index + 1), locale: locale))
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
      if set.isWarmup || (set.loadMultiplier ?? 1) > 1 {
        HStack {
          if set.isWarmup { Text(L10n.text("Разминка", locale: locale)) }
          if let multiplier = set.loadMultiplier, multiplier > 1 {
            Text(L10n.format("Множитель веса: %@", String(multiplier), locale: locale))
          }
        }.font(.caption).foregroundStyle(.secondary).padding(.leading, 44)
      }
    }
    .padding(.vertical, typeSize.isAccessibilitySize ? 16 : 12)
    .contextMenu {
      if editable {
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
        TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
          .focused(focus, equals: .weight(set.id)).accessibilityIdentifier("setWeight_\(set.id)")
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
        TextField(L10n.text("Повторы", locale: locale), text: $repetitions).keyboardType(.numberPad)
          .focused(focus, equals: .repetitions(set.id)).accessibilityIdentifier(
            "setRepetitions_\(set.id)"
          )
          .accessibilityLabel(L10n.text("Повторения", locale: locale))
      } else {
        Text(String(set.repetitions)).frame(maxWidth: .infinity, alignment: .leading)
      }
    }.font(.system(size: numberSize, weight: .regular)).monospacedDigit()
  }
}
