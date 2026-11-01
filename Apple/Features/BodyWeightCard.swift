import FitnessTrackerCore
import SwiftUI

struct BodyWeightCard: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var recording = false
  let model: BodyWeightViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if typeSize.isAccessibilitySize {
        weightColumn
        changeColumn
      } else {
        HStack(alignment: .top, spacing: 20) {
          weightColumn.frame(maxWidth: .infinity, alignment: .leading)
          changeColumn.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16).overlay(alignment: .leading) {
              Rectangle().fill(FitTheme.separator).frame(width: 1)
            }
        }
      }
      Divider()
      ViewThatFits(in: .horizontal) {
        HStack {
          dateLabel
          Spacer(minLength: 12)
          recordButton
        }
        VStack(alignment: .leading, spacing: 12) {
          dateLabel
          recordButton
        }
      }
    }
    .resultsCard().accessibilityIdentifier("bodyWeightCard")
    .sheet(isPresented: $recording) { BodyWeightEditor(unit: unit) }
  }

  private var weightColumn: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.text("Вес", locale: locale)).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(formatted(model.summary.latest?.weightKG)).font(.largeTitle.weight(.medium))
          .monospacedDigit()
        if model.summary.latest != nil {
          Text(L10n.text(unit.rawValue, locale: locale)).font(.title3)
        }
      }.accessibilityElement(children: .combine).accessibilityIdentifier("latestBodyWeight")
    }
  }
  private var changeColumn: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.text("Изменение", locale: locale)).font(.subheadline).foregroundStyle(.secondary)
      Text(
        model.summary.changeKG.map {
          let number = unit.display($0).formatted(
            .number.locale(L10n.numberLocale).precision(.fractionLength(0...2)).sign(
              strategy: .always()))
          return "\(number) \(L10n.text(unit.rawValue, locale: locale))"
        } ?? "—"
      ).font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(colorTheme.accent)
      Text(L10n.text("К предыдущей записи", locale: locale)).font(.caption).foregroundStyle(
        .secondary)
    }
  }
  private var dateLabel: some View {
    Group {
      if let latest = model.summary.latest {
        Text(latest.date, format: .dateTime.day().month().hour().minute())
      } else {
        Text(L10n.text("Нет записей", locale: locale))
      }
    }.font(.subheadline).foregroundStyle(.secondary)
  }
  private var recordButton: some View {
    Button(L10n.text("Записать", locale: locale)) { recording = true }
      .font(.headline).buttonStyle(.glassProminent).controlSize(.large).tint(colorTheme.accent)
      .accessibilityIdentifier("recordBodyWeight")
  }
  private func formatted(_ weight: Double?) -> String {
    guard let weight else { return "—" }
    return unit.display(weight).formatted(
      .number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))
  }
}
