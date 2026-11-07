import FitnessTrackerCore
import SwiftUI

/// One template keeps its place in the list while its exercise variation changes.
struct TemplateVariationSelector: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  let template: WorkoutTemplate
  @Binding var selection: UUID?

  private var choices: [(id: UUID, name: String)] {
    [(template.id, L10n.format("Вариант %@", "1", locale: locale))]
      + template.variations.enumerated().map { index, variation in
        (
          variation.id,
          variation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("Вариант %@", String(index + 2), locale: locale) : variation.name
        )
      }
  }

  private var currentIndex: Int {
    choices.firstIndex { $0.id == (selection ?? template.id) } ?? 0
  }

  var body: some View {
    HStack(spacing: 10) {
      Button {
        changeSelection(by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .frame(width: 44, height: 44).contentShape(.rect)
      }
      .disabled(currentIndex == 0)
      .accessibilityLabel(L10n.text("Предыдущая вариация", locale: locale))
      .accessibilityIdentifier("previousTemplateVariation_\(template.id)")
      Menu {
        ForEach(choices, id: \.id) { choice in
          Button {
            selection = choice.id == template.id ? nil : choice.id
          } label: {
            if choice.id == choices[currentIndex].id {
              Label(choice.name, systemImage: "checkmark")
            } else {
              Text(choice.name)
            }
          }
          .accessibilityIdentifier("chooseTemplateVariation_\(template.id)_\(choice.id)")
        }
      } label: {
        VStack(spacing: 2) {
          Text(choices[currentIndex].name)
            .font(.subheadline.weight(.semibold)).lineLimit(2)
          Text(
            L10n.format("%@ из %@", String(currentIndex + 1), String(choices.count), locale: locale)
          ).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
      }
      .accessibilityLabel(L10n.text("Вариация шаблона", locale: locale))
      .accessibilityValue(choices[currentIndex].name)
      .accessibilityIdentifier("templateVariationMenu_\(template.id)")
      Button {
        changeSelection(by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .frame(width: 44, height: 44).contentShape(.rect)
      }
      .disabled(currentIndex == choices.count - 1)
      .accessibilityLabel(L10n.text("Следующая вариация", locale: locale))
      .accessibilityIdentifier("nextTemplateVariation_\(template.id)")
    }
    .buttonStyle(.borderless).foregroundStyle(colorTheme.accent)
    .background(colorTheme.accent.opacity(0.08), in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("templateVariationSelector_\(template.id)")
  }

  private func changeSelection(by offset: Int) {
    let index = min(max(currentIndex + offset, 0), choices.count - 1)
    selection = index == 0 ? nil : choices[index].id
  }
}
